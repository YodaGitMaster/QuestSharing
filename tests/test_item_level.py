"""Item levels of other players (inspect nearby, Quest Sharing users answer) and the party finder filters.
python tests/test_item_level.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_lfg_invite import LFG  # noqa: E402

STYLES = ("modern", "classic")

# gear: EQUIP[unit][slot] = item level; links are "item:<level>:<slot>"; slot 16 of "target" is a two-hand weapon
GEAR = """
EQUIP = { player = {}, target = {} }
for _, s in ipairs({1, 3, 5, 6, 7, 8, 9, 10}) do EQUIP.player[s] = 30; EQUIP.target[s] = 20 end
EQUIP.player[16] = 40
EQUIP.target[16] = 26
function GetInventoryItemLink(unit, slot) local l = EQUIP[unit] and EQUIP[unit][slot] return l and ("item:" .. l .. ":" .. slot) or nil end
local oldInfo = GetItemInfo
function GetItemInfo(link)
    local l, slot = string.match(tostring(link), "^item:(%d+):(%d+)$")
    if not l then return oldInfo and oldInfo(link) end
    local loc = (tonumber(slot) == 16 and EQUIP.target[16] == tonumber(l)) and "INVTYPE_2HWEAPON" or "INVTYPE_CHEST"
    return "Thing", link, 2, tonumber(l), 1, "Armor", "Cloth", 1, loc
end
INSPECTED = {}
TARGET_PLAYER = nil      -- { name =, guid =, near = true }
local oldExists, oldName, oldNear = UnitExists, UnitName, CheckInteractDistance
function UnitExists(u) if u == "target" and TARGET_PLAYER then return true end return oldExists and oldExists(u) end
function UnitIsPlayer(u) return u == "target" and TARGET_PLAYER ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitGUID(u) return u == "target" and TARGET_PLAYER and TARGET_PLAYER.guid or nil end
function CanInspect(u) return TARGET_PLAYER ~= nil end
function CheckInteractDistance(u, i) if u == "target" and TARGET_PLAYER then return TARGET_PLAYER.near end return oldNear(u, i) end
function UnitName(u) if u == "target" and TARGET_PLAYER then return TARGET_PLAYER.name end return oldName(u) end
function NotifyInspect(u) INSPECTED[#INSPECTED + 1] = u end
"""


def game(style):
    g = Game(style, LFG + GEAR)
    g.start()
    return g


def addon(g, text, sender):
    g.fire("CHAT_MSG_ADDON", "QSILVL", text, "WHISPER", sender)


def test_my_item_level_counts_the_equipped_items(style):
    g = game(style)
    assert g.eval("NS.itemLevel.mine()") == 31                     # 8 x 30 + 40 over 9 items


def test_a_quest_sharing_user_who_asks_gets_my_number_unless_sharing_is_off(style):
    g = game(style)
    addon(g, "Q", "Bob")
    assert "M:31" in g.addon_sent()
    g.run("ADDON_SENT = {}; NS.setSetting('ilvlShare', false)")
    addon(g, "Q", "Bob")
    assert g.addon_sent() == []


def test_inspecting_a_nearby_target_remembers_its_item_level_and_shares_it(style):
    g = game(style)
    g.run("TARGET_PLAYER = { name = 'Tess', guid = 'G1', near = false }")
    g.fire("PLAYER_TARGET_CHANGED")
    assert len(g.eval("INSPECTED")) == 0, "too far: no inspect"
    g.run("TARGET_PLAYER.near = true")
    g.fire("PLAYER_TARGET_CHANGED")
    assert list(g.eval("INSPECTED").values()) == ["target"]
    g.fire("INSPECT_READY", "G1")
    assert g.eval("(NS.itemLevel.known('Tess'))") == 21              # (8 x 20 + two-hand 26 counted twice) / 10
    addon(g, "Q:Tess", "Bob")
    assert any(t.startswith("S:Tess:21:") for t in g.addon_sent())


def test_min_item_level_waits_for_the_answer_and_invites_when_high_enough(style):
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [] and "Q" in g.addon_sent(), "asked Lia first"
    addon(g, "M:33", "Lia")
    assert g.invited() == ["Lia"]
    assert any("invited Lia 24 Priest (healer, ilvl 33)" in p for p in g.printed())


def test_a_low_answer_is_skipped(style):
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30)")
    g.eval("NS.lfgInvite.scan")()
    addon(g, "M:21", "Lia")
    assert g.invited() == []
    assert any("skipped Lia" in p and "below item level 30" in p for p in g.printed())


def test_no_answer_follows_the_unknown_choice(style):
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30)")
    g.eval("NS.lfgInvite.scan")()
    g.advance(3)
    assert g.invited() == ["Lia"], "unknown: invite anyway (default)"
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30); NS.setSetting('lfgUnknown', 'skip')")
    g.eval("NS.lfgInvite.scan")()
    g.advance(3)
    assert g.invited() == []
    assert any("item level unknown" in p for p in g.printed())


def test_a_remembered_number_decides_at_once(style):
    g = game(style)
    g.run("NS.setSetting('lfgMinIlvl', 30); NS.itemLevel.remember('Lia', 35)")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"]
    g.slash("ilvl")
    assert any("my item level: 31" in p for p in g.printed())


def test_character_level_range(style):
    g = game(style)
    g.slash("lfg level 10 23")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == [], "Lia is level 24"
    g.slash("lfg level 24 30")
    g.eval("NS.lfgInvite.scan")()
    assert g.invited() == ["Lia"]


def test_forget_clears_the_numbers(style):
    g = game(style)
    g.run("NS.itemLevel.remember('Lia', 35)")
    g.run("NS.itemLevel.forget()")
    assert g.eval("NS.itemLevel.known('Lia')") is None


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
