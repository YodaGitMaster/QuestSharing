"""Dungeon Journal look, stream A: the shared theme (JournalTheme.lua) and the home card grid (DungeonHomeUI.lua)."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_quests import game
from test_loot import click

STYLES = ("modern", "classic")
ROWS = r'''
HOME_ROWS = {
 {area=1581,name="The Deadmines",minLevel=17,maxLevel=26,total=8,open=3,done=5,alliance=true,horde=false},
 {area=16919,name="The Hall of Thanes",minLevel=13,maxLevel=20,total=5,open=0,done=5,alliance=true,horde=true},
 {area=2437,name="Ragefire Chasm",minLevel=13,maxLevel=18,total=6,open=6,done=0,alliance=false,horde=true},
 {area=99999,name="Unknown Hole",minLevel=30,maxLevel=30,total=0,open=0,done=0},
}
OPENED_AREAS = {}
'''


def home(style, extra=""):
    g = game(style, ROWS + extra, open_tab=False)
    g.run("NS.dungeonHomeUI.build(UIParent, 1000, 560, function(area) OPENED_AREAS[#OPENED_AREAS+1] = area end)")
    g.run("NS.dungeonHomeUI.refresh(HOME_ROWS)")
    return g, g.eval("NS.dungeonHomeUI._frame()")


def visible(f):
    return [c.row.name for c in f.cards.values() if c.shown and c.row]


def card(f, name):
    for c in f.cards.values():
        if c.row and c.row.name == name and c.shown:
            return c
    raise AssertionError(name + " has no card")


def type_search(f, text):
    f.search.SetText(f.search, text)
    f.search.scripts.OnTextChanged(f.search, True)


def test_card_art_table_covers_every_dungeon_with_the_crop(style):
    g = game(style, open_tab=False)
    names = g.eval("NS.dungeonQuestData.names")
    assert len(list(names.keys())) == 28
    for area in names.keys():
        assert g.eval("(NS.journalTheme.cardArt(%d))" % area) is not None, names[area]
    art = g.eval("{NS.journalTheme.cardArt(1581)}")
    assert art[1] == "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines"
    assert [art[i] for i in (2, 3, 4, 5)] == [.02, .98, .24, .82]
    assert g.eval("(NS.journalTheme.cardArt(16611))") == 7963782
    assert g.eval("(NS.journalTheme.cardArt(16919))") == 7963781
    assert g.eval("(NS.journalTheme.cardArt('Ruins of Lordaeron'))") == 7963782
    assert g.eval("(NS.journalTheme.cardArt(99999))") is None
    for name in ("JournalTheme.lua", "DungeonHomeUI.lua"):   # client art only, never the other addon's media
        assert "ForeverDungeonJournal" not in (pathlib.Path(__file__).resolve().parent.parent / "QuestSharing" / name).read_text()


def test_card_art_is_checked_where_the_client_can_tell(style):
    g = game(style, "GetFileIDFromPath=function(p) if p:find('Monastery$') then return nil end if p:find('Deadmines') then return 1 end end", open_tab=False)
    assert g.eval("(NS.journalTheme.cardArt(1581))") == "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines"
    assert g.eval("(NS.journalTheme.cardArt(209))") is None          # not in this client
    assert g.eval("(NS.journalTheme.cardArt(16550))") == 7963741     # FileDataIDs are used as they are


def test_lfg_icons_for_classic_dungeons_and_ruins(style):
    g = game(style, open_tab=False)
    assert g.eval("NS.journalTheme.lfgIcon(1581)") == "Interface\\LFGFrame\\LFGIcon-Deadmines"
    assert g.eval("NS.journalTheme.lfgIcon(1176)") == "Interface\\LFGFrame\\LFGIcon-ZulFarak"
    assert g.eval("NS.journalTheme.lfgIcon(16611)") == "Interface\\LFGFrame\\LFGIcon-RuinsOfLordaeron"
    assert g.eval("NS.journalTheme.lfgIcon(16919)") is None


def test_theme_builders_use_client_textures(style):
    g = game(style, "CLICKED_THEME=0", open_tab=False)
    T = g.eval("NS.journalTheme")
    f = g.eval("CreateFrame('Frame', nil, UIParent)")
    T.panel(f, "header")
    assert f.jFill.rgba[1] == g.eval("NS.journalTheme.C.header[1]") and f.jPage.texture == "Interface\\QuestFrame\\QuestBG"
    assert f.jEdge.edgeSize == 12
    b = g.eval("NS.journalTheme.button(UIParent, 'Share', 80, function() CLICKED_THEME=CLICKED_THEME+1 end)")
    assert b.label.text == "Share" and b.hl.texture == "Interface\\QuestFrame\\UI-QuestTitleHighlight"
    click(b); assert g.eval("CLICKED_THEME") == 1
    tab = g.eval("NS.journalTheme.tab(UIParent, 'Bosses', 'Interface\\\\TargetingFrame\\\\UI-RaidTargetingIcon_8', 110)")
    assert tab.icon.texture.endswith("UI-RaidTargetingIcon_8") and not tab.selected
    tab.SetSelected(tab, True); assert tab.selected and tab.mark.shown
    tab.SetSelected(tab, False); assert not tab.selected and not tab.mark.shown
    xp, rep, money = (g.eval("NS.journalTheme.pill(UIParent, '%s', '%s')" % (k, t)) for k, t in (("xp", "2,300 XP"), ("rep", "+250"), ("money", "1g")))
    assert xp.text.text == "2,300 XP" and xp.bg.rgba[3] > xp.bg.rgba[2]          # purple
    assert rep.bg.rgba[2] > rep.bg.rgba[1] and money.icon.texture.endswith("UI-GoldIcon")
    xp.SetText(xp, "100 XP"); assert xp.text.text == "100 XP"
    crest = g.eval("NS.journalTheme.crest(UIParent, 'Horde', 18)")
    assert crest.texture == "Interface\\TargetingFrame\\UI-PVP-Horde" and crest.width == 18 and list(crest.coords.values()) == [0, .625, 0, .625]
    badge = g.eval("NS.journalTheme.badge(UIParent, 20, 28)")
    assert badge.text.text == "20" and badge.disc.texture.endswith("TempPortraitAlphaMask") and badge.ring.texture.endswith("MiniMap-TrackingBorder")
    badge.SetLevel(badge, 42); assert badge.text.text == "42"
    assert g.eval("NS.journalTheme.tick(UIParent).texture") == "Interface\\RaidFrame\\ReadyCheck-Ready"
    icon = g.eval("UIParent:CreateTexture()")
    T.round(icon, g.eval("UIParent"), 40)
    assert icon.jRing.texture == "Interface\\Common\\GoldRing" and icon.width == 40


def test_template_tab_moves_its_label_right_of_the_icon(style):
    g = game(style, "", open_tab=False)
    # a client whose UIPanelButtonTemplate gives a centred font string
    g.run("""
local create=CreateFrame
CreateFrame=function(kind,name,parent,template,...)
  local f=create(kind,name,parent,template,...)
  if template=="UIPanelButtonTemplate" then
    local fs=f:CreateFontString(nil,"OVERLAY");fs.points={}
    local setPoint=fs.SetPoint
    fs.SetPoint=function(self,p,rel,...) self.points[p]=rel;return setPoint(self,p,rel,...) end
    fs.ClearAllPoints=function(self) self.points={} end
    fs:SetPoint("CENTER",f,"CENTER",0,0)
    f.GetFontString=function() return fs end
    f.SetText=function(self,t) fs:SetText(t) end
  end
  return f
end""")
    tab = g.eval("NS.journalTheme.tab(UIParent, 'Bosses', 'Interface\\\\TargetingFrame\\\\UI-RaidTargetingIcon_8', 90)")
    assert tab.template
    assert g.eval("(function(t) local fs=t:GetFontString(); return fs.points.LEFT==t.icon and fs.points.RIGHT==t and not fs.points.CENTER end)")(tab)
    plain = g.eval("NS.journalTheme.tab(UIParent, 'Map', nil, 90)")
    assert g.eval("(function(t) return t:GetFontString().points.CENTER==t end)")(plain), "no icon: the label stays centred"


def test_cards_show_art_or_fallback_level_counts_and_tick(style):
    g, f = home(style)
    assert visible(f) == ["The Deadmines", "The Hall of Thanes", "Ragefire Chasm", "Unknown Hole"]
    dm, thanes, rfc, unknown = (card(f, n) for n in visible(f))
    assert dm.width == 488 and dm.height == 126          # (1000 - 2*6 margin - 12 gap) / 2: the grid fills the page
    assert dm.artFile.endswith("LoadScreenDeadmines") and not dm.fallback and list(dm.art.coords.values()) == [.02, .98, .24, .82]
    assert thanes.artFile == 7963781
    assert unknown.fallback and unknown.artFile.endswith("UI-Background-Rock")
    assert dm.title.text == "The Deadmines" and dm.lv.text == "LV 17-26" and dm.count.text == "3/8 quests"
    assert unknown.lv.text == "LV 30" and unknown.count.text == "0/0 quests"
    assert thanes.tick.shown and not dm.tick.shown and not unknown.tick.shown   # nothing left vs no quests at all
    assert dm.crests.Alliance.shown and not dm.crests.Horde.shown
    assert thanes.crests.Alliance.shown and thanes.crests.Horde.shown
    assert dm.band.height == 42
    # 2 columns, 138 px rows, 12 px gap
    assert dm.point[3] == "TOPLEFT" and (dm.point[4], dm.point[5]) == (0, 0)
    assert (thanes.point[4], thanes.point[5]) == (500, 0) and (rfc.point[4], rfc.point[5]) == (0, -138)
    assert f.scroll.width == 988 and f.content.width == 988 and f.scroll.point[4] == 6
    assert f.content.height == 276 and f.status.text == ""


def test_hover_turns_the_border_gold_and_click_opens(style):
    g, f = home(style)
    dm = card(f, "The Deadmines")
    gold = list(g.eval("NS.journalTheme.GOLD").values())
    plain = list(g.eval("NS.journalTheme.C.border").values())
    assert list(dm.edges[1].rgba.values()) == plain
    dm.scripts.OnEnter(dm)
    assert all(list(e.rgba.values()) == gold for e in dm.edges.values())
    dm.scripts.OnLeave(dm)
    assert list(dm.edges[4].rgba.values()) == plain
    click(dm)
    click(card(f, "Ragefire Chasm"))
    assert list(g.eval("OPENED_AREAS").values()) == [1581, 2437]


def test_search_and_crest_filters(style):
    g, f = home(style)
    type_search(f, "DEAD")
    assert visible(f) == ["The Deadmines"]
    type_search(f, "zzz")
    assert visible(f) == [] and "No dungeon" in f.status.text
    type_search(f, "")
    assert len(visible(f)) == 4
    click(f.horde)
    assert visible(f) == ["The Hall of Thanes", "Ragefire Chasm"] and f.horde.selected and not f.alliance.selected
    click(f.alliance)
    assert visible(f) == ["The Deadmines", "The Hall of Thanes"] and f.alliance.selected and not f.horde.selected
    type_search(f, "ragefire")
    assert visible(f) == []
    click(f.alliance)                       # again: all factions
    assert visible(f) == ["Ragefire Chasm"] and f.faction is None
    # the card the filter moved keeps its click target
    click(card(f, "Ragefire Chasm"))
    assert list(g.eval("OPENED_AREAS").values()) == [2437]


def test_wheel_scrolls_one_row_and_refresh_reads_summaries(style):
    g, f = home(style)
    f.scroll.scrollRange = 500
    f.scroll.scripts.OnMouseWheel(f.scroll, -1)
    assert f.scroll.GetVerticalScroll(f.scroll) == 138
    f.scroll.scripts.OnMouseWheel(f.scroll, 1)
    f.scroll.scripts.OnMouseWheel(f.scroll, 1)
    assert f.scroll.GetVerticalScroll(f.scroll) == 0
    g.run("NS.dungeonQuests.summaries = function() return {HOME_ROWS[3]} end")
    g.run("NS.dungeonHomeUI.refresh()")
    assert visible(f) == ["Ragefire Chasm"]
    g.run("NS.dungeonHomeUI.refresh({})")
    assert visible(f) == [] and "Reading" in f.status.text
    g.run("NS.dungeonHomeUI.hide()"); assert not f.shown
    g.run("NS.dungeonHomeUI.show()"); assert f.shown


def test_grid_width_follows_the_page_width(style):
    g = game(style, ROWS, open_tab=False)
    assert g.eval("NS.dungeonHomeUI.cardWidth(1000)") == 488
    assert g.eval("NS.dungeonHomeUI.cardWidth(800)") == 388
    g.run("NS.dungeonHomeUI.build(UIParent, 800, 500)")
    g.run("NS.dungeonHomeUI.refresh(HOME_ROWS)")
    f = g.eval("NS.dungeonHomeUI._frame()")
    dm, thanes = card(f, "The Deadmines"), card(f, "The Hall of Thanes")
    assert dm.width == 388 and dm.height == 126 and thanes.point[4] == 400
    assert list(dm.art.coords.values()) == [.02, .98, .24, .82]   # the art crop is kept


def test_home_search_clear_button(style):
    g, f = home(style)
    clear = f.search.clear
    assert clear.icon.texture == "Interface\\Buttons\\UI-StopButton" and not clear.shown
    type_search(f, "dead")
    assert clear.shown and not f.search.hint.shown and visible(f) == ["The Deadmines"]
    click(clear)
    assert f.search.GetText(f.search) == "" and f.query == "" and not clear.shown and f.search.hint.shown
    assert len(visible(f)) == 4
    type_search(f, "rage")
    f.search.scripts.OnEscapePressed(f.search)
    assert not clear.shown and len(visible(f)) == 4


def test_home_search_clear_button_without_its_texture_shows_an_x(style):
    g, f = home(style, "GetFileIDFromPath=function(p) if p:find('UI%-StopButton') then return nil end return 1 end")
    clear = f.search.clear
    assert clear.icon is None and clear.label.text == "x", "a missing texture never leaves an invisible button"
    type_search(f, "dead")
    assert clear.shown
    click(clear)
    assert f.query == "" and not clear.shown


def test_done_cards_glow_behind_the_tick(style):
    g, f = home(style)
    thanes, dm, unknown = card(f, "The Hall of Thanes"), card(f, "The Deadmines"), card(f, "Unknown Hole")
    assert thanes.glow.shown and thanes.tick.shown and thanes.glow.texture == "Interface\\Cooldown\\star4"
    assert thanes.glow.blend == "ADD" and thanes.glow.point[1] == "CENTER"
    assert g.eval("(function(c) return c.glow.point[2] == c.tick end)")(thanes)
    assert not dm.glow.shown and not unknown.glow.shown
    # a card reused for another dungeon drops the glow
    g.run("NS.dungeonHomeUI.refresh({HOME_ROWS[1]})")
    assert not card(f, "The Deadmines").glow.shown


def test_glow_class_dungeon_and_chain_icons(style):
    g = game(style, open_tab=False)
    glow = g.eval("NS.journalTheme.glow(UIParent, 30)")
    assert glow.texture == "Interface\\Cooldown\\star4" and glow.blend == "ADD" and glow.width == 30
    war = g.eval("NS.journalTheme.classIcon(UIParent, 14, 'WARRIOR')")
    assert war.texture == "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES" and war.width == 14
    assert list(war.coords.values()) == list(g.eval("CLASS_ICON_TCOORDS.WARRIOR").values())
    assert list(g.eval("NS.journalTheme.classIcon(UIParent, 14, 'priest')").coords.values()) == [0.5, 0.75, 0.25, 0.5]
    # a class the client table lacks: the theme's own copy of the sheet layout
    assert list(g.eval("NS.journalTheme.classIcon(UIParent, 14, 'PALADIN')").coords.values()) == [0, .25, .5, .75]
    g.run("CLASS_ICON_TCOORDS=nil")
    assert list(g.eval("NS.journalTheme.classIcon(UIParent, 14, 'MAGE')").coords.values())[0] == .25
    # dungeon icon: the "Dungeon" atlas when the client has it, else the rune icon
    rune = g.eval("NS.journalTheme.dungeonIcon(UIParent, 16)")
    assert rune.texture == "Interface\\Icons\\INV_Misc_Rune_01" and rune.atlas is None
    g.run("""local create=UIParent.CreateTexture
UIParent.CreateTexture=function(self,...) local t=create(self,...); t.SetAtlas=function(s,a) s.setAtlas=a end; return t end""")
    atlas = g.eval("NS.journalTheme.dungeonIcon(UIParent, 16)")
    assert atlas.atlas == "Dungeon" and atlas.setAtlas == "Dungeon" and atlas.texture is None
    g.run("C_Texture={GetAtlasInfo=function(name) return nil end}")
    assert g.eval("NS.journalTheme.dungeonIcon(UIParent, 16)").texture == "Interface\\Icons\\INV_Misc_Rune_01"
    g.run("C_Texture={GetAtlasInfo=function(name) if name=='Dungeon' then return {} end end}")
    assert g.eval("NS.journalTheme.dungeonIcon(UIParent, 16)").atlas == "Dungeon"
    # chain icon: first listfile icon the client has, else the note
    g.run("GetFileIDFromPath=nil")
    assert g.eval("NS.journalTheme.chainIcon(UIParent, 16)").texture == "Interface\\Icons\\Spell_Frost_ChainsOfIce"
    g.run("GetFileIDFromPath=function(p) if p:find('WartornScrap') then return 134515 end end")
    assert g.eval("NS.journalTheme.chainIcon(UIParent, 16)").texture == "Interface\\Icons\\INV_Misc_WartornScrap_Chain"
    g.run("GetFileIDFromPath=function(p) return nil end")
    chain = g.eval("NS.journalTheme.chainIcon(UIParent, 16)")
    assert chain.texture == "Interface\\Icons\\INV_Misc_Note_01" and list(chain.coords.values()) == [.08, .92, .08, .92]


def test_new_texture_paths_are_in_the_client_listfile(style):
    lf = pathlib.Path("/tmp/listfile/lf.csv")
    if not lf.exists():
        return
    known = set()
    with lf.open(errors="ignore") as fh:
        for line in fh:
            known.add(line.split(";", 1)[-1].strip().lower())
    g = game(style, open_tab=False)
    paths = [g.eval("NS.journalTheme.GLOW"), g.eval("NS.journalTheme.CLASS_SHEET"), g.eval("NS.journalTheme.DUNGEON_FALLBACK"),
             g.eval("NS.journalTheme.CHAIN_FALLBACK"), "Interface\\Buttons\\UI-StopButton"] + list(g.eval("NS.journalTheme.CHAIN_ICONS").values())
    for p in paths:
        assert p.replace("\\", "/").lower() + ".blp" in known, p


# Round 3 (stream L): the card hover tooltip.
def test_card_hover_tooltip_name_levels_counts_and_journal_text(style):
    g, f = home(style)
    dm = card(f, "The Deadmines")
    dm.scripts.OnEnter(dm)
    assert g.eval("TOOLTIP.shown") and g.eval("TOOLTIP.text") == "The Deadmines"
    lines = list(g.eval("TOOLTIP.lines").values())
    assert lines[0] == "Level 17-26"
    assert lines[1] == "8 quests: 3 to pick up, 5 done"
    assert lines[2].startswith("It is said the Deadmines' gold deposits")
    assert lines[-1] == "Click to open the dungeon."
    dm.scripts.OnLeave(dm)
    assert not g.eval("TOOLTIP.shown")
    rfc = card(f, "Ragefire Chasm")
    rfc.scripts.OnEnter(rfc)
    assert list(g.eval("TOOLTIP.lines").values())[1] == "6 quests: 6 to pick up"   # nothing done: no done count
    assert not g.eval("NS.db.errors")


def test_card_hover_without_journal_text(style):
    g, f = home(style)
    thanes = card(f, "The Hall of Thanes")                 # a Forever dungeon: its hand-written intro shows in the tooltip
    thanes.scripts.OnEnter(thanes)
    assert list(g.eval("TOOLTIP.lines").values())[:3] == ["Level 13-20", "5 quests: 0 to pick up, 5 done", "Hidden beneath the High Seat of Ironforge, the Hall of Thanes is the resting place of the legendary dwarves of the Eastern Kingdoms. Now the Dark Iron dwarves have invaded it, and it is part of the old Ironforge that was sealed away until Forever."]
    unknown = card(f, "Unknown Hole")
    unknown.scripts.OnEnter(unknown)
    assert list(g.eval("TOOLTIP.lines").values())[0] == "Level 30"
    g.run("NS.dungeonLore=nil")                             # the lore file missing: still a tooltip, no error
    dm = card(f, "The Deadmines")
    dm.scripts.OnEnter(dm)
    assert g.eval("TOOLTIP.text") == "The Deadmines" and len(list(g.eval("TOOLTIP.lines").values())) == 3
    g.run("NS.dungeonLore={dungeon=function() error('boom') end}")
    dm.scripts.OnEnter(dm)
    assert g.eval("TOOLTIP.shown") and len(list(g.eval("TOOLTIP.lines").values())) == 3
    assert not g.eval("NS.db.errors")


def test_card_hover_tooltip_wraps_the_description(style):
    g, f = home(style, "WRAPS={}; local add=GameTooltip.AddLine; GameTooltip.AddLine=function(t,s,r,g,b,w) WRAPS[#WRAPS+1]=w and true or false; return add(t,s,r,g,b,w) end")
    dm = card(f, "The Deadmines")
    dm.scripts.OnEnter(dm)
    assert list(g.eval("WRAPS").values()) == [False, False, True, False]

if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES:
            total += 1
            try:
                fn(style); print("ok", name, style)
            except Exception as exc:
                failed += 1; print("FAIL", name, style, type(exc).__name__, str(exc)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))
