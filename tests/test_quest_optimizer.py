"""Predictive decisions and their independent probability/cost expectations."""
import math
from harness import Game
from test_quest_planner_zone_steps import WESTFALL, text, rows

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
    assert g.eval("QuestSharingPlannerOptions.shown")
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
    assert not g.eval('NS.dataWork.busy("quest-costs")')

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
