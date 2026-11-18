"""Gathering items: tooltip lists the three zones with the most spawns of what drops them; Ctrl+right-click marks them."""
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
UnitFactionGroup = function() return "Alliance" end
'''


def game(style):
    g = Game(style, DATA, fresh=True)
    g.start()
    g.fire("PLAYER_LOGIN")
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
    assert "Where to gather" in text
    assert "1. Senior Raptor (level 38-41)" in text and "7 known spawns" in text, text
    assert "2. Stranglethorn Leopard (level 30-32)" in text and "4 known spawns" in text
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
