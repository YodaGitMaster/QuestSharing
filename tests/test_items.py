"""Quest items you can use: an icon next to the quest in the game's tracker for usable quest items in your bags (the
game only shows its "special" ones), and a key / button for the item of your nearest quest.   python tests/test_items.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")
TRACKER = """
function WatchFrame_Update() end
WATCHFRAME_LINKBUTTONS = {}
function TRACK_LINES(indexes)
    WATCHFRAME_LINKBUTTONS = {}
    for i, idx in ipairs(indexes) do
        local b = CreateFrame("Button"); b.type = "QUEST"; b.index = idx
        WATCHFRAME_LINKBUTTONS[i] = b
    end
    WatchFrame_Update()
end
"""
TENTS = """
table.insert(QUESTS, 5, { id = 700, title = "Burning the Tents", level = 6, objectives = {
    { text = "Kobold Tent burned with the Unlit Torch: 0/3", finished = false, numFulfilled = 0, numRequired = 3, type = "event" } } })
ITEMS[6000] = { name = "Unlit Torch", spell = "Light Torch", icon = "Interface\\\\Icons\\\\INV_Torch_Unlit", count = 1 }
ITEMS[6001] = { name = "Signal Flare", spell = "Fire Flare", icon = "Interface\\\\Icons\\\\INV_Flare", count = 3 }
ITEMS[6002] = { name = "Wolf Pelt", icon = "Interface\\\\Icons\\\\INV_Pelt" }              -- not usable: no "Use:"
"""


def game(style, bags="", pre=""):
    g = Game(style, TRACKER + TENTS + pre)
    g.start()
    g.slash("auto off")
    if bags:
        g.run(bags)
    g.fire("BAG_UPDATE_DELAYED")
    g.advance(1)
    return g


def index_of(g, qid):
    return int(g.eval(f"NS.compat.findEntry({qid}).index"))


def shown_icons(g):
    icons = g.eval("NS._trackerItemIcons()")
    out = []
    for i in range(1, 9):
        b = icons[i]
        if b is not None and b.shown:
            out.append((b.questID, b.attrs.item))
    return out


def track(g, *qids):
    g.run("TRACK_LINES({%s})" % ", ".join(str(index_of(g, q)) for q in qids))
    g.advance(1)


def test_a_usable_item_named_by_an_objective_gets_an_icon_next_to_its_quest(style):
    g = game(style, "BAGS[0] = { { id = 6000 } }")
    track(g, 100, 700)
    assert shown_icons(g) == [(700, "item:6000")], shown_icons(g)
    icons = g.eval("NS._trackerItemIcons()")
    same = g.eval("(function() return NS._trackerItemIcons()[1].point[2] == WATCHFRAME_LINKBUTTONS[2] end)()")
    assert same is True and icons[1].point[1] == "TOPRIGHT", "where the game puts its own item buttons"


def test_the_bag_says_which_quest_an_item_belongs_to(style):
    g = game(style, "BAGS[0] = { { id = 6001, questID = 100, isQuestItem = true } }")
    track(g, 100)
    assert shown_icons(g) == [(100, "item:6001")]


def test_questie_knows_the_item_a_quest_hands_out(style):
    pre = """QuestDB = { Get = function(id, key) if id == 101 and key == "sourceItemId" then return 6001 end end }"""
    g = game(style, "BAGS[0] = { { id = 6001 } }", pre=pre + "\nlocal q = BYID(101); q.complete = false; q.objectives[1].finished = false\n")
    track(g, 101)
    assert shown_icons(g) == [(101, "item:6001")]


def test_quests_the_game_already_shows_an_item_for_are_left_to_the_game(style):
    g = game(style, "BAGS[0] = { { id = 6001, questID = 100 } }")
    g.run(f"SPECIAL[{index_of(g, 100)}] = 6001")
    g.run("NS.refreshQuestItems()")
    g.advance(1)
    track(g, 100)
    assert shown_icons(g) == [], "no second button next to the game's own"


def test_items_without_a_use_get_nothing(style):
    g = game(style, "BAGS[0] = { { id = 6002, questID = 100, isQuestItem = true } }")
    track(g, 100)
    assert shown_icons(g) == []


def test_in_combat_the_icons_wait_for_the_end_of_the_fight(style):
    g = game(style, "BAGS[0] = { { id = 6000 } }")
    g.run("IN_COMBAT = true")
    track(g, 700)
    assert shown_icons(g) == [] and g.eval("NS.questItemState.pending") is True
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(1)
    assert shown_icons(g) == [(700, "item:6000")]


# ---- the key and the little button ------------------------------------------------------------------------------------------
def test_the_button_holds_the_item_of_the_nearest_quest(style):
    g = game(style, "BAGS[0] = { { id = 6000 }, { id = 6001, questID = 100 } }")
    if style == "modern":
        g.set_dist(q100=900, q700=100)
        g.run("NS.refreshQuestItems()")
        g.advance(1)
    b = g.eval("NS.questItemButton()")
    assert b.shown is True and b.attrs.type == "item"
    assert b.attrs.item == ("item:6000" if style == "modern" else b.attrs.item), "the torch: its quest is nearer"
    assert b.icon.texture is not None


def test_the_item_key(style):
    g = game(style, "BAGS[0] = { { id = 6000 } }")
    g.slash("itemkey Q")
    assert g.eval("BINDINGS.Q") == "CLICK QuestSharingItemButton:LeftButton" and g.eval("NS.itemKeyName()") == "Q"
    g.run('BINDINGS["CTRL-M"] = "TOGGLEMUSIC"')
    g.slash("itemkey CTRL-M")
    assert g.eval("BINDINGS['CTRL-M']") == "TOGGLEMUSIC"
    g.slash("itemkey none")
    assert g.eval("NS.itemKeyName()") is None


def test_count_and_range_show_on_the_button(style):
    g = game(style, "BAGS[0] = { { id = 6001, questID = 100 } }")
    b = g.eval("NS.questItemButton()")
    assert b.count.text == "3"
    g.run('TARGET = { name = "Kobold", player = false }; ITEM_IN_RANGE = false')
    g.advance(1.5)
    assert tuple(round(v, 1) for v in list(b.icon.vertex.values())[:3]) == (1, 0.3, 0.3), "red: out of range"


def test_no_item_no_button_and_the_switches(style):
    g = game(style)
    assert g.eval("NS.questItemButton()").shown is False
    g2 = game(style, "BAGS[0] = { { id = 6000 } }")
    g2.slash("itembutton off")
    assert g2.eval("NS.questItemButton()").shown is False
    assert g2.eval("NS.questItemButton()").attrs.item == "item:6000", "the key still works without the button"
    g2.slash("items off")
    track(g2, 700)
    assert shown_icons(g2) == []


def test_the_settings_tab(style):
    g = game(style)
    g.slash("settings")
    g.eval("NS.settingsTab")("actions")
    W = g.eval("NS._settingsWindow()")
    labels = [re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", W.rows[n].text.text) for n in range(1, 19) if W.rows[n].frame.shown]
    for want in ("Pinging quest targets", "Ping key", "Quest items", "Item icons next to the quests in the tracker",
                 "Quest item key", "A button with the nearest quest's item"):
        assert want in labels, (want, labels)
    row = next(W.rows[n] for n in range(1, 19) if W.rows[n].frame.shown and W.rows[n].text.text == "Quest item key")
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(row.button)
    g.eval("NS.captureKeyPressed")("Q")
    assert g.eval("BINDINGS.Q") == "CLICK QuestSharingItemButton:LeftButton"


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
