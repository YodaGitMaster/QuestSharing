"""Selected quest step -> native direction HUD, own map geometry and waypoint."""
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_quest_planner_zone_steps import WESTFALL
from test_data_budget import COUNTERS, counts

MAP = r'''
QUESTS={}
CreateVector2D=function(x,y) return {x=x,y=y} end
C_Map.GetWorldPosFromMapPos=function(map,pos)
 if map~=1436 then return end
 return 100,{GetXY=function() return 10000-pos.y*2000,20000-pos.x*3000 end}
end
C_Map.GetMapWorldSize=function(map) if map==1436 then return 3000,2000 end end
FACING=0;GetPlayerFacing=function() return FACING end
WORLDMAP_ID=1436
WorldMapFrame=CreateFrame("Frame");WorldMapFrame.shown=false
WorldMapFrame.ScrollContainer={Child=CreateFrame("Frame")}
WorldMapFrame.ScrollContainer.Child.width,WorldMapFrame.ScrollContainer.Child.height=1000,700
function WorldMapFrame:GetMapID() return WORLDMAP_ID end
'''


def game(style, extra=""):
    g = Game(style, WESTFALL + MAP + extra + COUNTERS, fresh=True)
    g.start()
    return g


def open_guide(g, show_map=True):
    if show_map:
        g.run("WorldMapFrame:Show()")
    g.slash("plan")
    g.advance(5)
    assert g.eval("QuestSharingDirection.shown")


def tick(g, dt=0.25):
    g.run(f'local h=QuestSharingDirection;if h and h.scripts.OnUpdate then h.scripts.OnUpdate(h,{dt}) end')


def markers(g):
    return [f for f in g.eval("FRAMES").values() if f.steps and f.shown]


def click(g, pin):
    pin.scripts.OnEnter(pin)
    g.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    g.fire("GLOBAL_MOUSE_UP", "LeftButton")


def test_login_creates_no_arrow_map_layer_or_catalogue_scan(style):
    g = game(style)
    g.run("NS.db.questPlanner=true")
    g.fire("PLAYER_LOGIN")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(10)
    assert g.eval("QuestSharingDirection") is None
    assert g.eval("QuestSharingRouteOverlay") is None
    assert g.eval("DB_ENUMS.quest") == 0


def test_selected_step_shows_direct_yards_and_facing_relative_arrow(style):
    g = game(style)
    open_guide(g)
    hud = g.eval("QuestSharingDirection")
    assert "Accept quests at Sentinel Hill" in hud.title.text
    assert "180 yd" in hud.distance.text and "NE" in hud.distance.text
    assert abs(hud.arrow.rotation - math.atan2(-150, 100)) < 1e-8
    g.run("FACING=math.pi/2")
    tick(g)
    assert abs(hud.arrow.rotation - (math.atan2(-150, 100) - math.pi / 2)) < 1e-8
    assert g.eval("OPENED_MAP") is None


def test_map_groups_colocated_stops_and_cycles_selected_stop_to_native_waypoint(style):
    g = game(style)
    open_guide(g)
    pins = markers(g)
    assert len(pins) == 2
    shared = next(p for p in pins if len(p.steps) == 2)
    assert "1/3" in shared.text.text and shared.selectedStop == 1
    assert shared.scripts.OnClick is None
    click(g, shared)
    assert shared.selectedStop == 3
    assert "Hand in quests" in g.eval("QuestSharingDirection.title.text")
    assert g.eval("WAYPOINT.map") == 1436
    assert g.eval("WAYPOINT.x") == 0.55


def test_native_lines_connect_order_and_geometry_reuses_regions_while_stationary(style):
    g = game(style)
    open_guide(g)
    overlay = g.eval("QuestSharingRouteOverlay")
    lines = [c for c in overlay.children.values() if c.isLine and c.shown]
    assert len(lines) == 4
    lines = [line for line in lines if line.thickness == 2]
    assert len(lines) == 2
    assert lines[0].startPoint[3] == 550 and lines[0].startPoint[4] == -315
    assert lines[0].endPoint[3] == 440 and lines[0].endPoint[4] == -350
    before = len(overlay.children)
    reads = counts(g, "DB_READS")
    for _ in range(60):
        tick(g)
    assert len(overlay.children) == before
    assert counts(g, "DB_READS") == reads


def test_next_step_updates_arrow_and_highlight_without_completing_quest(style):
    g = game(style)
    open_guide(g)
    assert g.eval("NS.questPlanner.navigate")(1)
    assert "Complete objectives" in g.eval("QuestSharingDirection.title.text")
    assert "W" in g.eval("QuestSharingDirection.distance.text")
    assert any(p.selectedStop == 2 for p in markers(g))
    assert g.eval("WAYPOINT.x") == 0.44
    assert len(g.eval("QUESTS")) == 0


def test_arrival_never_advances_or_accepts_a_quest(style):
    g = game(style)
    open_guide(g)
    g.run("POS={x=0.55,y=0.45}")
    tick(g)
    hud = g.eval("QuestSharingDirection")
    assert "At destination" in hud.distance.text and not hud.arrow.shown
    assert any(p.selectedStop == 1 for p in markers(g))
    assert len(g.eval("QUESTS")) == 0


def test_arrow_map_cleanup_on_close_and_master_disable(style):
    g = game(style)
    open_guide(g)
    g.slash("plan hide")
    assert not g.eval("QuestSharingDirection.shown")
    assert g.eval("QuestSharingDirection.scripts.OnUpdate") is None
    assert not g.eval("QuestSharingRouteOverlay.shown")
    reads = counts(g, "DB_READS")
    g.fire("ZONE_CHANGED")
    g.advance(5)
    assert counts(g, "DB_READS") == reads
    open_guide(g)
    g.eval("NS.setSetting")("enabled", False)
    assert not g.eval("QuestSharingDirection.shown")
    assert not g.eval("QuestSharingRouteOverlay.shown")


def test_missing_world_projection_uses_native_map_size_without_distorting_axes(style):
    g = game(style, "C_Map.GetWorldPosFromMapPos=nil")
    open_guide(g)
    assert "180 yd" in g.eval("QuestSharingDirection.distance.text")
    assert abs(g.eval("QuestSharingDirection.arrow.rotation") - math.atan2(-150, 100)) < 1e-8


def test_missing_metrics_or_facing_does_not_invent_yards_or_a_heading(style):
    g = game(style, "C_Map.GetWorldPosFromMapPos=nil;C_Map.GetMapWorldSize=nil")
    open_guide(g)
    assert not g.eval("QuestSharingDirection.arrow.shown")
    assert "Distance unavailable" in g.eval("QuestSharingDirection.distance.text")
    g = game(style, "GetPlayerFacing=nil")
    open_guide(g)
    assert not g.eval("QuestSharingDirection.arrow.shown")
    assert "NE" in g.eval("QuestSharingDirection.distance.text")


def test_transient_player_position_loss_recovers_and_zone_departure_clears_guidance(style):
    g = game(style)
    open_guide(g)
    g.run("C_Map.GetBestMapForUnit=function() return nil end")
    tick(g)
    assert "Position unavailable" in g.eval("QuestSharingDirection.distance.text")
    assert g.eval("QuestSharingDirection.scripts.OnUpdate") is not None
    g.run("C_Map.GetBestMapForUnit=function() return MAP_ID end")
    tick(g)
    assert g.eval("QuestSharingDirection.arrow.shown")
    g.run("MAP_ID=1429")
    tick(g)
    assert not g.eval("QuestSharingDirection.shown")


def test_foreign_displayed_map_never_gets_projected_sibling_points(style):
    g = game(style)
    open_guide(g)
    g.run("WORLDMAP_ID=1429;C_Map.GetMapRectOnMap=function() return 0,1,0,1 end")
    g.fire("WORLD_MAP_UPDATE")
    assert not g.eval("QuestSharingRouteOverlay.shown")
    assert not markers(g)


def test_combat_hides_map_interactions_without_stopping_read_only_arrow(style):
    g = game(style)
    open_guide(g)
    g.run("IN_COMBAT=true")
    g.fire("PLAYER_REGEN_DISABLED")
    assert not g.eval("QuestSharingRouteOverlay.shown")
    g.run("FACING=1")
    tick(g)
    assert g.eval("QuestSharingDirection.arrow.shown")
    assert g.eval("WAYPOINT") is None
    g.run("IN_COMBAT=false")
    g.fire("PLAYER_REGEN_ENABLED")
    assert g.eval("QuestSharingRouteOverlay.shown")


def test_clients_without_lines_use_bounded_reusable_breadcrumbs(style):
    g = game(style, r'''
local create=CreateFrame
CreateFrame=function(...) local f=create(...);f.CreateLine=nil;return f end
''')
    open_guide(g)
    overlay = g.eval("QuestSharingRouteOverlay")
    textures = [c for c in overlay.children.values() if c.isTexture]
    assert 0 < len(textures) <= 800
    g.run("WorldMapFrame.ScrollContainer.Child.scale=2")
    tick(g)
    assert len([c for c in overlay.children.values() if c.isTexture]) <= 800



def test_cardinal_bearings_use_north_west_world_axes(style):
    g = game(style)
    open_guide(g)
    for x, y, compass, angle in ((0.55, 0.55, "N", 0), (0.65, 0.45, "W", math.pi/2),
                                  (0.55, 0.35, "S", math.pi), (0.45, 0.45, "E", -math.pi/2)):
        g.run(f"POS={{x={x},y={y}}}")
        tick(g)
        hud = g.eval("QuestSharingDirection")
        assert hud.distance.text.startswith(compass + " ·")
        assert abs(hud.arrow.rotation - angle) < 1e-8


def test_map_drag_off_and_right_click_do_not_change_waypoint(style):
    g = game(style)
    open_guide(g)
    pin = next(p for p in markers(g) if p.selectedStop is None)
    pin.scripts.OnEnter(pin)
    g.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    pin.scripts.OnLeave(pin)
    g.fire("GLOBAL_MOUSE_UP", "LeftButton")
    assert g.eval("WAYPOINT") is None
    pin.scripts.OnEnter(pin)
    g.fire("GLOBAL_MOUSE_DOWN", "RightButton")
    g.fire("GLOBAL_MOUSE_UP", "RightButton")
    assert g.eval("WAYPOINT") is None



def test_late_map_metrics_recover_without_reopening_or_selecting_another_step(style):
    g = game(style, r'''
METRICS_READY=false
local project=C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos=function(...) if METRICS_READY then return project(...) end end
C_Map.GetMapWorldSize=nil
''')
    open_guide(g)
    assert "Distance unavailable" in g.eval("QuestSharingDirection.distance.text")
    before = counts(g, "DB_READS")
    g.run("METRICS_READY=true")
    for _ in range(12):
        tick(g, 0.1)
    assert "180 yd" in g.eval("QuestSharingDirection.distance.text")
    assert g.eval("QuestSharingDirection.arrow.shown")
    assert counts(g, "DB_READS") == before


def test_group_label_keeps_selected_step_visible_and_marks_its_exact_position(style):
    g = game(style)
    open_guide(g)
    g.run(r'''
local stops={}
for i=1,8 do stops[i]={point={map=1436,x=0.55+i/1000,y=0.45},kind="objective",destination="Camp "..i} end
NS.questGuidance.set(stops,8,QuestSharingPlannerPanel,function() end,"Current camp")
''')
    pin = next(p for p in markers(g) if p.selectedStop == 8)
    assert "8" in pin.text.text
    assert abs(pin.point[4] / 1000 - 0.558) < 1e-9
    assert abs(pin.point[5] / -700 - 0.45) < 1e-9


def test_zoom_preserves_stop_screen_positions_and_constant_pin_size_without_extra_regions(style):
    g = game(style)
    open_guide(g)
    overlay = g.eval("QuestSharingRouteOverlay")
    before = len(overlay.children)
    for scale in (0.5, 2, 3, 1):
        g.run(f"WorldMapFrame.ScrollContainer.Child.scale={scale}")
        tick(g)
        pin = next(p for p in markers(g) if p.selectedStop == 1)
        assert abs(pin.scale * scale - 1) < 1e-9
        assert abs(pin.point[4] * pin.scale - 550) < 1e-9
        assert abs(pin.point[5] * pin.scale + 315) < 1e-9
        assert len(overlay.children) == before


def test_descendant_map_projects_only_points_inside_its_verified_rectangle(style):
    g = game(style)
    open_guide(g)
    g.run(r'''
WORLDMAP_ID=2001
C_Map.GetMapRectOnMap=function(child,parent)
 if child==2001 and parent==1436 then return 0.5,0.6,0.4,0.5 end
 return 0,0,0,0
end
''')
    g.fire("WORLD_MAP_UPDATE")
    pins = markers(g)
    assert len(pins) == 1 and len(pins[0].steps) == 2
    assert abs(pins[0].point[4] - 500) < 1e-8
    assert abs(pins[0].point[5] + 350) < 1e-8



# Frame levels/strata like the client: children start one level above their parent; a native map pin sits on the
# canvas far above the canvas itself (Blizzard and addon pin templates use levels in the hundreds).
LEVELS = r'''
LEVEL_SETS=0
function TRACK(f)
 f.level,f.strata=f.level or 0,f.strata or "MEDIUM"
 function f:SetFrameLevel(n) self.level=n;LEVEL_SETS=LEVEL_SETS+1 end
 function f:GetFrameLevel() return self.level end
 function f:SetFrameStrata(s) self.strata=s end
 function f:GetFrameStrata() return self.strata end
 local font=f.CreateFontString
 function f:CreateFontString(...)
  local t=font(self,...)
  function t:SetShadowOffset(x,y) self.shadow={x,y} end
  function t:SetShadowColor(r,g,b,a) self.shadowColor={r,g,b,a} end
  return t
 end
 return f
end
local create=CreateFrame
CreateFrame=function(kind,name,parent)
 local f=TRACK(create(kind,name,parent))
 if parent and parent.level then f.level,f.strata=parent.level+1,parent.strata end
 return f
end
CANVAS=TRACK(WorldMapFrame.ScrollContainer.Child)
CANVAS.level,CANVAS.strata=3,"HIGH"
NATIVE_PIN=CreateFrame("Frame",nil,CANVAS);NATIVE_PIN.level=CANVAS.level+500
function RAISE_CANVAS(n) CANVAS.level=CANVAS.level+n;NATIVE_PIN.level=NATIVE_PIN.level+n end
function SHOW_MAP() WorldMapFrame:Show();for _,fn in ipairs((WorldMapFrame.posthooks or {}).OnShow or {}) do fn(WorldMapFrame) end end
'''


def test_neighbouring_step_markers_never_overlap_and_merge_instead(style):
    g = game(style)
    open_guide(g)
    g.run(r'''
local stops={}
for i=1,9 do stops[i]={point={map=1436,x=0.05+i*0.09,y=0.15},kind="objective",destination="Far "..i} end
stops[10]={point={map=1436,x=0.500,y=0.60},kind="objective",destination="Camp A"}
stops[11]={point={map=1436,x=0.501,y=0.60},kind="objective",destination="Camp A"}
stops[12]={point={map=1436,x=0.527,y=0.60},kind="pickup",destination="Giver"}
NS.questGuidance.set(stops,1,QuestSharingPlannerPanel,function() end,"Far 1")
''')
    pins = markers(g)
    def rect(p):
        cx, cy, w, h = p.point[4] * p.scale, p.point[5] * p.scale, p.width, p.height
        return cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2
    for i, a in enumerate(pins):
        for b in pins[i + 1:]:
            ax0, ax1, ay0, ay1 = rect(a)
            bx0, bx1, by0, by1 = rect(b)
            overlap = min(ax1, bx1) - max(ax0, bx0) > 0.5 and min(ay1, by1) - max(ay0, by0) > 0.5
            assert not overlap, (a.text.text, b.text.text, rect(a), rect(b))
    merged = next(p for p in pins if 10 in list(p.steps.values()))
    assert sorted(merged.steps.values()) == [10, 11, 12], list(merged.steps.values())


def assert_on_top(g):
    canvas, native = g.eval("CANVAS"), g.eval("NATIVE_PIN")
    overlay, pins = g.eval("QuestSharingRouteOverlay"), markers(g)
    assert pins
    assert overlay.level == min(9900, canvas.level + 2000), (overlay.level, canvas.level)
    assert overlay.strata == canvas.strata
    legend = next(c for c in overlay.children.values() if c.kind == "Frame" and not c.steps and c.text)
    assert legend.level == overlay.level + 1 and legend.strata == canvas.strata
    for pin in pins:
        assert pin.level == overlay.level + (3 if pin.selectedStop else 2), (pin.level, overlay.level)
        assert pin.strata == canvas.strata
        assert pin.level > native.level > canvas.level, (pin.level, native.level)


def test_map_step_numbers_stay_above_native_pins_on_every_redraw_and_map_show(style):
    g = game(style, LEVELS)
    open_guide(g)
    assert_on_top(g)
    # Stationary redraws keep the cached geometry and do not touch levels that are already right.
    sets = g.eval("LEVEL_SETS")
    for _ in range(20):
        tick(g)
    assert g.eval("LEVEL_SETS") == sets
    # The map raises its canvas (and its own pins with it); the next redraw restates our stacking.
    g.run("RAISE_CANVAS(300)")
    tick(g)
    assert_on_top(g)
    # Closing and reopening the map re-applies the stacking on show, before the next redraw tick.
    g.run("WorldMapFrame:Hide()")
    tick(g)
    assert not g.eval("QuestSharingRouteOverlay.shown")
    g.run("RAISE_CANVAS(300);SHOW_MAP()")
    assert g.eval("QuestSharingRouteOverlay.level") == g.eval("CANVAS.level") + 2000
    tick(g)
    assert_on_top(g)
    # Near the client's level ceiling the overlay is clamped and markers stay above the native pin.
    g.run("RAISE_CANVAS(8400)")
    tick(g)
    assert g.eval("QuestSharingRouteOverlay.level") == 9900
    assert_on_top(g)


def test_map_step_numbers_use_large_outlined_text_bright_border_and_dark_face(style):
    g = game(style, LEVELS)
    open_guide(g)
    for scale in (1, 0.5, 3):
        g.run(f"WorldMapFrame.ScrollContainer.Child.scale={scale}")
        tick(g)
        pins = markers(g)
        assert len(pins) == 2
        for pin in pins:
            _, size, flags = pin.text.font[1], pin.text.font[2], pin.text.font[3]
            assert size >= 13 and flags is not None and "OUTLINE" in flags, (size, flags)
            assert pin.text.shadow[1] == 1 and pin.text.shadow[2] == -1
            assert pin.text.shadowColor[4] == 1
            # On-screen size: the canvas zoom times the pin's inverse scale stays 1.
            assert pin.width * pin.scale * scale >= 30 and pin.height * pin.scale * scale >= 24
            border, face = list(pin.border.vertex.values()), list(pin.face.vertex.values())
            assert face[3] == 1 and max(face[:3]) <= 0.2, face
            if pin.selectedStop:
                assert border == [1, 0.82, 0, 1], border
                assert "|cffffd100" in pin.text.text
            else:
                assert min(border[:3]) >= 0.75 and max(border[:3]) - min(border[:3]) < 0.05 and border[3] == 1, border
                assert "|cffffffff" in pin.text.text
    # Selecting another stop moves the gold border and keeps the label format.
    shared = next(p for p in markers(g) if len(p.steps) == 2)
    click(g, shared)
    assert shared.selectedStop == 3 and "1/3" in shared.text.text
    assert list(shared.border.vertex.values()) == [1, 0.82, 0, 1]
    assert_on_top(g)


def test_missing_metric_retries_are_throttled_and_stop_when_guide_closes(style):
    g = game(style, r'''
METRIC_READS=0
C_Map.GetWorldPosFromMapPos=function() METRIC_READS=METRIC_READS+1;return nil end
C_Map.GetMapWorldSize=nil
''')
    open_guide(g)
    initial = g.eval("METRIC_READS")
    for _ in range(24):
        tick(g, 0.1)
    assert 2 <= g.eval("METRIC_READS") - initial <= 3
    before = g.eval("METRIC_READS")
    g.slash("plan hide")
    for _ in range(20):
        tick(g)
    assert g.eval("METRIC_READS") == before


if __name__ == "__main__":
    failed = total = 0
    for name, test in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in ("modern", "classic"):
            total += 1
            try:
                test(style);print("ok", name, style)
            except Exception as error:
                failed += 1;print("FAIL", name, style, type(error).__name__, str(error)[:300])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
