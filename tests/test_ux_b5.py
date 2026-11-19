"""UX review 2026-11-19, batch B5: Adventurer's Journal wording, row markers, map buttons and README accuracy."""
import inspect
import pathlib
import re
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_optional import game as rewards_game
from test_loot import game as loot_game, click
from test_dungeon_quests import game as dungeon_game, HOVER_DATA, hover, tooltip, chain_text, plain, filters, rows_by_id, border_on

STYLES = ("modern", "classic")
ROOT = pathlib.Path(__file__).resolve().parent.parent
WAYPOINT = 'WAYPOINT=nil;UiMapPoint={CreateFromCoordinates=function(map,x,y)return {map=map,x=x,y=y} end};C_Map.SetUserWaypoint=function(p)WAYPOINT=p end'


def press(g, label):
    g.run('for _,f in ipairs(FRAMES) do if f.text==%r then f.scripts.OnClick(f,"LeftButton"); break end end' % label)


# ---- UX-16: an empty list explains the blue-or-better rule ----------------------------------------------------
def test_rewards_empty_list_explains_only_blue_items_are_listed(style):
    g = rewards_game(style, "for _,r in pairs(REWARD_ITEMS) do r.quality=2 end")
    g.slash("rewards")
    w = g.eval("NS.rewards._window()")
    assert not g.eval("NS.rewards._results()").values() or len(g.eval("NS.rewards._results()")) == 0
    assert "Only blue (rare) and better items are listed" in w.status.text, w.status.text
    assert "most quest rewards at this level are green" in w.route.text, w.route.text


def test_instance_drops_empty_list_explains_only_blue_items_are_listed(style):
    g = loot_game(style, "for _,r in pairs(LOOT_ITEMS) do r.quality=2 end")
    g.slash("loot")
    w = g.eval("NS.loot._window()")
    assert "Only blue (rare) and better items are listed" in w.status.text, w.status.text
    assert "many dungeon drops are green" in w.detailsText.text, w.detailsText.text


# ---- UX-19: missing data says what to install, in player words -------------------------------------------------
def test_instance_drops_without_any_catalogue_puts_install_hint_in_status(style):
    g = loot_game(style, "AtlasLoot=nil;ItemDB.GetAllIds=nil;LibQuestieDB.Item=nil")
    g.slash("loot")
    status = g.eval("NS.loot._window().status.text")
    assert "No matching" not in status and "Install" in status and "/qs questie" in status, status


def test_rewards_and_dungeon_quests_missing_data_use_plain_words(style):
    g = rewards_game(style, "ItemDB.GetAllIds=nil")
    g.slash("rewards")
    status = g.eval("NS.rewards._window().status.text")
    assert "Install or update QuestieDB (see /qs questie)" in status and "enumerable" not in status, status
    g = rewards_game(style, "LibQuestieDB.Enum=nil")
    g.slash("rewards")
    status = g.eval("NS.rewards._window().status.text")
    assert "Install or update QuestieDB (see /qs questie)" in status and "mappings" not in status, status
    g = dungeon_game(style, "QuestDB.GetAllIds=nil", False)
    g.slash("dungeons"); g.advance(1)
    status = g.eval("NS.dungeonQuests._window().status.text")
    assert "Install or update QuestieDB (see /qs questie)" in status and "enumerable" not in status, status
    g = dungeon_game(style, "LibQuestieDB.Enum=nil")
    click(g.eval("NS.dungeonQuests._window()").mine)
    status = g.eval("NS.dungeonQuests._window().status.text")
    assert "Install or update QuestieDB (see /qs questie)" in status and "mappings" not in status, status


# ---- UX-18: gold is selection only; ! = to pick up, ? = in your log ------------------------------------------
def test_dungeon_rows_mark_to_take_with_exclamation_and_in_log_with_question_mark(style):
    g = dungeon_game(style, HOVER_DATA); filters(g, dungeon=1581)
    g.run("QUESTS[#QUESTS+1]={id=2,title='A dungeon job',level=20,objectives={}}")
    g.fire("QUEST_LOG_UPDATE"); g.advance(.3)
    rows = rows_by_id(g)
    assert "ActiveQuestIcon" in rows[2].icon.texture, rows[2].icon.texture
    assert "AvailableQuestIcon" in rows[3].icon.texture, rows[3].icon.texture
    assert not any(border_on(r) for r in rows.values()), "no gold 'to take' border: gold means selected"
    status = g.eval("NS.dungeonQuests._window().status.text")
    assert "gold border" not in status and "!: to pick up" in status and "?: in your log" in status, status


# ---- UX-30: quest level and quest ID are never both written as '(quest N)' -----------------------------------
def test_rewards_say_quest_level_and_dungeon_quests_say_quest_id(style):
    g = rewards_game(style); g.slash("rewards")
    w = g.eval("NS.rewards._window()")
    w.rows[1].frame.scripts.OnClick(w.rows[1].frame)
    assert "(quest level 20, requires level 15)" in w.route.text, w.route.text
    assert "(quest 20" not in w.route.text
    g = dungeon_game(style, HOVER_DATA); filters(g, dungeon=1581)
    hover(g, 3)
    assert "A dungeon job (quest ID 2)" in tooltip(g), tooltip(g)


# ---- UX-31: no raw field names in the journal ------------------------------------------------------------------
def test_dungeon_details_hide_raw_chain_fields_unless_debug_logging_is_on(style):
    g = dungeon_game(style, HOVER_DATA); filters(g, dungeon=1581)
    g.run("NS.db.debug=false")      # the test harness logs by default
    text = plain(chain_text(g, 2))
    assert "preQuestSingle" not in text and "Questie data" not in text, text
    assert "no chain links" not in plain(chain_text(g, 4))
    g.run("NS.db.debug=true")
    assert "preQuestSingle=1" in plain(chain_text(g, 2))


def test_reward_extra_requirements_use_plain_words(style):
    g = rewards_game(style, "QUESTIE_QUESTS[8000].requiredSkill={186,50};QUESTIE_QUESTS[8000].requiredMinRep={72,3000};"
                            "QUESTIE_QUESTS[8000].requiredSpell=1234")
    g.slash("rewards")
    w = g.eval("NS.rewards._window()")
    w.rows[1].frame.scripts.OnClick(w.rows[1].frame)
    text = w.route.text
    for raw in ("requiredSkill", "requiredMinRep", "requiredSpell"):
        assert raw not in text, text
    assert "Needs a profession skill" in text and "Needs reputation" in text and "Needs a spell" in text, text


# ---- UX-32: both map buttons mark the quest giver the same way --------------------------------------------------
def test_reward_map_button_marks_the_quest_giver_like_dungeon_quests(style):
    g = rewards_game(style, WAYPOINT); g.slash("rewards")
    w = g.eval("NS.rewards._window()")
    w.rows[1].frame.scripts.OnClick(w.rows[1].frame)
    press(g, "Mark quest giver (then press M)")
    pt = g.eval("WAYPOINT")
    assert pt is not None and pt.map == 1429 and abs(pt.x - .4892) < .0001 and abs(pt.y - .4161) < .0001
    out = "\n".join(g.printed())
    assert "map pin: Marshal McBride" in out and g.eval("#MAP_OPENS") == 0, out
    g = dungeon_game(style)
    g.eval("NS.dungeonQuests.menu")(2)
    menu, _ = g.eval("NS._questMenu()")
    assert any(x.text == "Mark quest giver (then press M)" for x in menu["items"].values())
    assert not any("(open M)" in x.text for x in menu["items"].values())


# ---- README (UX-16, UX-18, UX-23, UX-24, UX-29, UX-32) --------------------------------------------------------
def test_readme_matches_the_addon():
    text = (ROOT / "README.md").read_text()
    core = (ROOT / "QuestSharing" / "Core.lua").read_text()
    assert "a level-20 Alliance Druid can find staffs, leather and cloth rewards from ordinary quests" not in text
    assert "most quest rewards at levelling levels are green" in text
    assert 'a gold border the ones you still have to pick up' not in text
    assert "Quest and equipment explorer" not in text and "equipment explorer" not in text
    assert "(open M)" not in text and "Mark quest giver (then press M)" in text
    # minimap: three shortcut buttons, report on Errors & logs
    assert "Two shortcut buttons" not in text and "Three shortcut buttons" in text
    assert "General > Copy logs" not in text
    # commands table rows
    for cmd in ("`/qs lfg", "`/qs ilvl`", "`/qs dungeons"):
        assert re.search(r"^\| " + re.escape(cmd), text, re.M), cmd
    # a numbered Party finder section
    assert re.search(r"^#+ .*Party finder", text, re.M)
    # settings that no longer exist / old labels
    for old in ("Show it when I am not in a party too", "Send the message at once", "Auto messages go to", "**Clear camp wait**",
                "**Plan** button chooses"):
        assert old not in text, old
    assert "Also show the Party quests window when playing alone" in text
    assert "Send quick chat messages without pressing Enter" in text and "Who receives messages set to Automatic" in text
    assert "Errors & logs > Check my setup, errors and logs" in text
    # UX-29/UX-32/UX-04/UX-27: one name for the Journal, real Settings row, real button, real reset scope
    assert "the browser" not in text and "their browsers" not in text
    assert "*Settings > Items & dungeons > Instance drops*" in text and "Items & dungeons > Dungeon loot" not in text
    assert "map directions refer" not in text and "**Mark quest giver** uses the first quest listed" in text
    assert "(everything on)" not in text and "**Quest planner.**" not in text
    # defaults in the commands table follow Core.lua
    assert re.search(r"\bchat\s*=\s*false", core) and re.search(r"\bannounce\s*=\s*false", core)
    for row in [l for l in text.splitlines() if l.startswith("| `/qs chat") or l.startswith("| `/qs announce")]:
        assert "default on" not in row, row


# ==== Low findings (UX-52..UX-73) ==============================================================================
IN_CAVERNS = '''IN_INSTANCE=true
function GetInstanceInfo() return "Wailing Caverns","party",1,"Normal",5,0,false,43 end
'''


# ---- UX-52: Dungeon quests opens on the dungeon you are in --------------------------------------------------
def test_dungeon_quests_open_on_the_dungeon_you_are_in(style):
    g = dungeon_game(style, IN_CAVERNS, False)
    g.slash("dungeons"); g.advance(90)
    w = g.eval("NS.dungeonQuests._window()")
    assert "Wailing Caverns" in w.dungeon.text, w.dungeon.text
    assert {r.id for r in g.eval("NS.dungeonQuests._results()").values()} <= {8, 9}
    # a dungeon you chose yourself stays chosen until the next open
    filters(g, dungeon=1581)
    g.run("NS.dungeonQuests.refresh()")
    assert "The Deadmines" in w.dungeon.text


def test_dungeon_quests_outdoors_keep_all_dungeons(style):
    g = dungeon_game(style, "", False)
    g.slash("dungeons"); g.advance(90)
    assert "All dungeons" in g.eval("NS.dungeonQuests._window()").dungeon.text


# ---- UX-53: the details follow a filter change even when the same quest stays selected ----------------------
def test_dungeon_quest_details_redraw_after_the_dungeon_filter_changes(style):
    g = dungeon_game(style, HOVER_DATA)
    g.run("DETAIL_DRAWS=0;local w=NS.dungeonQuests._window();local old=w.showQuest;"
          "w.showQuest=function(r) DETAIL_DRAWS=DETAIL_DRAWS+1;return old(r) end")
    filters(g, dungeon=1581)
    before = g.eval("DETAIL_DRAWS")
    filters(g, dungeon=0)
    assert g.eval("DETAIL_DRAWS") > before, "changing the dungeon filter redraws the details"


# ---- UX-54: opening Quest rewards does not flip a Settings switch ----------------------------------------------
def test_opening_quest_rewards_does_not_change_a_setting(style):
    g = rewards_game(style)
    g.slash("rewards")
    assert g.eval("NS.db.rewardBrowser") is None
    assert g.eval("NS.rewards._window().frame.shown") and len(g.eval("NS.rewards._results()")) > 0



def test_repeated_qs_on_keeps_an_open_quest_rewards_tab_and_its_results(style):
    g = rewards_game(style)
    g.slash("rewards")
    before = len(g.eval("NS.rewards._results()"))
    assert before > 0 and g.eval("NS.rewards._window().frame.shown")
    g.slash("on")
    assert g.eval("NS.rewards._window().frame.shown")
    assert g.eval("(NS.rewards._state())") is True
    assert len(g.eval("NS.rewards._results()")) == before


def test_master_switch_off_still_closes_the_rewards_tab(style):
    g = rewards_game(style)
    g.slash("rewards")
    assert g.eval("NS.rewards._window().frame.shown")
    g.run('NS.setSetting("enabled",false)')
    assert not g.eval("NS.rewards._window().frame.shown")
    assert g.eval("(NS.rewards._state())") is False


def test_quest_rewards_has_no_switch_of_its_own(style):
    g = rewards_game(style)
    assert g.eval("NS.db.rewardBrowser") is None
    assert not g.eval("(function() for _, r in ipairs(NS.settingRows) do if r.key == 'rewardBrowser' then return true end end end)()")
    g.slash("rewards off")
    assert g.eval("NS.rewards._window().frame.shown"), "/qs rewards with any word just opens the tab"

# ---- UX-64 / UX-74: Bag cleanup names QuestieDB and the backpack ---------------------------------------------
def test_bag_cleanup_names_questiedb_like_the_settings_card():
    text = (ROOT / "QuestSharing" / "QuestCleanup.lua").read_text()
    assert "Questie data is required" not in text and "missing from Questie." not in text
    assert "QuestieDB is required" in text and '"Backpack"' in text
    bags = (ROOT / "QuestSharing" / "Bags.lua").read_text()
    assert 'r.here and "in this zone"' in bags


# ---- UX-69: ingredient tooltips in player words, with the faction of the water -------------------------------
def test_fish_tooltip_uses_plain_words_and_tags_the_other_factions_water(style):
    from test_professions import game as profession_game
    g = profession_game(style)
    text = "\n".join(g.eval("NS.professions.materialLines(6303)").values())
    assert "Durotar (Horde area)" in text, text
    text = "\n".join(g.eval("NS.professions.materialLines(6289)").values())
    assert "Fish stay hooked from skill 75" in text, text
    for jargon in ("no-getaway", "effective skill", "client reference"):
        assert jargon not in text, text
    g.run("NS.professions.clearCaches()")
    text = "\n".join(g.eval("NS.professions.materialLines(159)").values())
    assert "Sold by vendors (seller not known)" in text and "client reference" not in text, text


# ---- UX-70: no "req 0", no "1 tables", "scroll to browse" only with more pages ------------------------------
def test_journal_rows_and_status_leave_out_meaningless_values(style):
    g = loot_game(style)
    g.run("NS.db.debug=false")
    g.slash("loot")
    w = g.eval("NS.loot._window()")
    texts = [r.item.text for r in w.rows.values() if r.frame.shown]
    assert any("Cookie's Ladle" in t for t in texts) and not any("req 0" in t for t in texts), texts
    assert "tables" not in w.note.text, w.note.text
    assert "scroll to browse" not in w.status.text, w.status.text
    g.run("NS.db.debug=true"); g.slash("loot")
    assert "1 table could not be read" in w.note.text, w.note.text
    status = g.eval("NS.equipmentUI.pageStatus")
    assert status(1, 8, 1) == "1 item", status(1, 8, 1)
    assert "scroll to browse" in status(1, 8, 20) and "scroll to browse" not in status(1, 8, 5)
    g = rewards_game(style, "for _,r in pairs(REWARD_ITEMS) do r.requiredLevel=1 end")
    g.slash("rewards")
    texts = [r.item.text for r in g.eval("NS.rewards._window()").rows.values() if r.frame.shown]
    assert texts and not any("req" in t for t in texts), texts


# ---- UX-71: source lines in parchment tan, the chosen dungeon in gold ------------------------------------------
def test_source_lines_are_tan_and_the_chosen_dungeon_is_gold(style):
    g = loot_game(style)
    g.slash("loot")
    w = g.eval("NS.loot._window()")
    row = next(r for r in w.rows.values() if r.frame.shown)
    assert row["from"].text.startswith("|cffccb88f"), row["from"].text
    click(next(b for b in w.instances.values() if b.place and b.place.name == "The Deadmines"))
    chosen = next(b for b in w.instances.values() if b.place and b.place.name == "The Deadmines")
    assert "> " not in chosen.text and g.eval("NS.style.GOLD") in chosen.text, chosen.text


# ---- UX-72: the same filters look and read the same in both quest tabs -----------------------------------------
def test_rewards_and_dungeon_quests_share_filter_controls_and_wording(style):
    g = rewards_game(style); g.slash("rewards")
    w = g.eval("NS.rewards._window()")
    assert "Hide completed quests" in w.completed.text.text and w.completed.tick.shown
    click(w.completed)
    assert not w.completed.tick.shown
    assert w.near.text.startswith("Quest levels: ")
    g = dungeon_game(style)
    d = g.eval("NS.dungeonQuests._window()")
    assert d.levelMode.text == "Quest levels: all", d.levelMode.text
    click(d.levelMode)
    assert d.levelMode.text.startswith("Quest levels: for level "), d.levelMode.text
    assert d.faction.text.startswith("Faction: ") and d["class"].text.startswith("Class: "), (d.faction.text, d["class"].text)


# ---- UX-73: spell rank messages in plain words ------------------------------------------------------------------
def test_spell_rank_messages_use_plain_words(style):
    from test_spell_ranks import game as ranks_game
    g = ranks_game(style, "PlaceAction=nil")
    g.eval("NS.spellRanks.update")(True)
    out = "\n".join(g.printed())
    assert "this game version cannot change action bar spells" in out and "expose" not in out, out
    g = ranks_game(style, 'GetCursorInfo=function()error("unavailable")end')
    g.eval("NS.spellRanks.update")(True)
    out = "\n".join(g.printed())
    assert "could not read your cursor" in out and "The client" not in out, out
    text = (ROOT / "QuestSharing" / "SpellRanks.lua").read_text()
    assert "spell-book/action-bar APIs" not in text and "has any client errors" not in text
    assert "spell ranks paused until /reload" in text


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total += 1
            try:
                fn(style) if style else fn()
                print("ok", name, style)
            except Exception as error:
                failed += 1
                print("FAIL", name, style, type(error).__name__, str(error)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
