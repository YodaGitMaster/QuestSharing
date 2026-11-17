"""Optional database tools must stay idle at login and share a cooperative work budget."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_quest_planner_zone_steps import WESTFALL
from test_vendor_map import SETUP as VENDOR_DATA

COUNTERS = r'''
DB_READS={quest=0,npc=0,item=0}; DB_ENUMS={quest=0,npc=0,item=0}; SPAWN_READS=0
for _,kind in ipairs({"quest","npc","item"}) do
 local db=({quest=QuestDB,npc=NpcDB,item=ItemDB})[kind]
 local get,ids=db.Get,db.GetAllIds
 db.Get=function(id,key)
  DB_READS[kind]=DB_READS[kind]+1
  if kind=="npc" and key=="spawns" then SPAWN_READS=SPAWN_READS+1 end
  return get(id,key)
 end
 if ids then db.GetAllIds=function() DB_ENUMS[kind]=DB_ENUMS[kind]+1;return ids() end end
end
'''


def game(pre):
    g = Game("modern", pre + COUNTERS, fresh=True)
    g.start()
    return g


def counts(g, key):
    return dict(g.eval(key).items())


def test_saved_tools_do_not_scan_catalogues_during_login_or_normal_play():
    g = game(WESTFALL + r'''
ItemDB.GetAllIds=function() return {} end
NpcDB.GetAllIds=function() return {} end
QuestSharingDB={enabled=true,questPlanner=true,vendorSearch=true,dbVersion=3,welcomed="0.4.18"}
''')
    g.fire("PLAYER_LOGIN")
    g.advance(20)
    assert counts(g, "DB_ENUMS") == {"quest": 0, "npc": 0, "item": 0}


def test_enabling_map_search_or_showing_blank_map_does_not_preload_data():
    g = game(VENDOR_DATA)
    g.eval("NS.setSetting")("vendorSearch", True)
    g.advance(3)
    assert counts(g, "DB_ENUMS") == {"quest": 0, "npc": 0, "item": 0}
    g.run("WorldMapFrame:Show(); NS.vendorMap.refresh()")
    g.advance(3)
    assert counts(g, "DB_ENUMS") == {"quest": 0, "npc": 0, "item": 0}


def test_closed_guide_does_not_rebuild_on_quest_events():
    g = game(WESTFALL)
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    g.slash("plan hide")
    before = counts(g, "DB_ENUMS")
    g.fire("QUEST_ACCEPTED", 1, 9000)
    g.fire("ZONE_CHANGED")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(5)
    assert counts(g, "DB_ENUMS") == before


def test_same_zone_events_do_not_repeat_the_catalogue_scan():
    g = game(WESTFALL)
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    before = counts(g, "DB_ENUMS")
    for _ in range(3):
        g.fire("ZONE_CHANGED")
        g.advance(2)
    assert counts(g, "DB_ENUMS") == before


def test_quest_updates_reuse_discovered_zone_ids_instead_of_world_catalogue():
    g = game(WESTFALL)
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    before = counts(g, "DB_ENUMS")
    g.run('QUESTS={{id=9000,title="Local Harvest",level=8,objectives={{text="Harvest Watcher: 0/8",have=0,need=8}}}}')
    g.fire("QUEST_ACCEPTED", 1, 9000)
    g.advance(5)
    assert counts(g, "DB_ENUMS") == before


def test_shared_budget_limits_combined_jobs_and_pauses_in_combat():
    g = game(WESTFALL)
    g.run(r'''
PROFILE=0; debugprofilestop=function() return PROFILE end
WORK_DONE={0,0}
for owner=1,2 do
 NS.dataWork.start("test-"..owner,function()
  for i=1,20 do PROFILE=PROFILE+0.4;WORK_DONE[owner]=WORK_DONE[owner]+1;NS.dataWork.yield() end
 end)
end
''')
    before = 0
    for _ in range(12):
        g.advance(0.1)
        now = g.eval("PROFILE")
        assert now - before <= 2.401
        before = now
    assert g.eval("WORK_DONE[1]") == 20 and g.eval("WORK_DONE[2]") == 20
    g.run('''IN_COMBAT=true; NS.dataWork.start("combat",function() WORK_DONE[1]=999 end)''')
    g.advance(2)
    assert g.eval("WORK_DONE[1]") == 20
    g.run("IN_COMBAT=false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert g.eval("WORK_DONE[1]") == 999


def test_foreground_budget_speeds_only_its_job_and_keeps_background_at_shared_slice():
    g = game(WESTFALL)
    g.run(r'''
PROFILE=0; debugprofilestop=function() return PROFILE end
FG,BG=0,0
NS.dataWork.start("background",function() for i=1,200 do PROFILE=PROFILE+0.4;BG=BG+1;NS.dataWork.yield() end end)
NS.dataWork.start("foreground",function() for i=1,200 do PROFILE=PROFILE+0.4;FG=FG+1;NS.dataWork.yield() end end,nil,nil,8)
''')
    before = 0
    for _ in range(5):
        g.advance(0.1)
        now = g.eval("PROFILE")
        assert now - before <= 8.401, now - before  # whole slice never exceeds the largest requested budget
        before = now
    fg, bg = g.eval("FG"), g.eval("BG")
    assert bg <= 5 * 3 and fg >= 3 * bg, (fg, bg)  # background keeps ~2 ms per slice; foreground gets ~4x
    g.run("debugprofilestop=nil")
    fg0, bg0 = g.eval("FG"), g.eval("BG")
    g.advance(0.1)
    assert g.eval("BG") - bg0 <= 80 and g.eval("FG") - fg0 > 80  # no profiler: step caps scale the same way


def test_shared_work_pause_and_cancel_do_not_keep_idle_jobs_running():
    g = game(WESTFALL)
    g.run('''WORK_COUNT=0
NS.dataWork.start("paused",function() for i=1,100 do WORK_COUNT=WORK_COUNT+1;NS.dataWork.yield() end end)
NS.dataWork.pause("paused")''')
    g.advance(3)
    assert g.eval("WORK_COUNT") == 0
    g.eval("NS.dataWork.resume")("paused")
    g.advance(2)
    assert g.eval("WORK_COUNT") == 100
    g.run('NS.dataWork.start("cancelled",function() error("must not execute") end);NS.dataWork.cancel("cancelled")')
    g.advance(2)
    assert not g.eval("NS.dataWork.busy")("cancelled")



LARGE_ROLES = r'''
local ids={}
for id=1,1000 do
 ids[#ids+1]=id
 QUESTIE_NPCS[id]={subName=id==2 and "Skinning Trainer" or "General Goods",spawns={[12]={{20,30}}}}
end
NpcDB.GetAllIds=function() return ids end
'''


def show_search(g, text):
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    g.eval("NS.vendorMap.search")(text, True)


def test_role_search_reads_only_matching_locations_and_no_item_catalogue():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + LARGE_ROLES)
    show_search(g, "skinner trainer")
    g.advance(20)
    assert len(pins(g)) == 1
    assert g.eval("SPAWN_READS") == 1
    assert g.eval("DB_ENUMS.item") == 0
    before = counts(g, "DB_READS")
    g.advance(20)
    assert counts(g, "DB_READS") == before
    vendor = pins(g)[0].result.vendor
    g.eval("NS.vendorMap.search")("", True)
    assert vendor.spawns is None and not pins(g)


def test_hidden_map_pauses_and_reopens_without_restarting_role_catalogue():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + LARGE_ROLES)
    show_search(g, "skinner trainer")
    g.advance(0.5)
    g.run("WorldMapFrame:Hide(); NS.vendorMap.refresh()")
    before = counts(g, "DB_READS")
    g.advance(10)
    assert counts(g, "DB_READS") == before
    g.run("WorldMapFrame:Show(); NS.vendorMap.refresh()")
    g.advance(20)
    assert len(pins(g)) == 1 and g.eval("DB_ENUMS.npc") == 1


def test_combat_defers_actual_vendor_database_reads_until_regen():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + LARGE_ROLES)
    g.run("IN_COMBAT=true")
    show_search(g, "skinner trainer")
    g.advance(5)
    assert counts(g, "DB_ENUMS") == {"quest": 0, "npc": 0, "item": 0}
    assert g.eval("SPAWN_READS") == 0
    g.run("IN_COMBAT=false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(20)
    assert len(pins(g)) == 1


def test_clearing_debounced_query_never_starts_catalogue_and_discards_old_tab_choice():
    from test_vendor_map import type_query, ui
    g = game(VENDOR_DATA)
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    for text in ("s", "sk", "ski", "skinner"):
        type_query(g, text, settle=False)
    type_query(g, "", settle=False)
    ui(g).scripts.OnTabPressed()
    g.advance(5)
    assert counts(g, "DB_ENUMS") == {"quest": 0, "npc": 0, "item": 0}
    type_query(g, "gene")
    type_query(g, "paladin", settle=False)
    ui(g).scripts.OnTabPressed()
    assert ui(g).text == "paladin"


def test_replacing_a_job_from_its_coroutine_keeps_the_replacement_alive():
    g = game(WESTFALL)
    g.run('''WORK_REPLACED=0
NS.dataWork.start("replace",function()
 NS.dataWork.start("replace",function() WORK_REPLACED=1 end)
end)''')
    g.advance(1)
    assert g.eval("WORK_REPLACED") == 1


def test_shared_planner_starter_cache_avoids_redecoding_same_world_npc():
    g = game(WESTFALL + r'''
local ids={9000}
for id=1,1000 do QUESTIE_QUESTS[id]={name="Remote quest",startedBy={{700},{},{}},questLevel=8}; ids[#ids+1]=id end
QuestDB.GetAllIds=function() return ids end
''')
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(20)
    assert g.eval("DB_ENUMS.quest") == 1
    assert g.eval("SPAWN_READS") <= 5


def test_vendor_and_planner_share_budget_with_actual_db_getters():
    g = game(WESTFALL + VENDOR_DATA + LARGE_ROLES + r'''
MAP_ID=1429
QUESTIE_QUESTS[100].questLevel=8;QUESTIE_QUESTS[100].startedBy={{1}}
QuestDB.GetAllIds=function() return {100} end
''')
    g.run(r'''
NS.db.questItems=false
PROFILE=0; debugprofilestop=function() return PROFILE end
for _,db in ipairs({QuestDB,NpcDB,ItemDB}) do
 local get=db.Get; db.Get=function(...) PROFILE=PROFILE+0.2;return get(...) end
end
''')
    show_search(g, "skinner trainer")
    g.eval("NS.setSetting")("questPlanner", True)
    before = 0
    for _ in range(30):
        g.advance(0.1)
        now = g.eval("PROFILE")
        assert now - before <= 2.801
        before = now



def test_master_disable_cancels_guide_work_and_requires_explicit_reopen():
    g = game(WESTFALL)
    g.eval("NS.setSetting")("questPlanner", True)
    g.eval("NS.setSetting")("enabled", False)
    g.advance(5)
    assert not g.eval('NS.dataWork.busy("quest-plan")')
    assert not g.eval("QuestSharingPlannerPanel.shown")
    g.eval("NS.setSetting")("enabled", True)
    g.advance(5)
    assert g.eval("DB_ENUMS.quest") == 0
    g.slash("plan")
    g.advance(5)
    assert g.eval("DB_ENUMS.quest") == 1


def test_map_switch_during_pin_batches_cannot_leave_old_zone_pins():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + LARGE_ROLES)
    show_search(g, "general vendor")
    # Stop during rendering of the first map, then change the displayed map.
    for _ in range(250):
        g.advance(0.1)
        if 0 < len(pins(g)) < 999:
            break
    assert 0 < len(pins(g)) < 999
    g.run("WORLDMAP_ID=1436;NS.vendorMap.refresh()")
    g.advance(20)
    assert not pins(g)


def test_item_fallback_reads_names_only_for_buyable_items_and_locations_only_for_matches():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + r'''
local ids={}; ITEM_NAME_READS=0
for id=20,1019 do ids[#ids+1]=id;QUESTIE_ITEMS[id]={name="Non vendor item"} end
QUESTIE_ITEMS[20]={name="Copper Rivet",vendors={4}}
ItemDB.GetAllIds=function() return ids end
local get=ItemDB.Get
ItemDB.Get=function(id,key) if key=="name" then ITEM_NAME_READS=ITEM_NAME_READS+1 end;return get(id,key) end
''')
    show_search(g, "Copper Rivet")
    g.advance(20)
    assert g.eval("ITEM_NAME_READS") == 1
    assert g.eval("SPAWN_READS") == 1
    assert [p.result.vendor.id for p in pins(g)] == [4]

if __name__ == "__main__":
    failed = total = 0
    for name, test in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        total += 1
        try:
            test();print("ok", name)
        except Exception as error:
            failed += 1;print("FAIL", name, type(error).__name__, str(error)[:300])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
