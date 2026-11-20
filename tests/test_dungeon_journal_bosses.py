"""Dungeon Journal "Bosses & drops": L.bossesOf from mocked AtlasLoot / QuestieDB tables and the DungeonBossesUI page."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_loot import game as loot_game
from test_dungeon_quests import game as quest_game

STYLES = ("modern", "classic")

# AtlasLoot boss fields as AtlasLootClassic ships them: npcID, Level, DisplayIDs = {{id}}.
ATLAS = r'''
local dm=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items
dm[1].Level=21; dm[1].DisplayIDs={{2029}}
dm[2].Level=20; dm[2].DisplayIDs={{1305}}
JOURNAL_ART={["Interface\\EncounterJournal\\UI-EJ-BOSS-Edwin VanCleef"]=1}
function GetFileIDFromPath(path) return JOURNAL_ART[path] end
PORTRAITS={}
function SetPortraitTextureFromCreatureDisplayID(texture,id) texture.displayID=id; PORTRAITS[#PORTRAITS+1]=id end
HYPERLINK,COMPARED=nil,false
GameTooltip.SetHyperlink=function(_,link) HYPERLINK=link end
function GameTooltip_ShowCompareItem() COMPARED=true end
INVTYPE_WEAPON="One-Hand"
'''

# No AtlasLoot: QuestieDB knows the dungeon captain (spawns inside The Deadmines) drops item 951.
QUESTIE = r'''
AtlasLoot=nil
local allIds=ItemDB.GetAllIds
ItemDB.GetAllIds=function() local ids=allIds(); ids[#ids+1]=951; return ids end
'''
# Enough item IDs that the scan needs several timer steps (100 per step).
SLOW = QUESTIE + r'''
local fewIds=ItemDB.GetAllIds
ItemDB.GetAllIds=function() local ids=fewIds(); for i=1,400 do table.insert(ids,1,800) end; return ids end
'''


def names(bosses):
    return [b.name for b in bosses.values()]


def items(boss):
    return list(boss["items"].values())


def page(g, area=1581, name="The Deadmines"):
    B = g.eval("NS.dungeonBossesUI")
    parent = g.eval("CreateFrame('Frame')")
    assert B.build(parent, 1000, 560) is not None
    B.show(area, name)
    return B, g.eval("NS.dungeonBossesUI._window()")


def shown_rows(w):
    return [r for r in w.rows.values() if r.shown]


def shown_loot(w):
    return [b for b in w.loot.values() if b.shown]


def test_atlas_bosses_keep_encounter_order_and_skip_trash_and_ignored(style):
    g = loot_game(style, ATLAS)
    got = []
    bosses, source, reason = g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: got.append(a))
    assert names(bosses) == ["Edwin VanCleef", "Cookie", "Chest"], names(bosses)
    assert source == "AtlasLoot" and reason is None
    assert len(got) == 1 and names(got[0][0]) == names(bosses)  # done is called exactly once, at once
    assert not g.eval("NS.db.errors")


def test_atlas_boss_fields_items_npc_display_and_level(style):
    g = loot_game(style, ATLAS)
    bosses = g.eval("NS.loot.bossesOf")("Deadmines")[0]  # "The" and punctuation do not matter
    edwin, cookie, chest = bosses[1], bosses[2], bosses[3]
    assert items(edwin) == [10001]  # Heroic aliases Normal; headings and negative ids are not items
    assert edwin.npcID == 639 and edwin.displayID == 2029 and edwin.level == 21
    assert items(cookie) == [10003] and cookie.displayID == 1305
    assert items(chest) == [10005] and chest.npcID is None and chest.displayID is None


def test_atlas_matches_by_area_and_reports_unknown_dungeons(style):
    g = loot_game(style, ATLAS)
    assert names(g.eval("NS.loot.bossesOf")("Some other name", None, 718)[0]) == ["Lord Cobrahn"]
    bosses, source, reason = g.eval("NS.loot.bossesOf")("Nowhere Keep")
    assert len(bosses) == 0 and source == "AtlasLoot" and "no table" in reason


def test_bosses_of_does_not_change_the_loot_browser(style):
    g = loot_game(style, ATLAS)
    g.eval("NS.loot.bossesOf")("The Deadmines")
    assert g.eval("NS.loot._window()") is None and g.eval("NS.loot._state()")[3] == 0
    g.slash("loot")
    assert g.eval("NS.loot._state()")[2] == "AtlasLoot" and len(g.eval("NS.loot._results()")) == 4


def test_questie_fallback_scans_in_background_and_calls_done(style):
    g = quest_game(style, SLOW, open_tab=False)
    got = []
    first = g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: got.append(a))
    assert first[0] is None and first[2] == "loading"
    g.advance(30)
    assert len(got) == 1, got
    bosses, source, reason = got[0]
    assert source == "QuestieDB" and names(bosses) == ["Dungeon captain"]
    assert bosses[1].npcID == 900 and items(bosses[1]) == [951]
    again = g.eval("NS.loot.bossesOf")("The Deadmines")  # the index is ready now: answered at once
    assert again[1] == "QuestieDB" and names(again[0]) == ["Dungeon captain"]
    assert not g.eval("NS.db.errors")


def test_background_scan_keeps_the_menu_and_a_one_step_scan_returns_at_once(style):
    g = quest_game(style, QUESTIE, open_tab=False)
    g.run("DISMISSED=0; local d=NS.equipmentUI.dismissMenu; NS.equipmentUI.dismissMenu=function(...) DISMISSED=DISMISSED+1; return d(...) end")
    got = []
    bosses, source, reason = g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: got.append(a))
    # the few IDs fit in the first synchronous step: the flushed list comes back now, and done ran once
    assert source == "QuestieDB" and names(bosses) == ["Dungeon captain"], (source, reason)
    assert len(got) == 1 and names(got[0][0]) == ["Dungeon captain"]
    assert g.eval("DISMISSED") == 0, "a bossesOf background scan does not close the user's menu"
    g.eval("NS.loot.scan")()
    assert g.eval("DISMISSED") == 1, "a scan the user starts still closes the menu"


def test_a_cancelled_background_scan_answers_its_waiters(style):
    for cancel in ("NS.loot.purge()", "NS.loot.scan()"):
        g = quest_game(style, SLOW, open_tab=False)
        got = []
        first = g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: got.append(a))
        assert first[2] == "loading"
        g.run(cancel)
        assert len(got) == 1 and len(got[0][0]) == 0 and got[0][1] is None and got[0][2], (cancel, got)
        g.advance(30)
        assert len(got) == 1, "done is called exactly once"
        # the background flag was reset: a later call starts a fresh background scan and is answered
        more = []
        g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: more.append(a))
        g.advance(30)
        assert len(more) == 1 and names(more[0][0]) == ["Dungeon captain"], (cancel, more)
        assert not g.eval("NS.db.errors")


def test_no_loot_source_returns_empty_with_reason(style):
    g = quest_game(style, "AtlasLoot=nil; ItemDB.GetAllIds=nil; LibQuestieDB.Item=nil", open_tab=False)
    got = []
    bosses, source, reason = g.eval("NS.loot.bossesOf")("The Deadmines", lambda *a: got.append(a))
    assert len(bosses) == 0 and source is None and "AtlasLoot" in reason
    assert len(got) == 1 and got[0][2] == reason


def test_page_rows_portrait_chain_and_badges(style):
    g = loot_game(style, ATLAS)
    B, w = page(g)
    rows = shown_rows(w)
    assert [r.name.text for r in rows] == ["Edwin VanCleef", "Cookie", "Chest"]
    assert rows[0].width == 315 and rows[0].height == 55 and rows[0].portrait.width == 44
    assert [r.portrait.source for r in rows] == ["journal", "display", "skull"]
    assert rows[0].portrait.texture == "Interface\\EncounterJournal\\UI-EJ-BOSS-Edwin VanCleef"
    assert rows[1].portrait.displayID == 1305
    assert rows[2].portrait.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
    assert rows[0].badge.shown and rows[0].boss.level == 21 and not rows[2].badge.shown
    assert rows[0].sel.shown and not rows[1].sel.shown
    assert w.portrait.width == 68 and w.portrait.source == "journal" and w.name.text == "Edwin VanCleef"
    assert not g.eval("NS.db.errors")


def test_portrait_without_journal_art_api_uses_display_then_skull(style):
    g = loot_game(style, ATLAS + "GetFileIDFromPath=nil")
    B, w = page(g)
    assert [r.portrait.source for r in shown_rows(w)] == ["display", "display", "skull"]
    g = loot_game(style, ATLAS + "GetFileIDFromPath=nil; SetPortraitTextureFromCreatureDisplayID=nil")
    B, w = page(g)
    assert [r.portrait.source for r in shown_rows(w)] == ["skull", "skull", "skull"]


def test_loot_rows_follow_the_selected_boss(style):
    g = loot_game(style, ATLAS)
    B, w = page(g)
    loot = shown_loot(w)
    assert len(loot) == 1 and loot[0].bossItemID == 10001 and loot[0].width == 388 and loot[0].height == 52
    cookie = shown_rows(w)[1]
    cookie.scripts.OnClick(cookie, "LeftButton")
    loot = shown_loot(w)
    assert [b.bossItemID for b in loot] == [10003] and w.name.text == "Cookie"
    assert cookie.sel.shown and not shown_rows(w)[0].sel.shown


def test_loot_hover_shows_item_tooltip_and_shift_compare(style):
    g = loot_game(style, ATLAS)
    B, w = page(g)
    b = shown_loot(w)[0]
    b.scripts.OnEnter(b)
    assert g.eval("HYPERLINK") == "item:10001" and g.eval("TOOLTIP.shown")
    g.run("SHIFT=true")
    b.scripts.OnEnter(b)
    assert g.eval("COMPARED")
    b.scripts.OnLeave(b)
    assert not g.eval("TOOLTIP.shown")


def test_loading_then_questie_drops_with_install_hint(style):
    g = quest_game(style, SLOW, open_tab=False)
    B, w = page(g)
    assert w.status.text == "Loading drops…" and w.status.shown and not shown_rows(w) and not shown_loot(w)
    g.advance(30)
    assert [r.name.text for r in shown_rows(w)] == ["Dungeon captain"]
    assert [b.bossItemID for b in shown_loot(w)] == [951]
    assert "Install AtlasLoot for full drops" in w.note.text
    assert not g.eval("NS.db.errors")


def test_empty_states(style):
    g = quest_game(style, "AtlasLoot=nil; ItemDB.GetAllIds=nil; LibQuestieDB.Item=nil", open_tab=False)
    B, w = page(g)
    assert not shown_rows(w) and not shown_loot(w) and "Install AtlasLoot for full drops" in w.status.text
    g = loot_game(style, ATLAS)
    B, w = page(g, 0, "Nowhere Keep")
    assert not shown_rows(w) and "no table" in w.status.text and not w.name.shown


def test_stale_result_after_switching_dungeon_is_ignored(style):
    g = quest_game(style, SLOW, open_tab=False)
    B, w = page(g)
    B.hide()
    g.advance(30)
    assert not w.frame.shown and not shown_rows(w)  # the hidden page was not repainted by the late answer
    B.show(1581, "The Deadmines")
    assert [r.name.text for r in shown_rows(w)] == ["Dungeon captain"]


def test_journal_portrait_tries_names_with_and_without_spaces(style):
    g = loot_game(style, ATLAS + 'JOURNAL_ART={["Interface\\\\EncounterJournal\\\\UI-EJ-BOSS-EdwinVanCleef"]=1}')
    assert list(g.eval("NS.dungeonBossesUI.journalNames('Mutanus the Devourer')").values()) == [
        "Interface\\EncounterJournal\\UI-EJ-BOSS-Mutanus the Devourer", "Interface\\EncounterJournal\\UI-EJ-BOSS-MutanustheDevourer"]
    assert list(g.eval("NS.dungeonBossesUI.journalNames('Mr. Smite')").values())[-1] == "Interface\\EncounterJournal\\UI-EJ-BOSS-MrSmite"
    assert len(list(g.eval("NS.dungeonBossesUI.journalNames('Cookie')").values())) == 1
    B, w = page(g)
    edwin = shown_rows(w)[0]
    assert edwin.portrait.source == "journal" and edwin.portrait.texture == "Interface\\EncounterJournal\\UI-EJ-BOSS-EdwinVanCleef"
    g2 = loot_game(style, ATLAS.replace("UI-EJ-BOSS-Edwin VanCleef", "UI-EJ-BOSS-Cookie"))
    B2, w2 = page(g2)
    assert [r.portrait.source for r in shown_rows(w2)] == ["display", "journal", "skull"]  # spaced name used as is


def test_select_by_name_opens_that_boss(style):
    g = loot_game(style, ATLAS)
    B, w = page(g)
    assert B.select("cookie") is True                     # case does not matter
    assert w.name.text == "Cookie" and [b.bossItemID for b in shown_loot(w)] == [10003]
    assert shown_rows(w)[1].sel.shown and not shown_rows(w)[0].sel.shown
    assert B.select("Nobody") is False and w.name.text == "Cookie"
    assert B.select(None) is False and B.select("") is False
    assert not g.eval("NS.db.errors")


def test_select_while_loading_lands_when_the_bosses_arrive(style):
    g = quest_game(style, SLOW, open_tab=False)
    B, w = page(g)
    assert B.select("Dungeon captain") is True            # still loading: kept for later
    g.advance(30)
    assert w.name.text == "Dungeon captain" and g.eval("NS.dungeonBossesUI._view().want") is None


def test_select_before_the_page_is_built_or_shown(style):
    g = loot_game(style, ATLAS)
    B = g.eval("NS.dungeonBossesUI")
    assert B.select("Cookie") is False                    # not built yet: remembered
    B2, w = page(g)
    assert w.name.text == "Cookie" and g.eval("NS.dungeonBossesUI._view().want") is None
    B.show(0, "Nowhere Keep")
    assert B.select("Chest") is False                     # not in this list: kept for the next show
    B.show(1581, "The Deadmines")
    assert w.name.text == "Chest"


def test_a_wanted_boss_not_in_the_loaded_list_is_dropped(style):
    g = loot_game(style, ATLAS)
    B = g.eval("NS.dungeonBossesUI")
    assert B.select("Chest") is False                     # not built yet: remembered
    B2, w = page(g, 0, "Nowhere Keep")                    # loads a list without that boss
    assert g.eval("NS.dungeonBossesUI._view().want") is None, "no stale selection carried into another dungeon"
    B.show(1581, "The Deadmines")
    assert w.name.text != "Chest"
    assert not g.eval("NS.db.errors")


def test_select_scrolls_the_boss_into_view(style):
    many = ATLAS + r'''
local dm=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items
for i=1,12 do table.insert(dm, {name="Boss "..i, npcID=9000+i, [1]={{1,10100+i}}}) end
'''
    g = loot_game(style, many)
    B, w = page(g)
    bosses = g.eval("NS.dungeonBossesUI._view().bosses")
    last = bosses[len(list(bosses.values()))].name
    assert last not in [r.name.text for r in shown_rows(w)]
    assert B.select(last) is True
    assert last in [r.name.text for r in shown_rows(w)] and w.name.text == last


# Round 3 (stream L): the journal text on the right panel.
LORE = ATLAS
SPELL_MOCK = r'''
SPELLS={[14874]="Interface\\Icons\\Ability_Rogue_Rupture"}
function GetSpellTexture(id) return SPELLS[id] end
if C_Spell then C_Spell.GetSpellTexture=nil end
'''
NEEDED = r'''
NS.dungeonQuests.questsForNpc=function(id)
  QUESTS_ASKED=id
  if id==639 then return {166,{name="The Defias Brotherhood",id=166},{title="Red Silk Bandanas",questID=214}} end
  return {}
end
'''


def y(o):  # the y offset of a SetPoint(p, rel, rp, x, y)
    return o.point[5]


def lore_page(style, extra=""):
    g = loot_game(style, LORE)
    g.run(SPELL_MOCK)
    if extra:
        g.run(extra)
    return page(g) + (g,)


def test_description_under_the_boss_name_and_drops_below_it(style):
    B, w, g = lore_page(style)
    assert w.name.text == "Edwin VanCleef"
    assert w.desc.shown and w.desc.text.startswith("Formerly the leader of the Stonemasons Guild")
    assert y(w.desc) == -96 and w.desc.wordWrap
    assert 14 <= w.desc.height <= 5 * 14                             # 2-5 lines
    first = shown_loot(w)[0]
    assert -y(first) >= 96 + w.desc.height + 12, first.point          # the drops start under the description
    assert y(w.status) <= y(first)
    assert len(shown_loot(w)) == 1 and w.lootCount >= 5


def test_a_long_description_is_cut_and_the_hover_shows_all_of_it(style):
    long = "A " + "very " * 200 + "long story."
    B, w, g = lore_page(style, 'NS.dungeonLore.bosses["edwin vancleef"].description="%s"' % long)
    B.refresh()
    assert w.desc.text.endswith("…") and len(w.desc.text) < len(long)
    assert 4 * 12 <= w.desc.height <= 5 * 14 and w.descHit.height == w.desc.height
    w.descHit.scripts.OnEnter(w.descHit)
    assert g.eval("TOOLTIP.text") == "Edwin VanCleef" and g.eval("TOOLTIP.lines[1]") == long
    w.descHit.scripts.OnLeave(w.descHit)
    assert not g.eval("TOOLTIP.shown")


def test_abilities_with_spell_icon_fallbacks_and_full_text_hover(style):
    B, w, g = lore_page(style)
    assert w.abilityHead.shown and w.abilityHead.text == "Abilities"
    rows = [r for r in w.abilities.values() if r.shown]
    abil = list(g.eval("NS.dungeonLore.boss('Edwin VanCleef')").abilities.values())
    assert 1 <= len(rows) <= 4 and len(rows) == len(abil)
    assert rows[0].name.text == "Rupture" and rows[0].icon.texture == "Interface\\Icons\\Ability_Rogue_Rupture"
    assert rows[1].icon.texture == abil[1].icon        # no client spell texture: the journal's icon FileDataID
    assert g.eval("NS.dungeonBossesUI.abilityIcon({})") == "Interface\\Icons\\INV_Misc_QuestionMark"
    assert g.eval("NS.dungeonBossesUI.abilityIcon({spellID=1})") == "Interface\\Icons\\INV_Misc_QuestionMark"
    g.run("C_Spell=C_Spell or {}; C_Spell.GetSpellTexture=function(id) return 4242 end")
    assert g.eval("NS.dungeonBossesUI.abilityIcon({spellID=5})") == 4242
    assert len(rows[1].text.text) <= 66 and rows[1].text.text.endswith("…")   # short text on the row
    rows[1].scripts.OnEnter(rows[1])
    assert g.eval("TOOLTIP.text") == abil[1].name and g.eval("TOOLTIP.lines[1]") == abil[1].text
    assert y(rows[0]) == -20                                          # under the heading
    assert w.side.point[4] == 420 and y(w.side) == y(shown_loot(w)[0])  # right of the drops, level with them
    assert not g.eval("NS.db.errors")


def test_needed_for_lists_the_quests_that_kill_this_boss(style):
    B, w, g = lore_page(style, NEEDED)
    B.refresh()
    assert g.eval("QUESTS_ASKED") == 639
    assert w.questHead.shown and w.questHead.text == "Needed for"
    shown = [r for r in w.quests.values() if r.shown]
    titles = [r.label.text for r in shown]
    assert "The Defias Brotherhood" in titles and "Red Silk Bandanas" in titles
    assert len(titles) == len(set(titles)) == 2       # a bare quest id and its table are one quest
    shown[0].scripts.OnEnter(shown[0])
    assert g.eval("TOOLTIP.shown") and g.eval("TOOLTIP.text") == titles[0]
    last = [r for r in w.abilities.values() if r.shown][-1]
    assert y(w.questHead) < y(last)                    # after the abilities
    cookie = shown_rows(w)[1]
    cookie.scripts.OnClick(cookie, "LeftButton")
    assert g.eval("QUESTS_ASKED") == 645 and not w.questHead.shown


def test_needed_for_more_than_five_quests(style):
    B, w, g = lore_page(style, "NS.dungeonQuests.questsForNpc=function() local t={} for i=1,8 do t[i]={id=i,name='Q'..i} end return t end")
    assert len([r for r in w.quests.values() if r.shown]) == 5 and w.questMore.shown and w.questMore.text == "+3 more"


def test_needed_for_is_nil_guarded(style):
    B, w, g = lore_page(style, "NS.dungeonQuests.questsForNpc=nil")
    assert not w.questHead.shown and w.abilityHead.shown
    B, w, g = lore_page(style, "NS.dungeonQuests.questsForNpc=function() error('boom') end")
    assert not w.questHead.shown and w.abilityHead.shown
    B, w, g = lore_page(style, "NS.dungeonQuests=nil")
    assert not w.questHead.shown and w.name.text == "Edwin VanCleef"
    assert list(g.eval("NS.dungeonBossesUI.neededFor({name='X'})").values()) == []   # no npcID
    assert not g.eval("NS.db.errors")


def test_needed_for_asks_for_the_pages_dungeon_and_a_click_opens_the_quest(style):
    # the shell's dungeon filter may be 0 (home): the Bosses page passes its own area
    B, w, g = lore_page(style, r'''
NS.dungeonQuests.questsForNpc=function(id,area) QUESTS_AREA=area if id==639 and area==1581 then return {{id=166,name="The Defias Brotherhood"}} end return {} end
NS.dungeonQuests.openQuest=function(id) OPENED=id return true end
''')
    B.refresh()
    assert g.eval("QUESTS_AREA") == 1581
    row = [r for r in w.quests.values() if r.shown][0]
    assert row.label.text == "The Defias Brotherhood"
    row.scripts.OnEnter(row)
    assert "Click: open it in Quests." in "\n".join(g.eval("TOOLTIP.lines").values())
    row.scripts.OnClick(row, "LeftButton")
    assert g.eval("OPENED") == 166
    g.run("NS.dungeonQuests.openQuest=function() error('boom') end")
    row.scripts.OnClick(row, "LeftButton")
    g.run("NS.dungeonQuests.openQuest=nil")
    row.scripts.OnClick(row, "LeftButton")
    assert not g.eval("NS.db.errors")


def test_facts_line_level_rank_and_drops(style):
    B, w, g = lore_page(style, r'''
local get=NS.questie.get
NS.questie.get=function(kind,id,key) if kind=="npc" and key=="rank" and id==639 then return 1 end return get(kind,id,key) end
''')
    B.refresh()
    assert w.facts.shown and w.facts.text == "Level 21 · Elite · 1 drop"
    F = g.eval("NS.dungeonBossesUI.facts")
    assert F(g.eval("{level=30,rare=true,items={1,2,3}}")) == "Level 30 · Rare · 3 drops"
    assert F(g.eval("{items={}}")) == "0 drops"


def test_without_a_journal_entry_no_empty_headings(style):
    B, w, g = lore_page(style, NEEDED)
    chest = shown_rows(w)[2]
    chest.scripts.OnClick(chest, "LeftButton")
    assert w.name.text == "Chest" and w.facts.shown and "1 drop" in w.facts.text
    assert not w.desc.shown and not w.abilityHead.shown and not w.questHead.shown and not w.side.shown
    assert not [r for r in w.abilities.values() if r.shown]
    assert y(shown_loot(w)[0]) == -102                                # the drops keep their old place
    # a boss with quests but no journal text: only the quests heading, at the top of the column
    g.run("NS.dungeonLore.bosses['edwin vancleef']=nil")
    edwin = shown_rows(w)[0]
    edwin.scripts.OnClick(edwin, "LeftButton")
    assert not w.desc.shown and not w.abilityHead.shown and w.questHead.shown and y(w.questHead) == 0
    g.run("NS.dungeonLore=nil")
    B.refresh()
    assert w.name.text == "Edwin VanCleef" and not w.desc.shown and w.questHead.shown
    assert not g.eval("NS.db.errors")

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
