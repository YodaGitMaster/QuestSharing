"""Shared equipment explorer, dungeon identity, native classification and inclusive filters."""
import inspect
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_loot import game as loot_game, results as loot_results, click
from test_optional import game as quest_game, ids as quest_ids
STYLES=("modern","classic")


def controls(g):
    return g.eval("NS.equipmentUI._window()")


def choose(g, category="All equipment", subtype="Any type", slot="All slots", mode="Required level", low="", high=""):
    f=g.eval("NS.equipmentUI.filters")
    f.category,f.subtype,f.slot,f.mode=category,subtype,slot,mode
    assert g.eval("NS.equipmentUI.applyRange")(low,high)


def test_tabs_and_inline_details_use_one_window_even_after_repeated_opens(style):
    g=loot_game(style)
    for _ in range(4):
        g.slash("rewards"); q=g.eval("NS.rewards._window()")
        g.slash("loot"); d=g.eval("NS.loot._window()")
        d.rows[1].frame.scripts.OnClick(d.rows[1].frame,"LeftButton")
        assert not q.frame.shown and d.frame.shown
        assert "Source:" in d.detailsText.text
    names=list(g.eval("UISpecialFrames").values())
    assert names.count("QuestSharingEquipment")==1
    assert not set(names).intersection({"QuestSharingLoot","QuestSharingRewards","QuestSharingLootSource","QuestSharingRewardRoute"})
    g.eval("NS.equipmentUI.close")()
    assert not controls(g)[0].shown and not d.frame.shown


def test_type_subtype_slot_and_level_filters_for_dungeon_drops(style):
    g=loot_game(style);g.slash("loot")
    choose(g,"Weapons","Swords")
    assert {r[0] for r in loot_results(g)}=={10001}
    choose(g,"Armor","Cloth")
    assert {r[0] for r in loot_results(g)}=={10005}
    choose(g,"Weapons",low="15",high="18")
    assert {r[0] for r in loot_results(g)}=={10001,10002}
    choose(g,mode="Item level",low="20",high="22")
    assert {r[0] for r in loot_results(g)}=={10002,10003}
    choose(g,slot="Chest")
    assert {r[0] for r in loot_results(g)}=={10005}


def test_quest_rewards_share_type_and_level_filters_without_losing_eligibility(style):
    g=quest_game(style);g.slash("rewards")
    choose(g,"Weapons","Staves",low="18",high="18")
    assert quest_ids(g)==[(800,8000)]
    choose(g,"Armor","Cloth",mode="Item level",low="24",high="24")
    assert quest_ids(g)==[(801,8001)]
    choose(g,mode="Item level",low="26",high="100")
    assert quest_ids(g)==[] # ineligible sword and Horde reward do not leak through
    g.eval("NS.equipmentUI.reset")()
    assert quest_ids(g)==[(800,8000),(801,8001)]


def test_filter_controls_apply_reset_and_reverse_cycle(style):
    g=loot_game(style);g.slash("loot");_,c,_,_=controls(g)
    click(c.category); assert g.eval("NS.equipmentUI.filters.category")=="Weapons"
    c.category.scripts.OnClick(c.category,"RightButton")
    assert g.eval("NS.equipmentUI.filters.category")=="All equipment"
    c.min.SetText(c.min,"22");c.max.SetText(c.max,"25");click(c.mode);click(c.apply)
    assert {r[0] for r in loot_results(g)}=={10001,10002}
    click(c.reset)
    assert len(loot_results(g))==5 and c.min.GetText(c.min)==""


def test_invalid_ranges_are_rejected_without_changing_active_results(style):
    g=loot_game(style);g.slash("loot");choose(g,mode="Item level",low="20",high="25")
    before=loot_results(g)
    for low,high in (("30","10"),("-1","20"),("1.5","20"),("abc","20"),("0","1001")):
        assert g.eval("NS.equipmentUI.applyRange")(low,high) is False
        assert loot_results(g)==before
    assert "minimum" in controls(g)[1].error.text


def test_unknown_required_levels_do_not_pass_a_bound_but_zero_is_valid(style):
    g=loot_game(style);g.slash("loot")
    choose(g,low="0",high="0")
    assert {r[0] for r in loot_results(g)}=={10003}
    assert not g.eval("NS.equipmentUI.matches")(g.eval('{kind=2,sub=7,slot="Weapon"}'),None)


def test_filters_follow_tabs_and_closing_cancels_background_scans(style):
    g=loot_game(style,'''LibQuestieDB.Enum={classKeys={WARRIOR=1},factionRaceMasks={Alliance=1},raceMaskById={}}
        ItemDB.GetAllIds=function()local t={};for i=1,500 do t[i]=800 end;return t end''')
    g.slash("rewards");assert g.eval("NS.rewards._state()")[1]
    g.slash("loot");g.advance(1)
    assert not g.eval("NS.rewards._state()")[1]
    choose(g,"Weapons","Swords",mode="Item level",low="25",high="25")
    g.slash("rewards");g.advance(1);g.slash("loot")
    assert {r[0] for r in loot_results(g)}=={10001}
    g.eval("NS.equipmentUI.close")();g.advance(1)
    assert not g.eval("NS.equipmentUI.visible")("dungeons")


def test_master_switch_closes_shared_host_and_both_pages(style):
    g=loot_game(style);g.slash("rewards");g.slash("loot");g.slash("off")
    host,_,pages,_=controls(g)
    assert not host.shown and not pages.quests.shown and not pages.dungeons.shown


def test_dungeons_include_forever_but_exclude_raids_world_bosses_and_unknown_tables(style):
    g=loot_game(style,'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        m.MoltenCore={name="Molten Core",InstanceID=409,items={{name="Ragnaros",[1]={{1,10001}}}}}
        m.Custom={name="Forever dungeon",InstanceID=2999,ContentType=1,items={{name="Custom boss",[1]={{1,10001}}}}}
        m.Random={name="Random boss",InstanceID=9999,items={{name="Random",[1]={{1,10001}}}}}
        m.FakeRaid={name="Raid with dungeon ID",InstanceID=36,IsRaid=true,items={{name="Raid",[1]={{1,10001}}}}}
        m.FlaggedRaid={name="Raid content",InstanceID=36,ContentType=2,items={{name="Raid",[1]={{1,10001}}}}}
        function m:GetContentTypes()return {{"Dungeons"},{"Raids"}} end''')
    g.slash("loot")
    assert {p.name for p in g.eval("NS.loot.instances()").values()}=={"The Deadmines","Wailing Caverns","Forever dungeon"}
    assert {r[1] for r in loot_results(g)}=={"The Deadmines","Wailing Caverns","Forever dungeon"}


def test_dire_maul_wings_without_instance_id_are_kept(style):
    g=loot_game(style,'''AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.DireMaulEast={
        name="Dire Maul East",MapID=2557,items={{name="Boss",[1]={{1,10001}}}}}''')
    g.slash("loot")
    assert any(r[1]=="Dire Maul East" for r in loot_results(g))


def test_questie_raid_interiors_and_unknown_dungeon_areas_are_excluded(style):
    g=loot_game(style,'''AtlasLoot=nil
        ItemDB.GetAllIds=function()return {10001}end
        QUESTIE_ITEMS[10001]={name="Sword",npcDrops={639,999,998}}
        QUESTIE_NPCS[639]={name="Dungeon boss",spawns={[1581]={{-1,-1}}}}
        QUESTIE_NPCS[999]={name="Raid boss",spawns={[2717]={{-1,-1}}}}
        QUESTIE_NPCS[998]={name="Unknown boss",spawns={[9999]={{-1,-1}}}}''')
    g.slash("loot")
    assert {(r[0],r[2]) for r in loot_results(g)}=={(10001,"Dungeon boss")}


def test_cross_encounter_links_cannot_smuggle_raid_loot_into_dungeons(style):
    g=loot_game(style,'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        m.Raid={name="Raid",InstanceID=409,items={{name="Raid boss",[1]={{1,10001}}}}}
        table.insert(m.Deadmines.items,{name="Raid shortcut",link={"AtlasLootClassic_DungeonsAndRaids","Raid",1}})''')
    g.slash("loot")
    assert not any(r[2]=="Raid shortcut" for r in loot_results(g))


def test_unknown_database_subclass_is_not_mistaken_for_an_axe(style):
    g=loot_game(style,'''local old=GetItemInfo
        GetItemInfo=function(id)
            if id==10001 then return "Unknown weapon","item:10001",2,25,18,"","",1,"INVTYPE_WEAPON","icon" end
            return old(id)
        end
        QUESTIE_ITEMS[10001]={name="Unknown weapon",class=0,subClass=0}''')
    g.slash("loot");choose(g,"Weapons","Axes")
    assert not any(r[0]==10001 for r in loot_results(g))
    choose(g,"Weapons")
    assert any(r[0]==10001 for r in loot_results(g))


if __name__=="__main__":
    total=failed=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try: fn(style);print("ok",name,style)
            except Exception as e:
                failed+=1;print("FAIL",name,style,type(e).__name__,str(e)[:600])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
