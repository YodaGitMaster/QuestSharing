"""Bag helpers (bookmarks, sell gray items, arrange by topic) and the chat lock during a fight.
python tests/test_bagtools.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# A small bag world: ITEMS[id] = { name, quality, sell, class, sub }; BAGS[bag][slot] = { id, count } or false (empty).
# Picking up and dropping behave like the game: dropping on an item swaps it onto the cursor.
WORLD = """
ITEMS[1] = { name = "Gray Fang", quality = 0, sell = 5, class = 15, sub = 0 }
ITEMS[2] = { name = "Linen Cloth", quality = 1, sell = 13, class = 7, sub = 5 }
ITEMS[3] = { name = "Minor Healing Potion", quality = 1, sell = 20, class = 0, sub = 1 }
ITEMS[4] = { name = "Short Sword", quality = 2, sell = 90, class = 2, sub = 7 }
ITEMS[5] = { name = "Old Rag", quality = 0, sell = 1, class = 15, sub = 0 }
ITEMS[6] = { name = "Red Bandana", quality = 0, sell = 3, class = 12, sub = 0 }      -- gray, but quest Defias needs it
ITEMS[7] = { name = "Recipe: Soup", quality = 1, sell = 30, class = 9, sub = 3 }
ITEMS[8] = { name = "Linen Vest", quality = 1, sell = 15, class = 4, sub = 1 }
ITEMS[9] = { name = "Broken Tooth", quality = 0, sell = 0, class = 15, sub = 0 }      -- no sell price
ITEMS[10] = { name = "Wolf Pelt", quality = 1, sell = 2, class = 12, sub = 0 }
CURSOR_ITEM, SOLD = nil, {}
function GetItemInfo(id)
    local it = ITEMS[id]
    if not it then return nil end
    return it.name, "|Hitem:" .. id .. "|h[" .. it.name .. "]|h", it.quality, 1, 1, "", "", 1, "", "icon", it.sell, it.class, it.sub
end
C_Container.GetContainerItemInfo = function(bag, slot)
    local it = BAGS[bag] and BAGS[bag][slot]
    if not it then return nil end
    return { itemID = it.id, stackCount = it.count or 1, quality = ITEMS[it.id].quality, isLocked = it.locked or false,
             hasNoValue = ITEMS[it.id].sell == 0, hyperlink = "|Hitem:" .. it.id .. "|h[" .. ITEMS[it.id].name .. "]|h" }
end
C_Container.PickupContainerItem = function(bag, slot)
    local here = BAGS[bag][slot] or nil
    if CURSOR_ITEM then
        BAGS[bag][slot] = CURSOR_ITEM
        CURSOR_ITEM = here
    elseif here then
        CURSOR_ITEM = here
        BAGS[bag][slot] = false
    end
end
C_Container.UseContainerItem = function(bag, slot)
    SOLD[#SOLD + 1] = BAGS[bag][slot].id
    BAGS[bag][slot] = false
end
C_Container.GetContainerNumFreeSlots = function(bag) return 0, (SPECIAL_BAGS and SPECIAL_BAGS[bag]) or 0 end
function CursorHasItem() return CURSOR_ITEM ~= nil end
-- a backpack of 6 slots and a bag of 6 slots
BAGS[0] = { { id = 1 }, { id = 4 }, false, { id = 2, count = 5 }, { id = 3 }, { id = 5 } }
BAGS[1] = { { id = 8 }, false, { id = 7 }, { id = 6 }, { id = 9 }, { id = 10 } }
-- the backpack on screen, so the mouse can point at slots
ContainerFrame1 = CreateFrame("Frame"); ContainerFrame1.shown = true; ContainerFrame1.size = 6
function ContainerFrame1:GetID() return 0 end
function ContainerFrame1:GetName() return "ContainerFrame1" end
for i = 1, 6 do
    local b = CreateFrame("Button"); b.shown = true; b.slot = i; b.width = 37
    function b:GetID() return self.slot end
    function b:IsMouseOver() return self.hover end
    _G["ContainerFrame1Item" .. i] = b
end
QUESTS[#QUESTS].objectives[2] = { text = "Red Bandana: 2/10", finished = false, numFulfilled = 2, numRequired = 10 }   -- The Defias Brotherhood
"""


def game(style, pre=""):
    g = Game(style, WORLD + pre)
    g.start()
    g.slash("auto off")
    return g


def contents(g):
    """item ids per bag, 0 for an empty slot"""
    out = {}
    for bag in (0, 1):
        out[bag] = [int(s["id"]) if s else 0 for s in g.eval(f"BAGS[{bag}]").values()]
    return out


def flat(g):
    c = contents(g)
    return c[0] + c[1]


# ---- bookmarks ----------------------------------------------------------------------------------------------------

def point_at(g, slot):
    g.run(f"for i = 1, 6 do _G['ContainerFrame1Item' .. i].hover = (i == {slot}) end")


def test_bookmarks_are_on_and_the_other_helpers_are_off_in_a_new_install(style):
    g = game(style)
    assert g.eval("NS.db.bagBookmarks") is True
    assert g.eval("NS.db.autoSellGray") is False and g.eval("NS.db.autoSortBags") is False and g.eval("NS.db.chatLock") is False


def test_space_over_a_bag_item_bookmarks_it_and_again_removes_it(style):
    g = game(style)
    point_at(g, 1)
    assert g.eval("NS.bagTools.keyDown")("SPACE") is True, "the key was used: the character does not jump"
    assert g.eval("NS.bagTools.isBookmarked(1)") is True
    assert any("bookmarked" in p and "Gray Fang" in p for p in g.printed()), g.printed()
    g.advance(0.5)
    shown = [b.slot for b, m in g.eval("NS.bagTools.icons()").items() if m.shown]
    assert shown == [1], "a note icon marks the slot"
    assert g.eval("NS.bagTools.keyDown")("SPACE") is True
    assert g.eval("NS.bagTools.isBookmarked(1)") is False
    g.advance(0.5)
    assert not [1 for b, m in g.eval("NS.bagTools.icons()").items() if m.shown], "the icon is gone"


def test_space_elsewhere_or_other_keys_go_on_to_the_game(style):
    g = game(style)
    point_at(g, 99)                                                           # not over any slot
    assert g.eval("NS.bagTools.keyDown")("SPACE") is False
    point_at(g, 1)
    assert g.eval("NS.bagTools.keyDown")("A") is False
    g.slash("bookmarks off")
    assert g.eval("NS.bagTools.keyDown")("SPACE") is False, "switched off"
    point_at(g, 3)
    g.slash("bookmarks on")
    assert g.eval("NS.bagTools.keyDown")("SPACE") is False, "an empty slot"
    g.run("CURSOR_ITEM = BAGS[0][1]")
    point_at(g, 1)
    assert g.eval("NS.bagTools.keyDown")("SPACE") is False, "dragging an item"


def test_the_key_frame_swallows_space_only_when_it_bookmarked(style):
    g = game(style)
    g.run("""KEYFRAME = nil
        for _, f in ipairs(FRAMES) do if f.scripts.OnKeyDown then KEYFRAME = f end end
        PROP = {}
        function KEYFRAME:SetPropagateKeyboardInput(v) PROP[#PROP + 1] = v end""")
    point_at(g, 1)
    g.eval("function() KEYFRAME.scripts.OnKeyDown(KEYFRAME, 'SPACE') end")()
    g.eval("function() KEYFRAME.scripts.OnKeyDown(KEYFRAME, 'W') end")()
    assert list(g.eval("PROP").values()) == [False, True]
    assert g.eval("KEYFRAME.keyboard") is True


def test_the_keyboard_is_only_taken_while_bookmarks_are_on(style):
    g = game(style)
    g.slash("bookmarks off")
    assert g.eval("(function() for _, f in ipairs(FRAMES) do if f.scripts.OnKeyDown then return f.keyboard end end end)()") is False


def test_the_tooltip_of_a_bookmarked_item_says_so(style):
    g = game(style, "GameTooltip = CreateFrame('Frame'); GameTooltip.lines = {}; function GameTooltip:SetBagItem() end; "
                    "function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end")
    g.fire("PLAYER_LOGIN")
    point_at(g, 1)
    g.eval("NS.bagTools.keyDown")("SPACE")
    g.eval("GameTooltip.SetBagItem")(g.eval("GameTooltip"), 0, 1)
    lines = list(g.eval("GameTooltip.lines").values())
    assert lines and "bookmarked" in lines[0], lines


# ---- sell the gray items ------------------------------------------------------------------------------------------

def test_a_vendor_buys_the_gray_items_only_and_keeps_bookmarked_and_quest_ones(style):
    g = game(style)
    g.slash("sellgray on")
    point_at(g, 6)                                                            # Old Rag, bag 0 slot 6: bookmark it
    g.eval("NS.bagTools.keyDown")("SPACE")
    g.fire("MERCHANT_SHOW")
    g.advance(3)
    sold = sorted(int(v) for v in g.eval("SOLD").values())
    assert sold == [1], f"only Gray Fang goes: Old Rag is bookmarked, Red Bandana is for a quest, Broken Tooth has no price: {sold}"
    assert any("sold 1 gray item for 5c" in p for p in g.printed()), g.printed()


def test_selling_is_off_by_default_and_needs_an_open_vendor(style):
    g = game(style)
    g.fire("MERCHANT_SHOW")
    g.advance(3)
    assert not list(g.eval("SOLD").values()), "off by default"
    g.slash("sellgray on")
    g.fire("MERCHANT_CLOSED")
    assert g.eval("NS.bagTools.sellGray()") == 0, "no vendor window: nothing is sold"
    assert not list(g.eval("SOLD").values())


def test_with_selling_off_a_vendor_says_once_that_gray_items_could_go(style):
    g = game(style)
    g.fire("MERCHANT_SHOW")
    g.advance(1)
    hints = [p for p in g.printed() if "could be sold here" in p]
    assert len(hints) == 1 and "2 gray items" in hints[0] and "/qs sellgray on" in hints[0], g.printed()
    assert not list(g.eval("SOLD").values()), "the hint sells nothing"
    g.fire("MERCHANT_CLOSED")
    g.fire("MERCHANT_SHOW")
    g.advance(1)
    assert len([p for p in g.printed() if "could be sold here" in p]) == 1, "once per session"


def test_closing_the_vendor_stops_the_selling(style):
    g = game(style)
    g.run("for s = 1, 4 do BAGS[1][s] = { id = 1 } end; BAGS[1][4] = { id = 1 }")
    g.slash("sellgray on")
    g.fire("MERCHANT_SHOW")
    g.advance(0.35)                                                           # the first one or two are gone
    g.fire("MERCHANT_CLOSED")
    g.advance(3)
    assert 0 < len(list(g.eval("SOLD").values())) < 5, "selling stopped with the window"


def test_a_bookmark_protects_even_when_the_key_is_switched_off(style):
    g = game(style)
    g.run("NS.db.bookmarks = { [1] = true }")
    g.slash("bookmarks off")
    g.slash("sellgray on")
    g.fire("MERCHANT_SHOW")
    g.advance(3)
    assert 1 not in [int(v) for v in g.eval("SOLD").values()]


# ---- arrange by topic ---------------------------------------------------------------------------------------------

# topics: quest items, consumables, equipment, materials, recipes, other, gray items
EXPECTED = [10, 6,           # quest: Wolf Pelt, Red Bandana (gray, but a quest needs it)
            3,               # consumable
            4, 8,            # equipment: weapon, armor
            2,               # material
            7,               # recipe
            9, 1, 5, 0, 0]   # gray, by name: Broken Tooth, Gray Fang, Old Rag + empty slots at the end


def test_all_bags_are_arranged_as_one_bag_by_topic(style):
    g = game(style)
    g.slash("sort")
    g.advance(10)
    assert flat(g) == EXPECTED, flat(g)
    assert contents(g)[0][:6] == EXPECTED[:6], "the backpack is filled first"
    assert any("bags arranged by topic" in p for p in g.printed()), g.printed()


def test_a_tidy_bag_needs_no_moves(style):
    g = game(style)
    g.slash("sort")
    g.advance(10)
    assert g.eval("#NS.bagTools.plan()") == 0
    g.slash("sort")
    g.advance(1)
    assert any("already in order" in p for p in g.printed()), g.printed()
    assert flat(g) == EXPECTED


def test_stack_sizes_never_change_and_nothing_is_lost(style):
    g = game(style)
    before = sorted(i for i in flat(g) if i)
    g.slash("sort")
    g.advance(10)
    assert sorted(i for i in flat(g) if i) == before
    stacks = [int(s["count"]) for b in (0, 1) for s in g.eval(f"BAGS[{b}]").values() if s and int(s["id"]) == 2]
    assert stacks == [5], "the stack of 5 Linen Cloth is still one stack of 5"


def test_quivers_and_other_special_bags_are_left_alone(style):
    g = game(style, "SPECIAL_BAGS = { [1] = 1 }")                             # bag 1 is a quiver
    before = contents(g)[1]
    g.slash("sort")
    g.advance(10)
    assert contents(g)[1] == before, "the quiver keeps its own items where they are"
    assert contents(g)[0] == [3, 4, 2, 1, 5, 0], "the backpack alone is arranged by topic"


def test_no_arranging_in_a_fight_or_while_holding_an_item(style):
    g = game(style)
    start = flat(g)
    g.run("IN_COMBAT = true")
    g.slash("sort")
    g.advance(5)
    assert flat(g) == start and any("in a fight" in p for p in g.printed())
    g.run("IN_COMBAT = false; CURSOR_ITEM = BAGS[0][1]; BAGS[0][1] = false")
    g.slash("sort")
    g.advance(5)
    assert any("holding an item" in p for p in g.printed())


def test_a_fight_in_the_middle_stops_the_arranging(style):
    g = game(style)
    g.slash("sort")
    g.advance(0.2)
    g.run("IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    g.advance(10)
    assert flat(g) != EXPECTED
    assert any("bag arrangement stopped" in p for p in g.printed()), g.printed()
    g.run("IN_COMBAT = false")
    g.slash("sort")
    g.advance(10)
    assert flat(g) == EXPECTED


def test_automatic_arranging_waits_for_quiet_bags_and_a_calm_moment(style):
    g = game(style)
    g.slash("sort on")
    g.advance(1)
    assert flat(g) != EXPECTED, "not at once"
    g.fire("BAG_UPDATE_DELAYED")
    g.advance(2)
    g.fire("BAG_UPDATE_DELAYED")                                              # more loot: the wait starts again
    g.advance(2)
    assert flat(g) != EXPECTED
    g.advance(12)
    assert flat(g) == EXPECTED
    assert not any("bags arranged" in p for p in g.printed()), "the automatic run is silent"


def test_automatic_arranging_does_not_run_in_a_fight_and_resumes_after(style):
    g = game(style)
    g.slash("sort on")
    g.run("IN_COMBAT = true")
    g.fire("BAG_UPDATE_DELAYED")
    g.advance(10)
    assert flat(g) != EXPECTED
    g.run("IN_COMBAT = false")
    g.fire("PLAYER_REGEN_ENABLED")
    g.advance(15)
    assert flat(g) == EXPECTED


def test_automatic_arranging_off_does_nothing(style):
    g = game(style)
    g.fire("BAG_UPDATE_DELAYED")
    g.advance(15)
    assert flat(g) != EXPECTED


def test_a_locked_slot_makes_it_wait_not_fail(style):
    g = game(style)
    g.run("for b = 0, 1 do for s, it in ipairs(BAGS[b]) do if it then it.locked = true end end end")
    g.slash("sort")
    g.advance(1)
    assert flat(g) == [1, 4, 0, 2, 3, 5, 8, 0, 7, 6, 9, 10], "nothing moved while everything is locked"
    g.run("for b = 0, 1 do for s, it in ipairs(BAGS[b]) do if it then it.locked = false end end end")
    g.advance(10)
    assert flat(g) == EXPECTED


def test_a_move_the_game_refuses_stops_the_arranging_instead_of_looping(style):
    g = game(style)
    g.run("C_Container.PickupContainerItem = function() end")                  # every pickup does nothing
    g.slash("sort")
    g.advance(20)
    assert any("would not move an item" in p for p in g.printed()), g.printed()
    assert g.eval("NS.bagTools.isSorting()") is False


# ---- the chat box during a fight ----------------------------------------------------------------------------------

CHAT = """
CLOSED = {}
local box = CreateFrame("EditBox", "ChatFrame1EditBox")
ACTIVE_BOX = nil
function ChatEdit_ActivateChat(b) ACTIVE_BOX = b; b.shown = true end
function ChatEdit_DeactivateChat(b) CLOSED[#CLOSED + 1] = b; b.shown = false; if ACTIVE_BOX == b then ACTIVE_BOX = nil end end
function OPEN_BOX() ChatEdit_ActivateChat(ChatFrame1EditBox) end
"""


def test_the_chat_box_stays_closed_during_a_fight_when_locked(style):
    g = game(style, CHAT)
    g.fire("PLAYER_LOGIN")
    g.slash("chatlock on")
    g.run("IN_COMBAT = true")
    g.eval("OPEN_BOX")()
    assert g.eval("ChatFrame1EditBox.shown") is False and len(g.eval("CLOSED")) == 1
    assert any("chat box is locked" in p for p in g.printed()), g.printed()
    g.run("IN_COMBAT = false")
    g.eval("OPEN_BOX")()
    assert g.eval("ChatFrame1EditBox.shown") is True, "it opens again after the fight"


def test_an_open_chat_box_closes_when_the_fight_starts(style):
    g = game(style, CHAT)
    g.fire("PLAYER_LOGIN")
    g.slash("chatlock on")
    g.eval("OPEN_BOX")()
    assert g.eval("ChatFrame1EditBox.shown") is True
    g.run("IN_COMBAT = true")
    g.fire("PLAYER_REGEN_DISABLED")
    assert g.eval("ChatFrame1EditBox.shown") is False


def test_a_click_into_the_box_is_refused_too(style):
    g = game(style, CHAT)
    g.fire("PLAYER_LOGIN")
    g.slash("chatlock on")
    g.run("IN_COMBAT = true; ChatFrame1EditBox.shown = true; ACTIVE_BOX = ChatFrame1EditBox")
    g.eval("function() for _, fn in ipairs(ChatFrame1EditBox.posthooks.OnEditFocusGained) do fn(ChatFrame1EditBox) end end")()
    assert g.eval("ChatFrame1EditBox.shown") is False


def test_the_chat_box_is_left_alone_when_the_lock_is_off(style):
    g = game(style, CHAT)
    g.fire("PLAYER_LOGIN")
    g.run("IN_COMBAT = true")
    g.eval("OPEN_BOX")()
    assert g.eval("ChatFrame1EditBox.shown") is True
    g.slash("chatlock on")
    assert g.eval("ChatFrame1EditBox.shown") is False, "switching it on in a fight closes an open box"


def test_the_master_switch_turns_the_chat_lock_off(style):
    g = game(style, CHAT)
    g.fire("PLAYER_LOGIN")
    g.slash("chatlock on")
    g.slash("off")
    g.run("IN_COMBAT = true")
    g.eval("OPEN_BOX")()
    assert g.eval("ChatFrame1EditBox.shown") is True


# ---- how and what to arrange ----------------------------------------------------------------------------------------

def test_the_sort_options_default_to_topic_all_bags_from_the_start(style):
    g = game(style)
    assert g.eval("NS.db.sortBy") == "topic" and g.eval("NS.db.sortBags") == "all"
    assert g.eval("NS.db.sortFrom") == "start" and g.eval("NS.db.sortKeepBookmarked") is False


def test_arranging_by_quality_puts_the_best_items_first(style):
    g = game(style)
    g.slash("sort by quality")
    g.slash("sort")
    g.advance(10)
    q = {1: 0, 2: 1, 3: 1, 4: 2, 5: 0, 6: 0, 7: 1, 8: 1, 9: 0, 10: 1}
    ids = [i for i in flat(g) if i]
    assert ids[0] == 4, "the green sword first"
    assert [q[i] for i in ids] == sorted((q[i] for i in ids), reverse=True), ids
    assert flat(g)[-2:] == [0, 0]
    assert any("bags arranged by quality" in p for p in g.printed()), g.printed()


def test_arranging_by_name_is_alphabetical(style):
    g = game(style)
    g.slash("sort by name")
    g.slash("sort")
    g.advance(10)
    names = [g.eval(f"ITEMS[{i}].name") for i in flat(g) if i]
    assert names == sorted(names, key=str.lower), names


def test_only_the_chosen_bags_are_arranged(style):
    g = game(style)
    before = contents(g)
    g.slash("sort bags backpack")
    g.slash("sort")
    g.advance(10)
    assert contents(g)[1] == before[1], "bag 1 is left alone"
    assert contents(g)[0] == [3, 4, 2, 1, 5, 0], "the backpack alone is arranged by topic"
    g = game(style)
    before = contents(g)
    g.slash("sort bags bags")
    g.slash("sort")
    g.advance(10)
    assert contents(g)[0] == before[0], "the backpack is left alone"
    assert contents(g)[1] == [10, 6, 8, 7, 9, 0], contents(g)[1]


def test_items_can_gather_at_the_end_of_the_bags(style):
    g = game(style)
    g.slash("sort from end")
    g.slash("sort")
    g.advance(10)
    assert flat(g) == list(reversed(EXPECTED)), flat(g)


def test_bookmarked_items_can_stay_in_their_slot(style):
    g = game(style)
    g.eval("NS.bagTools.toggleBookmark")(0, 1)               # the Gray Fang in the first backpack slot
    g.slash("sort keep on")
    g.slash("sort")
    g.advance(10)
    c = flat(g)
    assert c[0] == 1, "the bookmarked item did not move"
    rest = [i for i in EXPECTED if i != 1]
    assert c[1:] == rest, c
    g.slash("sort keep off")
    g.slash("sort")
    g.advance(10)
    assert flat(g) == EXPECTED, "off: bookmarked items are arranged too"


def test_a_wrong_sort_option_says_how_to_use_it(style):
    g = game(style)
    g.slash("sort by colour")
    assert g.eval("NS.db.sortBy") == "topic"
    assert any("usage: /qs sort by" in p for p in g.printed()), g.printed()


# ---- the settings window ------------------------------------------------------------------------------------------

def test_every_helper_has_a_row_in_the_settings(style):
    g = game(style)
    rows = {r.key: r for r in g.eval("NS.settingRows").values() if r.key}
    for key, tab in (("bagBookmarks", "bags"), ("autoSellGray", "bags"), ("autoSortBags", "bags"), ("sortKeepBookmarked", "bags"), ("chatLock", "general")):
        assert key in rows and rows[key].kind == "bool" and rows[key].tab == tab, key
    assert any(r.kind == "action" and r.label == "Arrange my bags now" for r in g.eval("NS.settingRows").values())
    for key in ("sortBy", "sortBags", "sortFrom"):
        assert rows[key].kind == "choice" and rows[key].tab == "bags", key


def test_every_helper_shows_in_the_open_settings_window_and_switches_there(style):
    g = game(style)
    g.slash("settings")
    W = g.eval("NS._settingsWindow()")
    shown = {"general": ["Block the chat box during combat"],
             "bags": ["Order items by", "Bags to arrange", "Where items gather", "Leave bookmarked items where they are",
                      "Bookmark bag items with the Space bar", "Sell gray items when I open a vendor",
                       "Arrange my bags by topic automatically", "Arrange my bags now", "Remove all my bookmarks"]}
    for tab, labels in shown.items():
        g.eval("NS.settingsTab")(tab)
        all_rows = g.eval("NS.settingRows")
        texts = [all_rows[r.index].label for r in W.rows.values() if r.frame.shown and r.index]
        for label in labels:
            assert label in texts, (tab, label, texts)
    for key, default in (("bagBookmarks", True), ("autoSellGray", False), ("autoSortBags", False), ("chatLock", False)):
        i = g.eval(f"(function() for i, r in ipairs(NS.settingRows) do if r.key == '{key}' then return i end end end)()")
        assert g.eval(f"NS.db.{key}") is default
        g.eval("NS.settingsClick")(i, "LeftButton")
        assert g.eval(f"NS.db.{key}") is (not default), key
        g.eval("NS.settingsClick")(i, "LeftButton")
        assert g.eval(f"NS.db.{key}") is default, key


def test_the_settings_buttons_arrange_and_clear(style):
    g = game(style)
    point_at(g, 1)
    g.eval("NS.bagTools.keyDown")("SPACE")
    rows = g.eval("NS.settingRows")
    by_label = {r.label: i for i, r in rows.items() if r.kind == "action"}
    g.eval("NS.settingsAction")(by_label["Arrange my bags now"])
    g.advance(10)
    assert flat(g) == EXPECTED
    g.eval("NS.settingsAction")(by_label["Remove all my bookmarks"])
    assert g.eval("NS.bagTools.isBookmarked(1)") is False


def test_the_reset_puts_the_helpers_back(style):
    g = game(style)
    g.slash("sellgray on")
    g.slash("sort on")
    g.slash("chatlock on")
    g.slash("bookmarks off")
    g.slash("reset")
    assert g.eval("NS.db.autoSellGray") is False and g.eval("NS.db.autoSortBags") is False
    assert g.eval("NS.db.chatLock") is False and g.eval("NS.db.bagBookmarks") is True


def test_the_bookmark_commands(style):
    g = game(style)
    point_at(g, 1)
    g.eval("NS.bagTools.keyDown")("SPACE")
    g.slash("bookmarks list")
    assert any("bookmarked:" in p and "Gray Fang" in p for p in g.printed()), g.printed()
    g.slash("bookmarks clear")
    assert g.eval("NS.bagTools.isBookmarked(1)") is False
    assert any("1 bookmark(s) removed" in p for p in g.printed())


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
