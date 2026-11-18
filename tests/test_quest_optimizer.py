"""Predictive decisions and their independent probability/cost expectations."""
import math
from harness import Game
from test_quest_planner_zone_steps import WESTFALL, text, rows
from test_data_budget import SYNTHETIC_ZONE

FIXTURE = r"""
function sample(variant)
 local quests, stops={},{}
 local function add(qid,kind,x,target,deps)
  local id=#stops+1
  local s={id=id,kind=kind,point={map=1436,x=x,y=0.5},quests={[qid]="Quest "..qid},deps=deps or {}}
  if target then s.objectives={{questID=qid,target=target,sourceID=601,remaining=target.required,shareable=true}} end
  stops[id]=s
  return id
 end
 for id=1,8 do quests[id]={id=id,name="Quest "..id,status="ready",xp=id*100,prereqKinds={}} end
 quests[1].status="active"
 local a=add(1,"objective",0,{kind="kill",creditID=601,required=10})
 add(1,"turnin",0.4,nil,{[a]=true})
 local bp=add(2,"pickup",0.4)
 local b=add(2,"objective",0,{kind="loot",itemID=50,required=5,dropRates={[601]=0.25}},{[bp]=true})
 add(2,"turnin",0.4,nil,{[b]=true})
 local dp=add(4,"pickup",0.4)
 local d=add(4,"objective",0.6,nil,{[dp]=true})
 local dt=add(4,"turnin",0.4,nil,{[d]=true})
 local cp=add(3,"pickup",0.4,nil,{[dt]=true})
 local c=add(3,"objective",0,{kind="kill",creditID=601,required=8},{[cp]=true})
 add(3,"turnin",0.4,nil,{[c]=true})
 for qid=5,8 do
  local p=add(qid,"pickup",0.4)
  local o=add(qid,"objective",qid==5 and 0.2 or 0.6,nil,{[p]=true})
  add(qid,"turnin",0.4,nil,{[o]=true})
 end
 if variant=="sequential" then stops[cp].deps={[2]=true} end
 return quests,stops
end
function solve(mode,variant)
 local q,s=sample(variant)
 return NS.questOptimizer.optimize(q,s,{mode=mode or "all",origin={map=1436,x=0,y=0.5},
 travelSeconds=function(a,b)return math.abs(a.x-b.x)*100 end,killSeconds=10,interactionSeconds=3,
 selectedIDs={[3]=true},budgetSeconds=150,logCapacity=25,logCount=1})
end
"""
def game(style="modern"):
    return Game(style, WESTFALL+FIXTURE,fresh=True)

def test_eight_quest_simulation_prices_shared_drops(style):
    g=game(style)
    route, report=g.eval("solve")("all")
    expected=10+sum((5-j)*math.comb(10,j)*.25**j*.75**(10-j) for j in range(5))/.25
    assert abs(report.expectedKills-expected)<1e-8
    assert report.coverage==8 and report.expectedSeconds<report.baselineSeconds
    assert report.baselineComparable
    seen=set()
    for stop in route.values():
        for dep in stop.deps.keys(): assert dep in seen
        seen.add(stop.id)
    assert len(seen)==len(route)

def test_parent_handin_prevents_retroactive_credit(style):
    g=game(style)
    _,r=g.eval("solve")("all","sequential")
    # A must finish before C is accepted. Its ten kills can never satisfy C.
    assert r.expectedKills>=28

def test_distinct_modes_and_capacity(style):
    g=game(style)
    _,all_r=g.eval("solve")("all")
    _,selected=g.eval("solve")("selected")
    _,budget=g.eval("solve")("budget")
    _,xp=g.eval("solve")("xp")
    assert selected.completedIDs[3] and selected.completedIDs[4]
    assert not selected.plannedIDs[2] and selected.coverage<all_r.coverage
    assert budget.expectedSeconds<=150 and budget.coverage>0
    assert xp.expectedXP>0 and xp.mode=="xp"
    g.run('q,s=sample(); result,rep=NS.questOptimizer.optimize(q,s,{mode="all",logCapacity=1,logCount=1})')
    assert g.eval("rep.completedIDs[1]")

def test_mutual_exclusion_and_unavailable_source(style):
    g=game(style)
    g.run('''q,s=sample();q[2].exclusiveTo={3};q[3].exclusiveTo={2}
 r,rep=NS.questOptimizer.optimize(q,s,{mode="all"})
 ''')
    assert not (g.eval("rep.plannedIDs[2]") and g.eval("rep.plannedIDs[3]"))
    g.run('q,s=sample();s[4].objectives[1].target.dropRates[601]=0;r,rep=NS.questOptimizer.optimize(q,s,{mode="all"})')
    assert not g.eval("rep.completedIDs[2]")

def test_public_modes_report_and_no_login_work(style):
    g=game(style);g.start()
    assert not g.eval('NS.dataWork.busy("quest-plan")')
    g.slash("plan");g.advance(8)
    assert g.eval("NS.questPlanner.report")().mode=="all"
    g.slash("plan selected 9000");g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode=="selected"
    g.slash("plan budget 15");g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode=="budget"
    g.slash("plan options")
    assert g.eval("NS._settingsWindow().tab") == "guide" and g.eval("NS._settingsWindow().win.shown")
    g.slash("plan why")
    assert g.eval("QuestSharingReport.shown")
    g.slash("plan hide");g.advance(1)
    assert not g.eval('NS.dataWork.busy("quest-plan")')
    assert not g.eval("QuestSharingPlannerPanel.scripts.OnUpdate")

def test_provider_to_solver_predicts_before_farming(style):
    setup=r"""
QUESTS={{id=9000,title="Local Harvest",level=8,objectives={{text="Harvest Watcher slain: 0/10",type="monster",have=0,need=10}}}}
QUESTIE_NPCS[601].spawns={[40]={{50,50}}}
QUESTIE_QUESTS[9000].objectivesText={"Kill 10 Harvest Watchers."}
QUESTIE_QUESTS[9010]={name="Harvest Cores",questLevel=8,startedBy={{600}},finishedBy={{600}},
 objectives={nil,nil,{{50}}},objectivesText={"Collect 5 Harvest Cores."}}
QUESTIE_ITEMS[50]={name="Harvest Core",npcDrops={601}}
ItemDB.Get=function(id,key)local t=QUESTIE_ITEMS[id];return t and t[key]end
local old=QuestieLoader.ImportModule
QuestieLoader.ImportModule=function(self,name)
 if name=="DropDB" then return {GetItemDroprate=function()return {25,"fixture"}end} end
 return old(self,name)
end
"""
    g=Game(style,WESTFALL+setup,fresh=True);g.start();g.slash("plan");g.advance(12)
    r=g.eval("NS.questPlanner.report")()
    assert r.coverage==2 and abs(r.expectedKills-20.094718933105)<1e-6
    assert "Pick up Harvest Cores" in rows(g)[0].detail.text
    assert r.expectedSeconds<r.baselineSeconds
    g.slash("plan hide");g.fire("BAG_UPDATE_DELAYED");g.advance(4)
    assert not g.eval('NS.dataWork.busy("quest-plan")')

def test_cost_can_favor_working_now_and_expiry_is_respected(style):
    g=game(style)
    g.run("""
q,s=sample()
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin={map=1436,x=0,y=.5},
travelSeconds=function(a,b)return math.abs(a.x-b.x)*100 end,killSeconds=10,interactionSeconds=3,
availableAfter={[3]=1000}})
""")
    assert g.eval("r[1].id")==1  # Work A now while B's pickup is unavailable.
    assert g.eval("rep.coverage")==8
    assert g.eval("rep.expectedSeconds")<g.eval("rep.baselineSeconds")
    g.run("""
q,s=sample();q[2].availableUntilCompleted=1
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin={map=1436,x=0,y=.5}})
""")
    seen=False
    for stop in g.eval("r").values():
        if stop.id==2: seen=True
        if stop.id==3: assert not seen

def test_unknown_rates_and_same_name_counts_cannot_fabricate_progress(style):
    g=game(style)
    g.run('q,s=sample();s[4].objectives[1].target.dropRates={};r,rep=NS.questOptimizer.optimize(q,s,{mode="all"})')
    assert g.eval("rep.uncertain")
    assert g.eval("rep.expectedKills")>=10
    # Live collection has the same NPC in its text but must not finish a kill counter.
    g=Game(style,WESTFALL+"""
QUESTS={{id=9000,title="Local Harvest",level=8,objectives={
{text="Harvest Watcher: 8/8",type="item",have=8,need=8,finished=true}}}}
""",fresh=True)
    g.start();g.slash("plan");g.advance(6)
    assert "Kill Harvest Watcher" in text(g)

def test_movement_replans_without_world_rediscovery_and_close_cancels(style):
    g=game(style)
    g.run("ENUMS=0;local old=QuestDB.GetAllIds;QuestDB.GetAllIds=function() ENUMS=ENUMS+1;return old() end")
    g.start();g.slash("plan");g.advance(7)
    assert g.eval("ENUMS")==1
    g.run("POS={x=.85,y=.75}")
    g.advance(3);g.advance(6)
    assert g.eval("ENUMS")==1 and g.eval("NS.questPlanner.report")()
    g.slash("plan hide")
    g.run("POS={x=.1,y=.1}")
    g.advance(8)
    assert g.eval("ENUMS")==1
    assert not g.eval('NS.dataWork.busy("quest-improve")')

def test_real_log_full_requires_handin_before_a_new_pickup(style):
    g=game(style)
    g.run("""
q,s=sample()
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",logCapacity=1,logCount=1})
""")
    live={1}
    for stop in g.eval("r").values():
        qid=next(iter(stop.quests))
        if stop.kind=="pickup":
            assert len(live)<1
            live.add(qid)
        elif stop.kind=="turnin":live.remove(qid)

def test_carried_items_are_counted_and_bank_items_ignored(style):
    g=game(style)
    g.run("""
BAGS[0]={{id=50,count=2},{id=80,count=4}}
BAGS[1]={{id=50,count=3}}
BAGS[-1]={{id=50,count=99}}
local original=C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo=function(bag,slot)
 local item=original(bag,slot)
 if item then item.stackCount=BAGS[bag][slot].count end
 return item
end
""")
    counts=g.eval("NS.compat.plannerInventory")(
        g.lua.table_from({50:True}))
    assert counts.counts[50]==5
    assert counts.counts[80] is None
    assert counts.freeSlots>=0

def test_consumed_item_and_new_quest_loot_update_search_state(style):
    g=game(style)
    g.run("""
q,s=sample()
q[2].consumedItems={[50]=5}
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",inventory={counts={},freeSlots=1}})
""")
    assert g.eval("rep.completedIDs[2]")
    g.run("""
q,s=sample()
q[1].consumedItems={[50]=5}
q[2].consumedItems={[50]=10}
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",inventory={counts={[50]=5},freeSlots=0}})
""")
    assert g.eval("rep.completedIDs[1]") or g.eval("rep.completedIDs[2]")
    # A single carried stack cannot be consumed twice.
    assert not (g.eval("rep.completedIDs[1]") and g.eval("rep.completedIDs[2]"))
    g.run("""
q,s=sample()
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",inventory={counts={},freeSlots=0}})
""")
    assert not g.eval("rep.completedIDs[2]")

def test_known_one_level_threshold_unlocks_future_pickup(style):
    g=game(style)
    g.run("""
q,s=sample()
q[1].xp=100
q[2].requiredLevel=11
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",level=10,currentXP=90,nextLevelXP=100})
""")
    assert g.eval("rep.completedIDs[2]")
    ids=[stop.id for stop in g.eval("r").values()]
    assert any(stop.kind=="turnin" for stop in list(g.eval("r").values())[:ids.index(3)])
    g.run("""
q,s=sample()
q[2].requiredLevel=12
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",level=10,currentXP=90,nextLevelXP=100})
""")
    assert not g.eval("rep.completedIDs[2]")


def test_reputation_reward_unlocks_pickup_and_maximum_closes_it(style):
    g=game(style)
    g.run('''
q,s=sample()
q[1].reputationReward={[72]=300}
q[2].requiredMinRep={72,3000}
q[2].status="reputation"
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",reputation={[72]=2800}})
''')
    route=[stop.id for stop in g.eval("r").values()]
    assert g.eval("rep.completedIDs[2]") and route.index(2)<route.index(3)
    g.run('''
q,s=sample()
q[1].reputationReward={[72]=300}
q[2].requiredMaxRep={72,3000}
q[2].status="reputation"
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",reputation={[72]=2900}})
''')
    route=[stop.id for stop in g.eval("r").values()]
    assert not (2 in route and 3 in route and route.index(2)<route.index(3))


def test_skill_requirement_and_or_rank_gate(style):
    g=game(style)
    g.run('''
q,s=sample()
q[2].requiredSkill={164,75}
q[2].requiredRanks={{164,100},{165,50}}
q[2].status="future"
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",skillRanks={[164]=80,[165]=55}})
''')
    assert g.eval("rep.completedIDs[2]")
    g.run('''
q,s=sample()
q[2].requiredSkill={164,75}
q[2].requiredRanks={{164,100},{165,50}}
q[2].status="future"
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",skillRanks={[164]=80,[165]=40}})
''')
    assert not g.eval("rep.completedIDs[2]")


def test_two_active_drop_streams_keep_joint_probability_uncertain(style):
    g=game(style)
    g.run('''
local p={map=1436,x=.5,y=.5}
q={[1]={name="A",status="active"},[2]={name="B",status="active"}}
s={
 {id=1,kind="objective",point=p,quests={[1]="A"},deps={},objectives={{questID=1,
  target={kind="loot",itemID=50,required=2,dropRates={[601]=.5}},sourceID=601,remaining=2,shareable=true}}},
 {id=2,kind="objective",point=p,quests={[2]="B"},deps={},objectives={{questID=2,
  target={kind="loot",itemID=51,required=2,dropRates={[601]=.5}},sourceID=601,remaining=2,shareable=true}}},
 {id=3,kind="turnin",point=p,quests={[1]="A"},deps={[1]=true}},
 {id=4,kind="turnin",point=p,quests={[2]="B"},deps={[2]=true}}
}
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin=p,killSeconds=10})
''')
    report=g.eval("rep")
    assert report.coverage==2 and report.uncertain
    bounds=list(report.lootBounds.values())
    assert len(bounds)==1 and bounds[0].lowerKills==4 and bounds[0].upperKills==8
    assert "joint rate unknown" in report.reasons[2]


def test_tiny_route_matches_exhaustive_reference_for_four_goals(style):
    g=game(style)
    g.run('''
function tiny(mode)
 local q,s={},{}
 for id,x in ipairs({.1,.4,.8}) do
  q[id]={name="Quest "..id,status="ready",xp=id==3 and 500 or id*100}
  s[2*id-1]={id=2*id-1,kind="pickup",point={map=1436,x=x,y=.5},quests={[id]="Quest "..id},deps={}}
  s[2*id]={id=2*id,kind="turnin",point={map=1436,x=x,y=.5},quests={[id]="Quest "..id},
   deps={[2*id-1]=true}}
 end
 return NS.questOptimizer.optimize(q,s,{mode=mode,selectedIDs={[3]=true},budgetSeconds=95,
  origin={map=1436,x=0,y=.5},travelSeconds=function(a,b)return math.abs(a.x-b.x)*100 end,
  interactionSeconds=2,logCapacity=2,logCount=0})
end
''')
    def exhaustive(mode):
        best=None
        def score(done, steps, spent):
            xp=sum({1:100,2:200,3:500}[q] for q in done)
            if mode=="xp":return (xp/spent if spent else 0,xp,-spent)
            if mode=="selected":return (int(3 in done),sum(q==3 for _,q in steps),-spent)
            if mode=="budget":return (len(done),-spent,0)
            return (len(done),-spent,len(steps))
        def walk(opened,done,steps,at,spent):
            nonlocal best
            candidate=(score(done,steps,spent),spent,len(done))
            if best is None or candidate[0]>best[0]:best=candidate
            for q in (1,2,3):
                if mode=="selected" and q!=3:continue
                x={1:.1,2:.4,3:.8}[q]
                cost=abs(x-at)*100+2
                if mode=="budget" and spent+cost>95:continue
                if q in opened:
                    walk(opened-{q},done|{q},steps+[("turnin",q)],x,spent+cost)
                elif q not in done and len(opened)<2:
                    walk(opened|{q},done,steps+[("pickup",q)],x,spent+cost)
        walk(set(),set(),[],0,0)
        return best
    for mode in ("all","selected","xp","budget"):
        _,report=g.eval("tiny")(mode)
        expected=exhaustive(mode)
        assert abs(report.expectedSeconds-expected[1])<1e-8, (mode,report.expectedSeconds,expected)
        assert report.coverage==expected[2], (mode,report.coverage,expected)


def test_search_budget_keeps_feasible_incumbent(style):
    g=game(style)
    g.run('''
q,s=sample()
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",maxSearchChecks=1})
''')
    assert g.eval("rep.coverage")==8
    assert g.eval("rep.searchExhausted")
    assert len(list(g.eval("r").values()))>0

def test_selected_quest_chooses_cheaper_or_prerequisite(style):
    g=game(style)
    g.run("""
local function step(id, qid, kind, x, dep)
 return {id=id,kind=kind,point={map=1436,x=x,y=.5},
 quests={[qid]="Quest "..qid},deps=dep or {}}
end
q={
 [1]={name="Near pickup, far work",status="ready",gates={}},
 [2]={name="Second route",status="ready",gates={}},
 [3]={name="Selected followup",status="future",
      gates={{kind="turnin",choices={1,2}}}},
}
s={
 step(1,1,"pickup",.05),step(2,1,"objective",.95,{[1]=true}),step(3,1,"turnin",.05,{[2]=true}),
 step(4,2,"pickup",.20),step(5,2,"objective",.20,{[4]=true}),step(6,2,"turnin",.20,{[5]=true}),
 step(7,3,"pickup",.20),step(8,3,"turnin",.20,{[7]=true})
}
r,rep=NS.questOptimizer.optimize(q,s,{mode="selected",selectedIDs={[3]=true},
 origin={map=1436,x=0,y=.5},travelSeconds=function(a,b)return math.abs(a.x-b.x)*1000 end})
""")
    assert g.eval("rep.completedIDs[3]")
    assert g.eval("rep.completedIDs[2]")
    assert not g.eval("rep.completedIDs[1]")
    route=[stop.id for stop in g.eval("r").values()]
    assert route.index(6)<route.index(7)

SITES = r"""
function siteFixture()
 local q={[1]={id=1,name="Wolves",status="active",xp=100},[2]={id=2,name="Pelts",status="active",xp=100}}
 local function kill(id,qid,x,need,alts)
  return {id=id,kind="objective",point={map=1436,x=x,y=.5},quests={[qid]=q[qid].name},deps={},alternatives=alts,
   objectives={{questID=qid,target={kind="kill",creditID=601,required=need},sourceID=601,remaining=need,shareable=true}}}
 end
 local s={
  kill(1,1,.1,10),
  kill(2,2,.9,6,{{point={map=1436,x=.1,y=.5},sourceID=601,tasks={"Wolves at the west camp"},questTasks={[2]={"Wolves at the west camp"}}}}),
  {id=3,kind="turnin",point={map=1436,x=.5,y=.5},quests={[1]="Wolves"},deps={[1]=true}},
  {id=4,kind="turnin",point={map=1436,x=.5,y=.5},quests={[2]="Pelts"},deps={[2]=true}},
 }
 return q,s
end
"""

def test_alternative_site_joins_the_camp_already_farmed(style):
    g=Game(style,WESTFALL+FIXTURE+SITES,fresh=True)
    g.run('''
q,s=siteFixture()
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin={map=1436,x=.5,y=.5},
 travelSeconds=function(a,b)return math.abs(a.x-b.x)*100 end,killSeconds=10,interactionSeconds=3})
''')
    # Both quests farm the same west camp: ten shared kills cover the six as well.
    assert abs(g.eval("rep.expectedKills")-10)<1e-9
    route=list(g.eval("r").values())
    pelts=[stop for stop in route if stop.id==2][0]
    assert abs(pelts.point.x-.1)<1e-9 and pelts.tasks[1]=="Wolves at the west camp"
    # The caller's stop keeps the planner's default place.
    assert abs(g.eval("s[2].point.x")-.9)<1e-9

def test_local_search_repairs_a_nearest_first_detour(style):
    g=Game(style,WESTFALL+FIXTURE,fresh=True)
    g.run('''
q={[1]={id=1,name="A",status="active"},[2]={id=2,name="B",status="active"},[3]={id=3,name="C",status="active"}}
local function hand(id,x) return {id=id,kind="turnin",point={map=1436,x=x,y=.5},quests={[id]=q[id].name},deps={}} end
s={hand(1,.6),hand(2,.35),hand(3,1)}
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin={map=1436,x=.5,y=.5},maxSearchChecks=1,
 travelSeconds=function(a,b)return math.abs(a.x-b.x)*100 end,interactionSeconds=0})
''')
    # Nearest-first walks .6, .35, 1 (100 s); 2-opt/or-opt finds .35, .6, 1 (80 s).
    assert abs(g.eval("rep.nearestSeconds")-100)<1e-6
    assert abs(g.eval("rep.expectedSeconds")-80)<1e-6
    assert g.eval("rep.improveMoves")>=1
    assert [stop.id for stop in g.eval("r").values()]==[2,1,3]

def test_same_creature_camps_share_kills_across_quests_in_the_planner(style):
    setup=r"""
QUESTS={{id=9000,title="Local Harvest",level=8,objectives={{text="Harvest Watcher slain: 0/10",type="monster",have=0,need=10}}}}
QUESTIE_NPCS[601].spawns={[40]={{30,30},{31,31},{32,30}}}
QUESTIE_NPCS[602]={name="Harvest Reaper",spawns={[40]={{34,31},{35,32},{36,31}}}}
QUESTIE_QUESTS[9000].objectivesText={"Kill 10 Harvest Watchers."}
QUESTIE_QUESTS[9010]={name="Harvest Cores",questLevel=8,startedBy={{600}},finishedBy={{600}},
 objectives={nil,nil,{{50}}},objectivesText={"Collect 5 Harvest Cores."}}
QUESTIE_ITEMS[50]={name="Harvest Core",npcDrops={601,602}}
ItemDB.Get=function(id,key)local t=QUESTIE_ITEMS[id];return t and t[key]end
local old=QuestieLoader.ImportModule
QuestieLoader.ImportModule=function(self,name)
 if name=="DropDB" then return {GetItemDroprate=function()return {25,"fixture"}end} end
 return old(self,name)
end
"""
    g=Game(style,WESTFALL+setup,fresh=True);g.start();g.slash("plan");g.advance(12)
    r=g.eval("NS.questPlanner.report")()
    # The cores drop from both creatures; the Reaper camp is nearer, but the Watcher camp is the very
    # same point as the kill quest's, so ten kills there also yield the cores (joint expectation).
    assert r.coverage==2 and abs(r.expectedKills-20.094718933105)<1e-6, r.expectedKills

# The priority each shared-work job was started with (DataWork's sixth argument; nil is a normal job).
JOB_PRIORITIES = r'''
JOB_PRIORITY={}
local start=NS.dataWork.start
NS.dataWork.start=function(owner,run,valid,finished,budget,priority,...)
 JOB_PRIORITY[owner]=tostring(priority)
 return start(owner,run,valid,finished,budget,priority,...)
end
'''

def test_planner_shows_fast_route_then_refines_it_in_the_background(style):
    g=Game(style,WESTFALL,fresh=True);g.run(JOB_PRIORITIES);g.start();g.slash("plan");g.advance(12)
    r=g.eval("NS.questPlanner.report")()
    # The background refinement re-solves with local search after the first route is shown.
    assert r.improveSteps and r.improveSteps>0, r.improveSteps
    # It is idle work: it runs only while no other data work (map search, dungeon scan, the plan itself) waits.
    assert g.eval('JOB_PRIORITY["quest-improve"]')=="idle",g.eval('JOB_PRIORITY["quest-improve"]')
    assert g.eval('JOB_PRIORITY["quest-plan"]')=="nil"
    assert not g.eval('NS.dataWork.busy("quest-improve")')
    g.slash("plan hide");g.advance(2)
    assert not g.eval('NS.dataWork.busy("quest-improve")')

# Keeps the background refinement busy after its search, so the player can act before its route swaps in.
PAD_REFINE = r'''
local real=NS.questOptimizer.optimize
NS.questOptimizer.optimize=function(catalog,stops,opts)
 local a,b=real(catalog,stops,opts)
 if (opts.maxImproveSteps or 0)>0 then for _=1,5000 do NS.dataWork.checkpoint() end end
 return a,b
end
'''

def test_step_chosen_during_background_refinement_survives_the_route_swap(style):
    from test_quest_guidance import game as guide_game, markers, click
    for action in ("next", "map"):
        g=guide_game(style);g.run(PAD_REFINE)
        g.run("WorldMapFrame:Show()");g.slash("plan");g.advance(1)
        assert g.eval('NS.dataWork.busy("quest-improve")')
        if action=="next":
            g.slash("plan next");g.slash("plan next");want=3
        else:
            click(g,next(p for p in markers(g) if list(p.steps.values())==[2]));want=2
        waypoint=(g.eval("WAYPOINT.x"),g.eval("WAYPOINT.y"))
        for _ in range(300):
            g.advance(0.1)
            if not g.eval('NS.dataWork.busy("quest-improve")'):break
        assert not g.eval('NS.dataWork.busy("quest-improve")')
        assert g.eval("NS.questPlanner.report")().improveSteps>0
        current=[r for r in rows(g) if r.current]
        assert current
        assert current[0].stepIndex==want,(action,current[0].stepIndex)
        assert (g.eval("WAYPOINT.x"),g.eval("WAYPOINT.y"))==waypoint
        assert "%.1f, %.1f"%(waypoint[0]*100,waypoint[1]*100) in current[0].title.text,(action,current[0].title.text)
        assert [p.selectedStop for p in markers(g) if p.selectedStop]==[want]

COUNT_REFINES = r'''
REFINES=0
local real=NS.questOptimizer.optimize
NS.questOptimizer.optimize=function(catalog,stops,opts)
 if (opts.maxImproveSteps or 0)>0 then REFINES=REFINES+1 end
 return real(catalog,stops,opts)
end
'''

def test_local_search_runs_again_only_when_the_plan_inputs_change(style):
    g=Game(style,WESTFALL,fresh=True);g.run(COUNT_REFINES);g.start();g.slash("plan");g.advance(8)
    assert g.eval("REFINES")==1
    # Small moves re-plan from the new position (starting from the refined order) without a new local search.
    for x in (0.53,0.5,0.53):
        g.run(f"POS.x, POS.y = {x}, {x}");g.advance(4)
        assert "plan origin: map 1436 (%.4f, %.4f)"%(x,x) in g.eval("NS.questPlanner.debugText")()
    assert g.eval("REFINES")==1
    assert not g.eval('NS.dataWork.busy("quest-improve")')
    # Real movement, or another goal, refines again.
    g.run("POS.x, POS.y = 0.6, 0.6");g.advance(4)
    assert g.eval("REFINES")==2
    g.slash("plan xp");g.advance(5)
    assert g.eval("REFINES")==3

def test_local_search_gate_holds_with_any_spf_build(style):
    from test_quest_planner_zone_steps import SPF_BUILDS, spf_tick
    # SPF is never asked for walking estimates, so every build plans and refines exactly as without SPF:
    # one local search, and small moves re-plan without a new one.
    for spf in SPF_BUILDS:
        g=Game(style,WESTFALL+spf,fresh=True);g.run(COUNT_REFINES);g.start();g.slash("plan");spf_tick(g,8)
        assert g.eval("REFINES")==1,(spf,g.eval("REFINES"))
        for x in (0.53,0.5,0.53,0.5):
            g.run(f"POS.x, POS.y = {x}, {x}");spf_tick(g,4)
            assert "plan origin: map 1436 (%.4f, %.4f)"%(x,x) in g.eval("NS.questPlanner.debugText")()
        assert g.eval("REFINES")==1,(spf,g.eval("REFINES"))
        assert g.eval("SPF_ESTIMATES")==0,spf
        assert not g.eval('NS.dataWork.busy("quest-improve")')

SOLVE_LOG = r'''
EVENTS={}
local real=NS.questOptimizer.optimize
NS.questOptimizer.optimize=function(catalog,stops,opts)
 local a,b=real(catalog,stops,opts)
 EVENTS[#EVENTS+1]="solve "..tostring(opts.maxImproveSteps or 0)
 return a,b
end
local G=NS.questGuidance
local set=G.set
G.set=function(...) EVENTS[#EVENTS+1]="render";return set(...) end
'''

def test_route_shows_at_once_then_local_search_follows_with_or_without_spf(style):
    from test_quest_planner_zone_steps import TWO_CAMPS, SPF_BUILDS, spf_tick
    runs=[]
    for spf in ("",)+SPF_BUILDS:
        g=Game(style,WESTFALL+TWO_CAMPS+spf,fresh=True);g.run(SOLVE_LOG)
        g.start();g.eval("NS.setSetting")("questPlanner",True);spf_tick(g,8)
        runs.append(list(g.eval("EVENTS").values()))
        assert g.eval("SPF_ESTIMATES or 0")==0,spf
    # The straight-line schedule renders first; the background local search runs after it and swaps in.
    assert runs[0][:2]==["solve 0","render"],runs[0]
    assert "solve 250000" in runs[0][2:],runs[0]
    # No extra solve waits for SPF: the sequence is the same with every build.
    assert all(run==runs[0] for run in runs),runs

# Two hand-ins either side of the player: which order is cheaper depends only on small moves of the origin.
STABLE = r'''
function pair(originX, scale, mode, preferred, extra)
 local q={[1]={id=1,name="West",status="active",xp=100},[2]={id=2,name="East",status="active",xp=100}}
 local s={{id=1,kind="turnin",point={map=1436,x=.3,y=.5},quests={[1]="West"},deps={}},
  {id=2,kind="turnin",point={map=1436,x=.7,y=.5},quests={[2]="East"},deps={}}}
 local opts={mode=mode,origin={map=1436,x=originX,y=.5},preferredIDs=preferred,interactionSeconds=0,
  travelSeconds=function(a,b) return math.abs(a.x-b.x)*scale end}
 for k,v in pairs(extra or {}) do opts[k]=v end
 local r,rep=NS.questOptimizer.optimize(q,s,opts)
 local ids={}
 for i,stop in ipairs(r) do ids[i]=stop.id end
 return ids,rep
end
'''

def order(g, x, previous=None, scale=100, mode="all", **extra):
    ids, rep = g.eval("pair")(x, scale, mode, g.lua.table_from(previous) if previous else None,
                              g.lua.table_from(extra) if extra else None)
    return list(ids.values()), rep

def test_previous_route_stays_until_a_clearly_better_one_appears(style):
    g=Game(style,WESTFALL+FIXTURE+STABLE,fresh=True)
    route,rep=order(g,.48)
    assert route==[1,2] and not rep.keptPrevious
    # Each small move makes the other order 4 s cheaper; re-planning from the previous order must never flip.
    for extra in ({}, {"stabilitySeconds":10}):
        for x in (.52,.48,.52,.48,.52):
            new,rep=order(g,x,route,**extra)
            assert new==route,(extra,x,new)
            assert bool(rep.keptPrevious)==(x==.52),(extra,x,rep.keptPrevious)
    # 30 s better replaces the previous order.
    new,rep=order(g,.65,route)
    assert new==[2,1] and not rep.keptPrevious
    # 11 s: kept with the default margin (12 s), replaced with the planner's 10 s.
    assert order(g,.555,route)[0]==route
    assert order(g,.555,route,stabilitySeconds=10)[0]==[2,1]
    # Long routes: a saving under 5 % of the previous route's time is noise too (20 s of 610 s), 60 s of 630 s is not.
    new,rep=order(g,.51,route,scale=1000)
    assert new==route and rep.keptPrevious
    assert order(g,.53,route,scale=1000)[0]==[2,1]

def test_more_coverage_always_replaces_the_previous_route(style):
    g=Game(style,WESTFALL+FIXTURE,fresh=True)
    g.run('''
q={[1]={id=1,name="Near",status="ready",xp=100,exclusiveTo={2}},[2]={id=2,name="Far",status="ready",xp=100,exclusiveTo={1}},
 [3]={id=3,name="Follow-up",status="future",xp=100,gates={{kind="turnin",choices={2}}}}}
local function at(id,qid,kind,x,deps) return {id=id,kind=kind,point={map=1436,x=x,y=.5},quests={[qid]=q[qid].name},deps=deps or {}} end
s={at(1,1,"pickup",.45),at(2,1,"turnin",.45,{[1]=true}),at(3,2,"pickup",.9),at(4,2,"turnin",.9,{[3]=true}),
 at(5,3,"pickup",.9),at(6,3,"turnin",.9,{[5]=true})}
r,rep=NS.questOptimizer.optimize(q,s,{mode="all",origin={map=1436,x=.5,y=.5},preferredIDs={1,2},interactionSeconds=0,
 travelSeconds=function(a,b) return math.abs(a.x-b.x)*100 end})
''')
    # The previous order (the near quest, 5 s) blocks two quests; the 40 s route hands in two and wins.
    assert [stop.id for stop in g.eval("r").values()]==[3,4,5,6]
    assert g.eval("rep.coverage")==2 and not g.eval("rep.keptPrevious")

def test_xp_goal_keeps_the_previous_route_within_five_percent_xp_rate(style):
    g=Game(style,WESTFALL+FIXTURE+STABLE,fresh=True)
    route,_=order(g,.502,mode="xp")
    assert route==[2]
    # The west quest earns about 2 % more XP per second from here: noise, the previous route stays.
    new,rep=order(g,.498,route,mode="xp")
    assert new==route and rep.keptPrevious
    # About 67 % more XP per second replaces it.
    new,rep=order(g,.45,route,mode="xp")
    assert new==[1] and not rep.keptPrevious


# Wraps the optimizer's internal evaluate() (reached through upvalues) to see every local-search candidate.
HORIZON_PROBE = r'''
local function upvalue(f, name)
 local i = 1
 while true do
  local n, v = debug.getupvalue(f, i)
  if n == nil then return nil end
  if n == name then return v, i end
  i = i + 1
 end
end
local improve, evaluate, slot -- the addon loads after this setup, so look them up on first use
function probe(limit)
 if not improve then
  improve = upvalue(NS.questOptimizer.optimize, "improve")
  evaluate, slot = upvalue(improve, "evaluate")
 end
 PROBE = { candidates = 0, beyond = 0, deepest = 0 }
 local current
 debug.setupvalue(improve, slot, function(m, path, from, saved, bound, record)
  if record then current = path -- the incumbent, replayed to record resume states
  else
   local deepest = 0
   for i = 1, math.max(#path, #current) do if path[i] ~= current[i] then deepest = i end end
   PROBE.candidates, PROBE.deepest = PROBE.candidates + 1, math.max(PROBE.deepest, deepest)
   if deepest > limit then PROBE.beyond = PROBE.beyond + 1 end
  end
  return evaluate(m, path, from, saved, bound, record)
 end)
end
function bigZone(n, extra)
 TRAVELS = 0
 local q, s = syntheticZone(n)
 local opts = {mode="all", origin={map=1436,x=.5,y=.5}, killSeconds=10, interactionSeconds=3, maxImproveSteps=250000,
  travelSeconds=function(a, b) TRAVELS = TRAVELS + 1; local x, y = a.x - b.x, a.y - b.y; return math.sqrt(x*x + y*y) * 600 end}
 for k, v in pairs(extra or {}) do opts[k] = v end
 ROUTE, REPORT = NS.questOptimizer.optimize(q, s, opts)
 return REPORT
end
'''

def test_local_search_moves_only_actions_inside_the_horizon(style):
    g=Game(style,WESTFALL+SYNTHETIC_ZONE+HORIZON_PROBE,fresh=True)
    # 150 actions: candidates differ from the incumbent only in the first 12 (default) or 20 positions.
    for horizon,extra in ((12,None),(20,{"horizon":20})):
        g.eval("probe")(horizon)
        report=g.eval("bigZone")(50,g.lua.table_from(extra) if extra else None)
        probe=g.eval("PROBE")
        assert report.coverage==50 and probe.candidates>0
        assert probe.beyond==0,(horizon,probe.beyond,probe.deepest)
        assert probe.deepest==horizon,(horizon,probe.deepest)
    # 15 actions (<= 16): the horizon covers the whole route.
    g.eval("probe")(12)
    report=g.eval("bigZone")(5)
    assert report.coverage==5 and g.eval("PROBE.deepest")==15,g.eval("PROBE.deepest")

# Measured on the code before the horizon (beam search + whole-route local search), same zone and options:
# the local search used its whole budget (250055 simulated actions) and the solve asked 286871 travel estimates.
BEFORE_IMPROVE_STEPS, BEFORE_TRAVELS = 250055, 286871

def test_horizon_cuts_the_work_on_a_fifty_quest_zone(style):
    g=Game(style,WESTFALL+SYNTHETIC_ZONE+HORIZON_PROBE,fresh=True)
    report=g.eval("bigZone")(50)
    assert report.coverage==50 and report.expectedSeconds<report.nearestSeconds
    assert not report.improveExhausted
    assert report.improveSteps<BEFORE_IMPROVE_STEPS/2,report.improveSteps
    assert g.eval("TRAVELS")<BEFORE_TRAVELS/2,g.eval("TRAVELS")

def test_search_exhausted_reports_only_the_seed_budget(style):
    g=game(style)
    _,small=g.eval("solve")("all")
    assert not small.searchExhausted
    g=Game(style,WESTFALL+SYNTHETIC_ZONE+HORIZON_PROBE,fresh=True)
    # The seeds of a 150-action zone use up the default 36000 checks; the report says so.
    report=g.eval("bigZone")(50,g.lua.table_from({"maxImproveSteps":0}))
    assert report.searchChecks>=36000 and report.searchExhausted


def test_stability_margin_is_capped_at_sixty_seconds_on_long_routes(style):
    g=Game(style,WESTFALL+FIXTURE+HORIZON_PROBE,fresh=True)
    g.run(r'''
local i, f = 1, nil
while true do
 local n, v = debug.getupvalue(NS.questOptimizer.optimize, i)
 if n == nil then break end
 if n == "keepPrevious" then f = v end
 i = i + 1
end
KEEP = f
''')
    keep=g.eval("KEEP")
    T=g.lua.table_from
    def kept(prev, new, mode="all", stab=None):
        return keep(mode, T({1:1, 2:-prev, "time":prev}), T({1:1, 2:-new, "time":new}), stab)
    # 50 min route: 5 % would be 150 s; the cap keeps the bar at 60 s, so a 70 s saving replaces it.
    assert not kept(3000, 2930)
    assert kept(3000, 2950)            # 50 s: below the 60 s cap, kept
    assert kept(610, 590)              # 20 s on a 610 s route: below max(12, 30.5), kept
    assert not kept(630, 570)          # 60 s on a 630 s route: above 31.5, replaced
    assert kept(100, 92) and not kept(100, 85)   # short routes: the 12 s floor

def test_mid_size_zone_is_polished_over_the_whole_route(style):
    g=Game(style,WESTFALL+SYNTHETIC_ZONE+HORIZON_PROBE,fresh=True)
    g.eval("probe")(12)
    report=g.eval("bigZone")(12)      # 36 actions: at most 40, so the whole route may move
    assert report.coverage==12
    assert g.eval("PROBE.deepest")>12,g.eval("PROBE.deepest")
    assert report.expectedSeconds<report.nearestSeconds,(report.expectedSeconds,report.nearestSeconds)

if __name__=="__main__":
    failed=total=0
    for name,test in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in ("modern","classic"):
            total+=1
            try:test(style);print("ok",name,style)
            except Exception as e:failed+=1;print("FAIL",name,style,repr(e))
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
