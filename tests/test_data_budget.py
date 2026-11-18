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


IDLE_JOBS = r'''
PROFILE, NORMAL, IDLE, ORDER = 0, 0, {}, {}
function startNormal(n, valid)
 NS.dataWork.start("normal", function()
  for i=1,n do PROFILE=PROFILE+0.4; NORMAL=NORMAL+1; NS.dataWork.yield() end
 end, valid)
end
-- An idle job (n=nil: never finishes) that records how often and in which order it ran.
function startIdle(owner, n)
 IDLE[owner] = 0
 NS.dataWork.start(owner, function()
  local i = 0
  while not n or i < n do
   i = i + 1; PROFILE=PROFILE+0.4; IDLE[owner]=IDLE[owner]+1; ORDER[#ORDER+1]=owner; NS.dataWork.yield()
  end
 end, nil, function(ok) IDLE_DONE = ok end, nil, "idle")
end
'''


def idle_game(profiler):
    g = game(WESTFALL + IDLE_JOBS)
    if profiler:
        g.run("debugprofilestop=function() return PROFILE end")
    return g


def normal_job_pumps(with_idle, profiler, n):
    g = idle_game(profiler)
    if with_idle:
        g.eval("startIdle")("refine")
    g.eval("startNormal")(n)
    pumps = 0
    while g.eval("NORMAL") < n and pumps < 1000:
        g.advance(0.1)
        pumps += 1
    return pumps


def test_idle_job_that_never_ends_leaves_a_normal_job_at_least_90_percent_of_its_pace():
    for profiler, n in ((False, 800), (True, 200)):
        solo, shared = normal_job_pumps(False, profiler, n), normal_job_pumps(True, profiler, n)
        assert 0 < solo < 1000
        assert shared * 0.9 <= solo, (profiler, solo, shared)


def test_idle_job_alone_still_finishes_within_the_shared_slice():
    for profiler in (False, True):
        g = idle_game(profiler)
        g.eval("startIdle")("refine", 200)
        before, steps = 0, 0
        for _ in range(200):
            g.advance(0.1)
            now, done = g.eval("PROFILE"), g.eval("IDLE.refine")
            assert (now - before <= 2.401) if profiler else (done - steps <= 80), (profiler, now - before, done - steps)
            before, steps = now, done
            if not g.eval('NS.dataWork.busy("refine")'):
                break
        assert g.eval("IDLE.refine") == 200 and g.eval("IDLE_DONE") is True


def test_idle_job_started_first_yields_every_slice_to_a_later_normal_job():
    g = idle_game(False)
    g.eval("startIdle")("refine")
    g.advance(0.5)
    assert g.eval("IDLE.refine") > 0
    g.eval("startNormal")(400)
    for _ in range(50):
        idle, normal = g.eval("IDLE.refine"), g.eval("NORMAL")
        g.advance(0.1)
        if not g.eval('NS.dataWork.busy("normal")'):
            break
        assert g.eval("IDLE.refine") == idle, "the idle job ran while a normal job could run"
        assert g.eval("NORMAL") - normal in (0, 80)
    assert g.eval("NORMAL") == 400
    idle = g.eval("IDLE.refine")
    g.advance(0.3)
    assert g.eval("IDLE.refine") > idle, "the idle job did not continue after the normal job finished"


def test_paused_or_invalid_normal_jobs_do_not_hold_back_idle_jobs():
    g = idle_game(False)
    g.run("VALID=false")
    g.eval("startNormal")(400, g.eval("function() return VALID end"))
    g.eval("startIdle")("refine")
    g.advance(0.3)
    assert g.eval("NORMAL") == 0 and g.eval("IDLE.refine") > 0
    g.run("VALID=true")
    g.eval("NS.dataWork.resume")("normal")
    g.advance(0.2)
    idle = g.eval("IDLE.refine")
    g.advance(0.2)
    assert g.eval("NORMAL") > 0 and g.eval("IDLE.refine") == idle
    g.eval("NS.dataWork.pause")("normal")
    g.advance(0.3)
    assert g.eval("IDLE.refine") > idle


def test_idle_jobs_keep_their_order_and_obey_pause_resume_cancel_and_combat():
    g = idle_game(False)
    g.eval("startIdle")("first", 100)
    g.eval("startIdle")("second", 100)
    g.advance(0.1)
    assert list(g.eval("ORDER").values())[:4] == ["first", "second", "first", "second"]
    g.eval("NS.dataWork.pause")("first")
    first = g.eval("IDLE.first")
    g.advance(0.5)
    assert g.eval("IDLE.first") == first and g.eval("IDLE.second") == 100
    assert g.eval('NS.dataWork.busy("first")')
    g.run("IN_COMBAT=true")
    g.eval("NS.dataWork.resume")("first")
    g.advance(1)
    assert g.eval("IDLE.first") == first
    g.run("IN_COMBAT=false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert g.eval("IDLE.first") == 100 and not g.eval('NS.dataWork.busy("first")')
    g.eval("startIdle")("cancelled")
    g.eval("NS.dataWork.cancel")("cancelled")
    g.advance(0.5)
    assert g.eval("IDLE.cancelled") == 0 and not g.eval('NS.dataWork.busy("cancelled")')


def test_idle_job_paused_while_waiting_stays_paused_until_resumed():
    g = idle_game(False)
    g.eval("startIdle")("refine")
    g.run(r'''NS.dataWork.start("normal", function()
 NS.dataWork.pause("refine"); NS.dataWork.yield(); NORMAL = 1
end)''')
    g.advance(1)
    assert g.eval("NORMAL") == 1 and g.eval("IDLE.refine") == 0
    assert g.eval('NS.dataWork.busy("refine")')
    g.eval("NS.dataWork.resume")("refine")
    g.advance(0.2)
    assert g.eval("IDLE.refine") > 0


def test_normal_job_started_by_an_idle_job_takes_over_the_same_slice():
    g = idle_game(False)
    g.run(r'''
NS.dataWork.start("refine", function()
 IDLE.refine = 0
 while true do
  IDLE.refine = IDLE.refine + 1
  if IDLE.refine == 3 then startNormal(1000) end
  NS.dataWork.yield()
 end
end, nil, nil, nil, "idle")''')
    g.advance(0.1)
    assert g.eval("IDLE.refine") == 3 and g.eval("NORMAL") == 77


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


def test_item_fallback_reads_vendor_links_only_for_matching_names_and_locations_only_for_matches():
    from test_vendor_map import pins
    g = game(VENDOR_DATA + r'''
local ids={}; ITEM_NAME_READS, ITEM_VENDOR_READS=0,0
for id=20,1019 do ids[#ids+1]=id;QUESTIE_ITEMS[id]={name="Non vendor item"} end
QUESTIE_ITEMS[20]={name="Copper Rivet",vendors={4}}
ItemDB.GetAllIds=function() return ids end
local get=ItemDB.Get
ItemDB.Get=function(id,key)
 if key=="name" then ITEM_NAME_READS=ITEM_NAME_READS+1 elseif key=="vendors" then ITEM_VENDOR_READS=ITEM_VENDOR_READS+1 end
 return get(id,key)
end
''')
    show_search(g, "Copper Rivet")
    g.advance(20)
    # one cheap name read per item, but the vendor table is read only for the one item whose name matches
    assert g.eval("ITEM_NAME_READS") == 1000
    assert g.eval("ITEM_VENDOR_READS") == 1
    assert g.eval("SPAWN_READS") == 1
    assert [p.result.vendor.id for p in pins(g)] == [4]

SYNTHETIC_ZONE = r'''
function syntheticZone(n)
 local quests, stops, seed = {}, {}, 777
 local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
 local function add(qid, kind, deps, target)
  local id = #stops + 1
  stops[id] = {id=id,kind=kind,point={map=1436,x=rnd(),y=rnd()},quests={[qid]="Q"..qid},deps=deps or {}}
  if target then
   stops[id].objectives={{questID=qid,target=target,sourceID=600+qid%7,remaining=target.required,shareable=true}}
  end
  return id
 end
 for qid = 1, n do
  quests[qid] = {id=qid,name="Q"..qid,status="ready",xp=qid*50}
  local p = add(qid, "pickup")
  local o = add(qid, "objective", {[p]=true}, {kind="kill",creditID=600+qid%7,required=6+qid%5})
  add(qid, "turnin", {[o]=true})
 end
 return quests, stops
end
'''


def test_route_search_yields_at_least_every_64_simulated_actions():
    # Every stop has its own point, so each simulated action asks for exactly one travel time.
    g = game(WESTFALL + SYNTHETIC_ZONE)
    g.run(r'''
SINCE, WORST, YIELDS = 0, 0, 0
local q, s = syntheticZone(40)
ROUTE, REPORT = NS.questOptimizer.optimize(q, s, {mode="all", origin={map=1436,x=.5,y=.5}, killSeconds=10,
 interactionSeconds=3, maxImproveSteps=250000,
 travelSeconds=function(a, b) SINCE = SINCE + 1; local x, y = a.x - b.x, a.y - b.y; return math.sqrt(x*x + y*y) * 600 end,
 checkpoint=function() WORST = math.max(WORST, SINCE); SINCE = 0; YIELDS = YIELDS + 1 end})
WORST = math.max(WORST, SINCE)
''')
    assert g.eval("REPORT.coverage") == 40
    assert g.eval("REPORT.improveSteps") > 0
    assert g.eval("WORST") <= 64, g.eval("WORST")


GUIDE_ZONE = r'''
QUESTIE_QUESTS[9000],QUESTIE_QUESTS[9001],QUESTIE_QUESTS[9002]=nil,nil,nil
local seed = 7
local function at() seed = (seed * 1103515245 + 12345) % 2147483648; return 15 + seed % 70 end
for k = 0, 11 do
 local giver, mob = 6100 + k, 6200 + k
 local gx, gy, mx, my = at(), at(), at(), at()
 QUESTIE_QUESTS[9100 + k] = {name="Task "..k,questLevel=8,zoneOrSort=40,startedBy={{giver}},objectives={{{mob,5}}},finishedBy={{giver}}}
 QUESTIE_NPCS[giver] = {name="Giver "..k,spawns={[40]={{gx,gy}}}}
 QUESTIE_NPCS[mob] = {name="Mob "..k,spawns={[40]={{mx,my},{mx+1,my},{mx,my+1}}}}
end
local ids = {}
for id = 1, 3000 do
 ids[#ids + 1] = id
 QUESTIE_NPCS[id] = {subName=id==2 and "Skinning Trainer" or "General Goods",spawns={[12]={{20,30}}}}
end
NpcDB.GetAllIds = function() return ids end
for id = 20000, 23000 do QUESTIE_QUESTS[id] = {name="Filler "..id,questLevel=30} end
'''


def database_job_pumps(job, guide):
    """Pumps (0.1 s slices, step-capped as in the harness) until map search or the dungeon scan is done."""
    from test_vendor_map import pins
    g = game(VENDOR_DATA + WESTFALL + GUIDE_ZONE)
    g.advance(1)
    if guide:
        g.eval("NS.setSetting")("questPlanner", True)
        for _ in range(3000):
            g.advance(0.1)
            if not g.eval('NS.dataWork.busy("quest-plan") or NS.dataWork.busy("quest-improve")'):
                break
    if job == "vendor":
        show_search(g, "general vendor")
        def done():
            return len(pins(g)) > 0 and not g.eval('NS.dataWork.busy("vendor-search") or NS.dataWork.busy("vendor-index")')
    else:
        g.slash("dungeons")
        def done():
            return not g.eval('NS.dataWork.busy("dungeonQuests")')
    pumps, x = 0, 0.5
    while not done() and pumps < 3000:
        g.advance(0.1)
        pumps += 1
        if guide and pumps % 10 == 0:  # the player walks; the open guide re-plans every 3 s
            x = 0.53 if x == 0.5 else 0.5
            g.run(f"POS.x, POS.y = {x}, {x}")
    return pumps


def test_map_search_and_dungeon_scan_keep_half_their_pace_while_the_guide_replans():
    # Guard, not an A4 regression test: the 0.03 moves stay under REFINE_MOVE, so the guide re-plans (solve(0))
    # but never refines during the measured window, and this already passed before the A4 fix. The A4 regression
    # tests are the 64-action yield test above and the local-search gate tests in test_quest_optimizer.py.
    for job in ("vendor", "dungeon"):
        solo, shared = database_job_pumps(job, False), database_job_pumps(job, True)
        assert 0 < solo < 3000
        assert shared <= 2 * solo, (job, solo, shared)


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
