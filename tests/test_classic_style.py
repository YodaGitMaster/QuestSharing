"""Classic WoW menu look: every addon window is opaque stone inside the gold dialog border, buttons use the red panel art."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_quests import game as dungeon_game

STYLES = ("modern", "classic")
STONE = "Interface\\DialogFrame\\UI-DialogBox-Background"
BUTTON = "Interface\\Buttons\\UI-Panel-Button-Up"
RECORD = '''FILLS={} BACKS={} local fill=NS.style.fill
NS.style.fill=function(frame,layer,r,g,b,a) local t=fill(frame,layer,r,g,b,a); FILLS[t]=a; if (layer or 'BACKGROUND')=='BACKGROUND' then BACKS[#BACKS+1]=a end; return t end'''


def opened(style):
    g = dungeon_game(style, "", False)
    g.run(RECORD)
    g.slash("dungeons"); g.advance(90)
    g.run("NS.toggleSettings(true)")
    g.slash("log")
    return g


def stone(g, name):
    f = g.eval("_G['%s']" % name)
    assert f is not None, name
    assert f.stone is not None, name + " has no stone background"
    assert f.stone.tile.texture == STONE, name
    assert g.eval("FILLS")[f.stone.base] == 1, name + " stone base must be fully opaque"
    return f


def test_every_opened_window_is_opaque_stone(style):
    g = opened(style)
    for name in ("QuestSharingEquipment", "QuestSharingSettings", "QuestSharingReport"):
        stone(g, name)


def test_buttons_use_classic_panel_art_and_hidden_art_stays_hidden_after_click(style):
    g = opened(style)
    w = g.eval("NS.dungeonQuests._window()")
    b = w.reload
    assert b.bg.texture == BUTTON and b.highlightArt.texture.endswith("UI-Panel-Button-Highlight")
    b.bg.Hide(b.bg)
    b.scripts["OnMouseDown"](b); b.scripts["OnMouseUp"](b)
    assert b.bg.shown is False and b.pushedArt.shown is False, "text-only buttons keep their art hidden"


def test_journal_and_settings_drop_translucent_backgrounds(style):
    g = opened(style)
    # Dim washes (selection/hover tints at <=0.25) sit on top of an opaque base; anything 0.5-0.99 is a see-through panel.
    translucent = [a for a in g.eval("BACKS").values() if a is not None and 0.5 < a < 1]
    assert translucent == [], translucent


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"): continue
        for style in STYLES:
            total += 1
            try: fn(style); print("ok", name, style)
            except Exception as exc: failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
