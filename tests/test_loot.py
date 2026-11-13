"""Instance loot GUI: real Lua parser, public AtlasLoot API contracts and partial QuestieDB fallback."""
import inspect
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_questmap import DATA as MAP_DATA

STYLES = ("modern", "classic")
DATA = MAP_DATA + r'''
LOOT_ITEMS = {
    [10001]={name="Captain's Blade",level=25,required=18,kind=2,sub=7}, [10002]={name="Serpent Staff",level=22,required=15,kind=2,sub=10},
    [10003]={name="Cookie's Ladle",level=20,required=0,kind=2,sub=4}, [10004]={name="Silken Cloth",level=1,loc=""},
    [10005]={name="Locked Chest Prize",level=18,required=12,kind=4,sub=1,loc="INVTYPE_CHEST"},
}
LOOT_READS, PUBLIC_READS, UNCACHED = 0,0,{}
function GetItemInfo(id)
    LOOT_READS=LOOT_READS+1
    local r=LOOT_ITEMS[id]
    if not r or UNCACHED[id] then return nil end
    return r.name,"|Hitem:"..id.."|h["..r.name.."]|h",2,r.level,r.required or 0,"","",1,r.loc or "INVTYPE_WEAPON","icon",0,r.kind,r.sub
end
local module = {
    Deadmines={name="The Deadmines",InstanceID=36,MapID=1581,items={
        {name="Edwin VanCleef",npcID=639,[1]={{1,10001},{2,10001},{3,"icon-heading"},{4,-99}},[2]=1},
        {name="Cookie",npcID=645,[1]={{1,10003}}},
        {name="Trash",ExtraList=true,[1]={{1,10004}}},
        {name="Chest",[1]={{1,10005}}},
        {name="Quest reward",IgnoreAsSource=true,[1]={{1,99999}}},
        {name="Set IDs",[1]={{1,123}},setFormat=true},
    }},
    Caverns={name="Wailing Caverns",InstanceID=43,MapID=718,items={
        {name="Lord Cobrahn",npcID=3669,[1]={{1,10002}}},
    }},
    Empty={name="Empty Instance",InstanceID=999,items={{name="Unknown encounter",[1]={}}}},
    Outdoor={name="World bosses",InstanceID=0,items={{name="Outdoor Boss",[1]={{1,99998}}}}},
}
function module:GetDifficultyName(id) return ({[1]="Normal",[2]="Heroic"})[id] end
AtlasLoot={ItemDB={Storage={AtlasLootClassic_DungeonsAndRaids=module}}}
function AtlasLoot.ItemDB:GetItemTable(mod,content,boss,diff)
    PUBLIC_READS=PUBLIC_READS+1
    local b=self.Storage[mod][content].items[boss]
    if b.link then b=self.Storage[b.link[1]][b.link[2]].items[b.link[3]] end
    local rows=b[diff]
    if type(rows)=="number" then rows=b[rows] end
    return rows,{b.setFormat and "Set" or "Item"},{name=module:GetDifficultyName(diff)}
end
'''


def game(style, pre=""):
    g=Game(style, DATA+pre, fresh=True)
    g.start(); g.advance(3)
    return g


def results(g):
    return [(r.itemID,r.instanceName,r.who,r.difficulty) for r in g.eval("NS.loot._results()").values()]


def key(g, name):
    return next(p.key for p in g.eval("NS.loot.instances()").values() if p.name==name)


def row(g, item_id):
    return next(r for r in g.eval("NS.loot._window().rows").values() if r.result and r.result.itemID==item_id)


def click(b):
    b.scripts.OnClick(b,"LeftButton")


def test_no_loot_scan_or_item_requests_happen_at_login(style):
    g=game(style)
    assert g.eval("PUBLIC_READS")==0 and g.eval("LOOT_READS")==0
    assert g.eval("NS.loot._window()") is None


def test_browser_lists_instances_and_real_item_sources(style):
    g=game(style); g.slash("loot")
    rows=results(g)
    assert (10001,"The Deadmines","Edwin VanCleef","Normal") in rows
    assert (10002,"Wailing Caverns","Lord Cobrahn","Normal") in rows
    assert len(rows)==5,rows
    assert [p.name for p in g.eval("NS.loot.instances()").values()]==["The Deadmines","Wailing Caverns"]
    assert g.eval("NS.loot._state()")[2]=="AtlasLoot"


def test_difficulty_aliases_use_public_reader_and_remain_distinct(style):
    g=game(style); g.slash("loot")
    modes={r[3] for r in results(g) if r[0]==10001}
    assert modes=={"Normal","Heroic"} and g.eval("PUBLIC_READS")>0
    assert g.eval("AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[1][2]")==1


def test_only_equipment_drops_are_included_from_valid_source_tables(style):
    g=game(style); g.slash("loot")
    ids={r[0] for r in results(g)}
    assert 10005 in ids and 10004 not in ids
    assert not ids.intersection({123,99999,99998,-99})
    assert "unavailable or not item lists" in g.eval("NS.loot._window().note.text")


def test_search_matches_item_name_id_boss_instance_and_plain_percent(style):
    g=game(style); g.slash("loot")
    for text,expected in (("Captain",{10001}),("10003",{10003}),("Cobrahn",{10002}),("Wailing",{10002}),("Heroic",{10001}),("100%",set())):
        g.eval("NS.loot.search")(text,None,None)
        assert {r[0] for r in results(g)}==expected,(text,results(g))


def test_instance_and_encounter_filters_keep_only_selected_sources(style):
    g=game(style); g.slash("loot")
    g.eval("NS.loot.search")("",key(g,"The Deadmines"),"Cookie")
    assert results(g)==[(10003,"The Deadmines","Cookie","Normal")]


def test_gui_instance_search_selection_and_item_search_work(style):
    g=game(style); g.slash("loot"); w=g.eval("NS.loot._window()")
    w.instanceSearch.SetText(w.instanceSearch,"Caverns"); w.instanceSearch.scripts.OnEnterPressed(w.instanceSearch)
    assert w.instances[1].place.name=="Wailing Caverns" and not w.instances[2].shown
    click(w.instances[1]); assert {r[0] for r in results(g)}=={10002}
    w.search.SetText(w.search,"Cobrahn"); w.search.scripts.OnEnterPressed(w.search)
    assert len(results(g))==1


def test_click_source_details_identifies_supplier_without_fake_drop_rates(style):
    g=game(style); g.slash("loot")
    click(row(g,10003).frame)
    w=g.eval("NS.loot._window()")
    assert w.details.shown and "Source: Cookie" in w.detailsText.text
    assert "Instance: The Deadmines" in w.detailsText.text and "Drop chance is not supplied" in w.detailsText.text


def test_native_tooltip_and_equipped_comparison_are_used(style):
    g=game(style,'''COMPARED=false
        function GameTooltip:SetHyperlink(s) TOOLTIP.link=s end
        function GameTooltip_ShowCompareItem() COMPARED=true end''')
    g.slash("loot"); r=row(g,10002)
    r.frame.scripts.OnEnter(r.frame)
    assert g.eval("TOOLTIP.link")=="item:10002" and g.eval("COMPARED")


def test_same_item_can_have_multiple_boss_sources_without_duplicates(style):
    g=game(style,'''table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1],{2,10001})''')
    g.slash("loot")
    entries=[r for r in results(g) if r[0]==10001]
    assert len(entries)==3 and {r[2] for r in entries}=={"Edwin VanCleef","Cookie"}


def test_linked_encounter_tables_are_resolved_under_their_original_source_name(style):
    g=game(style,'''table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Caverns.items,
        {name="Shared chest",link={"AtlasLootClassic_DungeonsAndRaids","Deadmines",4}})''')
    g.slash("loot")
    assert (10005,"Wailing Caverns","Shared chest","Normal") in results(g)


def test_partial_questie_sources_exclude_outdoor_npcs_and_include_dungeon_chests(style):
    g=game(style,'''AtlasLoot=nil
        ItemDB.GetAllIds=function() return {10001,10005} end
        QUESTIE_ITEMS[10001]={name="Captain's Blade",npcDrops={639,299}}
        QUESTIE_ITEMS[10005]={name="Locked Chest Prize",objectDrops={55}}
        QUESTIE_NPCS[639]={name="Edwin VanCleef",spawns={[1581]={{-1,-1}}}}
        QUESTIE_OBJECTS[55]={name="Large Chest",spawns={[1581]={{-1,-1}}}}
        local area=C_Map.GetAreaInfo
        C_Map.GetAreaInfo=function(id) return id==1581 and "The Deadmines" or area(id) end''')
    g.slash("loot")
    assert g.eval("NS.loot._state()")[2]=="QuestieDB"
    assert {(r[0],r[2]) for r in results(g)}=={(10001,"Edwin VanCleef"),(10005,"Large Chest")}
    assert "Partial QuestieDB" in g.eval("NS.loot._window().note.text")


def test_missing_catalogues_give_install_instructions(style):
    g=game(style,"AtlasLoot=nil"); g.slash("loot")
    assert results(g)==[] and "Install compatible AtlasLoot" in g.eval("NS.loot._window().note.text")


def test_incompatible_atlas_reader_is_not_treated_as_a_complete_catalogue(style):
    g=game(style,"AtlasLoot.ItemDB.GetItemTable=nil"); g.slash("loot")
    assert g.eval("NS.loot._state()")[2] is None and results(g)==[]
    assert "Install compatible AtlasLoot" in g.eval("NS.loot._window().note.text")


def test_questie_spawns_on_dungeon_maps_are_recognized_without_sentinel_coordinates(style):
    g=game(style,'''AtlasLoot=nil
        ItemDB.GetAllIds=function()return {10001} end
        QUESTIE_ITEMS[10001]={name="Captain's Blade",npcDrops={639,299}}
        QUESTIE_NPCS[639]={name="Edwin VanCleef",spawns={[1581]={{40,50}}}}
        LibQuestieDB.Support.Get=function()return {private={areaIdToUiMapId="return {[1581]=999,[12]=1429}"}} end
        C_Map.GetMapInfo=function(id)return {mapType=id==999 and 4 or 3} end
        Enum={UIMapType={Dungeon=4}}
    ''')
    g.slash("loot")
    assert {(r[0],r[2]) for r in results(g)}=={(10001,"Edwin VanCleef")}


def test_load_on_demand_module_is_loaded_only_on_open(style):
    g=game(style,'''SAVED_LOOT=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        AtlasLoot.ItemDB.Storage={}; LOADS=0
        function LoadAddOn(name)
            LOADS=LOADS+1
            if name=="AtlasLootClassic_DungeonsAndRaids" then
                AtlasLoot.ItemDB.Storage[name]=SAVED_LOOT; return true
            end
        end''')
    assert g.eval("LOADS")==0
    g.slash("loot"); assert len(results(g))==5 and g.eval("LOADS")>0


def test_in_combat_module_loading_waits_until_combat_ends(style):
    g=game(style,'''SAVED_LOOT=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        AtlasLoot.ItemDB.Storage={}; COMBAT=true; LOADS=0
        function InCombatLockdown() return COMBAT end
        function LoadAddOn(name) LOADS=LOADS+1
            if name=="AtlasLootClassic_DungeonsAndRaids" then AtlasLoot.ItemDB.Storage[name]=SAVED_LOOT;return true end
        end''')
    g.slash("loot"); assert g.eval("LOADS")==0 and results(g)==[]
    g.run("COMBAT=false"); g.fire("PLAYER_REGEN_ENABLED")
    assert len(results(g))==5


def test_name_cache_updates_refresh_a_live_search(style):
    g=game(style,"UNCACHED[10001]=true"); g.slash("loot Captain")
    assert results(g)==[]
    g.run("UNCACHED[10001]=nil"); g.fire("GET_ITEM_INFO_RECEIVED",10001,True); g.advance(0.3)
    assert {r[0] for r in results(g)}=={10001}


def test_reopening_rechecks_item_names_that_arrived_while_hidden(style):
    g=game(style,"UNCACHED[10001]=true"); g.slash("loot Captain")
    w=g.eval("NS.loot._window()"); w.frame.Hide(w.frame)
    g.run("UNCACHED[10001]=nil"); g.fire("GET_ITEM_INFO_RECEIVED",10001,True)
    g.slash("loot Captain")
    assert {r[0] for r in results(g)}=={10001}


def test_large_catalogue_is_batched_and_closing_cancels_scan(style):
    g=game(style,'''local b=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[1]
        b[1]={}; b[2]=nil
        for i=1,500 do LOOT_ITEMS[20000+i]={name="Item "..i,level=1}; b[1][i]={i,20000+i} end''')
    g.slash("loot")
    assert g.eval("NS.loot._state()")[1]
    assert g.eval("LOOT_READS")==0
    w=g.eval("NS.loot._window()"); w.frame.Hide(w.frame)
    w.frame.scripts.OnHide(w.frame)  # the game fires OnHide; the lightweight mock does not
    count=g.eval("NS.loot._state()")[3]; g.advance(2)
    assert g.eval("NS.loot._state()")[3]==count
    g.slash("loot"); g.advance(3)
    assert g.eval("NS.loot._state()")[0]
    assert g.eval("LOOT_READS")<=300


def test_pagination_handles_many_instances_and_drops(style):
    g=game(style,'''local m=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids
        for i,id in ipairs({389,43,36,33,48,34,90,47,189,129,70,209,349,109,230,229,429,289,329}) do m["Extra"..i]={name="Dungeon "..i,InstanceID=id,items={{name="Boss",[1]={{1,10001}}}}} end''')
    g.slash("loot"); g.advance(1); w=g.eval("NS.loot._window()")
    first=w.instances[1].place.key; click(w.instanceNext)
    assert w.instances[1].place.key!=first
    first_item=w.rows[1].result.instanceKey; click(w.next)
    assert w.rows[1].result.instanceKey!=first_item


def test_master_switch_closes_browser_and_no_map_symbols_return(style):
    g=game(style); g.slash("loot"); g.slash("off")
    assert not g.eval("NS.loot._window().frame.shown")
    assert g.eval("NS.loot.open")() is False and g.eval("NS.questMap") is None


def test_optional_settings_and_reward_browser_offer_loot_entry_points(style):
    g=game(style); g.slash("settings")
    g.run('for i,r in ipairs(NS.settingRows) do if r.label=="Search instance loot and who drops it" then NS.settingsClick(i,"LeftButton") end end')
    assert g.eval("NS.loot._window().frame.shown")
    g.eval("NS.loot.close")(); g.slash("rewards")
    g.run('local _,_,_,tabs=NS.equipmentUI._window(); tabs.dungeons.scripts.OnClick(tabs.dungeons,"LeftButton")')
    assert g.eval("NS.loot._window().frame.shown")


def test_consumables_materials_quest_items_bags_and_unknown_slots_are_hidden(style):
    g=game(style,'''local rows=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1]
        for i,loc in ipairs({"", "INVTYPE_BAG", "INVTYPE_QUIVER", "UNKNOWN_SLOT"}) do
            LOOT_ITEMS[11000+i]={name="Non-equipment "..i,level=1,loc=loc}
            rows[#rows+1]={#rows+1,11000+i}
        end''')
    g.slash("loot"); g.advance(0.3)
    assert {r[0] for r in results(g)}=={10001,10002,10003,10005}
    for text in ("Silken Cloth", "11001", "Non-equipment", "Trash"):
        g.eval("NS.loot.search")(text,None,None)
        assert results(g)==[],(text,results(g))


def test_all_wearable_slots_and_weapon_types_remain_visible(style):
    g=game(style,'''local rows=AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[2][1]
        for i,loc in ipairs({"INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
            "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST",
            "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON",
            "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
            "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC"}) do
            LOOT_ITEMS[12000+i]={name="Equipment "..i,level=20,loc=loc}
            rows[#rows+1]={#rows+1,12000+i}
        end''')
    g.slash("loot"); g.advance(1)
    assert {r[0] for r in results(g)}=={10001,10002,10003,10005}|set(range(12001,12024))


def test_uncached_items_never_appear_before_equipment_is_confirmed(style):
    g=game(style,"UNCACHED[10001]=true; UNCACHED[10004]=true")
    g.slash("loot")
    assert not {10001,10004}.intersection(r[0] for r in results(g))
    g.run("UNCACHED[10001]=nil; UNCACHED[10004]=nil")
    g.fire("GET_ITEM_INFO_RECEIVED",10001,True); g.fire("GET_ITEM_INFO_RECEIVED",10004,True); g.advance(0.3)
    assert 10001 in {r[0] for r in results(g)} and 10004 not in {r[0] for r in results(g)}


def test_encounter_choices_skip_material_only_sources_but_keep_trash_gear(style):
    g=game(style); g.slash("loot"); w=g.eval("NS.loot._window()")
    selected=set()
    for _ in range(8):
        click(w.boss); selected.add(w.boss.text)
    assert "Source: Trash" not in selected
    g.run("table.insert(AtlasLoot.ItemDB.Storage.AtlasLootClassic_DungeonsAndRaids.Deadmines.items[3][1],{2,10005})")
    g.eval("NS.loot.search")("",None,None)
    g.eval("NS.loot.scan")()
    assert (10005,"The Deadmines","Trash","Normal") in results(g)


def test_questie_fallback_also_excludes_non_equipment(style):
    g=game(style,'''AtlasLoot=nil
        ItemDB.GetAllIds=function() return {10001,10004} end
        QUESTIE_ITEMS[10001]={name="Captain's Blade",npcDrops={639}}
        QUESTIE_ITEMS[10004]={name="Silken Cloth",npcDrops={639}}
        QUESTIE_NPCS[639]={name="Edwin VanCleef",spawns={[1581]={{-1,-1}}}}''')
    g.slash("loot")
    assert {r[0] for r in results(g)}=={10001}


def test_namespaced_item_api_applies_the_same_equipment_filter(style):
    g=game(style,"C_Item={GetItemInfo=GetItemInfo}; GetItemInfo=nil")
    g.slash("loot")
    assert {r[0] for r in results(g)}=={10001,10002,10003,10005}


if __name__=="__main__":
    failed=total=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"): continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total+=1
            try:
                fn(style) if style else fn(); print("ok  ",f"{name}[{style}]")
            except Exception as e:
                failed+=1; print("FAIL",f"{name}[{style}]",type(e).__name__,str(e)[:500])
    print(f"\n{total-failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
