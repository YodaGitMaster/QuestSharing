"""Saved QuestieDB ID lists (QuestSharingCache): a new session reads only the IDs a full scan kept, with the same
results; a different QuestieDB/addon version, Refresh data and Purge go back to the full catalogue."""
import sys

from harness import Game
import test_dungeon_quests as dq
import test_optional as opt
import test_loot as loot
import test_vendor_map as vm
import test_travel_map as tm

SERIALIZE = r'''
function SERIALIZE(v)
    local t = type(v)
    if t == "table" then
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = "[" .. SERIALIZE(k) .. "]=" .. SERIALIZE(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then return string.format("%q", v) end
    return tostring(v)
end'''

COUNT_IDS = '''ID_ENUMS = {}
local ids = NS.questie.ids
NS.questie.ids = function(kind, ...) ID_ENUMS[kind] = (ID_ENUMS[kind] or 0) + 1; return ids(kind, ...) end'''


def saved_file(g):
    """What the game would write to disk at logout: QuestSharingCache as a Lua literal."""
    g.run(SERIALIZE)
    return "QuestSharingCache=" + g.eval("SERIALIZE(QuestSharingCache or {})") + "\n"


def old_version(cache):
    return cache.replace('["stamp"]="', '["stamp"]="old|', 1)


# ---- Dungeon quests -------------------------------------------------------------------------------------------------
def test_dungeon_quests_new_session_reads_only_the_saved_ids(style):
    g = dq.game(style)
    want, cache = sorted(dq.ids(g)), saved_file(g)
    assert want and '["dungeonQuests"]' in cache
    h = dq.game(style, cache)
    assert h.eval("QUEST_ENUMS") == 0, "no full quest catalogue enumeration"
    assert sorted(dq.ids(h)) == want and h.eval("NS.dungeonQuests._state()")[0]
    assert not h.eval("NS.db.errors")


def test_dungeon_quests_chain_names_survive_the_saved_list(style):
    g = dq.game(style, dq.HOVER_DATA)
    before = {i: dq.plain(dq.chain_text(g, i)) for i in (2, 3)}
    h = dq.game(style, dq.HOVER_DATA + saved_file(g))
    assert h.eval("QUEST_ENUMS") == 0
    assert {i: dq.plain(dq.chain_text(h, i)) for i in (2, 3)} == before


def test_dungeon_quests_other_version_refresh_and_purge_read_the_whole_catalogue(style):
    g = dq.game(style)
    cache = saved_file(g)
    h = dq.game(style, old_version(cache))
    assert h.eval("QUEST_ENUMS") > 0, "another QuestieDB/addon version drops the saved lists"
    h = dq.game(style, cache)
    w = h.eval("NS.dungeonQuests._window()")
    w.reload.scripts.OnClick(w.reload); h.advance(90)
    assert h.eval("QUEST_ENUMS") == 1, "Refresh data reads the whole catalogue"
    h.eval("NS.purgeData")()
    assert h.eval("QuestSharingCache") is None, "Purge also deletes the saved lists"


# ---- Quest rewards ---------------------------------------------------------------------------------------------------
ITEM_COUNT = '''ITEM_ENUMS = 0
local all = ItemDB.GetAllIds
ItemDB.GetAllIds = function(...) ITEM_ENUMS = ITEM_ENUMS + 1; return all(...) end
'''


def test_quest_rewards_new_session_reads_only_the_saved_ids(style):
    g = opt.game(style, ITEM_COUNT); g.slash("rewards"); g.advance(5)
    want, cache = sorted(opt.ids(g)), saved_file(g)
    assert want and g.eval("ITEM_ENUMS") == 1
    h = opt.game(style, ITEM_COUNT + cache); h.slash("rewards"); h.advance(5)
    assert h.eval("ITEM_ENUMS") == 0 and sorted(opt.ids(h)) == want


# ---- Dungeon loot (QuestieDB fallback) -------------------------------------------------------------------------------
LOOT = '''AtlasLoot=nil
LOOT_ENUMS=0
ItemDB.GetAllIds=function() LOOT_ENUMS=LOOT_ENUMS+1; return {10001,10005,10009} end
QUESTIE_ITEMS[10001]={name="Captain's Blade",npcDrops={639,299}}
QUESTIE_ITEMS[10005]={name="Locked Chest Prize",objectDrops={55}}
QUESTIE_ITEMS[10009]={name="Outdoor thing",npcDrops={299}}
QUESTIE_NPCS[639]={name="Edwin VanCleef",spawns={[1581]={{-1,-1}}}}
QUESTIE_OBJECTS[55]={name="Large Chest",spawns={[1581]={{-1,-1}}}}
local area=C_Map.GetAreaInfo
C_Map.GetAreaInfo=function(id) return id==1581 and "The Deadmines" or area(id) end
'''


def test_dungeon_loot_new_session_reads_only_the_saved_ids(style):
    g = loot.game(style, LOOT); g.slash("loot")
    want, cache = {(r[0], r[2]) for r in loot.results(g)}, saved_file(g)
    assert want == {(10001, "Edwin VanCleef"), (10005, "Large Chest")}
    h = loot.game(style, LOOT + cache); h.slash("loot")
    assert h.eval("LOOT_ENUMS") == 0 and {(r[0], r[2]) for r in loot.results(h)} == want


# ---- Map search ------------------------------------------------------------------------------------------------------
def test_map_search_new_session_reads_only_the_saved_npcs(style):
    queries = ("General Goods", "vendor", "silk")    # an NPC title, a seller query that reads items, an item name
    g = vm.game(style); g.run(COUNT_IDS)
    want = []
    for q in queries:
        vm.type_query(g, q); want.append(vm.labels(g)[1])
    cache = saved_file(g)
    assert g.eval("ID_ENUMS.npc") == 1 and g.eval("ID_ENUMS.item") == 1
    h = Game(style, vm.SETUP + cache, fresh=True); h.start(); h.run(COUNT_IDS)
    h.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()"); h.advance(2)
    got = []
    for q in queries:
        vm.type_query(h, q); got.append(vm.labels(h)[1])
    assert got == want and "3 locations" in want[0] and "4 locations" in want[1]
    assert h.eval("ID_ENUMS.npc") is None, "no full NPC enumeration (items are still read by name, a cheap read)"


# ---- Trainers --------------------------------------------------------------------------------------------------------
def trainers_game(style, pre=""):
    g = Game(style, tm.SETUP + tm.QUESTIE + pre, fresh=True)
    g.start(); g.run(COUNT_IDS); g.fire("PLAYER_LOGIN")
    g.run("WORLDMAP_ID=1413; WorldMapFrame:Show(); NS.travelMap.refresh()"); g.advance(5)
    return g


def test_trainers_new_session_reads_only_the_saved_ids(style):
    g = trainers_game(style)
    want, cache = sorted(n for p in tm.trainer_pins(g) for n in tm.members(p)), saved_file(g)
    assert want == ["Finn", "Gorn"] and g.eval("ID_ENUMS.npc") == 1
    h = trainers_game(style, cache)
    assert h.eval("ID_ENUMS.npc") is None
    assert sorted(n for p in tm.trainer_pins(h) for n in tm.members(p)) == want


# ---- Quest guide zone lists -----------------------------------------------------------------------------------------
def pickup_text(g):
    import test_quest_planner_ui as qp
    _, _, _, rows = qp.planner_rows(g)
    return sorted(row.children[i].text for row in rows for i in range(1, len(row.children) + 1)
                  if getattr(row.children[i], "isFontString", False) and "Pick up" in row.children[i].text)


def test_quest_guide_new_session_reads_the_saved_zone_list(style):
    import test_quest_planner_ui as qp
    count = "\nQUEST_ENUMS=0;local all=QuestDB.GetAllIds;QuestDB.GetAllIds=function() QUEST_ENUMS=QUEST_ENUMS+1;return all() end\n"
    g = qp.planner_game(qp.DATA + count)
    want, cache = pickup_text(g), saved_file(g)
    assert want and g.eval("QUEST_ENUMS") >= 1 and '["guideZones"]' in cache
    h = qp.planner_game(qp.DATA + count + cache)
    assert h.eval("QUEST_ENUMS") == 0, "the zone's quest list came from the saved file"
    assert pickup_text(h) == want


if __name__ == "__main__":
    total = failed = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in ("modern", "classic"):
            total += 1
            try:
                fn(style); print("ok", name, style)
            except Exception as exc:
                failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total - failed}/{total} passed")
    raise SystemExit(bool(failed))
