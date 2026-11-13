"""Shared, native item-stat conditions in both equipment explorer tabs."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_loot import game as loot_game,results,click
from test_optional import game as quest_game,ids
from test_equipment import controls,choose
from test_usability import pick,type_text
STYLES=("modern","classic")
DATA='''
STAT_READS=0
ITEM_STATS={
 [800]={ITEM_MOD_INTELLECT_SHORT=10,ITEM_MOD_STAMINA_SHORT=5,ITEM_MOD_SPIRIT_SHORT=3},
 [801]={ITEM_MOD_INTELLECT_SHORT=8,ITEM_MOD_STAMINA_SHORT=8},
 [802]={ITEM_MOD_INTELLECT_SHORT=100},
 [10001]={ITEM_MOD_STRENGTH_SHORT=6,ITEM_MOD_STAMINA_SHORT=4},
 [10002]={ITEM_MOD_INTELLECT_SHORT=10,ITEM_MOD_STAMINA_SHORT=5,ITEM_MOD_SPIRIT_SHORT=3},
 [10003]={ITEM_MOD_INTELLECT_SHORT=8},
 [10005]={RESISTANCE0_NAME=80,ITEM_MOD_STAMINA_SHORT=8,ITEM_MOD_SPELL_HEALING_DONE_SHORT=12},
}
function ReadStats(link)
 STAT_READS=STAT_READS+1
 assert(type(link)=="string","native stats require an item link")
 local id=tonumber(string.match(link,"item:(%d+)"))
 return ITEM_STATS[id]
end
'''


def game(style,quest=False,extra=""):
    api="C_Item=C_Item or {};C_Item.GetItemStats=ReadStats" if style=="modern" else "GetItemStats=ReadStats"
    g=(quest_game if quest else loot_game)(style,DATA+api+";"+extra)
    g.slash("rewards" if quest else "loot")
    return g


def apply(g,index,stat,minimum=""):
    return g.eval("NS.equipmentUI.applyStat")(index,stat,minimum)


def test_no_stat_lookup_until_a_condition_is_enabled(style):
    g=game(style);assert g.eval("STAT_READS")==0 and len(results(g))==4
    assert apply(g,1,"Intellect")
    assert {r[0] for r in results(g)}=={10002,10003}
    before=g.eval("STAT_READS");g.eval("NS.loot.search")("",None,None)
    assert g.eval("STAT_READS")==before


def test_three_conditions_use_and_and_inclusive_thresholds(style):
    g=game(style)
    for i,stat,n in ((1,"Intellect","10"),(2,"Stamina","5"),(3,"Spirit","3")):
        assert apply(g,i,stat,n)
    assert {r[0] for r in results(g)}=={10002}
    assert apply(g,2,"Stamina","6") and results(g)==[]
    assert apply(g,2,"","bad") and {r[0] for r in results(g)}=={10002}
    choose(g,"Armor");assert results(g)==[]


def test_quest_rewards_keep_class_faction_and_quality_rules(style):
    g=game(style,True)
    assert apply(g,1,"Intellect","9") and ids(g)==[(800,8000)]
    assert apply(g,2,"Stamina","6") and ids(g)==[]
    assert apply(g,1,"Intellect","8") and ids(g)==[(801,8001)]
    g.run("REWARD_ITEMS[801].quality=2");g.fire("GET_ITEM_INFO_RECEIVED",801,True);g.advance(.3)
    assert ids(g)==[]


def test_stats_refresh_after_item_cache_events_without_stale_values(style):
    g=game(style,extra="ITEM_STATS[10002]=nil")
    apply(g,1,"Intellect","10");assert results(g)==[]
    g.run("ITEM_STATS[10002]={ITEM_MOD_INTELLECT_SHORT=10}")
    g.fire("GET_ITEM_INFO_RECEIVED",10002,True);g.advance(.3)
    assert {r[0] for r in results(g)}=={10002}
    g.run("ITEM_STATS[10002]={ITEM_MOD_INTELLECT_SHORT=2}")
    g.fire("GET_ITEM_INFO_RECEIVED",10002,True);g.advance(.3)
    assert results(g)==[]


def test_missing_zero_and_malformed_stat_values_do_not_match(style):
    g=game(style,extra='ITEM_STATS[10002]={ITEM_MOD_INTELLECT_SHORT=0};ITEM_STATS[10003]={ITEM_MOD_INTELLECT_SHORT="20"}')
    apply(g,1,"Intellect");assert results(g)==[]


def test_invalid_input_keeps_last_valid_condition_and_results(style):
    g=game(style);apply(g,1,"Intellect","10")
    for value in ("0","-1","1.5","wat","100001","nan"):
        assert not apply(g,1,"Intellect",value)
        assert {r[0] for r in results(g)}=={10002}
    assert "whole number" in controls(g)[1].statError.text
    assert not apply(g,4,"Intellect") and not apply(g,1,"Made up bonus")


def test_searchable_controls_live_minimum_and_individual_clear(style):
    g=game(style);c=controls(g)[1];row=c.stats[1]
    pick(g,row.stat,"Intellect","intell")
    type_text(row.min,"10");g.advance(.19)
    assert {r[0] for r in results(g)}=={10002}
    type_text(row.min,"20");pick(g,row.stat,"")
    g.advance(.3)
    assert len(results(g))==4 and row.min.GetText(row.min)==""
    assert g.eval("NS.equipmentUI.filters.stats[1].stat")==None


def test_reset_cancels_pending_stat_edits_and_tabs_share_conditions(style):
    g=game(style);c=controls(g)[1]
    apply(g,1,"Intellect","10");g.slash("rewards");g.slash("loot")
    assert {r[0] for r in results(g)}=={10002}
    type_text(c.stats[1].min,"99");click(c.reset);g.advance(.3)
    assert len(results(g))==4 and c.stats[1].min.GetText(c.stats[1].min)==""
    assert all(not row.stat for row in g.eval("NS.equipmentUI.filters.stats").values())


def test_armor_healing_and_ratings_use_native_units(style):
    g=game(style)
    apply(g,1,"Armor","80");apply(g,2,"Healing","12")
    assert {r[0] for r in results(g)}=={10005}
    g.run("ITEM_STATS[10005].ITEM_MOD_CRIT_RATING_SHORT=7")
    apply(g,3,"Crit rating","7");assert {r[0] for r in results(g)}=={10005}
    apply(g,3,"Crit rating","8");assert results(g)==[]


def test_missing_erroring_and_legacy_only_api_are_safe(style):
    g=game(style,extra='C_Item=C_Item or {};C_Item.GetItemStats=nil;GetItemStats=nil')
    assert "unavailable" in controls(g)[1].statError.text
    apply(g,1,"Intellect");assert results(g)==[]
    g.eval("NS.equipmentUI.reset")();assert len(results(g))==4
    assert "unavailable" in controls(g)[1].statError.text
    g.run('C_Item.GetItemStats=function()error("unavailable")end;GetItemStats=ReadStats')
    apply(g,1,"Intellect","10");assert {r[0] for r in results(g)}=={10002}


if __name__=="__main__":
    total=failed=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try:fn(style);print("ok",name,style)
            except Exception as e:failed+=1;print("FAIL",name,style,type(e).__name__,str(e)[:700])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
