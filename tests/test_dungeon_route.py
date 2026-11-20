"""'Get them all' route: travel graph (walk, flights, boats, hearthstone), stop order and the read-only route window."""
import pathlib
import re
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_quests import game as dungeon_game, filters, plain, HOVER_DATA, SEEKING
from test_loot import click

STYLES = ("modern", "classic")
# A toy world: every map is a 1000 x 1000 yard square placed on a continent (0 = Eastern Kingdoms, 1 = Kalimdor).
WORLD = r'''
WORLD_MAPS={
 [1429]={0,0,0},        -- Elwynn Forest: player at 42.3, 61.8
 [1453]={0,300,-300},   -- Stormwind City (flight master 66.3, 62.2)
 [1436]={0,-1200,0},    -- Westfall (Sentinel Hill flight, Deadmines entrance)
 [1437]={0,-200,-9000}, -- Wetlands, far north (Menethil flight + docks)
 [1455]={0,1500,-3000}, -- Ironforge
 [1439]={1,0,0},        -- Darkshore (Auberdine docks)
 [1438]={1,500,-2000},  -- Teldrassil
}
function CreateVector2D(x,y) return {x=x,y=y} end
C_Map.GetWorldPosFromMapPos=function(map,v)
 local m=WORLD_MAPS[map]; if not m then return nil end
 return m[1],{x=m[2]+v.x*1000,y=m[3]+v.y*1000}
end
UnitFactionGroup=function() return "Alliance" end
do -- Questie's area -> map table for the areas used here (Elwynn 12, Westfall 40, Wetlands 11)
 local get=LibQuestieDB.Support.Get
 LibQuestieDB.Support.Get=function(name)
  if name=="ZoneDB" then return {private={areaIdToUiMapId="return {[12]=1429,[40]=1436,[11]=1437}",areaIdToUiMapIdOverride="return {}"}} end
  return get(name)
 end
end
'''


def game(style, extra="", open_tab=False):
    return dungeon_game(style, WORLD + extra, open_tab)


def plan(g, targets_lua, options_lua):
    return g.eval(f"NS.dungeonRoute.plan({targets_lua},{options_lua})")


def kinds(result):
    return [s.kind for s in result.steps.values()]


def picks(result):
    return [s.quest for s in result.steps.values() if s.kind in ("Pick up", "Hand in")]


START = "start={map=1429,x=42.3,y=61.8},level=20,hearth=false"


def target(qid, name, map_, x, y, kind="pickup", turn=None, unlocks=None):
    t = f'{{id={qid},name="{name}",kind="{kind}",pickup={{source={{name="Giver {qid}"}},point={{map={map_},x={x},y={y}}}}}'
    if turn:
        t += f',turnIn={{source={{name="Hand {qid}"}},point={{map={turn[0]},x={turn[1]},y={turn[2]}}}}}'
    if unlocks:
        t += ",unlocks={" + ",".join(map(str, unlocks)) + "}"
    return t + "}"


def test_same_zone_is_walking_only_in_the_shortest_order(style):
    g = game(style)
    r = plan(g, "{" + target(1, "Far", 1429, 90, 90) + "," + target(2, "Near", 1429, 45, 62) + "}", "{" + START + "}")
    assert set(kinds(r)) <= {"Walk", "Pick up"} and picks(r) == ["Near", "Far"]
    assert r.quests == 2 and r.totalSeconds > 0
    assert not g.eval("NS.db.errors")


def test_other_continent_takes_the_boat_and_never_walks_across_the_sea(style):
    g = game(style)
    r = plan(g, "{" + target(1, "Darkshore errand", 1439, 40, 40) + "}", "{" + START + "}")
    assert "Boat" in kinds(r), kinds(r)
    boat = [s for s in r.steps.values() if s.kind == "Boat"][0]
    assert "Auberdine" in boat.to
    assert picks(r) == ["Darkshore errand"]


def test_flight_is_used_when_faster_and_not_when_that_flight_path_is_unknown(style):
    g = game(style)
    far = "{" + target(1, "Wetlands job", 1437, 10, 60) + "}"
    r = plan(g, far, "{" + START + "}")
    assert "Fly" in kinds(r), kinds(r)
    # learned flight paths without Menethil Harbor: no flight there
    g.run('NS.db.knownFlights={Alliance={["Stormwind, Elwynn"]=true,["Sentinel Hill, Westfall"]=true}}')
    r = plan(g, far, "{" + START + "}")
    assert not any(s.kind == "Fly" and "Menethil" in s.to for s in r.steps.values())
    r = plan(g, far, "{" + START + ",assumeAllFlights=true}")
    assert any(s.kind == "Fly" and "Menethil" in s.to for s in r.steps.values()), "the check box assumes every path"


def test_hearthstone_is_used_once_on_the_leg_where_it_saves_most(style):
    g = game(style)
    targets = "{" + target(1, "Darkshore errand", 1439, 40, 40) + "}"
    finish = 'finish={label="The Deadmines entrance",point={map=1436,x=43,y=72}}'
    r = plan(g, targets, "{start={map=1429,x=42.3,y=61.8},level=20,hearth=true,bind='Stormwind City'," + finish + "}")
    assert kinds(r).count("Hearth") == 1 and r.hearthUsed
    k = kinds(r)
    assert k.index("Pick up") < k.index("Hearth") < k.index("Enter"), "hearth home after the far pickup"
    assert k[-1] == "Enter"
    r = plan(g, targets, "{start={map=1429,x=42.3,y=61.8},level=20,hearth=false,bind='Stormwind City'," + finish + "}")
    assert "Hearth" not in kinds(r)


def test_hearthstone_on_cooldown_or_missing_is_explained(style):
    g = game(style, "ITEMS[6948]={name='Hearthstone',count=1} GetTime=function() return 1000 end C_Container.GetItemCooldown=function() return 900,3600,1 end")
    r = plan(g, "{" + target(1, "Darkshore errand", 1439, 40, 40) + "}", "{start={map=1429,x=42.3,y=61.8},level=20,bind='Stormwind City'}")
    assert "Hearth" not in kinds(r) and any("cooldown" in n for n in r.notes.values())
    g = game(style)
    r = plan(g, "{" + target(1, "Darkshore errand", 1439, 40, 40) + "}", "{start={map=1429,x=42.3,y=61.8},level=20,bind='Stormwind City'}")
    assert any("no hearthstone" in n for n in r.notes.values())


def test_lead_in_is_handed_in_before_the_quest_it_unlocks(style):
    g = game(style)
    # the lead-in is picked up far away; its hand-in NPC (next to you) offers quest 2
    targets = "{" + target(1, "Seeking Helper", 1436, 50, 50, kind="leadin", turn=(1429, 44, 62), unlocks=[2]) + "," + \
        target(2, "Dungeon errand", 1429, 44, 62) + "}"
    r = plan(g, targets, "{" + START + "}")
    seq = [(s.kind, s.quest) for s in r.steps.values() if s.kind in ("Pick up", "Hand in")]
    assert seq == [("Pick up", "Seeking Helper"), ("Hand in", "Seeking Helper"), ("Pick up", "Dungeon errand")], seq
    assert r.quests == 1, "a lead-in is a step, not one of the dungeon quests"


def test_unplaceable_pickups_are_listed_not_routed(style):
    g = game(style)
    targets = "{" + target(1, "Inside job", 1581, 10, 10) + "," + target(2, "Elwynn job", 1429, 45, 62) + "}"
    r = plan(g, targets, "{" + START + "}")
    assert list(r.unknown.values()) == ["Inside job"] and picks(r) == ["Elwynn job"]
    r = plan(g, "{" + target(2, "Elwynn job", 1429, 45, 62) + "}", "{level=20,hearth=false}")
    assert len(list(r.steps.values()))==0 and any("position is unknown" in n for n in r.notes.values())


def test_flight_paths_are_learned_when_a_flight_master_opens(style):
    g = game(style, 'C_TaxiMap={GetAllTaxiNodes=function() return {{name="Stormwind, Elwynn",state=0},{name="Menethil Harbor, Wetlands",state=1},{name="Theramore, Dustwallow Marsh",state=2}} end}')
    g.fire("TAXIMAP_OPENED")
    known = g.eval("NS.db.knownFlights.Alliance")
    assert known["Stormwind, Elwynn"] and known["Menethil Harbor, Wetlands"] and known["Theramore, Dustwallow Marsh"] is None
    assert g.eval("NS.dungeonRoute.knowsFlight")("Stormwind City", "Alliance", False)
    assert not g.eval("NS.dungeonRoute.knowsFlight")("Theramore Isle", "Alliance", False)


ROUTE_DATA = HOVER_DATA + SEEKING + r'''
QUESTIE_NPCS[501]={name="Caitlin Grassman",spawns={[11]={{11,58}}}}
QUESTIE_NPCS[500]={name="Llana",spawns={[12]={{20,20}}}}
UnitLevel=function() return 30 end
'''


def test_button_needs_a_dungeon_and_opens_a_read_only_route_with_click_to_pin_steps(style):
    g = game(style, ROUTE_DATA, True)
    w = g.eval("NS.dungeonQuests._window()")
    assert w.route.disabled, "no dungeon chosen yet"
    filters(g, dungeon=1581)
    assert not w.route.disabled
    click(w.route); g.advance(30)
    # the Quests page button opens the Route tab of the same dungeon; the old window stays as D.planRoute()
    assert w.tabs.route.selected and not w.questsPage.shown and g.eval("NS.dungeonQuests.current")() == 1581
    assert g.eval("NS.dungeonQuests._routeWindow()") is None, "no separate window from the button"
    g.eval("NS.dungeonQuests.planRoute")(); g.advance(30)
    f = g.eval("NS.dungeonQuests._routeWindow()")
    assert f.shown and "The Deadmines" in plain(f.summary.text) and "about" in plain(f.summary.text)
    rows = [b for b in f.rows.values() if b.shown]
    texts = [plain(b.text.text) for b in rows]
    assert any(t.startswith("Pick up ") for t in texts), texts
    # the lead-in Seeking Caitlin comes before the quest Caitlin gives
    # Llana's two quests (one is the lead-in Seeking Caitlin) are one grouped step; its hand-in comes before Caitlin's quest
    lead = next(i for i, t in enumerate(texts) if t == "Pick up 2 quests from Llana")
    rows[lead].scripts.OnEnter(rows[lead])
    tip = "\n".join(g.eval("TOOLTIP.lines").values())
    assert "• Seeking Caitlin" in tip and "• Fetch for Llana" in tip
    hand = next(i for i, t in enumerate(texts) if t.startswith("Hand in Seeking Caitlin"))
    caitlin = next(i for i, t in enumerate(texts) if t.startswith("Pick up Lost in the Thicket"))
    assert lead < hand < caitlin
    assert "Mage mission" not in tip and not any("Mage mission" in t for t in texts), "a mage-only quest is not routed for a warrior"
    walks = [t for t in texts if t.startswith("Walk to ")]
    assert all("Seeking" not in t and "mission" not in t for t in walks), "walk steps name the NPC or place, not the quest"
    assert "Do these first" in plain(f.notes.text) and "Outdoor preparation" in plain(f.notes.text)
    g.run("WAYPOINT=nil;C_Map.SetUserWaypoint=function(p) WAYPOINT=p end")
    rows[0].scripts.OnClick(rows[0], "LeftButton")
    assert g.eval("WAYPOINT") is not None, "a step click pins its place"
    # read-only: no edit boxes in the window
    assert not any(getattr(b, "kind", None) == "EditBox" for b in rows)
    assert not g.eval("NS.db.errors")


def test_quests_needing_kill_or_collect_first_are_listed_as_do_first(style):
    g = game(style, ROUTE_DATA + "QUESTIE_QUESTS[7].preQuestSingle={4} QUESTIE_QUESTS[7].requiredClasses=0", True)
    filters(g, dungeon=1581)
    targets, do_first, later = g.eval("NS.dungeonQuests.routeTargets")(1581)
    names = [t.name for t in targets.values()]
    assert "Mage mission" not in names and any(q.name == "Mage mission" and q.needs == "Class mission" for q in do_first.values())
    assert later >= 1, "the level-40 quest is counted, not routed"


def route_window(g, area):
    filters(g, dungeon=area)
    g.eval("NS.dungeonQuests.planRoute")(); g.advance(30)  # the old route window (the button opens the Route tab)
    return g.eval("NS.dungeonQuests._routeWindow()")


def test_nothing_left_says_so_instead_of_a_route_to_the_entrance(style):
    g = game(style, ROUTE_DATA + "for id=1,60 do FINISHED[id]=true end", True)
    f = route_window(g, 1581)
    assert plain(f.summary.text) == "The Deadmines: nothing left to pick up"
    assert not any(b.shown for b in f.rows.values())


def test_inside_a_dungeon_explains_why_there_is_no_route(style):
    g = game(style, ROUTE_DATA, True); g.run("POS=nil")
    f = route_window(g, 1581)
    assert plain(f.summary.text) == "Can't plan from here" and "Step outside" in plain(f.notes.text)
    assert "0 s" not in plain(f.summary.text)


def test_entrance_comes_from_questiedb_dungeon_list_when_travel_data_has_none(style):
    # Forever's Excavation Site is only in QuestieDB's ZoneDB.private.dungeons (area 16732, entrance in Wetlands).
    extra = ROUTE_DATA + r'''
    local names2={[16732]="Excavation Site: Wetlands"}
    local area=C_Map.GetAreaInfo
    C_Map.GetAreaInfo=function(id) return names2[id] or area(id) end
    QUESTIE_QUESTS[90]={name="Excavation errand",questLevel=31,zoneOrSort=16732,startedBy={{197}}}
    local get=LibQuestieDB.Support.Get
    LibQuestieDB.Support.Get=function(name)
     local z=get(name)
     if name=="ZoneDB" and z then z.private.dungeons={[16732]={"Excavation Site: Wetlands",nil,11,{{11,47.79,56.16}}}} end
     return z
    end
    '''
    g = game(style, extra, True)
    f = route_window(g, 16732)
    texts = [plain(b.text.text) for b in f.rows.values() if b.shown]
    assert any("Excavation Site: Wetlands entrance" in t for t in texts), texts
    assert texts[-1] == "You are there: enter the dungeon"


def test_walk_steps_say_where_the_npc_stands_and_pickups_count_talk_time(style):
    g = game(style, ROUTE_DATA, True)
    f = route_window(g, 1581)
    walk = next(plain(b.text.text) for b in f.rows.values() if b.shown and plain(b.text.text).startswith("Walk to Llana"))
    assert "(Elwynn Forest 20.0, 20.0)" in walk
    r = g.eval("NS.dungeonQuests")._lastRoute
    pick = [s for s in r.steps.values() if s.kind == "Pick up"]
    assert all(s.seconds >= 5 for s in pick)
    entrance = next(plain(b.text.text) for b in f.rows.values() if b.shown and "entrance" in plain(b.text.text))
    assert "?" not in entrance, entrance


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"): continue
        for style in STYLES:
            total += 1
            try: fn(style); print("ok", name, style)
            except Exception as exc: failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:600])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
