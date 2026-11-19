"""Shared camps: the Quest guide's planned camps as circles on the world map, and the camps table.
Real Coldridge Valley data (tests/data/coldridge_valley.lua). python tests/test_camp_map.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_coldridge_valley import SETUP  # noqa: E402

STYLES = ("modern", "classic")


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


WORLD_MAP = r'''
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = { Child = CreateFrame("Frame") }
WorldMapFrame.ScrollContainer.Child.width, WorldMapFrame.ScrollContainer.Child.height = 1000, 667
function WorldMapFrame:GetMapID() return WORLDMAP_ID end
'''


def game(style, on=True):
    g = Game(style, SETUP + WORLD_MAP, fresh=True)
    g.start()
    g.fire("PLAYER_LOGIN")
    g.run("NS.db.questPlannerScope = 'all'")
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(10)
    if on:
        g.eval("NS.setSetting")("campMap", True)
    g.run("WORLDMAP_ID = 1426; WorldMapFrame:Show()")
    g.advance(1)
    return g


def shown(g):
    s = g.eval("NS.campMap._shown()")
    return list(s.circles.values()), list(s.labels.values())


def tooltip(g):
    t = g.eval("TOOLTIP")
    return plain(t.text), [plain(str(v)) for v in (t.lines or {}).values()]


def test_off_by_default_and_needs_the_switch(style):
    g = game(style, on=False)
    assert g.eval("NS.db.campMap") is False
    circles, labels = shown(g)
    overlay = g.eval("QuestSharingCampOverlay")
    assert not circles and not labels and not (overlay and overlay.shown)


def test_one_circle_and_label_per_camp_blue_when_shared(style):
    g = game(style)
    v = g.eval("NS.questPlanner.campView()")
    camps = list(v.camps.values())
    circles, labels = shown(g)
    assert len(camps) >= 10 and len(circles) == len(camps) == len(labels)
    assert [b.text.text for b in labels] == ["A%d" % (i + 1) for i in range(len(camps))]
    for camp, c in zip(camps, circles):
        r, gr, b = c.vertex[1], c.vertex[2], c.vertex[3]
        assert (b > r) == bool(camp.shared), "blue = shared by 2+ quests, grey = one quest"
    assert sum(1 for c in camps if c.shared) >= len(camps) - 2, "Coldridge Valley camps are nearly all shared"


def test_circle_is_the_guides_100_yard_camp(style):
    g = game(style)
    circles, _ = shown(g)
    width = g.eval("WorldMapFrame.ScrollContainer.Child:GetWidth()")
    assert abs(circles[0].width - 2 * 100 / 4924.66 * width) < 0.5


def test_label_tooltip_lists_mobs_and_quests_and_click_sets_a_waypoint(style):
    g = game(style)
    _, labels = shown(g)
    a1 = labels[0]
    a1.scripts.OnEnter(a1)
    title, lines = tooltip(g)
    assert title.startswith("Camp A1 - ") and "quests share it" in title
    assert any("Ragged Young Wolf x" in l and "Dwarven Outfitters" in l for l in lines)
    assert any("A New Threat" in l for l in lines)
    a1.scripts.OnClick(a1, "LeftButton")
    wp = g.eval("WAYPOINT")
    camp = g.eval("NS.questPlanner.campView().camps[1]")
    assert wp and abs(wp.x - camp.point.x) < 1e-6 and abs(wp.y - camp.point.y) < 1e-6


def test_circles_never_take_map_clicks(style):
    g = game(style)
    assert g.eval("QuestSharingCampOverlay").mouse is not True


def test_hidden_on_another_map_in_combat_and_when_switched_off(style):
    g = game(style)
    g.run("WORLDMAP_ID = 1429"); g.advance(1)
    assert not g.eval("QuestSharingCampOverlay").shown, "only on the guide's own zone map"
    g.run("WORLDMAP_ID = 1426"); g.advance(1)
    assert g.eval("QuestSharingCampOverlay").shown and shown(g)[0]
    g.run("InCombatLockdown = function() return true end"); g.fire("PLAYER_REGEN_DISABLED"); g.advance(1)
    assert not g.eval("QuestSharingCampOverlay").shown
    g.run("InCombatLockdown = function() return false end"); g.fire("PLAYER_REGEN_ENABLED"); g.advance(1)
    assert g.eval("QuestSharingCampOverlay").shown
    g.eval("NS.setSetting")("campMap", False); g.advance(1)
    assert not g.eval("QuestSharingCampOverlay").shown


def test_camps_table_rows_columns_and_counts_match_the_map(style):
    g = game(style)
    g.slash("plan camps table")
    w = g.eval("NS.campMap._table()")
    assert w.shown and "Shared camps" in w.title.text
    v = g.eval("NS.questPlanner.campView()")
    camps = list(v.camps.values())
    rows = [r for r in w.rows.values() if r.shown]
    assert len(rows) == min(11, len(camps))
    assert plain(rows[0].name.text).startswith("A1 ")
    heads = [h.text.text for h in w.heads.values() if h.shown]
    assert "Ragged Young Wolf" in heads and "Small Crag Boar" in heads
    for row, camp in zip(rows, camps):
        cells = sum(int(plain(c.text.text)) for c in row.cells.values() if plain(c.text.text))
        assert cells == camp.total, "every spawn of the camp is in a cell (extra objectives fold into Other)"
    assert "serve 2 or more quests" in w.hint.text
    rows[0].scripts.OnClick(rows[0], "LeftButton")
    assert g.eval("WAYPOINT")



def shown_items(pool):
    return [it for it in pool["items"].values() if it.shown]


def test_window_has_the_network_map_and_matrix_like_the_html_view(style):
    g = game(style)
    g.slash("plan camps table")
    w = g.eval("NS.campMap._table()")
    v = g.eval("NS.questPlanner.campView()")
    cols, camps, points = list(v.columns.values()), list(v.camps.values()), list(v.points.values())
    assert w.net.shown and w.map.shown and w.title.text == "Shared camps"
    assert "Network" in w.net.title.text and "Map" in w.map.title.text and "matrix" in w.matTitle.text
    texts = [t.text for t in shown_items(w.net.texts)]
    for col in cols:
        assert col.name in texts and col.quest in texts, col.name
    assert any(t.startswith("A1 - ") and " of " in t or t.startswith("A1 - by ") for t in texts), "camps are named by the nearest quest giver"
    lines = shown_items(w.net.lines)
    assert len(lines) >= len(cols) + 8 * sum(len(list(c.counts.keys())) for c in camps[:11]), "every quest, mob and camp link is drawn"
    # map panel: one dot per spawn plus one circle per camp; quest givers as gold squares with names
    dots = shown_items(w.map.dots)
    assert len(dots) == len(points) + len(camps)
    names = [t.text for t in shown_items(w.map.texts)]
    assert any("Sten" in n and "Balir" in n for n in names) and any("Grelin" in n for n in names) and "A1" in names, "givers at one spot share a label"
    # filter buttons: All objectives + one per mob or object
    buttons = [b for b in w.filters.values() if b.shown]
    assert [b.text for b in buttons][0] == "All objectives" and len(buttons) == len(cols) + 1


def test_highlighting_one_objective_dims_the_rest_in_all_three_views(style):
    g = game(style)
    g.slash("plan camps table")
    w = g.eval("NS.campMap._table()")
    cols = list(g.eval("NS.questPlanner.campView()").columns.values())
    boar = next(i + 1 for i, c in enumerate(cols) if c.name == "Small Crag Boar")
    button = [b for b in w.filters.values() if b.shown][boar]
    button.scripts.OnClick(button, "LeftButton")
    assert button.edge.shown, "the chosen objective is marked"
    big = [d for d in shown_items(w.map.dots) if d.width == 7]
    spawns = [p for p in g.eval("NS.questPlanner.campView()").points.values() if p.col == boar]
    assert len(big) == len(spawns), "its spawns are drawn larger and blue on the map"
    first = [b for b in w.filters.values() if b.shown][0]
    first.scripts.OnClick(first, "LeftButton")
    assert first.edge.shown and not button.edge.shown
    assert not [d for d in shown_items(w.map.dots) if d.width == 7]

def test_camps_table_empty_state_when_the_guide_is_off(style):
    g = game(style, on=False)
    g.eval("NS.setSetting")("questPlanner", False); g.advance(1)
    g.eval("NS.campMap.openTable")()
    w = g.eval("NS.campMap._table()")
    assert w.shown and "No shared camps yet" in w.hint.text
    assert not [r for r in w.rows.values() if r.shown]


def test_slash_toggles_and_names_the_setting(style):
    g = game(style, on=False)
    g.run("PRINTED = {}")
    g.slash("plan camps")
    assert g.eval("NS.db.campMap") is True
    assert any("Shared camps on the world map: on (Settings > Quest guide)" in plain(p) for p in g.printed())
    g.slash("plan camps off")
    assert g.eval("NS.db.campMap") is False


def test_settings_row_in_the_quest_guide_tab_opens_the_table(style):
    g = game(style, on=False)
    rows = g.eval("NS.settingRows")
    row = next(r for r in rows.values() if r.key == "campMap")
    assert row.tab == "guide" and row.needs == "questPlanner" and row.button == "Camps table"
    row.action()
    assert g.eval("NS.campMap._table()").shown


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in list(globals().items()):
        if not name.startswith("test_"):
            continue
        for style in (STYLES if inspect.signature(fn).parameters else (None,)):
            total += 1
            try:
                fn(style) if style else fn()
                print("ok", name, style or "")
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print("FAIL", name, style or "", type(exc).__name__, str(exc)[:200])
    print(f"{total - failed}/{total} passed")
    raise SystemExit(bool(failed))
