"""Character-specific zone discovery and data contracts for predictive routing."""
from test_quest_planner_zone_steps import WESTFALL, game, text
from harness import Game


def test_dropdb_percent_and_evidence(style):
    g = Game(style, WESTFALL + '''
QuestieLoader.ImportModule=function(_,name) if name=="DropDB" then return {
 GetItemDroprate=function(i,n) return {({[601]=0.25,[602]=1,[603]=0,[604]=105})[n],"cmangos"} end} end end
QUESTIE_QUESTS[9000].objectives={nil,nil,{{50,"icon?",999}}}
QUESTIE_QUESTS[9000].objectivesText={"Bring 5 Harvest Cores."}
ItemDB.Get=function(i,k) if k=="name" then return "Harvest Core" elseif k=="npcDrops" then return {601,602,603,604} end end
''', fresh=True)
    g.start()
    q=g.eval("NS.questie.plannerQuest")(9000)
    t=q.targets[1]
    assert t.itemID==50 and t.required==5 and t.countSource=="description"
    assert t.dropRates[601]==0.0025 and t.dropRates[602]==0.01 and t.dropRates[603]==0 and t.dropRates[604] is None
    assert t.rateSources[601]=="cmangos"


def test_reputation_pairs_and_character_snapshot(style):
    g=Game(style, WESTFALL + '''
QUESTIE_QUESTS[9000].requiredMinRep={72,3000}
QUESTIE_QUESTS[9000].requiredMaxRep={73,21000}
QUESTIE_QUESTS[9000].reputationReward={{72,250},{72,50},{73,-25}}
C_Reputation={GetFactionDataByID=function(id)
 if id==72 then return {currentStanding=2900} end
end}
GetFactionInfoByID=function(id)
 if id==73 then return "Faction",nil,nil,9000,21000,10000 end
end
''',fresh=True)
    g.start()
    q=g.eval("NS.questie.plannerQuest")(9000)
    assert q.requiredMinRep[1]==72 and q.requiredMinRep[2]==3000
    assert q.requiredMaxRep[1]==73 and q.requiredMaxRep[2]==21000
    assert q.reputationReward[72]==300 and q.reputationReward[73]==-25
    snapshot=g.eval("NS.compat.plannerReputation")(g.lua.table_from({72:True,73:True}))
    assert snapshot[72]==2900 and snapshot[73]==10000


def test_local_reputation_reward_unlocks_later_quest(style):
    g=game(style, '''
QUESTIE_QUESTS[9000].reputationReward={{72,300}}
QUESTIE_QUESTS[9010]={name="Faction Followup",questLevel=8,startedBy={{600}},finishedBy={{600}},
 requiredMinRep={72,3000}}
C_Reputation={GetFactionDataByID=function(id)
 if id==72 then return {currentStanding=2800} end
end}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id) return id~=9010 end,
  IsDoableVerbose=function() return "low reputation",true,9 end,
  DoableStates={MISSING_REPUTATION=9}
 } end
end
''')
    report=g.eval("NS.questPlanner.report")()
    assert report.completedIDs[9000] and report.completedIDs[9010]
    planned=[next(iter(stop.quests.keys())) for stop in g.eval("NS.questPlanner.report")().baselineRoute.values()]
    assert 9010 in planned


def test_visible_reputation_change_replans_selected_quest(style):
    g=game(style, '''
REP=2800
QUESTIE_QUESTS[9010]={name="Faction Followup",questLevel=8,startedBy={{600}},finishedBy={{600}},
 requiredMinRep={72,3000}}
C_Reputation={GetFactionDataByID=function(id)
 if id==72 then return {currentStanding=REP} end
end}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id) return id~=9010 end,
  IsDoableVerbose=function() return "low reputation",true,9 end,
  DoableStates={MISSING_REPUTATION=9}
 } end
end
''')
    g.slash("plan selected 9010");g.advance(4)
    assert not g.eval("NS.questPlanner.report")().completedIDs[9010]
    g.run("REP=3100");g.fire("UPDATE_FACTION");g.advance(4)
    assert g.eval("NS.questPlanner.report")().completedIDs[9010]


def test_skill_rank_facts_are_id_based_or_unknown(style):
    g=Game(style, WESTFALL + '''
QUESTIE_QUESTS[9000].requiredSkill={164,75}
QUESTIE_QUESTS[9000].requiredRanks={{164,100},{165,50}}
C_SkillInfo={GetSkillLineInfoByID=function(id)
 if id==164 then return {skillID=id,rank=80} end
 if id==165 then return {skillID=id,rank=55} end
end}
''',fresh=True)
    g.start()
    q=g.eval("NS.questie.plannerQuest")(9000)
    assert q.requiredSkill[1]==164 and q.requiredSkill[2]==75
    assert q.requiredRanks[2][1]==165
    snapshot=g.eval("NS.compat.plannerSkills")(g.lua.table_from({164:True,165:True,166:True}))
    assert snapshot[164]==80 and snapshot[165]==55 and snapshot[166] is None


def test_objective_icons_do_not_supply_counts_or_kill_credit(style):
    g=Game(style, WESTFALL + '''
QUESTIE_QUESTS[9000].objectives={{{601,"Inspect the machine",57}}}
''',fresh=True)
    g.start()
    t=g.eval("NS.questie.plannerQuest")(9000).targets[1]
    assert t.required is None and t.creditID is None and t.kind=="interact"


def test_chain_beyond_four_and_cycle_coverage(style):
    g=game(style, '''
QUESTS={}
for id=9100,9108 do
 QUESTIE_QUESTS[id]={name="Chained "..id,questLevel=8,startedBy={{600}},finishedBy={{600}},
 preQuestSingle=id>9100 and {id-1} or nil}
end
QUESTIE_QUESTS[9107].preQuestSingle={9108}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
 IsDoable=function(id) return id<=9100 end,
 IsDoableVerbose=function()return "missing",true,7 end,DoableStates={NO_PREQUESTSINGLE=7}} end
end''')
    g.advance(5)
    coverage=g.eval("NS.questPlanner.coverage")()
    assert coverage.blocked[9106] is None
    assert coverage.blocked[9107] and coverage.blocked[9108]
    seen=text(g)
    for _ in range(18):
        g.eval("NS.questPlanner.navigate")(1); seen+=text(g)
    assert "Chained 9106" in seen and "Chained 9107" not in seen


def test_or_prerequisite_cycle_has_a_local_escape(style):
    g=game(style, '''
QUESTS={}
QUESTIE_QUESTS[9010]={name="Cycle A",questLevel=8,startedBy={{600}},finishedBy={{600}},preQuestSingle={9011,9012}}
QUESTIE_QUESTS[9011]={name="Cycle B",questLevel=8,startedBy={{600}},finishedBy={{600}},preQuestSingle={9010}}
QUESTIE_QUESTS[9012]={name="Escape",questLevel=8,startedBy={{600}},finishedBy={{600}}}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id)return id==9012 end,
  IsDoableVerbose=function()return "chain",true,7 end,
  DoableStates={NO_PREQUESTSINGLE=7}
 } end
end
''')
    report=g.eval("NS.questPlanner.report")()
    assert all(report.completedIDs[id] for id in (9010,9011,9012))
    route=[(stop.kind,next(iter(stop.quests.keys()))) for stop in report.baselineRoute.values()]
    assert route.index(("turnin",9012))<route.index(("pickup",9010))
    assert route.index(("turnin",9010))<route.index(("pickup",9011))


def test_external_repeatable_and_level_report(style):
    g=game(style, '''
UnitLevel=function()return 10 end
QUESTIE_QUESTS[9010]={name="Repeat",questLevel=8,startedBy={{600}},specialFlags=3}
QUESTIE_QUESTS[9011]={name="Out of zone",questLevel=8,startedBy={{600}},finishedBy={{700}}}
QUESTIE_QUESTS[9012]={name="Level gated",questLevel=15,requiredLevel=14,startedBy={{600}},finishedBy={{600}}}
''')
    c=g.eval("NS.questPlanner.coverage")()
    # 9012 needs level 14 at level 10 (more than 3 levels ahead): one cheap read rules it out, so it is counted, not listed as blocked
    assert c.repeatable[9010] and c.external[9011] and c.blocked[9012] is None and c.skipped.level==1
    g.run('MAP_ID=100');g.fire('ZONE_CHANGED_NEW_AREA');g.advance(2)
    assert g.eval("NS.questPlanner.coverage")().external[9011] is None



def test_future_character_restrictions_also_apply_to_chain_candidates(style):
    g=game(style, '''
UnitClass=function()return "Warrior","WARRIOR" end
LibQuestieDB.Enum={classKeys={WARRIOR=1,PALADIN=2}}
for id=9011,9012 do QUESTIE_QUESTS[id]={name="Restricted "..id,questLevel=8,
    preQuestSingle={9000},startedBy={{600}},finishedBy={{600}}} end
QUESTIE_QUESTS[9011].requiredClasses=2
QUESTIE_QUESTS[9012].requiredMinRep={33,1000}
QuestieLoader.ImportModule=function(_,name)if name=="QuestieDB" then return {
 IsDoable=function(id)return id<9011 end,
 IsDoableVerbose=function()return "chain",true,1 end,
 DoableStates={NO_PREQUESTSINGLE=1}} end end''')
    c=g.eval("NS.questPlanner.coverage")()
    # a Paladin-only quest is never a candidate for a Warrior: skipped before its starters are read
    assert c.blocked[9011] is None and c.skipped.character==1
    assert "reputation" in c.unknown[9012]


def test_no_unreachable_drop_or_unmapped_event_turnin(style):
    g=game(style, '''
QUESTIE_QUESTS[9010]={name="Dry farm",questLevel=8,objectives={nil,nil,{{50}}},startedBy={{600}},finishedBy={{600}}}
QUESTIE_QUESTS[9011]={name="Hidden event",questLevel=8,specialFlags=2,startedBy={{600}},finishedBy={{600}}}
ItemDB.Get=function(_,k) if k=="name" then return "Dry Core" elseif k=="npcDrops" then return {601} end end
local import=QuestieLoader.ImportModule
QuestieLoader.ImportModule=function(self,name)if name=="DropDB" then return {GetItemDroprate=function()return {0,"questie"} end}
else return import(self,name) end end''')
    c=g.eval("NS.questPlanner.coverage")()
    assert c.blocked[9010] and c.unknown[9011]
    shown = text(g)
    assert "Hand in to Sentinel Hill Giver:" in shown, "a reachable quest still gets its hand-in step"
    assert "Dry farm" not in shown and "Hidden event" not in shown
    assert c.external[9002] is None


def test_quest_color_is_optional_and_required_level_is_independent(style):
    g=game(style, '''
UnitLevel=function()return 10 end
UnitXP=function()return 70 end
UnitXPMax=function()return 100 end
for id=9020,9022 do QUESTIE_QUESTS[id]={name="Color "..id,startedBy={{600}},finishedBy={{600}},
questLevel=id==9020 and 2 or 15,requiredLevel=id==9022 and 11 or 1} end''')
    assert g.eval('NS.questPlanner.levelScope')=="all"
    assert "Color 9020" in text(g) and "Color 9021" in text(g)
    assert "30 XP" in g.eval('NS.questPlanner.coverage')().blocked[9022]


def test_positive_group_prerequisite_can_use_completed_exclusive(style):
    g=game(style, '''
QUESTIE_QUESTS[9000].exclusiveTo={9030}
C_QuestLog=C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted=function(id)return id==9030 end
for id=9020,9021 do QUESTIE_QUESTS[id]={name="Alternative "..id,questLevel=8,startedBy={{600}},finishedBy={{600}},
    preQuestGroup={id==9020 and 9000 or -9000}} end
QuestieLoader.ImportModule=function(_,name)if name=="QuestieDB" then return {
 IsDoable=function(id)return id<9020 end,IsDoableVerbose=function()return "requires group",true,11 end,
 DoableStates={NO_PREQUESTGROUP=11}} end end''')
    c=g.eval("NS.questPlanner.coverage")()
    assert "Alternative 9020" in text(g) and c.blocked[9020] is None
    assert "Alternative 9021" not in text(g) and c.blocked[9021]


def test_cheap_checks_run_before_the_big_tables_are_read(style):
    g=game(style, '''
UnitLevel=function()return 10 end
UnitClass=function()return "Warrior","WARRIOR" end
UnitRace=function()return "Human","Human",1 end
UnitFactionGroup=function()return "Alliance" end
LibQuestieDB.Enum={classKeys={WARRIOR=1,PALADIN=2},raceMaskById={[1]=1,[2]=2}}
C_Map.GetMapInfo=function(id)
 return ({[1436]={name="Westfall",mapType=3,parentMapID=100},[1429]={name="Far Zone",mapType=3,parentMapID=200},
          [100]={name="Eastern Kingdoms",mapType=2,parentMapID=0},[200]={name="Kalimdor",mapType=2,parentMapID=0}})[id]
end
QUESTIE_QUESTS[9010]={name="Too high",questLevel=20,requiredLevel=15,startedBy={{600}},finishedBy={{600}}}
QUESTIE_QUESTS[9011]={name="Paladin only",questLevel=8,requiredClasses=2,startedBy={{600}},finishedBy={{600}}}
QUESTIE_QUESTS[9012]={name="Orc only",questLevel=8,requiredRaces=2,startedBy={{600}},finishedBy={{600}}}
QUESTIE_QUESTS[9013]={name="Kalimdor quest",questLevel=8,zoneOrSort=12,startedBy={{600}},finishedBy={{600}}}
QUESTIE_QUESTS[9014]={name="Next level",questLevel=11,requiredLevel=11,startedBy={{600}},finishedBy={{600}}}
BIG_READS={}
local get=QuestDB.Get
QuestDB.Get=function(id,key) if key=="startedBy" then BIG_READS[id]=true end;return get(id,key) end''')
    reads=g.eval("BIG_READS")
    c=g.eval("NS.questPlanner.coverage")()
    for id in (9010,9011,9012,9013):
        assert reads[id] is None, id
    assert reads[9000] and reads[9014]            # one level above you stays: XP can unlock it
    s=c.skipped
    assert (s.level,s.character,s.continent)==(1,2,1)
    assert "Not read" in g.eval("NS.questPlanner.debugText")()


def test_level_up_rescans_what_the_old_level_skipped(style):
    g=game(style, '''
LEVEL=10;UnitLevel=function()return LEVEL end
QUESTIE_QUESTS[9010]={name="Needs twelve",questLevel=14,requiredLevel=14,startedBy={{600}},finishedBy={{600}}}''')
    assert g.eval("NS.questPlanner.coverage")().skipped.level==1
    g.run("LEVEL=14");g.fire("PLAYER_LEVEL_UP");g.advance(5)
    c=g.eval("NS.questPlanner.coverage")()
    assert c.skipped.level is None and "Needs twelve" in text(g)


if __name__=="__main__":
    tests=[(k,v) for k,v in globals().items() if k.startswith("test_")]
    failures=0
    for name,test in tests:
        for style in ("classic","modern"):
            try:
                test(style)
                print("ok",name,style)
            except Exception as exc:
                failures+=1; print("FAIL",name,style,type(exc).__name__,str(exc)[:180])
    print(f"{len(tests)*2-failures}/{len(tests)*2} passed")
    raise SystemExit(bool(failures))
