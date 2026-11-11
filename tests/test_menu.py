"""The right-click menu of the Party quests window, Questie's "where to get it", the key guard for the game's sound keys,
and the doctor's sound line.        python tests/test_menu.py"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402

STYLES = ("modern", "classic")

DATA = """
QUESTIE_QUESTS = {
    [100] = { name = "Wolves Among Us", startedBy = { { 197 } }, preQuestSingle = { 783 } },
    [783] = { name = "A Threat Within", startedBy = { { 823 } }, preQuestSingle = { 7 } },
    [7] = { name = "Kobold Camp Cleanup" },
    [101] = { name = "Report to Goldshire", startedBy = { nil, nil, { 5000 } } },
}
QUESTIE_NPCS = { [197] = { name = "Marshal McBride", spawns = { [12] = { { 48.92, 41.61 } } } },
                 [823] = { name = "Deputy Willem", spawns = { [12] = { { 48.17, 42.94 } } } },
                 [6] = { name = "Kobold Vermin", spawns = { [12] = { { 40.1, 80.2 } } } } }
QUESTIE_ITEMS = { [5000] = { name = "A Torn Letter", npcDrops = { 6 } } }
local function getter(t) return function(id, key) local r = t[id]; return r and r[key] end end
"""
QUESTIE_12 = DATA + """
QuestDB, NpcDB, ItemDB, ObjectDB = { Get = getter(QUESTIE_QUESTS) }, { Get = getter(QUESTIE_NPCS) }, { Get = getter(QUESTIE_ITEMS) }, { Get = getter({}) }
C_Map.GetAreaInfo = function(id) return ({ [12] = "Elwynn Forest" })[id] end
"""
QUESTIE_11 = DATA + """
Questie = { started = true }
QuestieLoader = { ImportModule = function(self, name)
    if name ~= "QuestieDB" then return { private = {} } end
    return { QueryQuestSingle = getter(QUESTIE_QUESTS), QueryNPCSingle = getter(QUESTIE_NPCS),
             QueryItemSingle = getter(QUESTIE_ITEMS), QueryObjectSingle = getter({}) }
end }
C_Map.GetAreaInfo = function(id) return ({ [12] = "Elwynn Forest" })[id] end
"""


def plain(t):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t or "")


def party(style, names=("Anna",), on_quest=None, pre=""):
    g = Game(style, pre)
    g.start()
    g.slash("auto off")
    for unit, ids in (on_quest or {}).items():
        g.run(f'ON_QUEST["{unit}"] = {{{", ".join("[%d] = true" % i for i in ids)}}}')
    g.join_party(list(names))
    g.advance(3)
    g.slash("panel on")
    g.advance(1)
    g.run("SENT = {}; PRINTED = {}")
    return g


def row(g, title):
    rows = g.eval("NS._panel()")[1]
    return next(rows[i] for i in range(1, 6) if rows[i].shown and title in rows[i].title.text)


def open_menu(g, title="Wolves Among Us"):
    g.eval("function(r) r.scripts.OnClick(r, 'RightButton') end")(row(g, title))
    menu, lines = g.eval("NS._questMenu()")
    return menu, [lines[i] for i in range(1, 9) if lines[i].shown]


def pick(g, lines, label):
    b = next(b for b in lines if label in plain(b.text))
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(b)


# ---- the menu ------------------------------------------------------------------------------------------------------------
def test_right_click_opens_a_small_menu_for_that_quest(style):
    g = party(style)
    menu, lines = open_menu(g)
    assert menu.shown is True and plain(menu.title.text) == "Wolves Among Us"
    assert [plain(b.text) for b in lines] == ["Tell the party how I am doing", "Offer it to the party", "Tell them where to get it",
                                             "How to do it", "Trace back the chain", "Focus it on my map",
                                             "Select it in the quest log"]
    assert "QuestSharingMenu" in list(g.eval("UISpecialFrames").values()), "Esc closes it"


def test_a_choice_does_it_and_closes_the_menu(style):
    g = party(style)
    menu, lines = open_menu(g)
    pick(g, lines, "Tell the party how I am doing")
    assert menu.shown is False and len(g.sent()) == 1
    assert g.sent()[0][0].endswith(("What about you?", "How about you?", "And you?")), g.sent()
    menu, lines = open_menu(g)
    g.run("PUSHED = {}")
    pick(g, lines, "Offer it to the party")
    assert g.pushed() == [100]


def test_lines_that_cannot_be_used_are_grey_and_say_why(style):
    g = party(style, on_quest={"party1": [100]})
    menu, lines = open_menu(g)
    offer = next(b for b in lines if "Offer it" in plain(b.text))
    assert offer.text.startswith("|cff9d9d9d"), "grey: Anna has it already"
    pick(g, lines, "Offer it to the party")
    assert "everybody has it" in "\n".join(g.printed()) and menu.shown is True, "a grey line says why and stays open"
    where = next(b for b in lines if "where to get it" in plain(b.text))
    assert where.tipText.startswith("needs the Questie addon"), where.tipText


def test_focus_it_on_my_map(style):
    g = party(style)
    menu, lines = open_menu(g)
    focus = next(b for b in lines if "Focus it" in plain(b.text))
    if style == "classic":
        assert focus.tipText == "not on this client"
        return
    pick(g, lines, "Focus it on my map")
    assert g.eval("SUPER") == 100 and "is now the focus on your map" in "\n".join(g.printed())


def test_open_it_in_the_quest_log(style):
    pre = "QuestLogFrame = CreateFrame('Frame'); QuestLogFrame.shown = false; function ShowUIPanel(f) f.shown = true end"
    g = party(style, pre=pre)
    menu, lines = open_menu(g)
    pick(g, lines, "Open it in the quest log")
    assert g.eval("QuestLogFrame.shown") is True, "the old quest log window opens at the quest"


def test_a_quest_log_inside_the_world_map_is_never_opened_by_the_addon(style):
    """Opening the map from addon code makes the game refuse SetPassThroughButtons() in the addon's name."""
    pre = """MAP_OPENED = nil
    function QuestMapFrame_OpenToQuestDetails(id) MAP_OPENED = id end
    function ToggleWorldMap() MAP_OPENED = true end
    function OpenWorldMap() MAP_OPENED = true end
    SELECTED = nil
    if C_QuestLog then C_QuestLog.SetSelectedQuest = function(id) SELECTED = id end end"""
    g = party(style, pre=pre)
    menu, lines = open_menu(g)
    labels = [plain(b.text) for b in lines]
    assert "Select it in the quest log" in labels and "Open it in the quest log" not in labels
    pick(g, lines, "Select it in the quest log")
    assert g.eval("MAP_OPENED") is None, "the map is left to you"
    if style == "modern":
        assert g.eval("SELECTED") == 100 and "open your quest log (L)" in "\n".join(g.printed())


# ---- Questie: where to get it ---------------------------------------------------------------------------------------------
def test_with_questie_the_party_hears_where_a_quest_starts(style):
    for pre in (QUESTIE_12, QUESTIE_11):
        g = party(style, ("Anna", "Bob"), on_quest={"party1": [100]}, pre=pre)
        menu, lines = open_menu(g)
        pick(g, lines, "Tell them where to get it")
        msg, channel = g.sent()[-1]
        assert channel == "PARTY"
        assert msg.startswith("Bob: ") and "[Wolves Among Us]" in msg, msg
        assert msg.endswith('starts at Marshal McBride in Elwynn Forest (48.9, 41.6), after "A Threat Within" '
                            '(from Deputy Willem in Elwynn Forest (48.2, 42.9)), 1 more step before that.'), msg


def test_the_steps_before_are_counted_without_looping(style):
    g = party(style, pre=QUESTIE_12)
    assert g.eval("NS.questie.stepsBefore")(100) == 2, "A Threat Within, then Kobold Camp Cleanup"
    g.run("QUESTIE_QUESTS[7].preQuestSingle = { 100 }")         # a broken chain that loops back
    assert g.eval("NS.questie.stepsBefore")(100) <= 10


def test_a_quest_that_starts_from_an_item_says_who_drops_it(style):
    g = party(style, pre=QUESTIE_12)
    text = g.eval("NS.questie.whereText")(101)
    assert text == "starts from the item A Torn Letter, dropped by Kobold Vermin in Elwynn Forest (40.1, 80.2)", text


# ---- Trace back the chain: one chat line, from QuestieDB ---------------------------------------------------------------
def unlink(s):
    return re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", plain(s or ""))


def chain(g, qid=100):
    return unlink(g.eval("NS.chainMessage")(g.eval(f"NS.compat.findEntry({qid})")))


def test_the_chain_is_one_line_from_the_first_quest_to_this_one(style):
    for pre in (QUESTIE_12, QUESTIE_11):
        g = party(style, pre=LOADED + pre)
        g.run("QUESTIE_QUESTS[7].startedBy = { { 823 } }; QUESTIE_QUESTS[100].requiredLevel = 5")
        line = chain(g)
        assert "\n" not in line and len(g.eval("NS.chainMessage")(g.eval("NS.compat.findEntry(100)"))) <= 255
        assert line == ('[Wolves Among Us] (level 5+): 2 quests before it: "Kobold Camp Cleanup" at Deputy Willem in '
                        'Elwynn Forest 48.2, 42.9 > "A Threat Within" > then this one at Marshal McBride in Elwynn Forest '
                        '48.9, 41.6'), line


def test_a_quest_with_nothing_before_it_says_where_it_starts(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    g.run("QUESTS[#QUESTS + 1] = { id = 101, title = 'Report to Goldshire', level = 2, objectives = {} }")
    line = chain(g, 101)
    assert line == ("[Report to Goldshire]: no quests before it, starts at the item A Torn Letter, dropped by Kobold Vermin "
                    "in Elwynn Forest 40.1, 80.2"), line


def test_other_quests_that_also_lead_there_are_counted(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    g.run("QUESTIE_QUESTS[100].preQuestSingle = { 783, 784 }")           # either one is enough
    assert '"A Threat Within" (or 1 other) > then this one' in chain(g), chain(g)
    g.run("QUESTIE_QUESTS[100].preQuestSingle = nil; QUESTIE_QUESTS[100].preQuestGroup = { 783, 785, 786 }")
    assert '"A Threat Within" (+2 more) > then this one' in chain(g), chain(g)


def test_a_long_chain_still_fits_in_one_chat_line(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    g.run("""for i = 1, 20 do
        QUESTIE_QUESTS[1000 + i] = { name = "A rather long quest name in a chain, part " .. i,
                                     preQuestSingle = (i > 1) and { 1000 + i - 1 } or nil }
    end
    QUESTIE_QUESTS[1001].startedBy = { { 823 } }
    QUESTIE_QUESTS[100].preQuestSingle = { 1020 }""")
    raw = g.eval("NS.chainMessage")(g.eval("NS.compat.findEntry(100)"))
    line = unlink(raw)
    assert len(raw) <= 255, len(raw)
    assert line.startswith('[Wolves Among Us]: 20 quests before it: "A rather long quest name in a chain, part 1" at Deputy '
                           'Willem in Elwynn Forest 48.2, 42.9 > ('), "where it all starts is always kept: " + line
    assert " more) > " in line and line.endswith("then this one at Marshal McBride in Elwynn Forest 48.9, 41.6"), line


def test_a_chain_that_loops_back_does_not_hang(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    g.run("QUESTIE_QUESTS[7].preQuestSingle = { 100 }")
    assert "quests before it" in chain(g)


def test_in_a_party_the_chain_goes_to_the_party_and_alone_only_to_you(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    menu, lines = open_menu(g)
    pick(g, lines, "Trace back the chain")
    msg, channel = g.sent()[-1]
    assert channel == "PARTY" and "2 quests before it" in unlink(msg), g.sent()
    g.leave_party()
    g.advance(2)
    g.run("SENT = {}; PRINTED = {}")
    g.eval("NS.traceBack")(g.eval("NS.compat.findEntry(100)"))
    assert g.sent() == [] and "2 quests before it" in unlink("\n".join(g.printed()))


def test_without_questie_the_line_is_grey_and_says_why(style):
    g = party(style)
    menu, lines = open_menu(g)
    b = next(b for b in lines if "Trace back the chain" in plain(b.text))
    assert b.text.startswith("|cff9d9d9d") and "needs the Questie addon" in (b.tipText or "")


def test_the_tooltip_says_where_it_starts(style):
    g = party(style, pre=QUESTIE_12)
    g.eval("function(r) r.scripts.OnEnter(r) end")(row(g, "Wolves Among Us"))
    lines = [plain(l) for l in g.eval("TOOLTIP.lines").values()]
    assert any(l.startswith("It starts at Marshal McBride in Elwynn Forest") for l in lines), lines


def test_without_questie_nothing_breaks(style):
    g = party(style)
    assert g.eval("NS.questie.available()") is False and g.eval("NS.questie.whereText(100)") is None
    g.run("QuestieLoader = { ImportModule = function() error('not yet') end }")
    assert g.eval("NS.questie.available()") is False, "a loader that fails: no Questie"
    g.run("""Questie = { started = false }
             QuestieLoader = { ImportModule = function() return { QueryQuestSingle = function() return 'x' end } end }""")
    assert g.eval("NS.questie.available()") is False, "Questie still starting: wait for it"
    g.run("Questie.started = true")
    assert g.eval("NS.questie.available()") is True
    assert len(g.eval("NS.db.errors") or {}) == 0


def test_a_questie_that_looks_different_is_handled(style):
    g = party(style, pre="QuestDB = { Get = function() error('changed') end }")
    assert g.eval("NS.questie.whereText(100)") is None and len(g.eval("NS.db.errors") or {}) == 0


# ---- /qs questie: does it work here? -------------------------------------------------------------------------------------
LIB_ONLY = DATA + """
LibQuestieDB = { Quest = { Get = getter(QUESTIE_QUESTS) }, Npc = { Get = getter(QUESTIE_NPCS) },
                 Item = { Get = getter(QUESTIE_ITEMS) }, Object = { Get = getter({}) } }
C_Map.GetAreaInfo = function(id) return ({ [12] = "Elwynn Forest" })[id] end
"""
LOADED = 'LOADED_ADDONS = { Questie = true, QuestieDB = true }; function IsAddOnLoaded(n) return LOADED_ADDONS[n] == true end\n'


def report(g):
    g.run("PRINTED = {}")
    g.slash("questie")
    return "\n".join(plain(l) for l in g.printed())


def test_slash_questie_proves_it_with_a_quest_from_your_log(style):
    for pre, how in ((QUESTIE_12, "QuestieDB (Questie 12 and newer)"), (LIB_ONLY, "LibQuestieDB"),
                     (QUESTIE_11, "Questie's own database (older Questie)")):
        g = party(style, pre=LOADED + pre)
        text = report(g)
        assert "Questie: loaded" in text and "QuestieDB (Questie's quest data, its own folder since Questie 12): loaded" in text, text
        assert "reading: " + how in text, (how, text)
        assert "[Wolves Among Us]|h starts at Marshal McBride in Elwynn Forest (48.9, 41.6)" in text, text
        assert "Questie works with Quest Sharing." in text


def test_slash_questie_names_the_language_of_its_names(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    assert "names: enUS, the game's language" in report(g)
    g2 = party(style, pre=LOADED + QUESTIE_12 + "LibQuestieDB = { l10n = { currentLocale = 'frFR' } }\n")
    assert "Questie's names are in frFR, the game is in enUS" in report(g2)
    g3 = party(style, pre=LOADED + QUESTIE_11 + "Questie.db = { global = { questieLocaleDiff = true, questieLocale = 'deDE' } }\n")
    assert "Questie's names are in deDE, the game is in enUS" in report(g3), "older Questie: its language setting"


def test_slash_questie_says_what_is_missing(style):
    g = party(style, pre="LOADED_ADDONS = {}; function IsAddOnLoaded(n) return LOADED_ADDONS[n] == true end")
    text = report(g)
    assert "Questie: not loaded" in text and "-> no Questie found: install Questie (both folders" in text, text
    g2 = party(style, pre=LOADED + "Questie = { started = false }; QuestieLoader = { ImportModule = function() return {} end }")
    assert "still starting" in report(g2)


# The game's AddOns list: INSTALLED = { [folder] = reason or false (= fine) }; LOADED_ADDONS = loaded ones
ADDON_LIST = """
INSTALLED = INSTALLED or {}
local order = {}
for name in pairs(INSTALLED) do order[#order + 1] = name end
table.sort(order)
function GetNumAddOns() return #order end
function GetAddOnInfo(i)
    local name = type(i) == "number" and order[i] or i
    if INSTALLED[name] == nil then return name, nil, nil, false, "MISSING" end
    return name, name, "", INSTALLED[name] == false, INSTALLED[name] or nil
end
"""


def test_reported_questie_installed_without_its_database_says_what_to_do(style):
    """Reported: Questie is installed, Quest Sharing says it is missing - the QuestieDB folder was not."""
    pre = ('INSTALLED = { Questie = false }; LOADED_ADDONS = { Questie = true }; '
           'function IsAddOnLoaded(n) return LOADED_ADDONS[n] == true end\n' + ADDON_LIST)
    g = party(style, pre=pre)
    text = report(g)
    assert "Questie: loaded" in text and "QuestieDB (Questie's quest data, its own folder since Questie 12): not installed" in text
    assert "-> Questie 12 keeps its quest data in a second folder, QuestieDB, and it is missing" in text, text
    assert "Copy BOTH folders of the Questie download (Questie and QuestieDB)" in text
    assert g.eval("NS.questie.whyMissing()").startswith("Questie is here but its quest data (the QuestieDB folder) is missing")
    menu, lines = open_menu(g)
    chain = next(b for b in lines if "Trace back the chain" in plain(b.text))
    assert "QuestieDB folder" in chain.tipText, "the grey line says why too"


def test_questie_db_installed_but_switched_off_or_out_of_date(style):
    for reason, want in (("DISABLED", "switched off: tick it in the AddOns list"),
                         ("INTERFACE_VERSION", "marked out of date: tick \"Load out of date AddOns\"")):
        pre = (f'INSTALLED = {{ Questie = false, QuestieDB = "{reason}" }}; LOADED_ADDONS = {{ Questie = true }}; '
               'function IsAddOnLoaded(n) return LOADED_ADDONS[n] == true end\n' + ADDON_LIST)
        text = report(party(style, pre=pre))
        assert "-> QuestieDB is installed but " + want.split(": ")[0] in text and want in text, (reason, text)


def test_a_renamed_questie_folder_is_found_and_named(style):
    pre = ('INSTALLED = { ["Questie-master"] = false }; LOADED_ADDONS = { ["Questie-master"] = true }; '
           'function IsAddOnLoaded(n) return LOADED_ADDONS[n] == true end\n' + ADDON_LIST)
    text = report(party(style, pre=pre))
    assert "other folders with Questie in the name: Questie-master (loaded)" in text
    assert "-> Questie's folder has another name (Questie-master (loaded)): rename it to Questie" in text, text


def test_the_report_says_what_the_game_has(style):
    text = report(party(style, pre=LOADED + QUESTIE_12))
    assert "found in the game: QuestDB yes, LibQuestieDB no, QuestieLoader no" in text


def test_slash_questie_when_questie_knows_none_of_your_quests(style):
    g = party(style, pre=LOADED + "QuestDB = { Get = function() return nil end }")
    text = report(g)
    assert "Questie has no start for this quest" in text and "send me this report" in text


def test_the_doctor_names_where_questie_is_read_from(style):
    g = party(style, pre=LOADED + QUESTIE_12)
    assert "[OK] Questie: found (QuestieDB)" in "\n".join(g.eval("NS.doctorLines()").values())


# ---- the game's sound keys are never taken ---------------------------------------------------------------------------------
def test_the_quick_chat_never_takes_the_sound_keys(style):
    g = party(style)
    g.run('BINDINGS["CTRL-S"] = "TOGGLESOUND"; BINDINGS["CTRL-M"] = "TOGGLEMUSIC"; BINDINGS.ESCAPE = "TOGGLEGAMEMENU"')
    g.slash("key CTRL-S")
    assert g.eval("BINDINGS['CTRL-S']") == "TOGGLESOUND" and "toggle sound" in "\n".join(g.printed())
    g.slash("settings")
    g.eval("NS.captureKey")()
    g.run("CTRL = true")
    g.eval("NS.captureKeyPressed")("M")
    g.run("CTRL = false")
    assert g.eval("BINDINGS['CTRL-M']") == "TOGGLEMUSIC", "pressing Ctrl+M while setting the key changes nothing"


def test_the_doctor_reports_the_games_sound_settings_without_changing_them(style):
    g = party(style)
    g.run('CVARS.Sound_EnableAllSound = "1"; CVARS.Sound_EnableSFX = "0"')
    lines = "\n".join(g.eval("NS.doctorLines()").values())
    assert "game sound: on, effects OFF (Quest Sharing never changes these" in lines
    assert g.eval("CVARS.Sound_EnableSFX") == "0", "only read"
    assert "Questie: not found" in lines


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
