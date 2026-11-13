"""One result per equipment name, with every eligible source retained inline."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_loot import game as loot_game, click, row, key
from test_optional import game as quest_game
from test_equipment import choose
STYLES = ("modern", "classic")


def drops(g):
    return list(g.eval("NS.loot._results()").values())


def rewards(g):
    return list(g.eval("NS.rewards._results()").values())


SHARED = '''table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1],{2,10001})'''
VARIANT = '''LOOT_ITEMS[10006]={name="Captain's Blade",level=30,required=22,kind=2,sub=7}
    table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1],{3,10006})'''


def test_dungeon_has_one_row_per_name_and_lists_each_mob_once_with_all_modes(style):
    g=loot_game(style,SHARED);g.slash("loot")
    assert len(drops(g))==4
    r=row(g,10001);assert len(r.result.sources)==3
    assert {s.who for s in r.result.sources.values()}=={"Cookie","Edwin VanCleef"}
    click(r.frame);text=g.eval("NS.loot._window().detailsText.text")
    assert text.count("Source: Cookie")==1 and text.count("Source: Edwin VanCleef")==1
    assert "Heroic, Normal" in text
    assert "Cookie" in r["from"].text and "Edwin VanCleef" in r["from"].text
    assert "of 4 items" in g.eval("NS.loot._window().status.text")


def test_same_name_different_ids_merge_and_versions_are_visible(style):
    g=loot_game(style,VARIANT);g.slash("loot")
    assert len(drops(g))==4
    r=next(r for r in drops(g) if r.item.name=="Captain's Blade")
    assert r.itemID==10006 and list(r.itemIDs.values())==[10001,10006]
    click(row(g,10006).frame);text=g.eval("NS.loot._window().detailsText.text")
    assert "10001" in text and "10006" in text and "Edwin VanCleef" in text and "Cookie" in text
    assert "iLvl 25" in text and "iLvl 30" in text


def test_filters_and_source_search_apply_before_merging_variants(style):
    g=loot_game(style,VARIANT);g.slash("loot")
    choose(g,mode="Item level",low="25",high="25")
    assert len(drops(g))==1 and drops(g)[0].itemID==10001
    assert {s.who for s in drops(g)[0].sources.values()}=={"Edwin VanCleef"}
    g.eval("NS.equipmentUI.reset")()
    g.eval("NS.loot.search")("Cookie",None,None)
    r=next(r for r in drops(g) if r.item.name=="Captain's Blade")
    assert list(r.itemIDs.values())==[10006] and len(r.sources)==1
    g.eval("NS.loot.search")("10001",None,None)
    assert drops(g)[0].itemID==10001 and list(drops(g)[0].itemIDs.values())==[10001]


def test_other_dungeons_share_one_card_but_location_filter_keeps_matching_sources(style):
    g=loot_game(style,'''table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Caverns.items[1][1],{2,10001})''')
    g.slash("loot");assert len(drops(g))==4
    click(row(g,10001).frame);text=g.eval("NS.loot._window().detailsText.text")
    assert "The Deadmines" in text and "Wailing Caverns" in text and "Lord Cobrahn" in text
    g.eval("NS.loot.search")("",key(g,"Wailing Caverns"),None)
    r=next(r for r in drops(g) if r.itemID==10001)
    assert len(r.sources)==1 and r.sources[1].who=="Lord Cobrahn"


def test_quest_reward_appears_once_with_all_routes_and_prerequisites(style):
    g=quest_game(style,"REWARD_ITEMS[800].questRewards={8000,8001,8000}");g.slash("rewards")
    assert len(rewards(g))==2
    r=next(r for r in rewards(g) if r.itemID==800)
    lines,_=g.eval("NS.rewards.detail")(r);text="\n".join(lines.values())
    assert text.count("Reward Quest 8000 (")==1 and text.count("Reward Quest 8001 (")==1
    assert "Prerequisites (any)" in text and "Wolves" in text
    assert "Reward Quest 8000" in g.eval("NS.rewards._window().route.text")
    assert "Reward Quest 8001" in g.eval("NS.rewards._window().route.text")


def test_quest_search_and_eligibility_do_not_reintroduce_other_routes(style):
    g=quest_game(style,"REWARD_ITEMS[800].questRewards={8000,8001,8003,8005}");g.slash("rewards")
    r=next(r for r in rewards(g) if r.itemID==800)
    assert {s.questID for s in r.sources.values()}=={8000,8001}
    f=g.eval('{class="DRUID",level=20,faction="Alliance",slot="All slots",near=true,text="8001"}')
    g.eval("NS.rewards.search")(f)
    r=next(r for r in rewards(g) if r.itemID==800)
    assert {s.questID for s in r.sources.values()}=={8001}


def test_quest_items_with_the_same_name_merge_without_losing_variant_metadata(style):
    g=quest_game(style,'''REWARD_ITEMS[807]={name="Druid Staff",class=2,subClass=10,itemLevel=27,
        requiredLevel=18,questRewards={8001},loc="INVTYPE_2HWEAPON"}''');g.slash("rewards")
    assert len(rewards(g))==2
    r=next(r for r in rewards(g) if r.name=="Druid Staff")
    assert r.itemID==807 and list(r.itemIDs.values())==[800,807]
    text="\n".join(g.eval("NS.rewards.detail")(r)[0].values())
    assert "800" in text and "807" in text and "Reward Quest 8000" in text and "Reward Quest 8001" in text


def test_native_tooltip_compares_one_item_and_includes_merged_suppliers(style):
    g=loot_game(style,SHARED+'''function GameTooltip:SetHyperlink(s) TOOLTIP.link=s end''');g.slash("loot")
    r=row(g,10001);r.frame.scripts.OnEnter(r.frame)
    text="\n".join(g.eval("TOOLTIP.lines").values())
    assert g.eval("TOOLTIP.link")=="item:10001" and "Cookie" in text and "Edwin VanCleef" in text


def test_group_selection_survives_a_new_same_name_variant_arriving(style):
    g=loot_game(style,VARIANT+";UNCACHED[10006]=true");g.slash("loot")
    click(row(g,10001).frame)
    g.run("UNCACHED[10006]=nil");g.fire("GET_ITEM_INFO_RECEIVED",10006,True);g.advance(0.3)
    selected=next(r for r in g.eval("NS.loot._window().rows").values() if r.selected)
    assert selected.result.item.name=="Captain's Blade" and selected.result.itemID==10006
    assert len(drops(g))==4 and len(selected.result.sources)==3


def test_lower_quality_namesakes_never_supply_a_visible_group(style):
    g=loot_game(style,VARIANT+";LOOT_ITEMS[10006].quality=2");g.slash("loot")
    r=next(r for r in drops(g) if r.itemID==10001)
    assert list(r.itemIDs.values())==[10001] and {s.who for s in r.sources.values()}=={"Edwin VanCleef"}
    g.eval("NS.loot.search")("Cookie",None,None)
    assert all(r.item.name!="Captain's Blade" for r in drops(g))


def test_stat_filter_selects_only_the_matching_named_variant(style):
    g=loot_game(style,VARIANT+'''function GetItemStats(link)
        return {ITEM_MOD_INTELLECT_SHORT=string.find(link,"10006",1,true) and 20 or 0}
    end''');g.slash("loot")
    assert g.eval("NS.equipmentUI.applyStat")(1,"Intellect","10")
    assert len(drops(g))==1 and drops(g)[0].itemID==10006
    assert list(drops(g)[0].itemIDs.values())==[10006] and len(drops(g)[0].sources)==1


def test_name_grouping_ignores_casing_color_codes_and_outer_spaces(style):
    g=loot_game(style,VARIANT+'''LOOT_ITEMS[10006].name=" |cff0070ddCAPTAIN'S BLADE|r "''');g.slash("loot")
    assert len(drops(g))==4
    r=next(r for r in drops(g) if r.itemID==10006)
    assert list(r.itemIDs.values())==[10001,10006]


def test_many_quest_routes_use_one_row_and_full_scrollable_details(style):
    g=quest_game(style,'''REWARD_ITEMS[800].questRewards={}
        for id=9000,9017 do
            QUESTIE_QUESTS[id]={name="Route "..id,requiredLevel=15,questLevel=20,startedBy={{197}}}
            table.insert(REWARD_ITEMS[800].questRewards,id)
        end''');g.slash("rewards")
    w=g.eval("NS.rewards._window()")
    assert len(rewards(g))==2 and w.next.disabled and "18 quests" in w.rows[1]["from"].text
    assert "Route 9000" in w.route.text and "Route 9017" in w.route.text
    assert "first quest listed" in w.route.text


def test_quest_native_tooltip_keeps_both_routes_and_first_route_map(style):
    g=quest_game(style,'''REWARD_ITEMS[800].questRewards={8001,8000}
        function GameTooltip:SetHyperlink(s) TOOLTIP.link=s end''');g.slash("rewards")
    w=g.eval("NS.rewards._window()");w.rows[1].frame.scripts.OnEnter(w.rows[1].frame)
    text="\n".join(g.eval("TOOLTIP.lines").values())
    assert g.eval("TOOLTIP.link")=="item:800" and "Reward Quest 8000" in text and "Reward Quest 8001" in text
    assert w.routeMap==g.eval("NS.questie.uiMapOf(NS.questie.starter(8000).area)")


if __name__=="__main__":
    failed=total=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try:fn(style);print("ok  ",f"{name}[{style}]")
            except Exception as e:failed+=1;print("FAIL",f"{name}[{style}]",type(e).__name__,str(e)[:500])
    print(f"\n{total-failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
