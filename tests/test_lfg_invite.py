"""Party finder: search with one click, invite solo players listed with a wanted role.
python tests/test_lfg_invite.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

# The game's party finder: LISTED[id] = search result; Search only records the call, the test fires the event.
LFG = """
LISTED, SEARCHES, SEARCH_ACTS = {}, {}, {}
LISTING = { 101 }                      -- my listing: The Deadmines (nil = not listed)
ACTIVITIES = { [101] = { fullName = "The Deadmines", categoryID = 2 }, [202] = { fullName = "Wailing Caverns", categoryID = 2 } }
local function solo(name, level, class, roles, act)
    return { numMembers = 1, leaderName = name, activityIDs = { act or 101 },
             player = { name = name, level = level, className = class, classFilename = string.upper(class), lfgRoles = roles } }
end
LISTED[11] = solo("Lia", 24, "Priest", { tank = false, healer = true, dps = false })
LISTED[12] = solo("Bram", 25, "Warrior", { tank = true, healer = false, dps = true })
LISTED[13] = solo("Kel", 23, "Mage", { tank = false, healer = false, dps = true })
LISTED[14] = { numMembers = 3, leaderName = "Group", player = { name = "Group", lfgRoles = { healer = true } } }
LISTED[15] = solo("Old", 22, "Druid", { healer = true }); LISTED[15].isDelisted = true
LISTED[16] = solo("Ann", 26, "Priest", { healer = true }, 202)          -- healer, but for another dungeon
C_LFGList = {
    Search = function(cat, f, p, lang, cross, adv, acts) SEARCHES[#SEARCHES + 1] = cat; SEARCH_ACTS[#SEARCH_ACTS + 1] = acts end,
    HasActiveEntryInfo = function() return LISTING ~= nil end,
    GetActiveEntryInfo = function() return LISTING and { activityIDs = LISTING } or nil end,
    GetActivityInfoTable = function(id) return ACTIVITIES[id] end,
    GetActivityFullName = function(id) return ACTIVITIES[id] and ACTIVITIES[id].fullName end,
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
    assert any("invited Lia 24 Priest (healer, item level unknown) for The Deadmines" in p for p in g.printed())
    assert list(g.eval("SEARCH_ACTS[1]").values()) == [101], "only my listing's dungeon is searched"


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
    assert g.invited() == ["Bram"], "one spot: the highest level (Bram 25) wins"


def test_blizzard_window_searches_invite_only_with_watch_on(style):
    g = game(style)
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == []
    g.slash("lfg watch on")
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == ["Lia"]


def test_minimap_spyglass_left_click_opens_the_picker_right_click_opens_settings(style):
    g = game(style)
    finder = list(g.eval("NS._minimapShortcuts()").values())[2]
    assert finder.shown is True
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(finder)
    assert g.eval("NS.lfgFinder._window()").win.shown is True
    assert g.invited() == [], "opening the picker invites nobody"
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


def test_not_listed_means_no_search_and_no_invite(style):
    g = game(style)
    g.run("LISTING = nil")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [] and len(g.eval("SEARCHES")) == 0
    assert any("list your group in the party finder first" in p for p in g.printed())
    g.slash("lfg watch on")
    g.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert g.invited() == []


def test_only_players_listed_for_my_dungeon_are_invited(style):
    g = game(style)
    g.run("LISTING = { 202 }")                                   # now listed for Wailing Caverns
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Ann"]


def test_highest_level_goes_first(style):
    g = game(style)
    g.run("LISTED[17] = { numMembers = 1, leaderName = 'Zed', activityIDs = { 101 }, player = { name = 'Zed', level = 27, className = 'Paladin', classFilename = 'PALADIN', lfgRoles = { healer = true } } }")
    g.join_party(["A", "B", "C"])                                # one free spot
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Zed"]


def test_classes_per_role_can_be_turned_off(style):
    g = game(style)
    g.eval("NS.lfgInvite.setClass")("healer", "PRIEST", False)
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "Lia is a priest"
    g.run("NS.setSetting('lfgDps', true)")
    g.eval("NS.lfgInvite.setClass")("dps", "MAGE", False)
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Bram"], "warrior dps yes, mage no"


def test_the_picker_toggles_roles_and_classes_and_find_searches(style):
    g = game(style)
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    click = g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")
    assert "The Deadmines" in W.listing.text
    priest = [b for b in W.classes.healer.values() if b["class"] == "PRIEST"][0]
    click(priest)
    assert g.eval("NS.lfgInvite.classAllowed('healer', 'PRIEST')") is False and priest.tick.shown is False
    click(priest)
    click(W.roles.tank)
    assert g.eval("NS.db.lfgTank") is True
    click(W.roles.tank)                                          # tank off again: only healers
    click(W.plus)
    assert g.eval("NS.db.lfgMinIlvl") == 1
    click(W.minus)
    click(W.find)
    assert len(g.eval("SEARCHES")) == 1 and g.invited() == ["Lia"]
    assert "invited Lia" in W.status.text


def test_a_player_who_joins_no_longer_holds_an_extra_spot(style):
    g = game(style)
    g.join_party(["A", "B"])                                     # 3 in the party: two spots
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"] and g.eval("NS.lfgInvite.freeSpots()") == 1
    g.join_party(["A", "B", "Lia"])                              # Lia accepted: 4 in the party, still one spot
    assert g.eval("NS.lfgInvite.freeSpots()") == 1


def test_a_declined_invite_frees_its_spot_at_once(style):
    g = game(style)
    g.join_party(["A", "B", "C"])                                # one spot
    g.eval("NS.lfgInvite.scan")()
    assert g.eval("(NS.lfgInvite.freeSpots())") == 0
    g.reply("Lia declines your group invitation.")
    assert g.eval("NS.lfgInvite.freeSpots()") == 1
    assert any("Lia declined, the spot is free again" in p for p in g.printed())


def test_a_search_the_game_never_answered_does_not_block_forever(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    g.eval("NS.lfgInvite.scan")()
    assert len(g.eval("SEARCHES")) == 1, "a second click while searching waits"
    g.advance(7)
    g.eval("NS.lfgInvite.scan")()
    assert len(g.eval("SEARCHES")) == 2


def test_the_picker_says_why_find_cannot_work_and_keeps_the_last_invite(style):
    g = game(style)
    g.run("LISTING = nil")
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert "Not listed" in W.status.text and "Not listed" in W.listing.text
    g.run("LISTING = { 101 }")
    g.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    assert W.status.text == "Ready: click Find."
    g.join_party(["A", "B", "C"])
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.find)
    assert "invited Lia" in W.status.text and "party is full" in W.status.text
    assert "0 free spots" in W.info.text


def whispers(g):
    return [(m["msg"], m["target"]) for m in g.eval("SENT").values() if m["channel"] == "WHISPER"]


def test_each_invite_is_followed_by_a_whisper_naming_the_dungeon(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    assert whispers(g) == [("Hi! I invited you to my group for The Deadmines as healer.", "Lia")]


def test_the_whisper_text_can_be_changed_or_switched_off(style):
    g = game(style)
    g.run("NS.setSetting('lfgWhisperText', 'Yo, {role} wanted for {dungeon}, inv sent!'); NS.setSetting('lfgTank', true)")
    g.eval("NS.lfgInvite.scan")()
    assert ("Yo, tank wanted for The Deadmines, inv sent!", "Bram") in whispers(g)
    g = game(style)
    g.run("NS.setSetting('lfgWhisper', false)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"] and whispers(g) == []


def test_no_whisper_without_an_invite_or_after_the_game_refused_chat(style):
    g = game(style)
    g.run("LISTING = nil")
    g.eval("NS.lfgInvite.scan")()
    assert whispers(g) == []
    g = game(style)
    g.run("NS.blockedFeatures.chat = true")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"] and whispers(g) == []


def test_the_picker_whisper_box_switches_the_whisper(style):
    g = game(style)
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert W.whisper.tick.shown is True
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.whisper)
    assert g.eval("NS.db.lfgWhisper") is False and W.whisper.tick.shown is False


HEALERS = """
for i, n in ipairs({ "Hea", "Heb", "Hec" }) do
    LISTED[30 + i] = { numMembers = 1, leaderName = n, activityIDs = { 101 },
        player = { name = n, level = 20 + i, className = 'Priest', classFilename = 'PRIEST', lfgRoles = { healer = true } } }
end
"""


def test_normal_mode_invites_one_healer_even_with_many_listed(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "1 healer needed: only the highest level (Lia 24)"
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "the healer spot is taken by the open invite"
    g.reply("Lia declines your group invitation.")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec"], "declined: the next healer by level"


def test_supercharge_invites_every_matching_healer_at_once(style):
    g = game(style)
    g.run(HEALERS)
    g.slash("lfg healer on")
    g.run("NS.setSetting('lfgSupercharge', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec", "Heb", "Hea"], "all four, highest level first"
    assert all(m.endswith("First to accept gets the spot.") for m, _ in whispers(g))
    assert g.eval("(NS.lfgInvite.freeSpots())") == 0, "4 open invites fill the 4 spots (the game counts them too)"


def test_a_joined_healer_fills_the_healer_role(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    g.join_party(["Lia"])
    g.advance(70)                                                # long after the invite expired
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "Lia joined as healer: no second healer"
    assert g.eval("NS.lfgInvite.roleOpen('healer')") == 0 and g.eval("NS.lfgInvite.roleOpen('damage')") == 3


def test_the_picker_supercharge_box_and_open_roles_line(style):
    g = game(style)
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert "open: 1 healer, 1 tank, 3 damage" in W.info.text
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.super)
    assert g.eval("NS.db.lfgSupercharge") is True and "every match" in W.info.text


DRUID = "LISTED[40] = { numMembers = 1, leaderName = 'Dru', activityIDs = { 101 }, player = { name = 'Dru', level = 30, className = 'Druid', classFilename = 'DRUID', lfgRoles = { healer = true, dps = true } } }"


def test_a_hybrid_takes_the_role_still_open(style):
    g = game(style)
    g.run(DRUID + "; NS.setSetting('lfgDps', true)")
    g.join_party(["Hel"])
    g.run("NS.lfgInvite.decide({ name = 'Hel', role = 'healer', roles = { 'healer' } })")   # Hel: invited as healer
    g.join_party(["Hel"])                                        # ... and joined
    g.run("INVITED = {}")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited()[0] == "Dru", "healer filled, the druid (30) comes as damage"
    assert any("invited Dru 30 Druid (damage" in p for p in g.printed())


def test_a_hybrid_prefers_the_scarcer_role(style):
    g = game(style)
    g.run(DRUID + "; NS.setSetting('lfgHealer', true); NS.setSetting('lfgDps', true)")
    g.eval("NS.lfgInvite.scan")()
    assert any("invited Dru 30 Druid (healer" in p for p in g.printed())


def test_supercharge_skips_a_role_party_members_already_fill(style):
    g = game(style)
    g.run(HEALERS + "; NS.setSetting('lfgSupercharge', true)")
    g.run("NS.lfgInvite.decide({ name = 'Hel', role = 'healer', roles = { 'healer' } })")
    g.join_party(["Hel"])
    g.run("INVITED = {}")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "a healer is in the party: supercharge invites no more healers"


def test_party_members_of_a_damage_only_class_fill_damage_spots(style):
    g = game(style)
    g.run("CLASSES.Ro, CLASSES.Ma, CLASSES.Wl = 'ROGUE', 'MAGE', 'WARLOCK'; NS.setSetting('lfgHealer', false); NS.setSetting('lfgDps', true)")
    g.join_party(["Ro", "Ma", "Wl"])
    assert g.eval("NS.lfgInvite.roleOpen('damage')") == 0
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == []


def test_older_clients_with_one_activity_id_and_leader_info_only(style):
    g = game(style)
    g.run("""
        local p = C_LFGList.GetSearchResultPlayerInfo
        C_LFGList.GetSearchResultPlayerInfo = nil
        C_LFGList.GetSearchResultLeaderInfo = function(id) return LISTED[id] and LISTED[id].player end
        for _, r in pairs(LISTED) do r.activityID = r.activityIDs and r.activityIDs[1]; r.activityIDs = nil end
        C_LFGList.GetActiveEntryInfo = function() return { activityID = 101 } end""")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"]


def test_after_the_item_level_wait_a_filled_role_is_not_invited(style):
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30); NS.setSetting('lfgUnknown', 'invite')")
    g.eval("NS.lfgInvite.scan")()                                # asks Lia, waits
    g.run("NS.lfgInvite.decide({ name = 'Hel', role = 'healer', roles = { 'healer' }, asked = true })")
    g.join_party(["Hel"])                                        # a healer joined meanwhile
    g.run("INVITED = {}")
    g.advance(3)
    assert g.invited() == [], "Lia is not invited: the healer spot was filled during the wait"


def test_settings_links_open_the_party_finder_page(style):
    g = game(style)
    finder = list(g.eval("NS._minimapShortcuts()").values())[2]
    g.eval("function(b) b.scripts.OnClick(b, 'RightButton') end")(finder)
    assert g.eval("NS._settingsWindow()").tab == "finder", "right click on the spyglass"
    g.eval("NS.toggleSettings")(False)
    g.eval("NS.lfgFinder.toggle")(True)
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(g.eval("NS.lfgFinder._window()").more)
    assert g.eval("NS._settingsWindow()").tab == "finder", "the picker's Settings button"


def test_supercharge_never_sends_more_invites_than_free_spots(style):
    g = game(style)
    g.run(HEALERS + "; NS.setSetting('lfgSupercharge', true)")
    g.join_party(["A", "B"])                                     # 3 in the party: 2 spots
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec"], "only 2 invites: a 3rd would get 'Your party is full.'"
    g.reply("Lia declines your group invitation.")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec", "Heb"], "a decline frees one spot for one more"


def test_supercharge_counts_players_still_being_asked_for_their_item_level(style):
    g = game(style)
    g.run(HEALERS + "; NS.setSetting('lfgSupercharge', true); NS.setSetting('lfgMinIlvl', 30)")
    g.join_party(["A", "B", "C"])                                # 1 spot
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [] and g.eval("(NS.lfgInvite.freeSpots())") == 0, "one player asked: the spot is held"
    g.advance(3)
    assert g.invited() == ["Lia"], "after the wait, one invite only"


def test_a_player_listed_twice_gets_one_invite(style):
    g = game(style)
    g.run("LISTED[50] = { numMembers = 1, leaderName = 'Lia', activityIDs = { 101 }, player = LISTED[11].player }")
    g.run("NS.setSetting('lfgSupercharge', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited().count("Lia") == 1


def test_an_open_invite_holds_its_spot_past_one_minute(style):
    g = game(style)
    g.join_party(["A", "B", "C"])                                # 1 spot
    g.eval("NS.lfgInvite.scan")()
    g.advance(65)                                                # the game may still show her the invite
    assert g.eval("(NS.lfgInvite.freeSpots())") == 0
    g.advance(15)
    assert g.eval("(NS.lfgInvite.freeSpots())") == 1


def test_the_games_party_full_error_gets_a_plain_explanation(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    g.reply("Your party is full.")
    assert any("open invites count as spots" in p for p in g.printed())


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
