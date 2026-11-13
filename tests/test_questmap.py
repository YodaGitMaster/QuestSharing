"""How-to quest text, plus guards that retired quest symbols cannot return to either map."""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# Quest 100 "Wolves Among Us": kill Wolves (npc 299), Wolf Pelt (item 750) dropped by Wolves; turned in at Marshal
# McBride (npc 197). Zone 12 (Elwynn Forest) is the game's map 1429. You stand at 42.3, 61.8.
DATA = """
QUESTIE_QUESTS = {
    [100] = { name = "Wolves Among Us", objectives = { { { 299 } }, nil, { { 750 } } }, finishedBy = { { 197 } } },
}
QUESTIE_NPCS = {
    [299] = { name = "Wolf", spawns = { [12] = { { 30.0, 70.0 }, { 42.5, 61.5 }, { 55.0, 50.0 } } } },
    [197] = { name = "Marshal McBride", spawns = { [12] = { { 48.92, 41.61 } } } },
    [400] = { name = "Kobold Miner", spawns = { [12] = { { 60.0, 60.0 } } } },
}
QUESTIE_ITEMS = { [750] = { name = "Wolf Pelt", npcDrops = { 299 } }, [751] = { name = "Kobold Candle", objectDrops = { 9 } } }
QUESTIE_OBJECTS = { [9] = { name = "Kobold Crate", spawns = { [12] = { { 41.0, 60.0 } } } } }
local function getter(t) return function(id, key) local r = t[id]; return r and r[key] end end
QuestDB, NpcDB, ItemDB, ObjectDB = { Get = getter(QUESTIE_QUESTS) }, { Get = getter(QUESTIE_NPCS) }, { Get = getter(QUESTIE_ITEMS) }, { Get = getter(QUESTIE_OBJECTS) }
LibQuestieDB = { Support = { Get = function(name)
    if name == "ZoneDB" then return { private = { areaIdToUiMapId = "return { [12] = 1429 }", areaIdToUiMapIdOverride = "return {}" } } end
end } }
C_Map.GetAreaInfo = function(id) return ({ [12] = "Elwynn Forest" })[id] end
-- the world: map 1429 is 3000 x 2000 yards, its top left corner at north 1000, west 500
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map.GetWorldPosFromMapPos = function(map, v)
    if map ~= 1429 then return nil end
    return 0, { GetXY = function() return 1000 - v.y * 2000, 500 - v.x * 3000 end }
end
Minimap:SetWidth(140)
WORLDMAP_ID = 1429
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = { Child = CreateFrame("Frame") }
WorldMapFrame.ScrollContainer.Child.width, WorldMapFrame.ScrollContainer.Child.height = 1000, 700
function WorldMapFrame:GetMapID() return WORLDMAP_ID end
"""


def game(style, pre="", party=False):
    g = Game(style, DATA + pre)
    g.start()
    g.slash("auto off")
    if party:
        g.join_party(["Anna"])
    g.advance(3)
    g.run("SENT = {}; PRINTED = {}")
    return g


def unlink(s):
    return re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s or ""))


def how(g, qid=100):
    return unlink(g.eval("NS.howMessage")(g.eval(f"NS.compat.findEntry({qid})")))


# ---- How to do it ----------------------------------------------------------------------------------------------------
def test_how_to_do_it_says_what_is_open_where_and_where_to_turn_in(style):
    g = game(style)
    assert how(g) == ("[Wolves Among Us]: kill Wolf (Elwynn Forest 42.5, 61.5); Wolf Pelt from Wolf (Elwynn Forest 42.5, "
                      "61.5); then turn in at Marshal McBride (Elwynn Forest 48.9, 41.6)"), how(g)


def test_finished_objectives_are_left_out_and_a_done_quest_only_says_where_to_turn_in(style):
    g = game(style)
    g.run("local q = BYID(100); q.objectives[1].finished = true; q.objectives[1].text = 'Wolf slain: 8/8'")
    assert how(g).startswith("[Wolves Among Us]: Wolf Pelt from Wolf (") and "kill Wolf" not in how(g), how(g)
    g.run("local q = BYID(100); q.complete = true; for _, o in ipairs(q.objectives) do o.finished = true end")
    assert how(g) == "[Wolves Among Us]: all done - turn in at Marshal McBride (Elwynn Forest 48.9, 41.6)", how(g)


def test_objects_to_use_items_from_chests_and_places_to_go(style):
    g = game(style)
    g.run("""QUESTIE_QUESTS[100].objectives = { nil, { { 9 } }, { { 751 } } }
    QUESTIE_QUESTS[100].triggerEnd = { "the Fargodeep Mine", { [12] = { { 39.0, 82.0 } } } }""")
    line = how(g)
    assert "use Kobold Crate (Elwynn Forest 41.0, 60.0)" in line and "Kobold Candle from Kobold Crate" in line, line
    assert "go to the Fargodeep Mine (Elwynn Forest 39.0, 82.0)" in line, line


def test_it_always_fits_one_chat_line(style):
    g = game(style)
    g.run("""local objs = {}
    for i = 1, 12 do QUESTIE_NPCS[500 + i] = { name = "A creature with a rather long name number " .. i, spawns = { [12] = { { 10, 10 } } } }
        objs[#objs + 1] = { 500 + i } end
    QUESTIE_QUESTS[100].objectives = { objs }""")
    raw = g.eval("NS.howMessage")(g.eval("NS.compat.findEntry(100)"))
    assert len(raw) <= 255 and unlink(raw).endswith("(and more)"), unlink(raw)


def test_the_menu_line_goes_to_the_party_or_only_to_you(style):
    g = game(style, party=True)
    g.eval("NS.howTo")(g.eval("NS.compat.findEntry(100)"))
    msg, channel = g.sent()[-1]
    assert channel == "PARTY" and "kill Wolf" in unlink(msg), g.sent()
    g.leave_party()
    g.advance(2)
    g.run("SENT = {}; PRINTED = {}")
    g.eval("NS.howTo")(g.eval("NS.compat.findEntry(100)"))
    assert g.sent() == [] and "kill Wolf" in unlink("\n".join(g.printed()))


# ---- retired quest map overlays ---------------------------------------------------------------------------
def test_quest_overlay_renderer_and_setting_are_absent(style):
    g = game(style)
    g.run("WorldMapFrame.shown = true")
    g.advance(20)
    assert g.eval("NS.questMap") is None
    assert g.eval("NS.defaults.questMap") is None
    assert g.eval("(function() for _,r in ipairs(NS.settingRows) do if r.key=='questMap' then return true end end return false end)()") is False
    assert g.eval("(function() for _,f in ipairs(FRAMES) do if f.qpoint then return true end end return false end)()") is False


def test_old_enabled_setting_is_removed_and_legacy_command_cannot_restore_symbols(style):
    g = game(style)
    g.run("QuestSharingDB.questMap = true")
    g.fire("ADDON_LOADED", "QuestSharing")
    assert g.eval("NS.db.questMap") is None
    g.slash("questmap on")
    g.fire("QUEST_LOG_UPDATE")
    g.advance(20)
    assert g.eval("NS.questMap") is None and g.eval("NS.db.questMap") is None
    assert "symbols on the world map and minimap have been removed" in "\n".join(g.printed())


def test_install_manifest_has_no_quest_overlay_module():
    addon = pathlib.Path(__file__).resolve().parents[1] / "QuestSharing"
    assert not (addon / "QuestMap.lua").exists()
    assert "QuestMap.lua" not in (addon / "QuestSharing.toc").read_text()


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
                print("FAIL", label, type(e).__name__, str(e)[:400])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
