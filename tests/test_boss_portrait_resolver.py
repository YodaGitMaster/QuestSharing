"""In-game boss display resolver (BossPortraitResolver.lua) and its use by the Bosses page (DungeonBossesUI.lua).
The PlayerModel is mocked: SetCreature logs the npc; GetDisplayInfo answers DISPLAYS[npc] once READY[npc] is set or
LOAD_AT[npc] seconds have passed since SetCreature, else 0 (not known)."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_journal_bosses_ui import game as ui_game, page, shown_rows, SKULL

STYLES = ("modern", "classic")

MODEL = r'''
MODEL_LOG, MODELS, DISPLAYS, READY, LOAD_AT, AFTER_READS = {}, {}, {}, {}, {}, {}
LOADED_INSIDE = false -- OnModelLoaded fires inside SetCreature (a creature the client already has)
STALE = false -- the model keeps answering with the previous creature's display until the new one is ready
local cf = CreateFrame
function CreateFrame(kind, name, parent, ...)
    local f = cf(kind, name, parent, ...)
    if kind == "PlayerModel" then
        MODELS[#MODELS + 1] = f
        function f:SetCreature(id)
            self.creature, self.setAt = id, NOW
            MODEL_LOG[#MODEL_LOG + 1] = id
            if LOADED_INSIDE and self.scripts.OnModelLoaded then self.scripts.OnModelLoaded(self) end
        end
        function f:ClearModel() self.creature = nil end
        function f:SetAlpha(a) self.alpha = a end
        function f:EnableMouse(v) self.mouse = v end
        function f:GetDisplayInfo()
            local id = self.creature
            if not id then return STALE and (self.showing or 0) or 0 end
            if AFTER_READS[id] then AFTER_READS[id] = AFTER_READS[id] - 1; if AFTER_READS[id] <= 0 then READY[id] = true end end
            local ready = READY[id] or (LOAD_AT[id] and NOW - self.setAt >= LOAD_AT[id] - 1e-9)
            if ready then self.showing = DISPLAYS[id] or 0; return self.showing end
            return STALE and (self.showing or 0) or 0
        end
    end
    return f
end
function LOADED() local m = MODELS[1]; m.scripts.OnModelLoaded(m) end
GOT = {}
function ASK(id) return NS.bossPortraitResolver.request(id, function(d) GOT[#GOT + 1] = id .. "=" .. d end) end
-- twenty Forever-only bosses with no art at all
OFFICIAL[16620] = {}
for i = 1, 20 do
    table.insert(OFFICIAL[16620], { official = true, items = {}, name = "Forever " .. i, order = i, npcID = 260000 + i,
        npcIDs = { 260000 + i }, level = 60 })
end
'''


def game(style, extra=""):
    return ui_game(style, MODEL + extra)


def log(g):
    return list(g.eval("MODEL_LOG").values())


def got(g):
    return list(g.eval("GOT").values())


def state(g):
    return g.eval("NS.bossPortraitResolver._state()")


def queue(g):
    return list(state(g).queue.values())


def test_queue_order_and_one_lookup_at_a_time(style):
    g = game(style)
    assert g.eval("#MODELS") == 0                                   # made on the first lookup only
    for npc in (101, 102, 103):
        g.run(f"DISPLAYS[{npc}] = {npc + 900}")
        assert g.eval(f"ASK({npc})") is True
    assert log(g) == [101] and queue(g) == [102, 103]               # one at a time, FIFO
    assert state(g).cur.id == 101
    g.run("READY[101] = true"); g.eval("LOADED()")
    assert log(g) == [101, 102] and queue(g) == [103]
    g.run("READY[102] = true"); g.eval("LOADED()")
    g.run("READY[103] = true"); g.eval("LOADED()")
    assert got(g) == ["101=1001", "102=1002", "103=1003"]
    assert state(g).cur is None and queue(g) == []
    assert g.eval("#MODELS") == 1                                   # one model for every lookup
    assert not g.eval("NS.db.errors")


def test_hidden_model_shape(style):
    g = game(style)
    g.eval("ASK(5)")
    m = g.eval("MODELS[1]")
    assert m.kind == "PlayerModel" and g.eval("MODELS[1].parent == UIParent")
    assert m.width == 1 and m.height == 1 and m.alpha == 0 and m.mouse is False and m.shown


def test_timer_path_reads_after_0_2_seconds(style):
    g = game(style, "DISPLAYS[7] = 4242; LOAD_AT[7] = 0.15")
    g.eval("ASK(7)")
    assert got(g) == [] and log(g) == [7]
    g.advance(0.4)
    assert got(g) == ["7=4242"] and log(g) == [7]                   # found on the first try's timer
    assert g.eval("NS.bossPortraitResolver.displayFor(7)") == 4242


def test_cached_creature_answers_at_once(style):
    g = game(style, "DISPLAYS[8] = 80; READY[8] = true")
    g.eval("ASK(8)")
    assert got(g) == ["8=80"] and state(g).cur is None
    g.eval("ASK(8)")                                                # cached: done at once, no new lookup
    assert got(g) == ["8=80", "8=80"] and log(g) == [8]


def test_on_model_loaded_inside_set_creature_does_not_read_the_next_one(style):
    g = game(style, "LOADED_INSIDE = true; DISPLAYS[1] = 11; DISPLAYS[2] = 22; READY[1] = true; READY[2] = true")
    g.run("IN_COMBAT = true")
    g.eval("ASK(1)"); g.eval("ASK(2)")
    g.run("IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED")
    assert got(g) == ["1=11", "2=22"]
    assert g.eval("NS.db.bossDisplays[1]") == 11 and g.eval("NS.db.bossDisplays[2]") == 22
    assert state(g).cur is None


def test_a_finished_lookup_never_reads_the_next_creature(style):
    # npc 1 answers inside SetCreature; npc 2 answers on its third read (OnModelLoaded, attempt, then the next), which must be its own, not npc 1's
    g = game(style, "LOADED_INSIDE = true; DISPLAYS[1] = 11; DISPLAYS[2] = 22; READY[1] = true; AFTER_READS[2] = 3")
    g.run("LOADED_INSIDE = false; IN_COMBAT = true")
    g.eval("ASK(1)"); g.eval("ASK(2)")
    g.run("LOADED_INSIDE = true; IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED")
    assert g.eval("NS.db.bossDisplays[1]") == 11
    assert got(g)[0] == "1=11" and "1=22" not in got(g)
    g.advance(1)
    assert g.eval("NS.db.bossDisplays[2]") == 22 and got(g) == ["1=11", "2=22"]


def test_a_stale_display_from_the_previous_creature_is_not_saved(style):
    # the client still answers with npc 1's display right after SetCreature(2): that read must not become npc 2's ID
    g = game(style, "STALE = true; DISPLAYS[1] = 11; DISPLAYS[2] = 22; READY[1] = true")
    g.eval("ASK(1)")
    assert got(g) == ["1=11"]
    g.eval("ASK(2)")
    assert got(g) == ["1=11"] and g.eval("NS.db.bossDisplays[2]") is None   # immediate read was 11: rejected
    g.advance(0.25)
    assert g.eval("NS.db.bossDisplays[2]") is None                         # timer read still 11: rejected
    g.run("LOAD_AT[2] = 0")                                                # the creature arrives
    g.advance(0.5)
    assert g.eval("NS.db.bossDisplays[2]") == 22 and got(g) == ["1=11", "2=22"]


def test_a_shared_display_counts_once_the_model_loaded(style):
    # two bosses can share one model: the same ID as the previous one is taken after OnModelLoaded for this lookup
    g = game(style, "STALE = true; DISPLAYS[1] = 11; DISPLAYS[2] = 11; READY[1] = true")
    g.eval("ASK(1)"); g.eval("ASK(2)")
    assert g.eval("NS.db.bossDisplays[2]") is None
    g.eval("LOADED()")
    assert g.eval("NS.db.bossDisplays[2]") == 11 and got(g) == ["1=11", "2=11"]


def test_gives_up_after_five_tries_for_the_session(style):
    g = game(style, "DISPLAYS[9] = 99; READY[9] = true")
    g.eval("ASK(3)")                                                # the client never knows npc 3
    g.eval("ASK(9)")
    g.advance(3)
    assert log(g).count(3) == 5 and log(g)[-1] == 9
    assert got(g) == ["9=99"]
    assert state(g).failed[3] is True
    assert g.eval("ASK(3)") is False and log(g).count(3) == 5       # not asked again this session
    assert g.eval("NS.db.bossDisplays[3]") is None


def test_zero_or_nil_display_means_not_known(style):
    g = game(style, "DISPLAYS[4] = 0; READY[4] = true")
    g.run("NS.db.bossDisplays = { [6] = 0 }")
    assert g.eval("NS.bossPortraitResolver.displayFor(6)") is None
    assert g.eval("NS.bossPortraitResolver.displayFor(nil)") is None
    assert g.eval("NS.bossPortraitResolver.request(nil)") is False
    g.eval("ASK(4)"); g.advance(3)
    assert got(g) == [] and state(g).failed[4] is True


def test_cache_lives_in_the_saved_variable(style):
    g = game(style, "DISPLAYS[12] = 1200; READY[12] = true")
    assert g.eval("NS.db.bossDisplays") is None                     # created lazily
    g.eval("ASK(12)")
    assert g.eval("NS.db.bossDisplays[12]") == 1200
    assert g.eval("QuestSharingDB.bossDisplays[12]") == 1200 and g.eval("NS.db == QuestSharingDB")


def test_no_lookup_in_combat_and_an_active_one_waits(style):
    g = game(style, "DISPLAYS[21] = 2100; DISPLAYS[22] = 2200")
    g.run("IN_COMBAT = true")
    g.eval("ASK(21)")
    assert log(g) == [] and queue(g) == [21]
    g.run("IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED")
    assert log(g) == [21]
    g.eval("ASK(22)")
    g.run("IN_COMBAT = true"); g.fire("PLAYER_REGEN_DISABLED")      # the active lookup goes back to the front
    assert state(g).cur is None and queue(g) == [21, 22]
    g.advance(3)
    assert log(g) == [21]
    g.run("IN_COMBAT = false; READY[21] = true; READY[22] = true"); g.fire("PLAYER_REGEN_ENABLED")
    assert got(g) == ["21=2100", "22=2200"] and log(g) == [21, 21, 22]


def test_combat_noticed_by_the_timer(style):
    g = game(style, "DISPLAYS[23] = 2300")
    g.eval("ASK(23)")
    g.run("IN_COMBAT = true")                                       # no event seen yet: the timer checks it
    g.advance(1)
    assert log(g) == [23] and queue(g) == [23] and state(g).cur is None
    g.run("IN_COMBAT = false; READY[23] = true"); g.fire("PLAYER_REGEN_ENABLED")
    assert got(g) == ["23=2300"]


def test_paused_during_a_loading_screen(style):
    g = game(style, "DISPLAYS[31] = 3100; DISPLAYS[32] = 3200")
    g.eval("ASK(31)")
    g.fire("PLAYER_LEAVING_WORLD")
    assert state(g).loading is True and state(g).cur is None and queue(g) == [31]
    g.eval("ASK(32)")
    g.advance(3)
    assert log(g) == [31] and queue(g) == [31, 32]
    g.run("READY[31] = true; READY[32] = true")
    g.fire("PLAYER_ENTERING_WORLD")
    assert got(g) == ["31=3100", "32=3200"]


def test_at_most_twelve_queued(style):
    g = game(style)
    g.run("IN_COMBAT = true")
    results = [g.eval(f"ASK({1000 + i})") for i in range(14)]
    assert results == [True] * 12 + [False, False] and len(queue(g)) == 12
    assert g.eval("ASK(1000)") is True and len(queue(g)) == 12      # already queued: just one more waiter


def test_bossdump_prints_the_cache_and_other_commands_still_work(style):
    g = game(style)
    g.slash("bossdump")
    assert any("no boss display IDs found yet" in p for p in g.printed())
    g.run("NS.db.bossDisplays = { [258968] = 123, [250001] = 77, [5] = 0 }")
    g.run("PRINTED = {}")
    g.slash("bossdump")
    out = g.printed()
    assert any("2 boss display IDs" in p for p in out)
    lines = [p.split("|r ", 1)[-1] for p in out]
    assert lines[1:] == ["250001=77", "258968=123"]
    g.run("PRINTED = {}")
    g.slash("questmap")                                             # the Core handler still answers the rest
    assert any("have been removed" in p for p in g.printed())


# -- the Bosses page -------------------------------------------------------------------------------

def test_page_asks_for_a_boss_without_art_and_repaints_on_success(style):
    g = game(style, "DISPLAYS[250001] = 77")
    B, w = page(g, 16611, "Forever place")
    rows = shown_rows(w)
    assert rows[0].portrait.source == "skull" and rows[0].portrait.texture == SKULL   # the muted skull meanwhile
    assert rows[1].portrait.source == "display" and rows[1].portrait.displayID == 91001
    assert log(g) == [250001]                                        # once for the row and the header
    g.run("READY[250001] = true"); g.eval("LOADED()")
    rows = shown_rows(w)
    assert rows[0].portrait.source == "display" and rows[0].portrait.displayID == 77 and rows[0].portrait.resolved
    assert w.portrait.source == "display" and w.portrait.displayID == 77           # the header too
    g.advance(3.5)                                                   # the staged display path takes it from there
    assert rows[0].portrait.staged is not None and w.portrait.staged is not None
    B.show(16611, "Forever place")                                   # next time: from the cache, no lookup
    assert shown_rows(w)[0].portrait.source == "display" and log(g) == [250001]
    assert not g.eval("NS.db.errors")


def test_cached_display_is_used_before_any_lookup(style):
    g = game(style)
    g.run("NS.db.bossDisplays = { [250001] = 55 }")
    B, w = page(g, 16611, "Forever place")
    assert shown_rows(w)[0].portrait.displayID == 55 and log(g) == []


COUNT = r'''
PAINTS = 0
local P = NS.dungeonBossesUI.portrait
NS.dungeonBossesUI.portrait = function(...) PAINTS = PAINTS + 1; return P(...) end
'''


def test_answer_for_a_stale_or_hidden_page_is_ignored(style):
    for leave in ("other", "hide"):
        g = game(style, "DISPLAYS[250001] = 77")
        B, w = page(g, 16611, "Forever place")
        g.run(COUNT)
        g.run("NS.bossPortraitResolver.clear = function() end")    # keep the old waiters: the page token decides
        if leave == "other":
            B.show(209, "Zul'Farrak")
        else:
            B.hide()
        g.run("PAINTS = 0; READY[250001] = true"); g.eval("LOADED()")
        assert g.eval("PAINTS") == 0, leave
        assert g.eval("NS.db.bossDisplays[250001]") == 77            # still cached for next time
        assert not g.eval("NS.db.errors")
    g = game(style, "DISPLAYS[250001] = 77")                         # the same page: it repaints row + header
    B, w = page(g, 16611, "Forever place")
    g.run(COUNT)
    g.run("READY[250001] = true"); g.eval("LOADED()")
    assert g.eval("PAINTS") == 2


def test_another_dungeon_drops_the_queued_lookups(style):
    g = game(style)
    B, w = page(g, 16620, "Forever twenty")
    assert log(g) == [260001] and len(queue(g)) == 7                 # 8 rows (the header is boss 1)
    B.show(209, "Zul'Farrak")
    assert queue(g) == [] and state(g).cur.id == 260001              # the active one finishes, no callback
    g.advance(3)
    assert log(g) == [260001] * 5 and state(g).cur is None


def test_no_lookups_when_every_boss_has_art(style):
    for area in (209, 1584):
        g = game(style)
        page(g, area, "x")
        assert log(g) == [] and g.eval("#MODELS") == 0, area
    g = game(style)
    page(g, 1581, "The Deadmines")                                   # only Miner Johnson has no art
    assert log(g) == [3586]


def test_only_the_shown_dungeon_and_at_most_twelve_queued(style):
    g = game(style)
    B, w = page(g, 16620, "Forever twenty")
    P = g.eval("NS.dungeonBossesUI.portrait")
    P(g.eval("UIParent:CreateTexture()"), g.eval("{name='Elsewhere', npcID=999999}"), 16611)
    assert 999999 not in queue(g)                                    # not the dungeon being shown
    B.scroll(8)
    B.scroll(8)
    assert len(queue(g)) <= 12 and 260001 in log(g)
    asked = g.eval("NS.dungeonBossesUI._view().asked")
    assert sum(1 for _ in asked.keys()) == 13                        # 1 active + 12 queued; the rest ask again later
    assert not g.eval("NS.db.errors")


def test_page_in_combat_waits_then_repaints(style):
    g = game(style, "DISPLAYS[250001] = 77; READY[250001] = true")
    g.run("IN_COMBAT = true")
    B, w = page(g, 16611, "Forever place")
    assert log(g) == [] and shown_rows(w)[0].portrait.source == "skull"
    g.run("IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED")
    assert shown_rows(w)[0].portrait.source == "display" and shown_rows(w)[0].portrait.displayID == 77


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES:
            total += 1
            try:
                fn(style); print("ok", name, style)
            except Exception as exc:
                failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
