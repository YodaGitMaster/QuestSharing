"""World-map overlay: dungeon entrances, boat / zeppelin / tram pins, hover lines and the nearest town per faction."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_questmap import DATA  # noqa: E402

STYLES = ("modern", "classic")

# Two continents on the Azeroth map. Every zone is one 0.15-wide cell of its continent's grid, so a town in the
# same zone as an entrance is always closer than a town in another zone.
SETUP = DATA + r'''
Enum = { UIMapType = { World = 1, Continent = 2, Zone = 3 } }
KALIMDOR = { 1411,1412,1413,1438,1439,1440,1441,1442,1443,1444,1445,1446,1447,1448,1449,1450,1451,1452,1454,1456,1457 }
EASTERN = { 1417,1418,1419,1420,1421,1422,1423,1424,1425,1426,1427,1428,1431,1432,1433,1434,1435,1436,1437,1453,1455,1458 }
CONTINENT_OF, CELL = {}, {}
for _, list in ipairs({ { 1414, KALIMDOR }, { 1415, EASTERN } }) do
    for i, id in ipairs(list[2]) do CONTINENT_OF[id] = list[1]; CELL[id] = { (i - 1) % 5, math.floor((i - 1) / 5) } end
end
C_Map.GetMapInfo = function(id)
    if id == 947 then return { name = "Azeroth", parentMapID = 0, mapType = 1 } end
    if id == 1414 or id == 1415 then return { name = id == 1414 and "Kalimdor" or "Eastern Kingdoms", parentMapID = 947, mapType = 2 } end
    if CONTINENT_OF[id] then return { name = "Zone " .. id, parentMapID = CONTINENT_OF[id], mapType = 3 } end
end
C_Map.GetMapRectOnMap = function(id, parent)
    if parent == 947 and id == 1414 then return 0, 0.4, 0, 1 end
    if parent == 947 and id == 1415 then return 0.5, 0.9, 0, 1 end
    if CONTINENT_OF[id] == parent then
        local c = CELL[id]
        local x1, y1 = 0.04 + c[1] * 0.19, 0.04 + c[2] * 0.19
        return x1, x1 + 0.15, y1, y1 + 0.15
    end
end
function geometry(map)
    local n = 0
    for _, e in ipairs(NS.travelData.dungeons) do if CONTINENT_OF[e.map] == map then n = n + 1 end end
    return n
end
'''


# QuestieDB with trainers: 1 Mining + 4 Fishing (both mine) close together in the Barrens, 2 a Druid trainer for the
# Alliance in Ashenvale, 3 a Druid trainer for the Horde only, 5 Tailoring (not mine), 6 a mining vendor, 7 a Cooking
# trainer I do not know. The player is an Alliance druid with Mining and Fishing.
QUESTIE = r'''
QUESTIE_NPCS = {
    [1] = { name = "Gorn", subName = "Mining Trainer", friendlyToFaction = "AH", spawns = { [100] = { { 45.0, 36.0 } } } },
    [2] = { name = "Elara", subName = "Druid Trainer", friendlyToFaction = "A", spawns = { [101] = { { 30.0, 50.0 } } } },
    [3] = { name = "Grosh", subName = "Druid Trainer", friendlyToFaction = "H", spawns = { [100] = { { 60.0, 60.0 } } } },
    [4] = { name = "Finn", subName = "Fishing Trainer", friendlyToFaction = "AH", spawns = { [100] = { { 45.6, 36.3 } } } },
    [5] = { name = "Tess", subName = "Tailoring Trainer", friendlyToFaction = "AH", spawns = { [100] = { { 20.0, 20.0 } } } },
    [6] = { name = "Pike", subName = "Mining Supplies", friendlyToFaction = "AH", spawns = { [100] = { { 70.0, 70.0 } } } },
    [7] = { name = "Chef", subName = "Cooking Trainer", friendlyToFaction = "AH", spawns = { [100] = { { 80.0, 20.0 } } } },
}
NpcDB.Get = function(id, key) local r = QUESTIE_NPCS[id]; return r and r[key] end
NpcDB.GetAllIds = function() return { 1, 2, 3, 4, 5, 6, 7 } end
LibQuestieDB.Support.Get = function(name)
    if name == "ZoneDB" then
        return { private = { areaIdToUiMapId = "return {[100]=1413,[101]=1440}", areaIdToUiMapIdOverride = "return {}" } }
    end
end
UnitClass = function() return "Druid", "DRUID" end
UnitFactionGroup = function() return "Alliance" end
SKILL_RANKS = { [186] = 150, [356] = 1 }
C_SkillInfo = { GetSkillLineInfoByID = function(id) return { rank = SKILL_RANKS[id] or 0 } end }
'''


def game(style, map_id=1414, questie=False):
    g = Game(style, SETUP + (QUESTIE if questie else ""), fresh=True)
    g.start()
    g.fire("PLAYER_LOGIN")                      # starts the map tick, as the game does
    g.run(f"WORLDMAP_ID={map_id}; WorldMapFrame:Show(); NS.travelMap.refresh()")
    g.advance(5 if questie else 1)           # the trainer index is a background job
    return g


def pins(g, kind=None):
    return [f for f in g.eval("FRAMES").values() if f.entry and f.shown and (kind is None or f.kind == kind)]


def names(g, kind):
    return sorted(p.entry.name for p in pins(g, kind))


def hover(g, name):
    pin = next(p for p in pins(g) if p.entry.name == name)
    pin.scripts.OnEnter(pin)
    return pin


def tooltip(g):
    t = g.eval("TOOLTIP")
    return t.text, [str(v) for v in (t.lines or {}).values()]


def strokes(g):
    layer = g.eval("QuestSharingTravelOverlay")
    return [c for c in layer.children.values() if c.isLine and c.shown and c.vertex]


def test_data_is_consistent(style):
    g = Game(style, SETUP, fresh=True)
    g.start()
    assert g.eval("#NS.travelData.dungeons") == 22
    assert g.eval("""(function()
        local D = NS.travelData
        for _, r in ipairs(D.routes) do
            if not (D.stops[r.a] and D.stops[r.b]) then return "route " .. r.a .. "-" .. r.b end
            if r.faction ~= "Alliance" and r.faction ~= "Horde" and r.faction ~= "Both" then return "faction " .. r.a end
        end
        local function ok(e) return e.map and CONTINENT_OF[e.map] and e.x > 0 and e.x < 100 and e.y > 0 and e.y < 100 end
        for id, s in pairs(D.stops) do if not ok(s) then return "stop " .. id end end
        for _, d in ipairs(D.dungeons) do if not ok(d) or #d.inside == 0 then return "dungeon " .. d.name end end
        for _, t in ipairs(D.towns) do
            if not ok(t) or (t.faction ~= "Alliance" and t.faction ~= "Horde" and t.faction ~= "Both") then return "town " .. t.name end
        end
        return "ok"
    end)()""") == "ok"


def test_continent_map_shows_its_dungeons_and_transport_stops(style):
    g = game(style, 1414)
    expected = g.eval("geometry(1414)")
    assert len(pins(g, "dungeon")) == expected == 10
    assert "Wailing Caverns" in names(g, "dungeon") and "The Deadmines" not in names(g, "dungeon")
    stops = names(g, "stop")
    assert "Auberdine docks" in stops and "Ratchet docks" in stops and "Orgrimmar zeppelin tower" in stops
    assert "Menethil Harbor docks" not in stops, "an Eastern Kingdoms stop is not on the Kalimdor map"


def test_zone_map_shows_only_that_zone(style):
    g = game(style, 1413)
    assert names(g, "dungeon") == ["Razorfen Downs", "Razorfen Kraul", "Wailing Caverns"]
    assert names(g, "stop") == ["Ratchet docks"]


def test_azeroth_map_shows_both_continents(style):
    g = game(style, 947)
    assert len(pins(g, "dungeon")) == 22 and len(pins(g, "stop")) == 11


def test_pin_is_placed_by_its_map_position(style):
    g = game(style, 1413)
    pin = next(p for p in pins(g, "dungeon") if p.entry.name == "Wailing Caverns")
    p = pin.point
    assert p[1] == "CENTER" and p[2].name == "QuestSharingTravelOverlay" and p[3] == "TOPLEFT"
    # zone 1413 is the zone shown itself (identity projection): 46.0 %, 36.6 % of the 1000 x 700 canvas
    assert abs(p[4] - 460) < 0.01 and abs(p[5] + 256.2) < 0.01


def test_hovering_a_boat_draws_the_line_and_names_where_it_goes(style):
    g = game(style, 947)
    hover(g, "Auberdine docks")
    title, lines = tooltip(g)
    text = " ".join(lines)
    assert "Auberdine docks" in title
    assert "Menethil Harbor docks" in text and "Rut'theran Village dock" in text and "Boat" in text
    assert len(strokes(g)) == 2, "one line to each linked stop"
    pin = next(p for p in pins(g) if p.entry.name == "Auberdine docks")
    pin.scripts.OnLeave(pin)
    assert not strokes(g), "the lines go away with the mouse"


def test_hovering_a_zeppelin_connects_all_three_towers(style):
    g = game(style, 947)
    hover(g, "Undercity zeppelin tower")
    _, lines = tooltip(g)
    assert len([l for l in lines if "Zeppelin to" in l]) == 2 and len(strokes(g)) == 2
    assert any("Horde" in l for l in lines)


def test_a_line_that_leaves_the_map_is_explained_not_drawn(style):
    g = game(style, 1414)
    hover(g, "Auberdine docks")
    _, lines = tooltip(g)
    assert any("Azeroth map" in l for l in lines)
    assert len(strokes(g)) == 1, "only Rut'theran is on the Kalimdor map"


def test_hovering_a_dungeon_names_the_closest_town_per_faction(style):
    g = game(style, 1414)
    hover(g, "Wailing Caverns")
    title, lines = tooltip(g)
    text = "\n".join(lines)
    assert title == "Wailing Caverns" and "level 15-25" in text
    assert "Alliance" in text and "Horde" in text
    assert "The Crossroads (The Barrens)" in text, text
    assert "Ratchet (The Barrens) · neutral" in text, "the Alliance's closest is the neutral town in the same zone"
    assert len(strokes(g)) == 2


def test_dungeon_with_several_instances_lists_each_with_its_levels(style):
    g = game(style, 1428)
    hover(g, "Blackrock Mountain")
    _, lines = tooltip(g)
    text = "\n".join(lines)
    for expected in ("Blackrock Depths · level 52-60", "Lower Blackrock Spire", "Molten Core · level 60", "Blackwing Lair"):
        assert expected in text, text


def test_only_towns_on_the_same_continent_count(style):
    g = game(style, 1414)
    town = g.eval("NS.travelMap.nearestTown")
    alliance = town(g.eval("NS.travelData.dungeons[1]"), "Alliance")      # Ragefire Chasm, Kalimdor
    assert alliance.name and g.eval("CONTINENT_OF")[alliance.map] == 1414


def test_setting_off_hides_the_overlay_and_back_on_restores_it(style):
    g = game(style, 1414)
    assert g.eval("QuestSharingTravelOverlay").shown
    g.eval("NS.setSetting")("travelMap", False)
    assert g.eval("QuestSharingTravelOverlay").shown and not pins(g, "dungeon"), "my trainers keep the overlay open"
    g.eval("NS.setSetting")("myTrainers", False)
    assert not g.eval("QuestSharingTravelOverlay").shown
    g.eval("NS.setSetting")("travelMap", True); g.eval("NS.setSetting")("myTrainers", True)
    assert g.eval("QuestSharingTravelOverlay").shown and pins(g, "dungeon")


def test_nothing_is_drawn_in_combat_or_with_the_map_closed(style):
    g = game(style, 1414)
    g.run("IN_COMBAT = true"); g.fire("PLAYER_REGEN_DISABLED")
    assert not g.eval("QuestSharingTravelOverlay").shown
    g.run("IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED")
    assert g.eval("QuestSharingTravelOverlay").shown
    g.run("WorldMapFrame:Hide()"); g.advance(1)
    assert not g.eval("QuestSharingTravelOverlay").shown


def trainer_pins(g):
    return pins(g, "trainer")


def members(pin):
    return sorted(m.entry.name for m in pin.entry.members.values())


def test_my_trainers_are_my_class_and_professions_for_my_faction(style):
    g = game(style, 1413, questie=True)
    found = sorted(n for p in trainer_pins(g) for n in members(p))
    assert found == ["Finn", "Gorn"], "mining + fishing; not tailoring, cooking, the supplies vendor or the Horde druid"
    g = game(style, 1414, questie=True)
    assert sorted(n for p in trainer_pins(g) for n in members(p)) == ["Elara", "Finn", "Gorn"], "the Alliance druid joins on the continent"


def test_trainers_standing_together_share_one_pin_and_the_tooltip_lists_them(style):
    g = game(style, 1413, questie=True)
    pin = trainer_pins(g)[0]
    assert members(pin) == ["Finn", "Gorn"]
    pin.scripts.OnEnter(pin)
    title, lines = tooltip(g)
    text = "\n".join(lines)
    assert title == "Your trainers" and "Gorn · Mining Trainer" in text and "Finn · Fishing Trainer" in text
    assert "Click to set a waypoint" in text


def test_clicking_a_trainer_sets_a_waypoint(style):
    g = game(style, 1413, questie=True)
    pin = trainer_pins(g)[0]
    pin.scripts.OnClick(pin)
    wp = g.eval("WAYPOINT")
    assert wp.map == 1413 and abs(wp.x - 0.45) < 0.001 and abs(wp.y - 0.36) < 0.001


def test_trainer_icons_are_the_profession_and_class_art(style):
    g = game(style, 1413, questie=True)
    assert trainer_pins(g)[0].icon.texture.endswith("Trade_Mining")


def test_trainers_hide_on_the_azeroth_map_and_with_the_setting_off(style):
    g = game(style, 947, questie=True)
    assert not trainer_pins(g)
    g = game(style, 1413, questie=True)
    assert trainer_pins(g)
    g.eval("NS.setSetting")("myTrainers", False)
    g.advance(1)
    assert not trainer_pins(g) and pins(g, "dungeon"), "dungeons stay"
    g.eval("NS.setSetting")("myTrainers", True)
    g.advance(5)
    assert trainer_pins(g)


def test_nothing_is_indexed_until_a_map_with_the_setting_on_is_open(style):
    g = Game(style, SETUP + QUESTIE, fresh=True)
    g.start()
    g.fire("PLAYER_LOGIN")
    g.advance(5)
    assert g.eval("NS.trainerIndex.state()") == "idle"
    g.run("WORLDMAP_ID=1413; WorldMapFrame:Show()"); g.advance(5)
    assert g.eval("NS.trainerIndex.state()") == "done"


def test_without_questie_nothing_is_drawn_and_nothing_breaks(style):
    g = game(style, 1413)
    assert not trainer_pins(g) and pins(g, "dungeon")


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        styles = STYLES if inspect.signature(fn).parameters else (None,)
        for style in styles:
            total += 1
            label = f"{name}[{style}]" if style else name
            try:
                fn(style) if style else fn()
                print("ok  ", label)
            except Exception as e:                       # noqa: BLE001
                failed += 1
                print("FAIL", label, type(e).__name__, str(e)[:500])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
