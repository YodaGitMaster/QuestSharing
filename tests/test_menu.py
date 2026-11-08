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
    return menu, [lines[i] for i in range(1, 7) if lines[i].shown]


def pick(g, lines, label):
    b = next(b for b in lines if label in plain(b.text))
    g.eval("function(b) b.scripts.OnClick(b, 'LeftButton') end")(b)


# ---- the menu ------------------------------------------------------------------------------------------------------------
def test_right_click_opens_a_small_menu_for_that_quest(style):
    g = party(style)
    menu, lines = open_menu(g)
    assert menu.shown is True and plain(menu.title.text) == "Wolves Among Us"
    assert [plain(b.text) for b in lines] == ["Tell the party how I am doing", "Offer it to the party", "Tell them where to get it",
                                             "Focus it on my map", "Open it in the quest log"]
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
    assert where.tipText == "needs the Questie addon"


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
    pre = "OPENED_LOG = nil; function QuestMapFrame_OpenToQuestDetails(id) OPENED_LOG = id end; QuestLogFrame = CreateFrame('Frame'); QuestLogFrame.shown = false; function ShowUIPanel(f) f.shown = true end"
    g = party(style, pre=pre)
    menu, lines = open_menu(g)
    pick(g, lines, "Open it in the quest log")
    if style == "modern":
        assert g.eval("OPENED_LOG") == 100
    else:
        assert g.eval("QuestLogFrame.shown") is True


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
