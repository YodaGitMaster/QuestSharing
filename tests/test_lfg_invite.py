"""Party finder: search with one click, invite solo players listed with a wanted role.
python tests/test_lfg_invite.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# The game's party finder: LISTED[id] = search result; Search only records the call, the test fires the event.
LFG = """
LISTED, SEARCHES = {}, {}
local function solo(name, level, class, roles) return { numMembers = 1, leaderName = name, player = { name = name, level = level, className = class, lfgRoles = roles } } end
LISTED[11] = solo("Lia", 24, "Priest", { tank = false, healer = true, dps = false })
LISTED[12] = solo("Bram", 25, "Warrior", { tank = true, healer = false, dps = true })
LISTED[13] = solo("Kel", 23, "Mage", { tank = false, healer = false, dps = true })
LISTED[14] = { numMembers = 3, leaderName = "Group", player = { name = "Group", lfgRoles = { healer = true } } }
LISTED[15] = solo("Old", 22, "Druid", { healer = true }); LISTED[15].isDelisted = true
C_LFGList = {
    Search = function(cat, ...) SEARCHES[#SEARCHES + 1] = cat end,
    GetFilteredSearchResults = function()
        local ids = {} for id in pairs(LISTED) do ids[#ids + 1] = id end table.sort(ids) return #ids, ids end,
    GetSearchResultInfo = function(id) return LISTED[id] end,
    GetSearchResultPlayerInfo = function(id, i) return LISTED[id] and LISTED[id].player end,
}
"""


def game(style):
    g = Game(style, LFG)
    g.start()
    return g


def test_a_click_searches_and_the_results_invite_only_solo_healers(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    assert list(g.eval("SEARCHES").values()) == [2], "one search, Dungeons category"
    assert g.invited() == ["Lia"], "already-loaded results are checked at once"
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == ["Lia"], "no second invite for the same player"
    assert any("invited Lia 24 Priest (healer, ilvl ?)" in p for p in g.printed())


def test_roles_from_settings_choose_who_is_invited(style):
    g = game(style)
    g.run("NS.setSetting('lfgHealer', false); NS.setSetting('lfgTank', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Bram"]
    g.slash("lfg dps on")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Bram", "Kel"]


def test_nobody_chosen_means_no_search_and_no_invite(style):
    g = game(style)
    g.run("NS.setSetting('lfgHealer', false)")
    g.eval("NS.lfgInvite.scan")()
    assert len(g.eval("SEARCHES")) == 0 and g.invited() == []


def test_a_full_party_or_not_being_leader_stops_the_invites(style):
    g = game(style)
    g.join_party(["A", "B", "C", "D"])
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [] and len(g.eval("SEARCHES")) == 0
    g.join_party(["A"])
    g.run("LEADER = false")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == []


def test_invites_stop_at_the_free_spots(style):
    g = game(style)
    g.run("NS.setSetting('lfgTank', true); NS.setSetting('lfgDps', true)")
    g.join_party(["A", "B", "C"])                         # 4 in the party: one spot
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"]


def test_blizzard_window_searches_invite_only_with_watch_on(style):
    g = game(style)
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == []
    g.slash("lfg watch on")
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == ["Lia"]


def test_minimap_spyglass_left_click_scans_right_click_opens_settings(style):
    g = game(style)
    finder = list(g.eval("NS._minimapShortcuts()").values())[2]
    assert finder.shown is True
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(finder)
    assert g.invited() == ["Lia"]
    g.eval("function(b) b.scripts.OnClick(b, 'RightButton') end")(finder)
    assert g.eval("NS._settingsWindow()").win.shown is True
    g.eval("function(b) b.scripts.OnEnter(b) end")(finder)
    assert g.eval("TOOLTIP.text") == "Party finder"


def test_the_key_binding_scans_and_no_party_finder_is_handled(style):
    g = game(style)
    g.eval("QuestSharing_LFGScan")()
    assert g.invited() == ["Lia"]
    g.run("C_LFGList = nil")
    g.eval("QuestSharing_LFGScan")()
    assert any("no party finder" in p for p in g.printed())


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total += 1
            label = f"{name}[{style}]" if style else name
            try:
                fn(style) if style else fn()
                print("ok  ", label)
            except Exception as e:  # noqa: BLE001
                failed += 1
                print("FAIL", label, type(e).__name__, e)
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)
