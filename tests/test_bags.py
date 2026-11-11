"""Quest items marked in the bags (gold: a quest of this zone, blue: a quest elsewhere) and hiding the game's quest
tracker.        python tests/test_bags.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# the backpack on screen: ContainerFrame1 (bag 0) with 4 slots
BAG_FRAME = """
ContainerFrame1 = CreateFrame("Frame"); ContainerFrame1.shown = true; ContainerFrame1.size = 4
function ContainerFrame1:GetID() return 0 end
function ContainerFrame1:GetName() return "ContainerFrame1" end
for i = 1, 4 do
    local b = CreateFrame("Button"); b.shown = true; b.slot = i; b.width = 37
    function b:GetID() return self.slot end
    _G["ContainerFrame1Item" .. i] = b
end
ITEMS[6100] = { name = "Wolf Pelt" }                 -- for Wolves Among Us (Elwynn Forest, where you are)
ITEMS[6200] = { name = "Red Bandana" }               -- for The Defias Brotherhood (Westfall)
ITEMS[6300] = { name = "Linen Cloth" }               -- for nothing
QUESTS[#QUESTS].objectives[2] = { text = "Red Bandana: 2/10", finished = false, numFulfilled = 2, numRequired = 10 }
BAGS[0] = { { id = 6100 }, { id = 6200 }, { id = 6300 }, { id = 6400, questID = 200 } }
ITEMS[6400] = { name = "A Folded Note" }             -- the bag says it belongs to quest 200
"""


def game(style, pre=""):
    g = Game(style, BAG_FRAME + pre)
    g.start()
    g.slash("auto off")
    g.advance(2.5)                                                 # the marks are looked at from 2 s after loading
    return g


def marks(g):
    out = {}
    for b, m in g.eval("NS._bagMarks()").items():
        if m.shown:
            out[b.slot] = "here" if m.here else "elsewhere"
    return out


def test_quest_items_are_marked_gold_here_and_blue_elsewhere(style):
    g = game(style)
    assert marks(g) == {1: "here", 2: "elsewhere", 4: "elsewhere"}, marks(g)
    m = next(m for b, m in g.eval("NS._bagMarks()").items() if b.slot == 1)
    assert m.mouse is not True, "clicks go through to the item"
    assert tuple(round(v, 2) for v in list(m.tex.vertex.values())[:3]) == (1, 0.82, 0), "gold"


def test_moving_to_the_other_zone_swaps_them(style):
    g = game(style)
    g.run('ZONE = "Westfall"')
    g.fire("ZONE_CHANGED_NEW_AREA")
    g.advance(0.5)
    assert marks(g) == {1: "elsewhere", 2: "here", 4: "here"}, marks(g)


def test_the_tooltip_says_which_quest_and_where(style):
    g = game(style, "GameTooltip = CreateFrame('Frame'); GameTooltip.lines = {}; function GameTooltip:SetBagItem() end; "
                    "function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end")
    g.fire("PLAYER_LOGIN")
    g.eval("GameTooltip.SetBagItem")(g.eval("GameTooltip"), 0, 2)
    lines = list(g.eval("GameTooltip.lines").values())
    assert lines == ['Quest Sharing: for "The Defias Brotherhood" (in Westfall - the bank can keep it)'], lines


def test_with_questie_the_exact_items_of_a_quest_count_too(style):
    pre = """BAGS[0][3] = { id = 7000 }; ITEMS[7000] = { name = "Strange Device" }
    QuestDB = { Get = function(id, k) if id == 100 and k == "objectives" then return { nil, nil, { { 7000 } } } end end }
    NpcDB, ItemDB, ObjectDB = { Get = function() end }, { Get = function() end }, { Get = function() end }"""
    g = game(style, pre)
    assert marks(g).get(3) == "here", marks(g)


def test_closed_bags_have_no_marks_and_the_switch_turns_them_off(style):
    g = game(style)
    g.run("ContainerFrame1.shown = false; for i = 1, 4 do _G['ContainerFrame1Item' .. i].shown = false end")
    g.advance(0.5)
    assert marks(g) == {}
    g.run("ContainerFrame1.shown = true; for i = 1, 4 do _G['ContainerFrame1Item' .. i].shown = true end")
    g.advance(0.5)
    assert len(marks(g)) == 3
    g.slash("bagmarks off")
    assert marks(g) == {}


# ---- hiding the game's quest tracker ---------------------------------------------------------------------------------
TRACKER = 'WatchFrame = CreateFrame("Frame"); WatchFrame.shown = true\n'


def test_the_tracker_can_be_hidden_and_shown_again(style):
    g = game(style, TRACKER)
    assert g.eval("WatchFrame.shown") is True, "off by default"
    g.slash("hidetracker on")
    assert g.eval("WatchFrame.shown") is False
    g.run("WatchFrame.shown = true")                               # the game shows it again (a new quest)
    g.eval("function() for _, fn in ipairs(WatchFrame.posthooks.OnShow) do fn(WatchFrame) end end")()
    assert g.eval("WatchFrame.shown") is False, "hidden again"
    g.slash("hidetracker off")
    assert g.eval("WatchFrame.shown") is True


def test_in_a_fight_it_waits_and_hides_right_after(style):
    g = game(style, TRACKER)
    g.run("IN_COMBAT = true")
    g.slash("hidetracker on")
    assert g.eval("WatchFrame.shown") is True, "the game does not allow it during a fight"
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert g.eval("WatchFrame.shown") is False


def test_the_settings_have_both_switches(style):
    g = game(style)
    keys = [g.eval(f"NS.settingRows[{i}].key") for i in range(1, int(g.eval("#NS.settingRows")) + 1)]
    assert "bagMarks" in keys and "hideTracker" in keys


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
