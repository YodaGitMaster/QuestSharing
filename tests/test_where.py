"""Showing each other where you are: the star over my head, positions on the world map, a pin where a teammate found the
items, the world pin preferring a quest we share, and the ring's group-up line.        python tests/test_where.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game, OPEN_101  # noqa: E402

STYLES = ("modern", "classic")
WORLD_MAP = """
WORLDMAP_ID = 1429
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.ScrollContainer = { Child = CreateFrame("Frame") }
WorldMapFrame.ScrollContainer.Child.width, WorldMapFrame.ScrollContainer.Child.height = 1000, 700
function WorldMapFrame:GetMapID() return WORLDMAP_ID end
function WorldMapFrame:HookScript(name, fn) self.hooked = self.hooked or {}; self.hooked[name] = fn end
"""


def party(style, names=("Anna",), pre=""):
    g = Game(style, pre)
    g.start()
    g.slash("auto off")
    g.join_party(list(names))
    g.advance(3)
    return g


def peer(g, name="Anna", listed="999:0:1/2"):
    g.peer(name, "H|1")
    g.peer(name, "L|1|1|" + listed)


# ---- the star over my head -----------------------------------------------------------------------------------------
def test_the_star_goes_on_me_in_a_party(style):
    g = party(style)
    assert g.eval("RAID_ICONS.player") == 1


def test_the_star_is_never_taken_back_from_someone_who_used_it(style):
    g = party(style)
    g.run("RAID_ICONS.player = nil; RAID_ICONS.target = 1")          # the tank put the star on a mob
    g.join_party(["Anna", "Bob"])
    g.advance(3)
    assert g.eval("RAID_ICONS.player") is None, "no tug of war"


def test_no_star_alone_in_a_raid_or_in_a_dungeon(style):
    alone = Game(style)
    alone.start()
    alone.advance(3)
    assert alone.eval("RAID_ICONS.player") is None
    g = party(style)
    g.run("IN_INSTANCE = true")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(3)
    assert g.eval("RAID_ICONS.player") is None, "taken off inside a dungeon: the tank may need it"
    g.run("IN_INSTANCE = false")
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(3)
    assert g.eval("RAID_ICONS.player") == 1, "and back outside"
    r = Game(style)
    r.start()
    r.run("RAID = true")
    r.join_party(["Anna"])
    r.advance(3)
    assert r.eval("RAID_ICONS.player") is None


def test_switching_it_off_takes_the_star_off(style):
    g = party(style)
    g.slash("star off")
    assert g.eval("RAID_ICONS.player") is None and g.eval("NS.db.selfMark") is False
    g.slash("star on")
    assert g.eval("RAID_ICONS.player") == 1


# ---- my position to the other Quest Sharing users --------------------------------------------------------------------
def positions(g):
    return [m for m in g.addon_sent() if m.startswith("M|")]


def test_my_position_goes_to_quest_sharing_users_while_i_move(style):
    g = party(style)
    g.advance(12)
    assert positions(g) == [], "nobody with the addon: nothing is sent"
    peer(g)
    g.advance(11)
    assert positions(g) == ["M|1429|0.4230|0.6180"]
    g.advance(30)
    assert len(positions(g)) == 1, "standing still: not every 10 seconds"
    g.run("POS = { x = 0.5, y = 0.6 }")
    g.advance(11)
    assert positions(g)[-1] == "M|1429|0.5000|0.6000"


def test_no_position_when_switched_off_or_in_a_dungeon(style):
    g = party(style)
    peer(g)
    g.slash("mappins off")
    g.advance(30)
    assert positions(g) == []
    g.slash("mappins on")
    g.run("POS = nil")                                               # inside a dungeon the game gives no map position
    g.advance(30)
    assert positions(g) == []


# ---- their positions on my world map ------------------------------------------------------------------------------------
def test_a_quest_sharing_user_shows_on_my_world_map(style):
    g = party(style, pre=WORLD_MAP)
    g.run('CLASSES.Anna = "MAGE"')
    peer(g)
    g.run("WorldMapFrame.shown = true")
    g.peer("Anna", "M|1429|0.2500|0.5000")
    pin = g.eval("NS._mapPins().anna")
    assert pin.shown is True and pin.who == "Anna" and pin.icon.coords[1] == 0.25, "her class icon"
    assert (pin.point[4], pin.point[5]) == (250, -350), "a quarter across, half down"
    g.run("WORLDMAP_ID = 1436")                                      # looking at another zone
    g.eval("WorldMapFrame.hooked.OnShow")()
    assert pin.shown is False
    g.run("WORLDMAP_ID = 1429")
    g.advance(130)
    g.eval("WorldMapFrame.hooked.OnShow")()
    assert pin.shown is False, "an old position is not shown"


def test_the_map_pins_can_be_switched_off(style):
    g = party(style, pre=WORLD_MAP)
    peer(g)
    g.run("WorldMapFrame.shown = true")
    g.peer("Anna", "M|1429|0.2500|0.5000")
    g.slash("mappins off")
    assert g.eval("NS._mapPins().anna").shown is False


# ---- a pin where a teammate found the items --------------------------------------------------------------------------------
def test_a_teammates_find_becomes_a_pin_on_my_map(style):
    g = party(style)
    peer(g, listed="100:0:3/8,2/4")
    g.peer("Anna", "S|100|1429|0.3000|0.4000|Wolf Pelt")
    assert dict(g.eval("WAYPOINT").items()) == {"map": 1429, "x": 0.3, "y": 0.4}
    assert "Anna found Wolf Pelt for" in "\n".join(g.printed()) and "30.0, 40.0" in "\n".join(g.printed())


def test_no_pin_for_a_quest_i_do_not_have_or_have_finished_or_when_switched_off(style):
    g = party(style)
    peer(g)
    g.peer("Anna", "S|999|1429|0.3000|0.4000|Boar Tusk")
    assert g.eval("WAYPOINT") is None
    g.peer("Anna", "S|101|1429|0.3000|0.4000|Letter")              # 101 is finished for me
    assert g.eval("WAYPOINT") is None
    g.slash("waypoint off")
    g.peer("Anna", "S|100|1429|0.3000|0.4000|Wolf Pelt")
    assert g.eval("WAYPOINT") is None


# ---- the world pin prefers a quest we share -------------------------------------------------------------------------------
def test_in_a_party_the_pin_goes_to_the_nearest_quest_we_share(style):
    if style != "modern":
        return                                                        # no distances on the classic client
    g = Game(style)
    g.run(OPEN_101)                                   # two quests in progress
    g.start()
    g.slash("auto off")
    g.run('ON_QUEST["party1"] = {[101] = true}')
    g.set_dist(q100=400, q101=900, q102=2500, q200=10000)
    g.join_party(["Anna"])
    g.slash("near 2")
    g.slash("near on")
    g.advance(6)
    assert g.eval("SUPER") == 101, "100 is nearer, but Anna and I both have 101"


# ---- the ring: "Doing [quest] here - anyone want to group up?" in /s -----------------------------------------------
def test_the_group_up_line_names_my_nearest_quest_and_goes_to_say(style):
    g = Game(style, fresh=True)
    g.fire("ADDON_LOADED", "QuestSharing")
    g.fire("PLAYER_ENTERING_WORLD")
    item = g.eval("NS.quickItems()[2]")
    assert item.label == "Team up?" and item.channel == "say"
    text = g.eval("NS.quickResolve")(item.text)
    assert text.startswith("Doing |cffffff00|Hquest:") and text.endswith("here - anyone want to group up?")


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
