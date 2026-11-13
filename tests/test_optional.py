"""Optional tools through the real Lua modules, with modern and classic WoW API mocks."""
import inspect
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_questmap import DATA as MAP_DATA

STYLES = ("modern", "classic")
DATA = MAP_DATA + r'''
function UnitClass() return "Druid", "DRUID" end
function UnitLevel() return 20 end
function UnitFactionGroup() return "Alliance" end
function UnitRace() return "Night Elf", "NightElf", 4 end
LibQuestieDB.Enum = {
    classKeys = { WARRIOR=1, MAGE=128, DRUID=1024, NONE=0 },
    factionRaceMasks = { Alliance=4294967373, Horde=8589934770 },
    raceMaskById = { [4]=8, [95]=4294967296 },
}
REWARD_ITEMS = {
    [800] = { name="Druid Staff", class=2, subClass=10, itemLevel=25, requiredLevel=18, questRewards={8000}, loc="INVTYPE_2HWEAPON" },
    [801] = { name="Healing Robe", class=4, subClass=1, itemLevel=24, requiredLevel=0, questRewards={8001}, loc="INVTYPE_ROBE" },
    [802] = { name="Warrior Sword", class=2, subClass=7, itemLevel=28, requiredLevel=18, questRewards={8002}, loc="INVTYPE_WEAPON" },
    [803] = { name="Horde Leather", class=4, subClass=2, itemLevel=27, requiredLevel=18, questRewards={8003}, loc="INVTYPE_CHEST" },
    [804] = { name="High Level Staff", class=2, subClass=10, itemLevel=70, requiredLevel=50, questRewards={8004}, loc="INVTYPE_2HWEAPON" },
    [805] = { name="High Quest Staff", class=2, subClass=10, itemLevel=55, requiredLevel=18, questRewards={8005}, loc="INVTYPE_2HWEAPON" },
    [806] = { name="Class Ring", class=4, subClass=0, itemLevel=26, requiredLevel=0, questRewards={8006}, loc="INVTYPE_FINGER" },
}
for i=8000,8006 do
    QUESTIE_QUESTS[i] = { name="Reward Quest "..i, requiredLevel=15, questLevel=20,
        requiredClasses=0, requiredRaces=0, startedBy={{197}} }
end
QUESTIE_QUESTS[8000].requiredClasses=1024
QUESTIE_QUESTS[8000].preQuestSingle={100}
QUESTIE_QUESTS[8000].requiredRaces=8
QUESTIE_QUESTS[8003].requiredRaces=178
QUESTIE_QUESTS[8005].requiredLevel=50
QUESTIE_QUESTS[8006].requiredClasses=1
local itemGet=ItemDB.Get
ItemDB.Get=function(id,key) local r=REWARD_ITEMS[id]; return r and r[key] or itemGet(id,key) end
ENUMERATIONS, ITEM_READS=0,0
ItemDB.GetAllIds=function()
    ENUMERATIONS=ENUMERATIONS+1
    local out={}; for id in pairs(REWARD_ITEMS) do out[#out+1]=id end
    table.sort(out); return out
end
UNCACHED, FINISHED={},{}
function GetItemInfo(id)
    ITEM_READS=ITEM_READS+1
    local r=REWARD_ITEMS[id]
    if not r or UNCACHED[id] then return nil end
    return r.name,"|Hitem:"..id.."|h["..r.name.."]|h",r.quality or 3,r.itemLevel,r.requiredLevel,"","",1,r.loc,"icon"
end
function IsQuestFlaggedCompleted(id) return FINISHED[id]==true end
MAP_OPENS={}
function WorldMapFrame:SetMapID(id) WORLDMAP_ID=id; MAP_OPENS[#MAP_OPENS+1]=id end
'''


def game(style, pre=""):
    g=Game(style, DATA+pre, fresh=True)
    g.start(); g.advance(4)
    return g


def ids(g):
    return [(r.itemID,r.questID) for r in g.eval("NS.rewards._results()").values()]


def save(g, extra=""):
    return g.eval("NS.fishing.save")(g.eval('{name="Crystal Lake",map=1429,x=52,y=66,minSkill=1,safeSkill=25,fish="Raw Brilliant Smallfish"'+extra+'}'))


def test_optional_is_off_and_does_not_scan_on_login(style):
    g=game(style)
    assert not g.eval("NS.db.fishingMap") and not g.eval("NS.db.rewardBrowser")
    assert g.eval("ENUMERATIONS")==0 and g.eval("ITEM_READS")==0
    assert g.eval("#NS.fishing._pins()")==0


def test_water_save_draw_hover_edit_delete_toggle(style):
    g=game(style)
    assert save(g)==1
    g.run("WorldMapFrame.shown=true"); g.slash("fishing on")
    p=g.eval("NS.fishing._pins()[1]")
    assert p.shown and p.water.name=="Crystal Lake"
    assert p.point[4]==520 and p.point[5]==-462
    p.scripts.OnEnter(p)
    assert "Minimum skill: 1" in g.eval("TOOLTIP.lines[1]")
    assert "Raw Brilliant Smallfish" in g.eval("TOOLTIP.lines[2]")
    p.scripts.OnClick(p)
    assert g.eval("NS.fishing._editor().name:GetText()") == "Crystal Lake"
    g.slash("fishing off")
    assert not p.shown and g.eval("NS.db.fishingWaters[1].name")=="Crystal Lake"
    assert g.eval("NS.fishing.remove")(1) and g.eval("#NS.fishing.list()")==0


def test_water_validation_and_unknown_skills(style):
    g=game(style)
    for value in ("x=-1","y=101","map=0","map=2.5","minSkill=-1","minSkill=0/0","safeSkill=0",'name="   "'):
        result=save(g,","+value)
        assert isinstance(result,tuple) and result[0] is None,value
    assert save(g,',minSkill="",safeSkill=""')==1
    assert g.eval("NS.db.fishingWaters[1].minSkill") is None


def test_water_map_and_zoom_filtering(style):
    g=game(style); save(g)
    g.run("WorldMapFrame.shown=true; WorldMapFrame.ScrollContainer.Child:SetScale(2)")
    g.slash("fishing on")
    p=g.eval("NS.fishing._pins()[1]")
    assert p.scale==0.5 and p.point[4]==1040
    g.run("WORLDMAP_ID=1453"); g.eval("NS.fishing.draw")()
    assert not p.shown and g.eval("NS.questMap") is None


def test_corrupt_saved_waters_are_ignored(style):
    g=game(style)
    g.run('NS.db.fishingWaters={bad="oops",[1]={name="broken",map=1,x=0/0,y=2},[2]=false}')
    g.slash("fishing on")
    assert g.eval("#NS.fishing.list()")==0


def test_saved_water_survives_reload_and_settings_reset(style):
    g=game(style); save(g)
    g.fire("ADDON_LOADED","QuestSharing"); g.slash("reset")
    assert g.eval("QuestSharingDB.fishingWaters[1].name")=="Crystal Lake"


def test_angleratlas_zone_data_does_not_become_water_data(style):
    g=game(style,'''AnglerAtlas={MM={GetModule=function() return {
        mapToZoneID={[1429]="12"},zones={["12"]={name="Elwynn Forest",fishingLevel=1,fishStats={["6291"]={}},isForeverZone=true}},
        fish={["6291"]={name="Raw Brilliant Smallfish"}}} end}}''')
    z=g.eval("NS.fishing.zoneSummary")(1429)
    assert z.minSkill==1 and z.fish[1]=="Raw Brilliant Smallfish" and z.provisional
    g.run("WorldMapFrame.shown=true"); g.slash("fishing on")
    assert "individual waters can differ" in g.eval("NS.fishing._overview().text.text")
    assert g.eval("#NS.fishing.list()")==0


def test_druid_reward_eligibility_and_sorting(style):
    g=game(style); g.slash("rewards")
    assert ids(g)==[(800,8000),(801,8001)],ids(g)
    assert g.eval("NS.db.rewardBrowser") and g.eval("NS.rewards._window().frame.shown")


def test_completed_race_and_max_level_restrictions(style):
    g=game(style,"FINISHED[8000]=true; QUESTIE_QUESTS[8001].requiredRaces=1")
    g.slash("rewards"); assert ids(g)==[]
    g.run("FINISHED[8000]=false; QUESTIE_QUESTS[8000].requiredMaxLevel=19")
    g.eval("NS.rewards.scan")(); assert ids(g)==[]


def test_forever_race_high_bits(style):
    g=game(style,'''function UnitRace() return "Skyborne","Skyborne",95 end
        QUESTIE_QUESTS[8000].requiredRaces=4294967296''')
    g.slash("rewards"); assert (800,8000) in ids(g)
    assert g.eval("NS.rewards.overlaps")(4294967296,8) is False


def test_search_slot_and_class_filters(style):
    g=game(style); g.slash("rewards")
    w=g.eval("NS.rewards._window()")
    w.search.SetText(w.search,"healing"); w.search.scripts.OnEnterPressed(w.search)
    assert ids(g)==[(801,8001)]
    w.search.SetText(w.search,"Elwynn"); w.search.scripts.OnEnterPressed(w.search)
    assert len(ids(g))==2
    g.eval("NS.rewards.search")(g.eval('{class="WARRIOR",faction="Alliance",level=20,near=true,slot="Weapon",text="",completed=false}'))
    assert ids(g)==[(802,8002)]


def test_reward_route_starter_prerequisite_map(style):
    g=game(style); g.slash("rewards")
    w=g.eval("NS.rewards._window()")
    w.rows[1].frame.scripts.OnClick(w.rows[1].frame)
    assert "Marshal McBride" in w.route.text and "Wolves Among Us" in w.route.text
    assert "Elwynn Forest" in w.route.text and w.routeMap==1429 and w.routeFrame.shown


def test_hover_compares_game_items(style):
    g=game(style,'''COMPARED=false
        function GameTooltip:SetHyperlink(link) TOOLTIP.link=link end
        function GameTooltip_ShowCompareItem() COMPARED=true end''')
    g.slash("rewards"); w=g.eval("NS.rewards._window()")
    w.rows[1].frame.scripts.OnEnter(w.rows[1].frame)
    assert g.eval("TOOLTIP.link")=="item:800" and g.eval("COMPARED")


def test_uncached_item_refreshes_on_data_event(style):
    g=game(style,"UNCACHED[800]=true"); g.slash("rewards")
    assert ids(g)==[(801,8001)], "unknown-quality rewards stay hidden until their native details load"
    g.run("UNCACHED[800]=nil"); g.fire("GET_ITEM_INFO_RECEIVED",800,True); g.advance(0.3)
    assert ids(g)==[(800,8000),(801,8001)] and g.eval("NS.rewards._results()[1].cached")


def test_switch_off_cancels_scan_and_reopen_restarts(style):
    g=game(style,'''ItemDB.GetAllIds=function() local t={}; for i=1,500 do t[i]=800 end; return t end''')
    g.slash("rewards")
    assert g.eval("NS.rewards._state()")[1]
    g.slash("rewards off"); g.advance(1)
    ready,loading,count=g.eval("NS.rewards._state()")
    assert not ready and not loading and count==100
    assert not g.eval("NS.rewards._window().frame.shown")
    g.slash("rewards"); g.advance(1)
    assert g.eval("NS.rewards._state()")[0]


def test_missing_catalogue_has_clear_empty_state(style):
    g=game(style,"ItemDB.GetAllIds=nil"); g.slash("rewards")
    assert "Needs a recent QuestieDB" in g.eval("NS.rewards._window().status.text") and ids(g)==[]


def test_optional_tabs_fit_window(style):
    g=game(style); g.slash("settings"); w=g.eval("NS._settingsWindow()")
    for tab in w.tabs.values():
        assert tab.frame.point[4]+tab.frame.width<=w.win.width-20
    g.eval("NS.settingsTab")("optional")
    assert w.bottom<w.win.height-30


def test_alt_click_adds_water_at_viewed_map_without_opening_game_map(style):
    g=game(style,'''local child=WorldMapFrame.ScrollContainer.Child
        WorldMapFrame.ScrollContainer=CreateFrame("Frame")
        WorldMapFrame.ScrollContainer.Child=child
        function WorldMapFrame:GetNormalizedCursorPosition() return 0.25,0.75 end''')
    g.run("WorldMapFrame.shown=true; WORLDMAP_ID=1433; ALT=true")
    g.slash("fishing on")
    scroll=g.eval("WorldMapFrame.ScrollContainer")
    click=scroll.posthooks.OnMouseDown[1]
    click(scroll,"LeftButton")
    e=g.eval("NS.fishing._editor()")
    assert (e.map.GetText(e.map),e.x.GetText(e.x),e.y.GetText(e.y))==("1433","25.00","75.00")
    assert g.eval("#NS.fishing.list()")==0 and g.eval("#MAP_OPENS")==0
    e.frame.Hide(e.frame); g.slash("fishing off"); click(scroll,"LeftButton")
    assert not e.frame.shown


def test_missing_enum_mappings_have_explicit_update_message(style):
    g=game(style,"LibQuestieDB.Enum=nil"); g.slash("rewards")
    assert "class, faction or race mappings" in g.eval("NS.rewards._window().status.text")
    assert ids(g)==[]


def test_fishing_editor_paginates_and_master_switch_hides_it(style):
    g=game(style)
    for i in range(7): assert save(g,',name="Water '+str(i)+'"')==i+1
    g.slash("fishing")
    e=g.eval("NS.fishing._editor()")
    assert "Page 1/2" in e.count.text
    g.run('for _,f in ipairs(FRAMES) do if f.text=="Next" then f.scripts.OnClick(f,"LeftButton"); break end end')
    assert "Page 2/2" in e.count.text and e.rows[1].shown and not e.rows[3].shown
    g.slash("off"); assert not e.frame.shown


def test_reward_browser_pages_and_never_opens_or_redraws_world_map(style):
    g=game(style,'''for id=9000,9017 do
            QUESTIE_QUESTS[id]={name="Route "..id,requiredLevel=15,questLevel=20,startedBy={{197}}}
            REWARD_ITEMS[id]={name="Staff "..id,class=2,subClass=10,itemLevel=25,requiredLevel=18,
                questRewards={id},loc="INVTYPE_2HWEAPON"}
        end''')
    g.slash("rewards"); w=g.eval("NS.rewards._window()")
    first=w.rows[1].result.questID
    g.run('for _,f in ipairs(FRAMES) do if f.text=="Next" then f.scripts.OnClick(f,"LeftButton"); break end end')
    assert w.rows[1].result.questID!=first
    w.rows[1].frame.scripts.OnClick(w.rows[1].frame)
    g.run('for _,f in ipairs(FRAMES) do if f.text=="Map directions (open M)" then f.scripts.OnClick(f,"LeftButton"); break end end')
    assert g.eval("#MAP_OPENS")==0 and "open your world map (M)" in "\n".join(g.printed())


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
