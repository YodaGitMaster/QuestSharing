"""Bosses fix, stream U: the calm Bosses page (DungeonBossesUI.lua) and the T.round / T.badge options (JournalTheme.lua).
NS.loot.bossesOf is stubbed with official-shaped rows, so these tests do not depend on the data or logic streams."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_loot import game as loot_game
from test_dungeon_journal_bosses import ATLAS, shown_rows, shown_loot

STYLES = ("modern", "classic")
MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
HINT = "Install AtlasLoot for full drops."

# Font strings record their colour (the harness mock has no SetTextColor); set before the addon loads.
TEXT_COLOR = r'''
local cf = CreateFrame
function CreateFrame(...)
    local f = cf(...)
    local cfs = f.CreateFontString
    f.CreateFontString = function(self, ...)
        local fs = cfs(self, ...)
        fs.SetTextColor = function(s, r, g, b) s.color = { r, g, b } end
        return fs
    end
    return f
end
'''

# official-shaped rows as stream L returns them (official = true, items, level)
OFFICIAL = r'''
local function boss(o) o.official = true; o.items = o.items or {}; return o end
OFFICIAL = {
  [1581] = {
    boss{ name="Rhahk'Zor", order=1, npcID=644, npcIDs={644}, level=19, ejFile=1385733, items={10001, 10003} },
    boss{ name="Sneed", order=2, npcID=643, npcIDs={643}, lootNpcIDs={642}, level=20, displayID=7125 },
    boss{ name="Miner Johnson", order=3, npcID=3586, npcIDs={3586}, level=19, optional=true },
    boss{ name="Gilnid", order=4, npcID=1763, npcIDs={1763}, level=20, displayID=7124, items={10003} },
    boss{ name="Captain Greenskin", order=5, npcID=647, npcIDs={647}, level=20, displayID=7113 },
    boss{ name="Mr. Smite", order=6, npcID=646, npcIDs={646}, level=20, displayID=2026 },
    boss{ name="Edwin VanCleef", order=7, npcID=639, npcIDs={639}, level=21, displayID=2029, items={10001} },
    boss{ name="Cookie", order=8, npcID=645, npcIDs={645}, level=20, displayID=1305 },
  },
  [1337] = {
    boss{ name="The Lost Dwarves", order=1, npcID=6906, npcIDs={6906, 6907, 6908}, group=true,
          members={"Baelog", "Olaf", "Eric 'The Swift'"}, level=41 },
    boss{ name="Revelosh", order=2, npcID=6910, npcIDs={6910}, level=40 },
  },
  [16611] = { -- Forever-only: the same-named journal art belongs to another creature
    boss{ name="Edwin VanCleef", order=1, npcID=250001, npcIDs={250001}, level=60 },
    boss{ name="Edwin VanCleef", order=2, npcID=250002, npcIDs={250002}, level=60, displayID=91001 },
  },
  [1584] = {},
  [209] = {},
}
for i = 1, 30 do
  local items = {}
  for k = 1, (i == 1 and 20 or 1) do items[k] = 10000 + k end
  table.insert(OFFICIAL[1584], boss{ name="Boss "..i, order=i, npcID=8000+i, npcIDs={8000+i}, level=50, displayID=5000+i, items=items })
end
for i = 1, 3 do table.insert(OFFICIAL[209], boss{ name="Zul "..i, order=i, npcID=7000+i, npcIDs={7000+i}, level=45, displayID=6000+i }) end
BOSS_SOURCE, BOSS_REASON = "AtlasLoot", nil
NS.loot.bossesOf = function(name, done, area)
  local list = OFFICIAL[tonumber(area)] or {}
  if done then done(list, BOSS_SOURCE, BOSS_REASON) end
  return list, BOSS_SOURCE, BOSS_REASON
end
function WALK(o, seen, out)
  seen, out = seen or {}, out or {}
  if type(o) ~= "table" or seen[o] then return out end
  seen[o] = true
  if o.texture ~= nil then out[#out + 1] = tostring(o.texture) end
  for _, c in ipairs(o.children or {}) do WALK(c, seen, out) end
  return out
end
'''


def game(style, extra=""):
    g = loot_game(style, TEXT_COLOR + ATLAS)
    g.run(OFFICIAL)
    if extra:
        g.run(extra)
    return g


def page(g, area=1581, name="The Deadmines"):
    B = g.eval("NS.dungeonBossesUI")
    assert B.build(g.eval("CreateFrame('Frame')"), 1000, 560) is not None
    B.show(area, name)
    return B, g.eval("NS.dungeonBossesUI._window()")


def lua(g, expr):
    return g.eval(expr)


def same(g, a, b):  # Lua identity (lupa wrappers of one table do not compare equal in Python)
    return g.eval("function(a, b) return a == b end")(a, b)


def vals(t):
    return [round(v, 3) for v in t.values()]


def live(g):
    return list(g.eval("NS.dungeonBossesUI._portraits()").values())


def row_named(w, name):
    return next(r for r in shown_rows(w) if r.name.text == name)


def test_row_and_header_geometry(style):
    g = game(style)
    B, w = page(g)
    rows = shown_rows(w)
    assert len(rows) == 8 and w.rowCount == 8
    r1, r2 = rows[0], rows[1]
    assert r1.width == 314 and r1.height == 52
    assert r1.point[4] == 10 and r1.point[5] == -44 and r2.point[5] == -104      # x inset 10, pitch 60
    assert r1.portrait.width == 44 and list(r1.portrait.point.values())[2:] == ["LEFT", 5, 0]
    assert r1.name.point[4] == 62 and r1.name.width == 314 - 72 and r1.name.wordWrap is False
    assert r1.name.font[2] == 12
    assert w.portrait.width == 68 and w.portrait.point[4] == 16 and w.portrait.point[5] == -14
    assert w.name.point[4] == 100 and w.name.point[5] == -30 and w.name.font[2] == 16
    assert vals(w.name.color) == [.93, .84, .66]
    assert w.facts.point[4] == 100 and w.facts.point[5] == -54 and w.facts.font[2] == 10
    loot = [b for b in w.loot.values()]
    assert loot[0].width == 384 and loot[0].height == 50
    assert loot[1].point[5] - loot[0].point[5] == -59                         # pitch 59
    assert not g.eval("NS.db.errors")


def test_flat_rows_no_edge_no_parchment_no_gold_ring(style):
    g = game(style)
    B, w = page(g)
    for r in w.rows.values():
        assert r.jEdge is None and r.jPage is None
        assert vals(r.bg.rgba) == [.145, .094, .043, 1]
        assert vals(r.top.rgba) == [.35, .24, .11, .6] and r.top.height == 1
        assert vals(r.bottom.rgba) == [0, 0, 0, .5] and r.bottom.height == 1
        assert r.portrait.jRing is None and r.portrait.back.texture == MASK
        assert vals(r.portrait.back.vertex) == [.055, .047, .04, 1]
        assert r.hl.texture == "Interface\\QuestFrame\\UI-QuestTitleHighlight" and round(r.hl.jAlpha, 2) == .35
    for b in w.loot.values():
        assert b.jEdge is None and b.jPage is None
        assert vals(b.bg.rgba) == [.145, .094, .043, 1]
        assert all(not e.shown for e in b.edges.values())
    assert not w.left.jPage.shown and not w.right.jPage.shown
    assert w.portrait.jRing is None
    textures = list(g.eval("WALK(NS.dungeonBossesUI._window().frame)").values())
    assert not [t for t in textures if "GoldRing" in t or "TrackingBorder" in t], textures


def test_selected_row_fill_outline_and_name_colour(style):
    g = game(style)
    B, w = page(g)
    rows = shown_rows(w)
    assert rows[0].sel.shown and vals(rows[0].sel.rgba) == [.34, .23, .11, 1]
    edges = list(rows[0].selEdges.values())
    assert len(edges) == 4 and all(e.shown for e in edges) and vals(edges[0].rgba) == [.80, .57, .21, .8]
    assert not rows[1].sel.shown and not any(e.shown for e in rows[1].selEdges.values())
    assert vals(rows[0].name.color) == [.95, .75, .32] and vals(rows[1].name.color) == [.82, .75, .60]
    rows[1].scripts.OnClick(rows[1], "LeftButton")
    assert rows[1].sel.shown and not rows[0].sel.shown and vals(rows[0].name.color) == [.82, .75, .60]


def test_flat_badge_look_and_anchor(style):
    g = game(style)
    B, w = page(g)
    r = shown_rows(w)[0]
    b = r.badge
    assert b.flat and b.width == 24 and b.shown and b.text.text == "19"
    assert b.ring.texture == MASK and b.ring.width == 26 and vals(b.ring.vertex) == [.80, .57, .21, 1]
    assert b.disc.texture == MASK and b.disc.width == 24 and vals(b.disc.vertex) == [.055, .047, .04, 1]
    assert b.text.font[2] == 11 and vals(b.text.color) == [1, 1, 1]
    assert lua(g, "(function() local r = NS.dungeonBossesUI._window().rows[1]; local p = r.badge.point;"
                  " return p[1] == 'CENTER' and p[2] == r.portrait and p[3] == 'BOTTOMLEFT' and p[4] == 9 and p[5] == 3 end)()")
    hb = w.badge
    assert hb.flat and hb.width == 30 and hb.ring.width == 32 and hb.text.font[2] == 13 and hb.text.text == "19"
    assert lua(g, "(function() local w = NS.dungeonBossesUI._window(); local p = w.badge.point;"
                  " return p[1] == 'CENTER' and p[2] == w.portrait and p[3] == 'BOTTOMLEFT' and p[4] == 7 and p[5] == 3 end)()")
    # the badge hangs about 6px under its row and stays inside the 8px gap (row bottom 4px under the portrait)
    overhang = 12 + 1 - (52 - 44) / 2 - 3
    assert 0 < overhang < 8


def test_portrait_chain_ejfile_then_name_then_staged_display_then_skull(style):
    g = game(style)
    B, w = page(g)
    by = {r.name.text: r.portrait for r in shown_rows(w)}
    rz = by["Rhahk'Zor"]
    assert rz.source == "journal" and rz.texture == 1385733 and rz.ejFile == 1385733 and rz.journalPath is None
    assert list(rz.coords.values()) == [.25, .75, 0, 1]
    ed = by["Edwin VanCleef"]                                        # no ejFile: by name in a classic area
    assert ed.source == "journal" and ed.journalPath == "Interface\\EncounterJournal\\UI-EJ-BOSS-Edwin VanCleef" and ed.ejFile is None
    sn = by["Sneed"]
    assert sn.source == "display" and sn.displayID == 7125
    mj = by["Miner Johnson"]                                         # nothing known: the muted skull
    assert mj.source == "skull" and mj.texture == SKULL
    assert vals(mj.vertex)[:3] == [.55, .50, .45] and round(mj.jAlpha, 2) == .6
    assert mj.back.texture == MASK and mj.back.shown
    # a boss with ejFile wins over a by-name hit and a display
    assert g.eval("NS.dungeonBossesUI.portrait(UIParent:CreateTexture(), {name='Edwin VanCleef', ejFile=42, displayID=1}, 1581)") == "journal"
    assert not g.eval("NS.db.errors")


def test_by_name_journal_art_is_ignored_in_forever_areas(style):
    g = game(style)
    B, w = page(g, 16611, "Forever place")
    rows = shown_rows(w)
    assert [r.portrait.source for r in rows] == ["skull", "display"]
    assert rows[0].portrait.journalPath is None and rows[0].portrait.texture == SKULL
    P = g.eval("NS.dungeonBossesUI.portrait")
    assert P(g.eval("UIParent:CreateTexture()"), g.eval("{name='Edwin VanCleef'}"), 16611) == "skull"
    assert P(g.eval("UIParent:CreateTexture()"), g.eval("{name='Edwin VanCleef'}"), 1581) == "journal"
    assert P(g.eval("UIParent:CreateTexture()"), g.eval("{name='Edwin VanCleef', ejFile=7}"), 16611) == "journal"  # ejFile is fine


def test_staged_display_moves_to_the_host_after_three_seconds(style):
    g = game(style)
    B, w = page(g)
    sn = row_named(w, "Sneed")
    row = row_named(w, "Sneed")
    e = next(x for x in live(g) if x.id == 7125)
    stage = w.stage
    assert stage.point[2] is not None and stage.point[3] == "TOPRIGHT" and stage.point[4] == 10000 and stage.width == 64
    assert same(g, e.tex.parent, stage) and not e.attached and sn.portrait.staged is None
    assert e.tex.displayID == 7125                                   # rendered into the stage texture, not the host
    assert sn.portrait.shown and sn.portrait.texture == SKULL        # the placeholder meanwhile
    g.advance(2.5)
    assert not e.attached and same(g, e.tex.parent, stage), "not before 3 s"
    g.advance(1)
    assert e.attached and lua(g, "(function() for _, e in ipairs(NS.dungeonBossesUI._portraits()) do"
                                 " if e.id == 7125 then return e.tex.parent == e.host.parent end end end)()")
    assert same(g, sn.portrait.staged, e.tex) and not sn.portrait.shown and e.tex.shown
    assert e.tex.width == 44 and list(e.tex.coords.values()) == [0, 1, 0, 1]
    assert list(e.tex.point.values())[2:] == ["LEFT", 5, 0]          # the host's points
    assert row.shown
    B.refresh()                                                      # a repaint keeps it attached
    assert e.attached and not sn.portrait.shown
    assert not g.eval("NS.db.errors")


def test_header_gets_its_own_staged_portrait(style):
    g = game(style)
    B, w = page(g)
    sneed = row_named(w, "Sneed")
    sneed.scripts.OnClick(sneed, "LeftButton")
    assert w.portrait.source == "display"
    mine = [x for x in live(g) if x.id == 7125]
    assert len(mine) == 2                                            # one per host: row and header
    g.advance(3.5)
    assert w.portrait.staged is not None and w.portrait.staged.width == 68 and not w.portrait.shown
    rz = row_named(w, "Rhahk'Zor")
    rz.scripts.OnClick(rz, "LeftButton")                             # back to journal art: the staged one leaves
    assert w.portrait.staged is None and w.portrait.shown and w.portrait.source == "journal"


def test_max_live_cap_lru_and_cache_reuse(style):
    g = game(style)
    B, w = page(g, 1584, "Blackrock Depths")
    assert len(live(g)) == 9                                         # 8 rows + the header
    g.advance(3.5)
    B.scroll(8); g.advance(3.5)
    assert len(live(g)) == 17
    B.scroll(8); g.advance(3.5)                                      # rows 17-24 need 8 more: the cap is 24
    entries = live(g)
    assert len(entries) == 24
    ids = [x.id for x in entries]
    assert ids.count(5001) == 1, "the least recently used row portrait (boss 1) was evicted; the header keeps its own"
    assert 5002 in ids and all(5016 + k in ids for k in range(1, 9))
    B.scroll(-8)                                                     # back to rows 9-16: cached portraits attach at once
    row9 = row_named(w, "Boss 9")
    assert row9.portrait.staged is not None and not row9.portrait.shown
    assert all(row_named(w, "Boss %d" % k).portrait.staged is not None for k in range(9, 17))
    assert len(live(g)) == 24
    assert not g.eval("NS.db.errors")


def test_release_on_hide_area_change_and_leaving_world(style):
    g = game(style)
    B, w = page(g)
    g.advance(3.5)
    sn = row_named(w, "Sneed")
    assert sn.portrait.staged is not None
    B.hide()
    assert all(x.id is None and x.tex.texture is None and not x.attached for x in live(g))
    assert sn.portrait.staged is None
    B.show(1581, "The Deadmines")
    e = next(x for x in live(g) if x.id == 7125)
    assert not e.attached
    g.advance(3.5)
    assert e.attached
    B.show(209, "Zul'Farrak")                                        # another dungeon
    ids = [x.id for x in live(g)]
    assert 7125 not in ids and 6001 in ids
    assert len(live(g)) <= 24
    g.advance(3.5)
    assert any(x.attached for x in live(g))
    g.fire("PLAYER_LEAVING_WORLD")
    assert all(x.id is None and x.tex.texture is None and not x.attached for x in live(g))
    assert all(r.portrait.staged is None for r in shown_rows(w))
    B.show(209, "Zul'Farrak")                                        # same area: no release, staged again
    assert [x.id for x in live(g) if x.id] and not any(x.attached for x in live(g))
    assert not g.eval("NS.db.errors")


def test_stale_portrait_timer_does_nothing(style):
    g = game(style)
    B, w = page(g, 1584, "Blackrock Depths")
    first = next(x for x in live(g) if x.id == 5002)
    host = shown_rows(w)[1].portrait
    B.scroll(8)                                                      # the row now shows boss 10
    g.advance(3.5)
    assert same(g, first.tex.parent, w.stage) and not first.attached, "the old boss never lands on the reused row"
    assert host.staged is not None and lua(g, "(function() local r = NS.dungeonBossesUI._window().rows[2];"
                                              " return r.portrait.jLive.id == 5010 end)()")
    # page hidden while waiting: nothing attaches
    g = game(style)
    B, w = page(g)
    B.hide(); g.advance(3.5)
    assert not any(x.attached for x in live(g))
    # token changed (hide + show): only the new timers attach, 3 s after the new show
    B.show(1581, "The Deadmines")
    g.advance(2)
    assert not any(x.attached for x in live(g))
    g.advance(1.5)
    assert any(x.attached for x in live(g))


def test_official_facts_have_no_rank_and_optional_is_marked(style):
    g = game(style, r'''
local get=NS.questie.get
NS.questie.get=function(kind,id,key) if kind=="npc" and key=="rank" then return 2 end return get(kind,id,key) end
''')
    B, w = page(g)
    assert w.facts.text == "Level 19 · 2 drops"                      # no "Rare Elite"
    F = g.eval("NS.dungeonBossesUI.facts")
    assert F(g.eval("{official=true,level=21,npcID=639,items={1,2,3,4,5,6,7,8,9,10}}")) == "Level 21 · 10 drops"
    assert F(g.eval("{level=30,rare=true,items={1,2,3}}")) == "Level 30 · Rare · 3 drops"   # legacy keeps the rank
    mj = row_named(w, "Miner Johnson")
    mj.scripts.OnClick(mj, "LeftButton")
    assert w.facts.text == "Level 19 · 0 drops (optional)" and mj.name.text == "Miner Johnson"
    assert w.status.text == "No drops listed for Miner Johnson."


def test_footer_only_when_the_list_overflows(style):
    g = game(style)
    B, w = page(g)
    assert not w.leftStatus.shown and w.leftStatus.text == ""        # Deadmines: 8 bosses fit
    B.show(1584, "Blackrock Depths")
    assert w.leftStatus.shown and w.leftStatus.text == "1-8 of 30"
    B.scroll(3)
    assert w.leftStatus.text == "4-11 of 30" and "wheel" not in w.leftStatus.text


def test_drop_counter_and_atlasloot_hint_once(style):
    g = game(style)
    B, w = page(g, 1584, "Blackrock Depths")                         # Boss 1 has 20 drops
    assert w.count.shown and w.count.text.startswith("1-") and w.count.text.endswith(" of 20 drops")
    assert "wheel" not in w.count.text and not w.note.shown          # AtlasLoot: no hint
    g.run('BOSS_SOURCE="QuestieDB"')
    B.show(1584, "Blackrock Depths")
    assert w.note.shown and w.note.text == HINT and HINT not in w.count.text
    assert vals(w.note.color) == [.82, .74, .60]
    texts = [w.status.text, w.note.text, w.count.text, w.leftStatus.text]
    assert sum(t.count("Install AtlasLoot") for t in texts) == 1
    assert w.count.point[5] == -(560 - 34) and w.note.point[5] == -(560 - 20)   # own lines
    two = shown_rows(w)[1]
    two.scripts.OnClick(two, "LeftButton")                           # 1 drop: no counter
    assert not w.count.shown and w.note.text == HINT
    # no bosses, no source: the reason in the status, the hint once below
    g.run('BOSS_SOURCE=nil; BOSS_REASON="Install compatible AtlasLoot, or QuestieDB."')
    B.show(0, "Nowhere Keep")
    assert w.status.text == "Install compatible AtlasLoot, or QuestieDB." and w.note.text == HINT
    assert not shown_rows(w) and not w.portrait.shown and not w.portrait.back.shown
    # loading: no hint yet
    g.run("NS.loot.bossesOf=function() return nil, nil, 'loading' end")
    B.show(1581, "The Deadmines")
    assert w.status.text == "Loading drops…" and not w.note.shown


def test_group_rows_list_members_on_hover(style):
    g = game(style)
    B, w = page(g, 1337, "Uldaman")
    rows = shown_rows(w)
    assert rows[0].name.text == "The Lost Dwarves"
    rows[0].scripts.OnEnter(rows[0])
    assert g.eval("TOOLTIP.shown") and g.eval("TOOLTIP.text") == "The Lost Dwarves"
    assert list(g.eval("TOOLTIP.lines").values()) == ["Baelog", "Olaf", "Eric 'The Swift'"]
    rows[0].scripts.OnLeave(rows[0])
    assert not g.eval("TOOLTIP.shown")
    rows[1].scripts.OnEnter(rows[1])                                 # a single boss: no tooltip
    assert not g.eval("TOOLTIP.shown")


def test_needed_for_tries_every_npc_id(style):
    g = game(style, "ASKED={}; NS.dungeonQuests.questsForNpc=function(id) ASKED[#ASKED+1]=id; if id==6908 then return {{id=1,name='Q'}} end return {} end")
    B, w = page(g, 1337, "Uldaman")
    assert list(g.eval("ASKED").values())[-3:] == [6906, 6907, 6908]
    assert [r.label.text for r in w.quests.values() if r.shown] == ["Q"]


def test_theme_round_and_badge_defaults_unchanged(style):
    g = game(style)
    T = g.eval("NS.journalTheme")
    icon = g.eval("UIParent:CreateTexture()")
    T.round(icon, g.eval("UIParent"), 40)
    assert icon.jRing.texture == "Interface\\Common\\GoldRing" and icon.width == 40
    bare = g.eval("UIParent:CreateTexture()")
    T.round(bare, g.eval("UIParent"), 40, g.eval("{ring=false}"))
    assert bare.jRing is None and bare.width == 40
    badge = T.badge(g.eval("UIParent"), 20, 28)
    assert badge.ring.texture.endswith("MiniMap-TrackingBorder") and badge.disc.texture == MASK and not badge.flat
    assert badge.text.text == "20" and badge.text.font is None
    flat = T.badge(g.eval("UIParent"), 7, 24, g.eval("{flat=true}"))
    assert flat.flat and flat.ring.texture == MASK and flat.ring.width == 26 and flat.text.font[2] == 11


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
