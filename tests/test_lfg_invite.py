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
ACTIVITIES = { [101] = { fullName = "The Deadmines", categoryID = 2, minLevelSuggestion = 15, maxLevelSuggestion = 30 },
               [202] = { fullName = "Wailing Caverns", categoryID = 2, minLevelSuggestion = 15, maxLevelSuggestion = 30 } }
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


def test_only_real_members_count_for_free_spots(style):
    g = game(style)
    g.join_party(["A", "B"])                                     # 3 in the party: two spots
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"] and g.eval("(NS.lfgInvite.freeSpots())") == 2, "an open invite holds no spot"
    g.join_party(["A", "B", "Lia"])                              # Lia accepted: 4 members, one spot
    assert g.eval("(NS.lfgInvite.freeSpots())") == 1


def test_a_declined_invite_says_so(style):
    g = game(style)
    g.join_party(["A", "B", "C"])
    g.eval("NS.lfgInvite.scan")()
    g.reply("Lia declines your group invitation.")
    assert any("Lia declined" in p for p in g.printed())
    assert g.eval("(NS.lfgInvite.freeSpots())") == 1


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
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.find)
    assert "invited Lia" in W.status.text
    g.join_party(["A", "B", "C", "Lia"])
    assert "invited Lia" in W.status.text and "party is full" in W.status.text, "full only with 5 real members"
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


def test_normal_mode_invites_one_healer_per_find(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "1 healer needed: only the highest level (Lia 24)"
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec"], "Lia has not joined: the next Find tries the next healer"
    g.join_party(["Lia"])
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec"], "a healer is in the party: no more healers"


def test_supercharge_invites_every_matching_healer_at_once(style):
    g = game(style)
    g.run(HEALERS)
    g.slash("lfg healer on")
    g.run("NS.setSetting('lfgSupercharge', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec", "Heb", "Hea"], "all four, highest level first"
    assert all(m.endswith("First to accept gets the spot.") for m, _ in whispers(g))
    assert g.eval("(NS.lfgInvite.freeSpots())") == 4, "open invites hold no spot"


def test_a_joined_healer_fills_the_healer_role(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    g.join_party(["Lia"])
    g.advance(70)                                                # long after the invite expired
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "Lia joined as healer: no second healer"
    assert g.eval("NS.lfgInvite.roleOpen('healer')") == 0 and g.eval("NS.lfgInvite.roleOpen('damage')") == 2, "me (damage by default) + Lia (healer)"


def test_the_picker_supercharge_box_and_open_roles_line(style):
    g = game(style)
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert "Party: tank 0/1, healer 0/1, damage 1/3" in W.info.text
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.super)
    assert g.eval("NS.db.lfgSupercharge") is True


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


def test_supercharge_skips_nobody_for_open_invites(style):
    g = game(style)
    g.run(HEALERS + "; NS.setSetting('lfgSupercharge', true)")
    g.join_party(["A", "B"])                                     # 3 members
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec", "Heb", "Hea"], "every listed healer at once; first to accept wins"


def test_supercharge_with_item_level_asks_then_invites_all(style):
    g = game(style)
    g.run(HEALERS + "; NS.setSetting('lfgSupercharge', true); NS.setSetting('lfgMinIlvl', 30)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == []
    g.advance(3)
    assert sorted(g.invited()) == ["Hea", "Heb", "Hec", "Lia"]


def test_a_player_listed_twice_gets_one_invite(style):
    g = game(style)
    g.run("LISTED[50] = { numMembers = 1, leaderName = 'Lia', activityIDs = { 101 }, player = LISTED[11].player }")
    g.run("NS.setSetting('lfgSupercharge', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited().count("Lia") == 1


def test_an_invite_nobody_answers_never_blocks_the_next_find(style):
    g = game(style)
    g.run(HEALERS)
    g.join_party(["A", "B", "C"])                                # 1 spot
    g.eval("NS.lfgInvite.scan")()                                # Lia invited, she just hangs
    assert g.eval("NS.lfgInvite.blocker()") is None, "no 'party is full' while she does not answer"
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia", "Hec"], "the next Find invites the next healer"


def test_someone_who_leaves_frees_the_spot_and_the_role(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    g.join_party(["Lia", "A", "B", "C"])                         # full: Lia (healer) + 3
    assert g.eval("(NS.lfgInvite.freeSpots())") == 0 and g.eval("NS.lfgInvite.roleOpen('healer')") == 0
    g.join_party(["A", "B", "C"])                                # Lia left
    assert g.eval("(NS.lfgInvite.freeSpots())") == 1 and g.eval("NS.lfgInvite.roleOpen('healer')") == 1
    g.run("INVITED = {}")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Hec"]


def test_the_games_party_full_error_gets_a_plain_explanation(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    g.reply("Your party is full.")
    assert any("the game says the party is full" in p for p in g.printed())


def test_my_own_role_counts(style):
    g = game(style)
    g.run("NS.setSetting('lfgMyRole', 'healer')")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "I am the healer: no second healer"
    g.run("NS.setSetting('lfgMyRole', 'tank'); NS.setSetting('lfgTank', true)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "I am the tank: Bram (tank) is not invited, Lia (healer) is"


def test_party_is_never_more_than_three_damage(style):
    g = game(style)
    g.run("NS.setSetting('lfgHealer', false); NS.setSetting('lfgDps', true); NS.setSetting('lfgSupercharge', true)")
    g.join_party(["A", "B"])                                     # me + 2 unknown = 3 damage
    assert g.eval("NS.lfgInvite.compositionText()") == "tank 0/1, healer 0/1, damage 3/3"
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "3 damage already: even supercharge invites no more damage"


def test_unknown_members_count_as_damage_but_a_known_role_wins(style):
    g = game(style)
    g.run("UnitGroupRolesAssigned = function(u) if u == 'party1' then return 'HEALER' end return 'NONE' end")
    g.join_party(["Pri", "B"])
    assert g.eval("NS.lfgInvite.compositionText()") == "tank 0/1, healer 1/1, damage 2/3"


def test_the_picker_i_am_button_cycles_my_role(style):
    g = game(style)
    g.eval("NS.lfgFinder.toggle")(True)
    W = g.eval("NS.lfgFinder._window()")
    assert W.me.text == "I am: auto (damage)"
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(W.me)
    assert g.eval("NS.db.lfgMyRole") == "tank" and W.me.text == "I am: tank"
    assert "tank 1/1" in W.info.text


def test_anyone_invited_is_not_invited_again_for_an_hour(style):
    g = game(style)
    g.eval("NS.lfgInvite.scan")()
    g.reply("Lia declines your group invitation.")
    g.run("INVITED = {}")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "declined 0 min ago: blocked"
    g.run("NOW = NOW + 61 * 60")                                  # an hour later
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "after 60 min she may be invited again"


def test_who_joined_and_who_left_is_remembered_and_blocked(style):
    g = game(style)
    g.run(HEALERS)
    g.eval("NS.lfgInvite.scan")()
    g.join_party(["Lia"])
    g.join_party([])                                             # she left
    h = g.eval("NS.db.lfgHistory.Lia")
    assert h.invited and h.joined and h.left
    g.run("NS.db.lfgHistory.Lia.invited = 1")                   # invited long ago ...
    g.run("INVITED = {}")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Hec"], "... but she left just now: still blocked, the next healer instead"
    g.slash("lfg history")
    assert any("Lia: invited" in p and "joined" in p and "left" in p and "blocked" in p for p in g.printed())
    g.slash("lfg forget")
    assert g.eval("NS.lfgInvite.blockedFor('Lia')") is None


MAPS = r"""
Enum = Enum or {}; Enum.UIMapType = { World = 1, Continent = 2, Zone = 3 }
ZONES = { [1436] = { "Westfall", 1415, 0.40, 0.70 }, [1433] = { "Redridge Mountains", 1415, 0.60, 0.60 },
          [1413] = { "The Barrens", 1414, 0.50, 0.50 } }
C_Map.GetMapInfo = function(id)
    if id == 1414 or id == 1415 then return { name = "Continent", parentMapID = 947, mapType = 2 } end
    local z = ZONES[id]; if z then return { name = z[1], parentMapID = z[2], mapType = 3 } end
end
C_Map.GetMapRectOnMap = function(id, parent)
    local z = ZONES[id]; if z and z[2] == parent then return z[3] - 0.05, z[3] + 0.05, z[4] - 0.05, z[4] + 0.05 end
end
C_Map.GetMapChildrenInfo = function(root)
    local out = {}
    for id, z in pairs(ZONES) do if z[2] == root then out[#out + 1] = { mapID = id, name = z[1], mapType = 3 } end end
    return out
end
"""


def far_world(g):
    g.run("LISTED[11].player.areaName = 'Westfall'")                                   # Lia 24, at the dungeon
    g.run("LISTED[60] = { numMembers = 1, leaderName = 'Far', activityIDs = { 101 }, player = { name = 'Far', level = 27, "
          "className = 'Priest', classFilename = 'PRIEST', areaName = 'The Barrens', lfgRoles = { healer = true } } }")


def test_nearness_to_the_dungeon_counts_with_level(style):
    g = Game(style, LFG + MAPS)
    g.start()
    far_world(g)
    assert g.eval("NS.lfgInvite.farness({ activity = 101, area = 'Westfall' })") == 0
    assert g.eval("NS.lfgInvite.farness({ activity = 101, area = 'The Barrens' })") == 6
    assert 0 < g.eval("NS.lfgInvite.farness({ activity = 101, area = 'Redridge Mountains' })") < 6
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "balanced: Lia 24 in Westfall beats Far 27 on another continent"
    assert any("in Westfall" in p for p in g.printed())


def test_order_choice_highest_level_or_nearest(style):
    g = Game(style, LFG + MAPS)
    g.start()
    far_world(g)
    g.run("NS.setSetting('lfgOrder', 'level')")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Far"], "highest level first"
    g = Game(style, LFG + MAPS)
    g.start()
    far_world(g)
    g.run("NS.setSetting('lfgOrder', 'near'); LISTED[11].player.level = 18")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"], "nearest first, whatever the level"


def test_levels_come_from_the_listed_dungeon(style):
    g = game(style)
    g.run("ACTIVITIES[101].minLevelSuggestion, ACTIVITIES[101].maxLevelSuggestion = 18, 23")
    assert list(g.eval("{ NS.lfgInvite.levelRange() }").values()) == [18, 23, "dungeon"]
    g.run(HEALERS)                                               # Hea 21, Heb 22, Hec 23; Lia 24 is too high
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Hec"], "Lia 24 is above the dungeon's 23: Hec 23 is invited"


def test_without_game_levels_the_bundled_dungeon_range_is_used(style):
    g = game(style)
    g.run("ACTIVITIES[101].minLevelSuggestion, ACTIVITIES[101].maxLevelSuggestion = 0, 0")
    assert list(g.eval("{ NS.lfgInvite.levelRange() }").values()) == [18, 23, "dungeon"], "TravelData: The Deadmines 18-23"
    g.run("ACTIVITIES[101].fullName = 'A brand new dungeon'")
    lo, hi, src = g.eval("{ NS.lfgInvite.levelRange() }").values()
    assert src == "manual" and (lo, hi) == (1, 60), "unknown dungeon: your own range"


def test_several_listed_dungeons_span_their_levels_and_manual_mode_wins(style):
    g = game(style)
    g.run("LISTING = { 101, 202 }; ACTIVITIES[101].minLevelSuggestion, ACTIVITIES[101].maxLevelSuggestion = 18, 23")
    g.run("ACTIVITIES[202].minLevelSuggestion, ACTIVITIES[202].maxLevelSuggestion = 17, 24")
    assert list(g.eval("{ NS.lfgInvite.levelRange() }").values())[:2] == [17, 24]
    g.run("NS.setSetting('lfgLevelMode', 'manual'); NS.setSetting('lfgMinLevel', 40)")
    assert list(g.eval("{ NS.lfgInvite.levelRange() }").values()) == [40, 60, "manual"]


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
