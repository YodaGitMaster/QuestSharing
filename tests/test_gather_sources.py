"""Gathering items: tooltip lists the three best zones for my level and faction (name · zone · chance); Ctrl+right-click marks them."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_travel_map import SETUP  # noqa: E402

STYLES = ("modern", "classic")

# Light Hide (1000, leather) drops from: Senior Raptor (two records, 5 + 2 points in area 100), Young Wolf (3 points,
# area 100: loses to the raptor), Stranglethorn Leopard (4, area 101), Plains Wolf (2, area 102), Cave Bat (1, area 103,
# the fourth zone: not shown) and a friendly Cow (20 points, area 104: never prey). 1001 is a sword, not a gathering item.
DATA = SETUP + r'''
Enum.TooltipDataType = { Item = 0 }
POST = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) POST[#POST + 1] = fn end }
function GetItemInfoInstant(id)
    if id == 1000 then return id, "Trade Goods", "Leather", "", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01", 7, 6 end
    if id == 1001 then return id, "Weapon", "Sword", "", "Interface\\Icons\\INV_Sword_04", 2, 7 end
    if id == 1002 then return id, "Trade Goods", "Leather", "", "Interface\\Icons\\INV_Misc_LeatherScrap_02", 7, 6 end
    if id == 1003 then return id, "Trade Goods", "Herb", "", "Interface\\Icons\\INV_Misc_Herb_01", 7, 9 end
    -- the Classic data: leather, ore and cloth are plain 7/0 "Trade Goods", elementals 5/0 "Reagent" (v0.4.26 bug)
    if id == 1004 then return id, "Trade Goods", "Trade Goods", "", "Interface\\Icons\\INV_Misc_LeatherScrap_03", 7, 0 end
    if id == 1005 then return id, "Trade Goods", "Trade Goods", "", "Interface\\Icons\\INV_Ore_Copper_01", 7, 0 end
    if id == 1006 then return id, "Reagent", "Reagent", "", "Interface\\Icons\\INV_Stone_05", 5, 0 end
end
GameTooltip.CUR = nil
function GameTooltip:GetItem() return "x", GameTooltip.CUR end
function GameTooltip:IsShown() return TOOLTIP.shown ~= false end
function GameTooltip:ClearLines() TOOLTIP.lines = {} end
local function pts(n, x0) local t = {}; for i = 1, n do t[i] = { x0 + i, 30 + i } end; return t end
QUESTIE_NPCS = {
    [11] = { name = "Senior Raptor", minLevel = 38, maxLevel = 40, spawns = { [100] = pts(5, 10) } },
    [16] = { name = "Senior Raptor", minLevel = 39, maxLevel = 41, spawns = { [100] = pts(2, 60) } },
    [12] = { name = "Young Wolf", minLevel = 5, maxLevel = 6, spawns = { [100] = pts(3, 20) } },
    [13] = { name = "Stranglethorn Leopard", minLevel = 30, maxLevel = 32, spawns = { [101] = pts(4, 40) } },
    [14] = { name = "Plains Wolf", minLevel = 10, maxLevel = 12, spawns = { [102] = pts(2, 40) } },
    [15] = { name = "Cave Bat", minLevel = 3, maxLevel = 4, spawns = { [103] = pts(1, 40) } },
    [17] = { name = "Cow", minLevel = 1, maxLevel = 1, friendlyToFaction = "AH", spawns = { [104] = pts(20, 10) } },
}
NpcDB.Get = function(id, key) local r = QUESTIE_NPCS[id]; return r and r[key] end
QUESTIE_ITEMS[1000] = { name = "Light Hide", npcDrops = { 11, 16, 12, 13, 14, 15, 17 } }
QUESTIE_ITEMS[1001] = { name = "Sword", npcDrops = { 11 } }
LibQuestieDB.Support.Get = function(name)
    if name == "ZoneDB" then
        return { private = { areaIdToUiMapId = "return {[100]=1413,[101]=1440,[102]=1441,[103]=1442,[104]=1443}", areaIdToUiMapIdOverride = "return {}" } }
    end
end
QUESTIE_ITEMS[1002] = { name = "Light Leather", objectDrops = { 91 } }   -- QuestieDB: a chest, no creature (as in the real data)
QUESTIE_ITEMS[1004] = { name = "Light Leather", objectDrops = { 91 } }
QUESTIE_ITEMS[1005] = { name = "Copper Ore", npcDrops = { 15 }, objectDrops = { 91, 92 } }
QUESTIE_ITEMS[1006] = { name = "Elemental Earth", npcDrops = { 13 } }
QUESTIE_OBJECTS[91] = { name = "Battered Chest", spawns = { [102] = pts(9, 50) } }
QUESTIE_OBJECTS[92] = { name = "Copper Vein", spawns = { [102] = pts(4, 60) } }
QUESTIE_ITEMS[1003] = { name = "Peacebloom", objectDrops = { 90 } }
QUESTIE_OBJECTS[90] = { name = "Peacebloom Node", spawns = { [101] = pts(3, 50) } }
IsMetaKeyDown = function() return META end
META = false
FACTION, LEVEL = "Horde", 60        -- area 100 is The Barrens (1413), a Horde home zone
UnitFactionGroup = function() return FACTION end
UnitLevel = function() return LEVEL end
'''


def game(style):
    g = Game(style, DATA, fresh=True)
    g.start()
    g.fire("PLAYER_LOGIN")
    # the bundled skinning table: creature, tenths of a percent (a 17 = friendly Cow, 12 = Young Wolf, under the 1% floor)
    g.run("NS.skinningData[1002] = { 11, 610, 13, 450, 12, 20, 17, 900 }")
    g.run("NS.skinningData[1004] = { 11, 610, 13, 450 }")
    g.run("NS.db.itemSources = true; NS.gatherSources.refresh()")
    return g


def hover(g, item):
    g.run(f'GameTooltip.CUR = "|cffffffff|Hitem:{item}::::::::|h[x]|h|r"; GameTooltip:SetOwner(UIParent); TOOLTIP.shown = true;'
          f' for _, fn in ipairs(POST) do fn(GameTooltip, {{ id = {item} }}) end')
    g.advance(2)
    return [str(v) for v in g.eval("TOOLTIP.lines").values()]


def test_tooltip_lists_top_three_zones_by_spawn_count(style):
    lines = hover(game(style), 1000)
    text = "\n".join(lines)
    assert "Where to gather (for your level and faction)" in text
    assert "1. Senior Raptor · " in text and "chance unknown" in text, text
    assert "2. Stranglethorn Leopard · " in text
    assert "known spawn" not in text and "(level" not in text, "a tooltip line is name · zone · chance only"
    assert "3. Plains Wolf" in text
    assert "Young Wolf" not in text, "one creature per zone"
    assert "Cave Bat" not in text and "Cow" not in text, "only the top three prey zones"
    assert "Ctrl+right-click" in text


def test_non_gathering_item_and_setting_off_add_nothing(style):
    g = game(style)
    assert hover(g, 1001) == []
    g.run("NS.db.itemSources = false; NS.gatherSources.refresh()")
    assert hover(g, 1000) == []


def test_tooltip_is_added_once_per_hover(style):
    g = game(style)
    count = len(hover(g, 1000))
    g.run("for _, fn in ipairs(POST) do fn(GameTooltip, { id = 1000 }) end")
    g.advance(2)
    assert len(g.eval("TOOLTIP.lines")) == count


def test_ctrl_right_click_marks_every_zone_with_the_item_icon_and_sets_a_waypoint(style):
    g = game(style)
    hover(g, 1000)
    g.run("WORLDMAP_ID = 1414; WorldMapFrame:Show()")
    g.run("CTRL = true"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active().id") == 1000
    assert any("open your world map" in p for p in g.printed()), "the addon never opens the map itself"
    assert g.eval("WAYPOINT.map") == 1413
    g.run("WORLDMAP_ID = 1414; NS.gatherSources.draw()")
    pins = [f for f in g.eval("FRAMES").values() if f.source and f.shown]
    assert len(pins) == 7 + 4 + 2, "every spawn point of the three zones, on the continent map"
    assert all(p.icon.texture == "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" for p in pins)
    g.run("WORLDMAP_ID = 1413; NS.gatherSources.draw()")
    assert len([f for f in g.eval("FRAMES").values() if f.source and f.shown]) == 7, "a zone map shows its own spawns only"


def test_second_ctrl_right_click_removes_the_marks_and_plain_right_click_does_nothing(style):
    g = game(style)
    hover(g, 1000)
    g.run("WorldMapFrame:Show(); WORLDMAP_ID = 1413")
    g.run("CTRL = false"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active()") is None
    g.run("CTRL = true"); g.fire("GLOBAL_MOUSE_DOWN", "LeftButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active()") is None
    g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active()") is not None
    g.advance(1); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active()") is None
    assert not [f for f in g.eval("FRAMES").values() if f.source and f.shown]


def test_item_with_no_known_source_says_so_and_marks_nothing(style):
    g = game(style)
    g.run("QUESTIE_ITEMS[1000].npcDrops = {}; NS.gatherSources._reset()")
    hover(g, 1000)
    g.run("WorldMapFrame:Show(); CTRL = true"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active()") is None
    assert any("no creature or node" in p for p in g.printed())


def test_skinned_item_without_questie_drops_uses_the_bundled_skinning_table(style):
    g = game(style)
    text = "\n".join(hover(g, 1002))
    assert "1. Senior Raptor · " in text and text.split("1. Senior Raptor")[1].splitlines()[0].endswith(" · 61%"), text
    assert "2. Stranglethorn Leopard" in text and "45%" in text
    assert "Cow" not in text, "friendly creatures are never skinned for this"
    assert "Kobold Crate" not in text and "Chest" not in text, "leather is not gathered from containers"


def test_herb_node_is_listed_for_a_herb(style):
    text = "\n".join(hover(game(style), 1003))
    assert "1. Peacebloom Node · " in text and "· node" in text, text


def test_command_explains_the_state(style):
    g = game(style)
    hover(g, 1002)
    g.run("NS.gatherSources.command('')"); g.advance(2)
    out = "\n".join(g.printed())
    assert "Light Leather: shown. 2 zones known." in out and "1. Senior Raptor" in out, out
    assert "class 7" not in out and "QuestieDB found" not in out, "developer terms stay in the debug log"
    assert any("class 7, subclass 6" in str(line) for line in g.eval("QuestSharingLog").values()), "the details are logged"
    g.run("NS.gatherSources.command('1001')")
    assert "Sword is not something you gather, so no places are listed." in "\n".join(g.printed())


def test_cmd_works_like_ctrl_and_a_hint_says_when_the_setting_is_off(style):
    g = game(style)
    hover(g, 1002)
    g.run("WorldMapFrame:Show(); CTRL = false; META = true"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    assert g.eval("NS.gatherSources._active().id") == 1002
    g.run("NS.gatherSources.clear(); NS.db.itemSources = false")
    g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    hints = [p for p in g.printed() if "turn on Settings" in p]
    assert len(hints) == 1 and g.eval("NS.gatherSources._active()") is None


def test_classic_trade_goods_subclass_zero_leather_still_shows_its_skinning_sources(style):
    """v0.4.26: Light Leather is 7/0 in Classic data, so the subclass gate hid every leather, hide, cloth and ore"""
    text = "\n".join(hover(game(style), 1004))
    assert "1. Senior Raptor" in text and "61%" in text, text
    assert "Battered Chest" not in text


def test_classic_ore_lists_its_vein_but_not_the_chest(style):
    text = "\n".join(hover(game(style), 1005))
    assert "Copper Vein" in text and "· node" in text, text
    assert "Battered Chest" not in text, "a chest with 9 spawns must not win over the vein"
    assert "Cave Bat" in text, "creature drops stay"


def test_classic_elemental_reagent_shows_its_drops(style):
    text = "\n".join(hover(game(style), 1006))
    assert "1. Stranglethorn Leopard" in text, text


def test_container_names_are_recognised(style):
    g = game(style)
    f = g.eval("NS.gatherSources._isContainer")
    for name in ("Battered Chest", "Alliance Strongbox", "Armor Crate", "Large Iron Bound Chest", "Hidden Strongbox"):
        assert f(name) is True, name
    for name in ("Copper Vein", "Peacebloom", "Tin Vein", "Incendicite Mineral Vein", "Small Thorium Vein"):
        assert f(name) is False, name


def test_the_click_hint_names_cmd_on_a_mac(style):
    g = game(style)
    assert any("Ctrl+right-click" in l for l in hover(g, 1000))
    g.run("IsMacClient = function() return true end; NS.gatherSources._reset(); GameTooltip:ClearLines(); GameTooltip.questSharingGatherID = nil")
    lines = hover(g, 1000)
    assert any("Cmd+right-click" in l for l in lines) and not any("Ctrl+right-click" in l for l in lines), lines


def test_map_pin_tips_use_the_right_verb_and_the_tooltip_percent_format(style):
    g = game(style)
    hover(g, 1005)
    g.run("WorldMapFrame:Show(); WORLDMAP_ID = 1441; CTRL = true"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2)
    g.run("NS.gatherSources.draw()")
    tips = []
    for f in g.eval("FRAMES").values():
        if f.source and f.shown:
            g.eval("function(p) p.scripts.OnEnter(p) end")(f)
            tips.append("\n".join(str(v) for v in (g.eval("TOOLTIP.lines") or {}).values()))
    assert any("Gather it here for" in t for t in tips), "the vein: you mine it, it does not drop it"
    assert not any("Gather it here" in t and "Drops" in t for t in tips), tips
    g.run("NS.gatherSources.clear()")
    hover(g, 1004)
    g.run("WORLDMAP_ID = 1413"); g.fire("GLOBAL_MOUSE_DOWN", "RightButton"); g.advance(2); g.run("NS.gatherSources.draw()")
    tips = []
    for f in g.eval("FRAMES").values():
        if f.source and f.shown:
            g.eval("function(p) p.scripts.OnEnter(p) end")(f)
            tips.append("\n".join(str(v) for v in (g.eval("TOOLTIP.lines") or {}).values()))
    assert any("Skin it for" in t and "(61%)" in t for t in tips), tips


def set_player(g, faction, level):
    g.run(f'FACTION, LEVEL = "{faction}", {level}; NS.gatherSources._reset()')


def test_creatures_far_above_my_level_are_left_out(style):
    g = game(style)
    set_player(g, "Horde", 10)
    text = "\n".join(hover(g, 1000))
    assert "1. Young Wolf · " in text and "2. Plains Wolf · " in text and "3. Cave Bat · " in text, text
    assert "Senior Raptor" not in text and "Stranglethorn Leopard" not in text, "level 30+ is no place for a level 10"


def test_the_other_factions_home_zones_are_left_out(style):
    g = game(style)
    set_player(g, "Alliance", 60)
    text = "\n".join(hover(g, 1000))
    assert "Senior Raptor" not in text and "Young Wolf" not in text, "area 100 is The Barrens, Horde land"
    assert "1. Stranglethorn Leopard · " in text, text


def test_more_items_per_visit_beats_more_spawns(style):
    g = game(style)
    # Plains Wolf (2 spawns) skins at 90 %, Senior Raptor (7 spawns) at 5 %: 1.8 against 0.35 hides per visit
    g.run("NS.skinningData[1002] = { 11, 50, 16, 50, 14, 900 }")
    text = "\n".join(hover(g, 1002))
    assert text.index("Plains Wolf") < text.index("Senior Raptor"), text


def test_when_nothing_fits_it_still_shows_the_best_it_knows(style):
    g = game(style)
    set_player(g, "Horde", 10)
    g.run("NS.skinningData[1002] = { 11, 610, 13, 450 }")
    text = "\n".join(hover(g, 1002))                    # only raptors (38+) and leopards (30+) are skinned for it
    assert "1. Senior Raptor · " in text and "2. Stranglethorn Leopard · " in text, text


def test_home_zone_table_marks_both_factions_starting_zones(style):
    g = game(style)
    home = {int(k): str(v) for k, v in g.eval("NS.gatherSources._HOME").items()}
    assert home[1429] == "A" and home[1426] == "A" and home[1438] == "A", "Elwynn, Dun Morogh, Teldrassil"
    assert home[1411] == "H" and home[1412] == "H" and home[1420] == "H", "Durotar, Mulgore, Tirisfal"
    assert 1434 not in home, "Stranglethorn Vale is open to both"


def test_levelling_up_ranks_again_for_the_new_level(style):
    g = game(style)
    set_player(g, "Horde", 10)
    assert "Senior Raptor" not in "\n".join(hover(g, 1000))
    g.run("LEVEL = 60; GameTooltip:ClearLines(); GameTooltip.questSharingGatherID = nil")
    g.fire("PLAYER_LEVEL_UP", 60)
    assert "1. Senior Raptor · " in "\n".join(hover(g, 1000))


def test_fallback_header_and_the_command_say_what_was_left_out(style):
    g = game(style)
    set_player(g, "Horde", 10)
    g.run("NS.skinningData[1002] = { 11, 610, 13, 450 }")
    lines = hover(g, 1002)
    assert lines[0] == "Where to gather (none for your level and faction; best known)", lines
    g.run("NS.gatherSources.command('1002')"); g.advance(2)
    out = "\n".join(g.printed())
    assert "left out: 2 zone(s) with creatures more than 3 levels above you, 0 in Alliance home zones" in out, out
    set_player(g, "Alliance", 60)
    g.run("NS.gatherSources.command('1000')"); g.advance(2)
    out = "\n".join(g.printed())
    assert "in Horde home zones" in out and "1 in Horde home zones" in out, out


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total += 1
            try:
                fn(style) if style else fn()
                print("ok  ", f"{name}[{style}]")
            except Exception as e:
                failed += 1
                print("FAIL", f"{name}[{style}]", type(e).__name__, str(e)[:900])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
