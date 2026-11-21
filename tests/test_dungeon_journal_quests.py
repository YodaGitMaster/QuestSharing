"""Dungeon Journal look, stream B: the page shell (home / dungeon page, header, tabs, lazy pages), the restyled quest
list and quest page, the item buttons with full tooltips (JournalItems.lua) and the exports for the other pages."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from test_dungeon_quests import game, filters, plain, HOVER_DATA, SEEKING
from test_loot import click

STYLES = ("modern", "classic")

# Records every call the shell makes into the other streams' page modules (their real bodies are not under test here).
SPIES = r'''
JCALLS={}
local function spy(name,mod)
  local m=NS[mod]
  m.build=function(p,w,h,a,b) JCALLS[#JCALLS+1]=name..".build "..w.."x"..h; _G[string.upper(name).."_PARENT"]=p; _G[string.upper(name).."_EXTRA"]=b; _G[string.upper(name).."_OPEN"]=a end
  m.show=function(area,n) JCALLS[#JCALLS+1]=name..".show "..tostring(area).." "..tostring(n) end
  m.hide=function() JCALLS[#JCALLS+1]=name..".hide" end
  m.refresh=function(list) JCALLS[#JCALLS+1]=name..".refresh "..#list; _G[string.upper(name).."_LIST"]=list end
end
spy("home","dungeonHomeUI");spy("bosses","dungeonBossesUI");spy("map","dungeonMapUI");spy("route","dungeonRouteUI")
'''


def opened(style, extra=""):
    """The journal tab opened with the page modules spied on, scoped to the whole catalogue."""
    g = game(style, HOVER_DATA + extra, open_tab=False)
    g.run(SPIES)
    g.slash("dungeons"); g.advance(90)
    click(g.eval("NS.dungeonQuests._window()").reset); g.advance(90)
    assert g.eval("NS.dungeonQuests._state()")[0], g.printed()
    return g


def calls(g):
    return list(g.eval("JCALLS").values())


def D(g, name):
    return g.eval("NS.dungeonQuests." + name)


def test_opens_on_the_home_with_dungeon_cards_and_the_shell_filters(style):
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    assert w.homeView.shown and not w.dungeonView.shown and D(g, "current")() == 0
    assert "home.build 1000x636" in calls(g) and g.eval("HOME_PARENT==NS.dungeonQuests._window().homeView")
    assert g.eval("HOME_EXTRA.completed==NS.dungeonQuests._window().completed and HOME_EXTRA.inLog==NS.dungeonQuests._window().inLog and HOME_EXTRA.search==NS.dungeonQuests._window().search")
    assert any(c.startswith("home.refresh ") and c != "home.refresh 0" for c in calls(g)), calls(g)
    assert not [c for c in calls(g) if c.startswith(("bosses.", "map.", "route."))], "other pages are built lazily"
    assert not g.eval("NS.db.errors")


def test_summaries_list_every_dungeon_with_level_range_counts_and_factions(style):
    g = opened(style, "UnitLevel=function() return 20 end UnitFactionGroup=function() return 'Alliance' end FINISHED[4]=true")
    rows = {s.area: s for s in D(g, "summaries")().values()}
    assert {1581, 718} <= set(rows)
    dm = rows[1581]
    assert dm.name == "The Deadmines" and dm.total == len([1 for r in D(g, "_results")().values() if r.dungeons[1581]])
    assert dm.done >= 2 and dm.open >= 1 and dm.open + dm.done <= dm.total, (dm.open, dm.done, dm.total)
    assert dm.alliance and dm.horde
    assert dm.minLevel == 20 and dm.maxLevel == 50, "the dungeon's own quests give its LV range"
    wc = rows[718]
    assert wc.name == "Wailing Caverns" and wc.total == 2 and wc.minLevel == 18 and wc.maxLevel == 25
    order = [s.area for s in D(g, "summaries")().values()]
    assert order.index(718) < order.index(1581), "sorted by level"
    g.eval("NS.dungeonQuests._release")()
    assert len(list(D(g, "summaries")().values())) == 0, "nothing before the scan"


def test_summary_rows_carry_quest_titles_for_the_home_search(style):
    g = opened(style)
    dm = {s.area: s for s in D(g, "summaries")().values()}[1581]
    titles = list(dm.quests.values())
    assert len(titles) == dm.total and all(isinstance(t, str) and t for t in titles), titles


def test_real_home_search_matches_quest_titles_and_holds_the_hide_boxes(style):
    g = game(style, HOVER_DATA, open_tab=False)
    g.slash("dungeons"); g.advance(90)
    click(g.eval("NS.dungeonQuests._window()").reset); g.advance(90)
    w = g.eval("NS.dungeonQuests._window()"); f = g.eval("NS.dungeonHomeUI._frame()")
    dm = {s.area: s for s in D(g, "summaries")().values()}[1581]
    title = list(dm.quests.values())[0]
    f.search.SetText(f.search, title.upper()); f.search.scripts.OnTextChanged(f.search, True)
    names = [c.row.name for c in f.cards.values() if c.shown and c.row]
    assert "The Deadmines" in names, (title, names)
    # on the home the hide boxes sit on the right of the home bar; on a dungeon page back in the filter bar
    W, BAR = "NS.dungeonQuests._window()", "NS.dungeonHomeUI._frame().bar"
    assert g.eval(f"{W}.inLog.point[2]=={BAR} and {W}.inLog.point[1]=='RIGHT' and {W}.completed.point[2]=={W}.inLog")
    D(g, "openDungeon")(1581)
    assert g.eval(f"{W}.completed.point[2]=={W}.frame and {W}.inLog.point[2]=={W}.frame")
    # one filter row: the hide boxes sit on the row of the search box, between All quests and Refresh data
    assert (w.completed.point[4], w.completed.point[5]) == (548, -17) and (w.inLog.point[4], w.inLog.point[5]) == (748, -17)
    D(g, "home")()
    assert g.eval(f"{W}.inLog.point[2]=={BAR}")
    assert not g.eval("NS.db.errors")


def test_a_card_opens_the_dungeon_page_with_header_tabs_and_quests(style):
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    g.eval("HOME_OPEN")(1581)
    assert D(g, "current")() == 1581 and w.dungeonView.shown and not w.homeView.shown and w.questsPage.shown
    assert w.title.text == "The Deadmines" and w.levels.text == "LV 20-50"
    assert w.tabs.quests.selected and not w.tabs.bosses.selected and not w.tabs.map.selected and not w.tabs.route.selected
    ids = {r.id for r in D(g, "_results")().values()}
    assert 8 not in ids and {1, 2, 3} <= ids, "the quest list is the dungeon's"
    assert plain(w.listTitle.text) in ("Quests  |  %d" % len(ids), "Quests  |  1–8 of %d" % len(ids)), w.listTitle.text
    for key, icon in (("map", "Ability_Spy"), ("bosses", "UI-RaidTargetingIcon_8"), ("quests", "AvailableQuestIcon"), ("route", "Ability_Mount_Gryphon_01")):
        assert w.tabs[key] is not None, key
    click(w.back)
    assert D(g, "current")() == 0 and w.homeView.shown and not w.dungeonView.shown
    assert len({r.id for r in D(g, "_results")().values()}) > len(ids), "back home lists every dungeon again"
    assert not g.eval("NS.db.errors")


def test_tabs_build_each_page_once_in_the_content_area_and_hide_the_others(style):
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    D(g, "openDungeon")(1581, "bosses")
    assert calls(g)[-2:] == ["bosses.build 1000x560", "bosses.show 1581 The Deadmines"]
    assert g.eval("BOSSES_PARENT.parent==NS.dungeonQuests._window().content") and g.eval("BOSSES_PARENT").shown
    assert not w.questsPage.shown and w.tabs.bosses.selected
    assert g.eval("NS.dungeonQuests._window().content.point[2]==NS.dungeonQuests._window().frame") and list(w.content.point.values())[2:] == ["TOPLEFT", 16, -140] and w.content.width == 1000 and w.content.height == 560
    click(w.tabs.map)
    assert calls(g)[-3:] == ["bosses.hide", "map.build 1000x560", "map.show 1581 The Deadmines"]
    assert not g.eval("BOSSES_PARENT").shown and g.eval("MAP_PARENT").shown
    click(w.tabs.bosses)
    assert calls(g).count("bosses.build 1000x560") == 1, "built once, shown again"
    assert calls(g)[-1] == "bosses.show 1581 The Deadmines"
    click(w.tabs.quests)
    assert w.questsPage.shown and calls(g)[-1] == "bosses.hide"
    D(g, "openDungeon")(718, "route")
    assert calls(g)[-1] == "route.show 718 Wailing Caverns" and w.title.text == "Wailing Caverns"
    D(g, "home")()
    assert calls(g)[-2] == "route.hide" or "route.hide" in calls(g)[-3:]
    assert not g.eval("NS.db.errors")


def test_a_failing_page_module_does_not_break_the_shell(style):
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    g.run("ERRORS_SEEN={} ERROR_HANDLER=function(e) ERRORS_SEEN[#ERRORS_SEEN+1]=e end NS.dungeonMapUI.build=function() error('map broke') end")
    D(g, "openDungeon")(1581, "map")
    assert w.tabs.map.selected and w.title.text == "The Deadmines"
    assert any("map broke" in e for e in g.eval("ERRORS_SEEN").values()), "reported, not swallowed"
    click(w.tabs.quests); assert w.questsPage.shown


def test_entrance_pin_button_and_exported_entrance(style):
    g = opened(style)
    g.run('WAYPOINT=nil;UiMapPoint={CreateFromCoordinates=function(map,x,y)return {map=map,x=x,y=y} end};C_Map.SetUserWaypoint=function(p)WAYPOINT=p end')
    D(g, "openDungeon")(1581)
    w = g.eval("NS.dungeonQuests._window()")
    e = D(g, "entranceOf")(1581)
    assert e and "entrance" in e.label and e.point.map
    click(w.pin)
    pt = g.eval("WAYPOINT")
    assert pt and pt.map == e.point.map and abs(pt.x - e.point.x / 100) < 1e-6
    w.pin.scripts.OnEnter(w.pin)
    assert "world map" in "\n".join(g.eval("TOOLTIP.lines").values())
    assert D(g, "entranceOf")(424242) is None


def test_quest_rows_are_296_by_48_with_marks_level_crests_and_you_have_it(style):
    g = opened(style, "UnitLevel=function() return 20 end UnitFactionGroup=function() return 'Alliance' end")
    g.run("QUESTS[#QUESTS+1]={id=2,title='A dungeon job',level=20,objectives={}}"); g.fire("QUEST_LOG_UPDATE"); g.advance(.3)
    filters(g, dungeon=1581)
    w = g.eval("NS.dungeonQuests._window()")
    rows = {r.result.id: r for r in w.rows.values() if r.result and r.frame.shown}
    top = rows[1]
    assert top.frame.width == 296 and top.frame.height == 48
    assert rows[2].frame.width < 296, "chain steps keep their indent"
    assert rows[2].have.shown and rows[2].have.text == "YOU HAVE IT" and "ActiveQuestIcon" in rows[2].icon.texture
    assert plain(rows[3]["from"].text).startswith("Available from level")
    assert top.crestA.shown and top.crestH.shown, "both factions"
    rows[3].frame.scripts.OnClick(rows[3].frame, "LeftButton")
    assert rows[3].selected and rows[3].selectedArt.shown and rows[3].edge.shown and not rows[1].selectedArt.shown
    from test_dungeon_quests import edit
    edit(w.search, "Alliance mission"); g.advance(.3)
    row = next(r for r in w.rows.values() if r.result and r.result.id == 6)
    assert row.crestA.shown and not row.crestH.shown, "Alliance-only quest: one crest"


def test_crest_buttons_filter_the_list_by_faction(style):
    g = opened(style); filters(g, dungeon=1581); w = g.eval("NS.dungeonQuests._window()")
    ids = lambda: {r.id for r in D(g, "_results")().values()}
    assert {5, 6} <= ids()
    click(w.crestAlliance); assert 6 in ids() and 5 not in ids()
    click(w.crestHorde); assert 5 in ids() and 6 not in ids()
    click(w.crestHorde); assert {5, 6} <= ids(), "clicking the chosen crest again shows both"
    assert not g.eval("NS.db.errors")


def test_quest_page_has_morpheus_title_sections_item_columns_and_pills(style):
    g = opened(style, "UnitLevel=function() return 30 end QUESTIE_QUESTS[2].reputationReward={{72,250}} QUESTIE_QUESTS[2].rewardMoney=12345 "
                      "GetFactionInfoByID=function(id) return id==72 and 'Stormwind' or nil end")
    w = g.eval("NS.dungeonQuests._window()")
    from test_dungeon_quests import edit
    edit(w.search, "A dungeon job"); g.advance(.3)
    row = next(r for r in w.rows.values() if r.result and r.result.id == 2)
    row.frame.scripts.OnClick(row.frame, "LeftButton"); g.advance(30)
    p = w.panel
    assert p.title.text == "A dungeon job" and "MORPHEUS" in p.title.font[1]
    assert plain(p.avail.text) == "Available from level 15" and p.crestA.shown and p.crestH.shown
    for key, label in (("do", "Objective"), ("start", "Starts at"), ("turn", "Turn in"), ("rewards", "Choose one reward")):
        assert p.heads[key].shown and p.heads[key].text == label, key
    shown = [b for b in p["items"].values() if b.shown]
    assert len(shown) == 2 and shown[0].point[4] == 14 and shown[1].point[4] > shown[0].point[4] and shown[0].point[5] == shown[1].point[5]
    assert p.xpPill.value == "200 XP" and p.moneyPill.shown and p.moneyPill.value == "1g 23s 45c"
    assert p.repPills[1].value == "+250 Stormwind"
    assert p.actions.shown
    click(p.actions)
    menu, _ = g.eval("NS._questMenu()"); assert menu.shown and menu.entry.questID == 2
    text = plain(g.eval("NS.dungeonQuests._panelText()"))
    assert text.index("Objective") < text.index("Starts at") < text.index("Turn in") < text.index("Choose one reward") < text.index("1g 23s 45c")
    assert not g.eval("NS.db.errors")



SIX_ITEMS = "".join("REWARD_ITEMS[%d]={name='Extra reward %d',class=4,subClass=1,itemLevel=20,requiredLevel=0,questRewards={2},quality=2} " % (812 + i, i) for i in range(4))


def quest_page(g, qid=2):
    from test_dungeon_quests import edit
    w = g.eval("NS.dungeonQuests._window()")
    edit(w.search, g.eval("NS.questie.get")("quest", qid, "name")); g.advance(.3)
    row = next(r for r in w.rows.values() if r.result and r.result.id == qid)
    row.frame.scripts.OnClick(row.frame, "LeftButton"); g.advance(30)
    return w


def bottoms_inside(w, limit=560):
    """Every shown element of the quest page ends at or above the 560 px parchment bottom."""
    p = w.panel
    shown = []
    for key in ("title", "avail", "meta", "doText", "doKind", "pickup", "turnIn", "itemNote", "itemMore", "xpPill", "moneyPill", "xpNote", "chain"):
        if p[key].shown: shown.append((key, p[key]))
    shown += [("head " + k, h) for k, h in p.heads.items() if h.shown]
    shown += [("item", b) for b in p["items"].values() if b.shown]
    shown += [("rep", b) for b in p.repPills.values() if b.shown]
    for name, el in shown:
        top = -el.point[5]
        assert top + (el.height or 16) <= limit, (name, top, el.height)  # font strings: one line
    return shown


def test_a_long_quest_page_with_six_items_and_a_chain_stays_inside_the_parchment(style):
    g = opened(style, SIX_ITEMS + "UnitLevel=function() return 30 end QUESTIE_QUESTS[2].reputationReward={{72,250}} QUESTIE_QUESTS[2].rewardMoney=12345")
    w = quest_page(g)
    p = w.panel
    shown = [b for b in p["items"].values() if b.shown]
    assert len(shown) == 6, "all six rewards are shown"
    assert len({b.point[5] for b in shown}) == 2 and len({b.point[4] for b in shown}) == 3, "three columns, two rows"
    bottoms_inside(w)
    assert w.moreScroll.shown and p.heads.more.shown
    assert -w.moreScroll.point[5] + w.moreScroll.height <= 560 and w.moreScroll.height >= 40, (w.moreScroll.point, w.moreScroll.height)
    assert not p.chain.shown and "Quest chain" in plain(w.detailsText.text), "no room for its own section: the chain moves into More details"
    assert "Before: " in plain(w.detailsText.text) and "Next: " in plain(w.detailsText.text)
    assert not g.eval("NS.db.errors")


def test_a_short_quest_page_keeps_the_chain_and_more_details_inside_the_parchment(style):
    g = opened(style, "UnitLevel=function() return 30 end")
    w = quest_page(g)
    p = w.panel
    assert p.chain.shown and p.heads.chain.shown and p.heads.more.shown and w.moreScroll.shown
    assert w.moreScroll.height >= 40 and -w.moreScroll.point[5] + w.moreScroll.height <= 560
    bottoms_inside(w)


def test_xp_pill_groups_thousands(style):
    g = opened(style, "UnitLevel=function() return 20 end")
    from test_dungeon_quests import edit
    w = g.eval("NS.dungeonQuests._window()"); edit(w.search, "A dungeon job"); g.advance(.3)
    row = next(r for r in w.rows.values() if r.result and r.result.id == 2)
    row.frame.scripts.OnClick(row.frame, "LeftButton")
    assert w.panel.xpPill.value == "2,000 XP" and not w.panel.xpNote.shown


ITEMS = r'''
GameTooltip.SetHyperlink=function(_,link) TOOLTIP.link=link end
COMPARED=0;HIDDEN_COMPARE=0;LINKED={};DRESSED={}
function GameTooltip_ShowCompareItem() COMPARED=COMPARED+1 end
function GameTooltip_HideShoppingTooltips() HIDDEN_COMPARE=HIDDEN_COMPARE+1 end
function HandleModifiedItemClick(link) LINKED[#LINKED+1]=link;return true end
function DressUpItemLink(link) DRESSED[#DRESSED+1]=link end
'''


def item_button(g):
    g.run("ITEM_BUTTON=NS.journalItems.button(UIParent,300,46);ITEM_BUTTON:SetItem(810,'Staff')")
    return g.eval("ITEM_BUTTON")


def test_item_button_shows_icon_quality_name_subtitle_and_full_tooltip(style):
    g = opened(style, ITEMS); b = item_button(g)
    assert b.icon.width == 38 and b.icon.texture == "icon" and list(b.icon.coords.values()) == [.08, .92, .08, .92]
    assert b.name.text == "|cff0070ddReward staff|r" and b.sub.text == "Staff"
    b.scripts.OnEnter(b)
    assert g.eval("TOOLTIP.link") == "item:810" and g.eval("TOOLTIP.shown") and g.eval("COMPARED") == 0
    b.scripts.OnLeave(b)
    assert not g.eval("TOOLTIP.shown") and g.eval("HIDDEN_COMPARE") >= 1 and b.scripts.OnUpdate is None
    g.run("ITEM_BUTTON:SetItem(424242)")
    assert "Item 424242" in b.name.text and "QuestionMark" in b.icon.texture


def test_shift_shows_compare_tooltips_and_toggles_while_hovering(style):
    g = opened(style, ITEMS); b = item_button(g)
    g.run("SHIFT=true"); b.scripts.OnEnter(b)
    assert g.eval("COMPARED") == 1
    g.run("SHIFT=false"); b.scripts.OnUpdate(b, .1)
    hidden = g.eval("HIDDEN_COMPARE"); assert hidden >= 1
    g.run("SHIFT=true"); b.scripts.OnUpdate(b, .1); b.scripts.OnUpdate(b, .1)
    assert g.eval("COMPARED") == 2, "compare again once, when Shift goes down"


def test_shift_click_links_and_ctrl_click_dresses_up(style):
    g = opened(style, ITEMS); b = item_button(g)
    g.run("SHIFT=true"); click(b)
    assert list(g.eval("LINKED").values()) == ["|Hitem:810|h[Reward staff]|h"]
    g.run("SHIFT=false CTRL=true"); click(b)
    assert list(g.eval("DRESSED").values()) == ["|Hitem:810|h[Reward staff]|h"]
    g.run("CTRL=false"); click(b)
    assert len(list(g.eval("LINKED").values())) == 1 and len(list(g.eval("DRESSED").values())) == 1, "plain click: nothing"
    g.run("HandleModifiedItemClick=nil INSERTED=nil ChatEdit_InsertLink=function(l) INSERTED=l return true end SHIFT=true")
    click(b); assert g.eval("INSERTED") == "|Hitem:810|h[Reward staff]|h", "chat link fallback"


def test_attach_accepts_a_function_for_the_item(style):
    g = opened(style, ITEMS)
    g.run("B=CreateFrame('Button',nil,UIParent);NS.journalItems.attach(B,function() return 811 end)")
    b = g.eval("B"); b.scripts.OnEnter(b)
    assert g.eval("TOOLTIP.link") == "item:811"


def test_route_exports_plan_the_dungeon_for_the_route_tab(style):
    g = opened(style)
    g.run("ROUTE_RESULT=nil;NS.dungeonQuests.routePlan(1581,true,function(result,first,later) ROUTE_RESULT={result=result,first=first,later=later} end)")
    g.advance(30)
    got = g.eval("ROUTE_RESULT")
    assert got and got.result and got.result.steps is not None and got.later >= 1
    steps = list(got.result.steps.values())
    assert steps, "a route with steps"
    text = D(g, "routeStepText")(steps[0])
    assert isinstance(text, str) and text
    assert D(g, "minutes")(30) == "30 s" and D(g, "minutes")(600) == "10 min"
    assert not D(g, "routePlan")(0, False, None)
    g.run('WAYPOINT=nil;UiMapPoint={CreateFromCoordinates=function(map,x,y)return {map=map,x=x,y=y} end};C_Map.SetUserWaypoint=function(p)WAYPOINT=p end')
    assert D(g, "pinPlace")(g.eval("{source={name='Somebody'},point={map=1429,x=40,y=50}}"))
    assert abs(g.eval("WAYPOINT").x - .40) < 1e-6
    assert not g.eval("NS.db.errors")


def test_plan_route_opens_the_route_tab_and_the_old_window_stays_as_a_fallback(style):
    g = opened(style); filters(g, dungeon=1581); w = g.eval("NS.dungeonQuests._window()")
    assert not w.route.disabled
    click(w.route); g.advance(30)
    assert w.tabs.route.selected and not w.questsPage.shown and calls(g)[-1] == "route.show 1581 The Deadmines"
    assert g.eval("NS.dungeonQuests._routeWindow()") is None, "the button no longer opens the separate window"
    g.run("NS.dungeonRouteUI=nil"); click(w.tabs.quests); click(w.route); g.advance(30)
    f = g.eval("NS.dungeonQuests._routeWindow()")
    assert f.shown and "The Deadmines" in f.summary.text, "without the Route page the old window opens"


QUEST_ONLY = ("search", "clearSearch", "level", "levelMode", "class", "faction", "mine", "reset", "filtersButton")
FILTER_PANEL = ("level", "levelMode", "class", "faction")  # behind the Filters button, inside the filter bar


def test_home_hides_the_quest_filters_and_status_line_and_keeps_refresh_and_hide_boxes(style):
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    assert D(g, "current")() == 0
    assert not w.filterBar.shown and not w.status.shown
    for key in QUEST_ONLY:
        where = "filterPanel" if key in FILTER_PANEL else "filterBar"
        assert g.eval("NS.dungeonQuests._window()[%r].parent==NS.dungeonQuests._window().%s" % (key, where)), key
    assert g.eval("NS.dungeonQuests._window().filterPanel.parent==NS.dungeonQuests._window().filterBar")
    for key in ("reload", "completed", "inLog"):
        assert g.eval("NS.dungeonQuests._window()[%r].parent==NS.dungeonQuests._window().frame" % key), key
        assert w[key].shown is not False, key
    D(g, "openDungeon")(1581)
    assert w.filterBar.shown and not w.status.shown, "no legend line on a dungeon page with quests"
    n = len(list(D(g, "_results")().values()))
    assert plain(w.listTitle.text).endswith("of %d" % n) or plain(w.listTitle.text).endswith("|  %d" % n), "the page range is in the list heading"
    D(g, "home")()
    assert not w.filterBar.shown and not w.status.shown
    # the hidden shell search keeps its text and filtering for the dungeon page
    from test_dungeon_quests import edit
    edit(w.search, "preparation"); g.advance(.3)
    assert {r.id for r in D(g, "_results")().values()} == {1}
    assert not g.eval("NS.db.errors")


def test_no_matching_quests_shows_only_on_the_quests_tab(style):
    # a dungeon with no quest results: the Quests tab says so, the Bosses, Map and Route pages keep a calm top
    g = opened(style); w = g.eval("NS.dungeonQuests._window()")
    from test_dungeon_quests import edit
    D(g, "openDungeon")(1581)
    edit(w.search, "zzqqxx no such quest"); g.advance(.3)
    assert len(list(D(g, "_results")().values())) == 0
    assert w.status.shown, "the Quests tab says there are no matching quests"
    for tab in ("bosses", "map", "route"):
        click(w.tabs[tab]); g.advance(.1)
        assert not w.status.shown, tab
    click(w.tabs.quests); g.advance(.1)
    assert w.status.shown, "back on the Quests tab the line returns"
    assert not g.eval("NS.db.errors")


def test_home_keeps_the_status_line_while_it_says_why_there_are_no_cards(style):
    g = game(style, HOVER_DATA, open_tab=False)
    g.run(SPIES)
    g.slash("dungeons")
    w = g.eval("NS.dungeonQuests._window()")
    assert D(g, "current")() == 0 and not w.filterBar.shown
    assert w.status.shown and "Reading dungeon quests" in w.status.text, "loading is said on the home"
    g.advance(90)
    assert not w.status.shown, "ready: the cards say the rest"


def summary(g, area=1581):
    return {s.area: s for s in D(g, "summaries")().values()}.get(area)


def test_summaries_follow_the_hide_boxes(style):
    g = opened(style, "UnitLevel=function() return 30 end FINISHED[1]=true")
    w = g.eval("NS.dungeonQuests._window()")
    g.run("QUESTS[#QUESTS+1]={id=3,title='Return outside',level=20,objectives={}}"); g.fire("QUEST_LOG_UPDATE"); g.advance(.3)
    before = summary(g)
    assert before.done >= 2, "19 and 1 are done"
    click(w.completed)
    after = summary(g)
    assert after.done == 0 and after.total == before.total - before.done, (after.total, before.total, before.done)
    assert "Completed quest" not in list(after.quests.values())
    assert any(c.startswith("home.refresh ") for c in calls(g)[-3:]), "a hide box repaints the cards"
    click(w.inLog)
    logged = summary(g)
    assert logged.total == after.total - 1 and "Return outside" not in list(logged.quests.values())
    click(w.completed); click(w.inLog)
    assert summary(g).total == before.total
    # a dungeon left with nothing to show is not listed
    g.run("for id=1,60 do FINISHED[id]=true end"); click(w.completed)
    assert summary(g, 718) is None and summary(g) is None
    assert not g.eval("NS.db.errors")


def test_summaries_count_the_chosen_factions_quests_and_keep_both_crests(style):
    g = opened(style)
    both = summary(g)
    # only the home crest filter (stream T's frame); the quest page's hidden faction filter is not used on the home
    g.run("HOME_FACTION=nil NS.dungeonHomeUI._frame=function() return {faction=HOME_FACTION} end")
    g.run("HOME_FACTION='Alliance'")
    ally = summary(g)
    assert "Horde mission" not in list(ally.quests.values()) and "Alliance mission" in list(ally.quests.values())
    assert ally.total < both.total and ally.alliance and ally.horde, "fewer quests, both crests still"
    g.run("HOME_FACTION='Horde'")
    horde = summary(g)
    assert "Alliance mission" not in list(horde.quests.values()) and "Horde mission" in list(horde.quests.values())
    g.run("HOME_FACTION=nil")
    assert summary(g).total == both.total
    g.eval("NS.dungeonQuests.openDungeon")(1581)
    click(g.eval("NS.dungeonQuests._window()").crestHorde)
    assert summary(g).total == both.total, "the quest page's faction filter does not change the home counts"
    assert not g.eval("NS.db.errors")


def test_the_home_crest_click_recounts_the_cards(style):
    g = game(style, HOVER_DATA, open_tab=False)
    g.slash("dungeons"); g.advance(90)
    click(g.eval("NS.dungeonQuests._window()").reset); g.advance(90)
    b = g.eval("NS.dungeonHomeUI._frame().alliance")
    assert b is not None
    g.run("RECOUNTS=0 local s=NS.dungeonQuests.summaries NS.dungeonQuests.summaries=function() RECOUNTS=RECOUNTS+1 return s() end")
    b.scripts.OnClick(b, "LeftButton")
    for fn in b.posthooks.OnClick.values():  # the client runs HookScript hooks after the frame's own OnClick
        fn(b, "LeftButton")
    assert g.eval("RECOUNTS") >= 1, "the shell hooks the home crest to recount"
    assert not g.eval("NS.db.errors")


# Stand-ins for stream T's icon helpers (JournalTheme.lua), so the rows can be checked before it lands.
ICONS = r'''
local T=NS.journalTheme
T.classIcon=function(parent,size,token) local t=parent:CreateTexture(nil,"ARTWORK");t:SetWidth(size);t:SetHeight(size);t.classToken=token;return t end
T.dungeonIcon=function(parent,size) local t=parent:CreateTexture(nil,"ARTWORK");t:SetWidth(size);t:SetHeight(size);t.iconKind="dungeon";return t end
T.chainIcon=function(parent,size) local t=parent:CreateTexture(nil,"ARTWORK");t:SetWidth(size);t:SetHeight(size);t.iconKind="chain";return t end
'''


def icon_game(style, extra=""):
    g = game(style, HOVER_DATA + extra, open_tab=False)
    g.run(SPIES + ICONS)
    g.slash("dungeons"); g.advance(90)
    click(g.eval("NS.dungeonQuests._window()").reset); g.advance(90)
    return g


def rows_by_id(g):
    return {r.result.id: r for r in g.eval("NS.dungeonQuests._window()").rows.values() if r.result and r.frame.shown}


def test_rows_show_class_dungeon_and_chain_icons(style):
    g = icon_game(style)
    from test_dungeon_quests import edit
    filters(g, dungeon=1581); w = g.eval("NS.dungeonQuests._window()")
    edit(w.search, "mission"); g.advance(.3)
    rows = rows_by_id(g)
    druid = rows[4]
    shown = [t for t in druid.classIcons.values() if t and t.shown]
    assert [t.classToken for t in shown] == ["DRUID"], "a class-only quest shows its class icon"
    assert shown[0].point[1] == "BOTTOMRIGHT" and shown[0].point[4] < druid.crestA.point[4], "left of the crests"
    assert not [t for t in rows[6].classIcons.values() if t and t.shown], "no class icon for every-class quests"
    edit(w.search, "Dungeon pickup"); g.advance(.3)
    assert rows_by_id(g)[12].dungeonIcon.shown, "picked up from an NPC inside the dungeon"
    edit(w.search, ""); g.advance(.3)
    rows = rows_by_id(g)
    assert rows[1].chain.shown and rows[2].chain.shown, "chain steps get the chain icon"
    assert not rows[1].dungeonIcon.shown, "picked up outside"
    assert not rows[4].chain.shown, "a standalone quest has none"
    rows[2].chain.scripts.OnEnter(rows[2].chain)
    tip = "\n".join(g.eval("TOOLTIP.lines").values())
    assert "Outdoor preparation" in tip and "Return outside" in tip, tip
    click(rows[2].chain); assert rows[2].selected
    assert not g.eval("NS.db.errors")


def test_rows_skip_the_icons_until_the_theme_has_the_helpers(style):
    g = game(style, HOVER_DATA, open_tab=False)
    g.run("NS.journalTheme.classIcon=nil NS.journalTheme.dungeonIcon=nil NS.journalTheme.chainIcon=nil")
    g.slash("dungeons"); g.advance(90)
    click(g.eval("NS.dungeonQuests._window()").reset); g.advance(90)
    filters(g, dungeon=1581)
    rows = rows_by_id(g)
    assert rows and all(r.dungeonIcon is None and r.chain is None for r in rows.values())
    assert all(not [t for t in r.classIcons.values() if t] for r in rows.values())
    w = quest_page(g, 4)
    assert w.panel.classOnly.shown and plain(w.panel.classOnly.text) == "DRUID ONLY", "the label without icons"
    assert not g.eval("NS.db.errors")


def test_quest_page_says_class_only_in_class_colours_with_icons(style):
    g = icon_game(style, "QUESTIE_QUESTS[4].requiredClasses=1025")
    filters(g, dungeon=1581)
    w = quest_page(g, 4); p = w.panel
    assert p.classOnly.shown and plain(p.classOnly.text) == "DRUID / WARRIOR ONLY", p.classOnly.text
    assert "|cffc79c6eWARRIOR|r" in p.classOnly.text, "WARRIOR in the warrior class colour"
    icons = sorted(t.classToken for t in p.classIcons.values() if t and t.shown)
    assert icons == ["DRUID", "WARRIOR"]
    assert "DRUID / WARRIOR ONLY" in plain(D(g, "_panelText")())
    w = quest_page(g, 2)
    assert not w.panel.classOnly.shown and not [t for t in w.panel.classIcons.values() if t and t.shown]
    bottoms_inside(w)
    assert not g.eval("NS.db.errors")


def test_share_button_is_green_in_your_log_in_a_party_and_grey_with_why_otherwise(style):
    g = opened(style, "UnitLevel=function() return 20 end")
    w = quest_page(g, 2); b = w.panel.share
    assert b.shown and b.text == "Share" and not b.shareable and "not in your quest log" in b.why
    assert [round(v, 2) for v in list(b.bg.rgba.values())[:3]] == [.17, .16, .15], "grey"
    b.scripts.OnEnter(b); assert "not in your quest log" in "\n".join(g.eval("TOOLTIP.lines").values())
    g.run("PUSHED={}"); click(b)
    assert g.pushed() == [] and any("cannot share" in line for line in g.printed())
    g.run('table.insert(QUESTS,{id=2,title="A dungeon job",level=20,objectives={}})')
    g.slash("auto off"); g.join_party(["Anna"]); g.fire("QUEST_LOG_UPDATE"); g.advance(1)
    w = quest_page(g, 2); b = w.panel.share
    assert b.shareable and b.why is None, b.why
    assert [round(v, 2) for v in list(b.bg.rgba.values())[:3]] == [.10, .34, .10], "green"
    b.scripts.OnEnter(b); assert "offer this quest" in "\n".join(g.eval("TOOLTIP.lines").values())
    g.run("PUSHED={}"); click(b)
    assert g.pushed() == [2], "the quest menu's own share action"
    assert not g.eval("NS.db.errors")


def test_status_strip_uses_the_badge_tint_not_white(style):
    g = opened(style, "UnitLevel=function() return 20 end")
    w = quest_page(g, 2); strip = w.panel.strip
    assert [round(v, 2) for v in strip.rgba.values()] == [0.90, 0.66, 0.12, 0.40], "to pick up: the gold tint"
    assert list(strip.vertex.values()) == [1, 1, 1, 1], "colour x vertex = tint"
    w = quest_page(g, 17)
    assert [round(v, 2) for v in w.panel.strip.rgba.values()] == [0.85, 0.25, 0.20, 0.30], "blocked: red"


BOSSES = r'''
BOSS_ASKS=0 SELECTED_BOSS=nil BOSS_LATE=false
NS.loot.bossesOf=function(name,done,area)
  BOSS_ASKS=BOSS_ASKS+1
  local list={{name="Rhahk'Zor",items={812}},{name="Edwin VanCleef",items={810,{itemID=813}}}}
  if name~="The Deadmines" then list={} end
  if BOSS_LATE then BOSS_DONE=function() done(list) end return nil,nil,"loading" end
  if done then done(list) end
  return list
end
NS.dungeonBossesUI.select=function(boss) SELECTED_BOSS=boss end
'''


def items_of(w):
    shown = {b.itemID: b for b in w.panel["items"].values() if b.shown}
    return shown[810], shown[811]


def tip_lines(g):
    return list((g.eval("TOOLTIP.lines") or {}).values())


def test_reward_item_dropped_by_a_boss_says_so_and_opens_it_on_the_bosses_tab(style):
    g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
    g.run(BOSSES)
    filters(g, dungeon=1581)
    w = quest_page(g, 2)
    staff, plain_item = items_of(w)
    staff.scripts.OnEnter(staff)
    assert g.eval("TOOLTIP.link") == "item:810" and "Drops from Edwin VanCleef" in tip_lines(g)
    staff.scripts.OnLeave(staff)
    plain_item.scripts.OnEnter(plain_item)
    assert not any("Drops from" in l for l in tip_lines(g))
    plain_item.scripts.OnLeave(plain_item)
    assert g.eval("BOSS_ASKS") == 1, "one boss list per dungeon, kept"
    click(plain_item)
    assert w.questsPage.shown, "an item no boss drops: a plain click does nothing"
    click(staff)
    assert w.tabs.bosses.selected and g.eval("SELECTED_BOSS") == "Edwin VanCleef"
    assert calls(g)[-1] == "bosses.show 1581 The Deadmines"
    # Shift-click still links instead of opening the boss
    click(w.tabs.quests); g.run("SHIFT=true SELECTED_BOSS=nil"); click(staff); g.run("SHIFT=false")
    assert len(list(g.eval("LINKED").values())) == 1 and w.questsPage.shown and g.eval("SELECTED_BOSS") is None
    # without a select() on the Bosses page the tab still opens
    g.run("NS.dungeonBossesUI.select=nil"); click(staff)
    assert w.tabs.bosses.selected
    assert not g.eval("NS.db.errors")


def test_a_late_boss_list_updates_the_tooltip_and_a_pending_click(style):
    g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
    g.run(BOSSES + "BOSS_LATE=true")
    filters(g, dungeon=1581)
    w = quest_page(g, 2)
    staff, _ = items_of(w)
    staff.scripts.OnEnter(staff)
    assert not any("Drops from" in l for l in tip_lines(g))
    click(staff)
    assert w.questsPage.shown, "still loading: nothing yet"
    g.run("BOSS_DONE()")
    assert "Drops from Edwin VanCleef" in tip_lines(g), "repainted while hovered"
    assert w.tabs.bosses.selected and g.eval("SELECTED_BOSS") == "Edwin VanCleef", "the pending click opens the boss"
    assert g.eval("BOSS_ASKS") == 1
    assert not g.eval("NS.db.errors")


def test_a_late_boss_list_does_not_jump_to_bosses_after_you_moved_on(style):
    g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
    g.run(BOSSES + "BOSS_LATE=true")
    filters(g, dungeon=1581)
    w = quest_page(g, 2)
    staff, _ = items_of(w)
    # left the item before the list came
    staff.scripts.OnEnter(staff); click(staff); staff.scripts.OnLeave(staff)
    g.run("BOSS_DONE()")
    assert w.questsPage.shown and g.eval("SELECTED_BOSS") is None, "leaving the item drops the pending click"
    assert not g.eval("NS.db.errors")
    # another quest chosen before the list came
    g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
    g.run(BOSSES + "BOSS_LATE=true")
    filters(g, dungeon=1581)
    w = quest_page(g, 2)
    staff, _ = items_of(w)
    staff.scripts.OnEnter(staff); click(staff)
    w = quest_page(g, 17)
    g.run("BOSS_DONE()")
    assert w.questsPage.shown and g.eval("SELECTED_BOSS") is None, "a quest change drops the pending click"
    assert not g.eval("NS.db.errors")


def test_share_button_repaints_when_the_party_or_the_log_changes(style):
    g = opened(style, "UnitLevel=function() return 20 end")
    w = quest_page(g, 2); b = w.panel.share
    assert not b.shareable
    g.run('table.insert(QUESTS,{id=2,title="A dungeon job",level=20,objectives={}})')
    g.slash("auto off"); g.join_party(["Anna"])
    g.fire("GROUP_ROSTER_UPDATE")
    assert b.shareable and b.why is None, "repainted on the roster / log event while the page is open"
    assert [round(v, 2) for v in list(b.bg.rgba.values())[:3]] == [.10, .34, .10]
    assert not g.eval("NS.db.errors")


def test_going_home_clears_a_level_error(style):
    g = opened(style)
    w = g.eval("NS.dungeonQuests._window()")
    w.levelError = "Character level must be a whole number from 1 to 1000."
    g.eval("NS.dungeonQuests.home")()
    assert w.levelError is None
    assert not g.eval("NS.db.errors")


def test_items_without_a_loot_source_keep_the_plain_tooltip(style):
    g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
    g.run("BOSS_ASKS=0 NS.loot.bossesOf=function(name,done) BOSS_ASKS=BOSS_ASKS+1 if done then done({},nil,'no loot source') end return {},nil,'no loot source' end")
    filters(g, dungeon=1581)
    w = quest_page(g, 2)
    staff, _ = items_of(w)
    staff.scripts.OnEnter(staff)
    assert g.eval("TOOLTIP.link") == "item:810" and not any("Drops from" in l for l in tip_lines(g))
    click(staff); assert w.questsPage.shown
    assert not g.eval("NS.db.errors")


def test_standing_in_a_dungeon_opens_its_page(style):
    g = game(style, HOVER_DATA + "IN_INSTANCE=true GetInstanceInfo=function() return 'The Deadmines','party' end", open_tab=False)
    g.slash("dungeons"); g.advance(90)
    w = g.eval("NS.dungeonQuests._window()")
    assert D(g, "current")() == 1581 and w.dungeonView.shown and w.tabs.quests.selected


# ===== Round 3, stream U: user-story polish =====
W = "NS.dungeonQuests._window()"


def test_the_filter_bar_is_one_row_and_the_rest_opens_from_a_filters_button(style):
    g = opened(style); w = g.eval(W)
    D(g, "openDungeon")(1581)
    for key in ("filtersButton", "mine", "reset", "reload", "completed", "inLog"):
        assert w[key].point[5] == -17, (key, w[key].point[5])
    assert w.search.point[5] == -17 and not w.filterPanel.shown, "one row; Level / Class / Faction start folded"
    assert w.filtersButton.text == "Filters", "All quests: no filter narrows the list"
    click(w.filtersButton)
    assert w.filterPanel.shown
    for key in ("level", "levelMode", "class", "faction"):
        assert g.eval(f"{W}[{key!r}].parent=={W}.filterPanel"), key
    w["class"].chooseValue("MAGE")
    assert w.filtersButton.text == "Filters (1)" and w.filterPanel.shown, "a choice keeps the panel open and is counted"
    assert all(r.classes == 0 or r.id == 7 for r in D(g, "_results")().values() if r.dungeons[1581]), "the class filter still filters"
    click(w.levelMode)
    assert w.filtersButton.text == "Filters (2)"
    click(w.reset)
    assert w.filtersButton.text == "Filters"
    click(w.filtersButton); assert not w.filterPanel.shown, "the button folds it again"
    click(w.filtersButton); click(w.tabs.map)
    assert not w.filterPanel.shown, "another tab folds it"
    click(w.tabs.quests); click(w.filtersButton); D(g, "home")()
    assert not w.filterPanel.shown
    assert not g.eval("NS.db.errors")


def test_talk_only_is_not_shown_under_objective_text_but_a_real_task_kind_is(style):
    g = opened(style, "QUESTIE_QUESTS[2].objectivesText={'Bring 10 Red Silk Bandanas to Scout Riell.'}")
    filters(g, dungeon=1581)
    p = quest_page(g, 2).panel
    assert "Bring 10 Red Silk Bandanas" in plain(p.doText.text)
    assert not p.doKind.shown, "'Talk only' contradicts 'Bring 10 ...'"
    g = opened(style, "QUESTIE_QUESTS[4].objectivesText={'Defeat the Dungeon captain.'}")
    filters(g, dungeon=1581)
    p = quest_page(g, 4).panel
    assert p.doKind.shown and p.doKind.text == "Defeat enemies"
    # with no objective text the talk-only quest still says who to talk to
    g = opened(style); filters(g, dungeon=1581)
    p = quest_page(g, 2).panel
    assert plain(p.doText.text).startswith("Talk to ") and not p.doKind.shown
    assert not g.eval("NS.db.errors")


def test_class_icons_get_a_class_coloured_ring_that_follows_the_icon(style):
    g = opened(style)
    icon = g.eval("NS.journalTheme.classIcon(UIParent, 16, 'WARRIOR')")
    ring = icon.ring
    assert [round(v, 2) for v in list(ring.rgba.values())[:3]] == [.78, .61, .43], "the warrior's class colour"
    assert g.eval("(function() local t=NS.journalTheme.classIcon(UIParent,16,'MAGE') return t.ring.point[2]==t end)()"), "anchored on the icon"
    icon.Hide(icon); assert not ring.shown and not icon.shown
    icon.Show(icon); assert ring.shown and icon.shown
    other = g.eval("NS.journalTheme.classIcon(UIParent, 16, 'DRUID')")
    assert other.ring and other.ring.rgba, "no client colour: a muted ring instead of none"
    assert not g.eval("NS.db.errors")


def test_a_pending_boss_click_is_dropped_on_a_tab_or_dungeon_change(style):
    for move in ("tab", "dungeon", "home"):
        g = opened(style, ITEMS + "UnitLevel=function() return 30 end")
        g.run(BOSSES + "BOSS_LATE=true")
        filters(g, dungeon=1581)
        w = quest_page(g, 2)
        staff, _ = items_of(w)
        staff.scripts.OnEnter(staff); click(staff)
        if move == "tab": click(w.tabs.map); click(w.tabs.quests)
        elif move == "dungeon": D(g, "openDungeon")(718); D(g, "openDungeon")(1581)
        else:
            D(g, "home")()
            g.run("BOSS_DONE()")  # the list arrives while you are still on the home
            assert w.homeView.shown and not w.tabs.bosses.selected and g.eval("SELECTED_BOSS") is None, "home"
            D(g, "openDungeon")(1581)
        g.run("BOSS_DONE()")
        assert w.questsPage.shown and not w.tabs.bosses.selected and g.eval("SELECTED_BOSS") is None, move
        assert not g.eval("NS.db.errors")


def test_quests_for_npc_lists_the_open_dungeons_kill_quests(style):
    g = opened(style)
    assert len(list(D(g, "questsForNpc")(900).values())) == 0, "no dungeon open"
    D(g, "openDungeon")(1581)
    rows = list(D(g, "questsForNpc")(900).values())
    ids = [r.id for r in rows]
    assert {4, 9, 15} <= set(ids), ids  # kill objective, two-NPC kill objective, kill-credit objective
    assert not {12, 13} & set(ids), "giving or taking a quest is not a kill"
    assert all(r.name and r.state and r.label and r.level for r in rows)
    levels = [r.level for r in rows]
    assert levels == sorted(levels)
    assert [r.id for r in D(g, "questsForNpc")(900, 718).values()] == [9], "another dungeon by area"
    assert len(list(D(g, "questsForNpc")("nope").values())) == 0
    assert not g.eval("NS.db.errors")


def test_open_quest_jumps_to_that_quest_on_the_quests_tab(style):
    g = opened(style); w = g.eval(W)
    D(g, "openDungeon")(1581, "bosses")
    assert D(g, "openQuest")(4) and w.tabs.quests.selected and w.questsPage.shown
    assert w.panel.title.text == "Class mission"
    assert not D(g, "openQuest")(8), "a quest of another dungeon"
    assert not g.eval("NS.db.errors")


def test_open_quest_reaches_a_quest_hidden_by_a_filter_through_all_quests(style):
    g = opened(style); w = g.eval(W)
    D(g, "openDungeon")(1581, "bosses")
    w["class"].chooseValue("MAGE")
    assert 4 not in [r.id for r in D(g, "_results")().values()], "the class filter hides it"
    assert D(g, "openQuest")(4), "Needed for always lands on the quest"
    assert w.tabs.quests.selected and w.panel.title.text == "Class mission"
    assert w.filtersButton.text == "Filters", "the filters were reset (All quests)"
    assert not D(g, "openQuest")(8), "a quest of another dungeon: no reset helps"
    assert not g.eval("NS.db.errors")


def test_the_filters_popover_closes_on_escape_and_on_a_click_outside(style):
    g = opened(style); w = g.eval(W)
    D(g, "openDungeon")(1581)
    click(w.filtersButton)
    assert w.filterPanel.shown and w.filterCatcher.shown
    w.filterPanel.scripts.OnKeyDown(w.filterPanel, "A")
    assert w.filterPanel.shown, "another key leaves it open"
    w.filterPanel.scripts.OnKeyDown(w.filterPanel, "ESCAPE")
    assert not w.filterPanel.shown and not w.filterCatcher.shown, "Escape closes it"
    click(w.filtersButton)
    w.filterCatcher.scripts.OnClick(w.filterCatcher, "LeftButton")
    assert not w.filterPanel.shown and not w.filterCatcher.shown, "a click outside closes it"
    click(w.filtersButton); click(w.tabs.map)
    assert not w.filterCatcher.shown, "a tab change drops the catcher too"
    assert not g.eval("NS.db.errors")


def test_the_filters_popover_never_swallows_keys_in_combat_after_an_escape(style):
    g = opened(style); w = g.eval(W)
    D(g, "openDungeon")(1581)
    g.run("""PROP={}; local p=%s.filterPanel
        function p:SetPropagateKeyboardInput(v)
            if InCombatLockdown() then error('protected in combat') end
            self.propagate=v; PROP[#PROP+1]=v end""" % W)
    click(w.filtersButton)
    w.filterPanel.scripts.OnKeyDown(w.filterPanel, "ESCAPE")
    assert not w.filterPanel.shown and w.filterPanel.propagate is True, "hide puts propagation back on"
    click(w.filtersButton)
    assert w.filterPanel.shown and w.filterPanel.keyboard and w.filterPanel.propagate is True
    g.run("InCombatLockdown=function() return true end"); g.fire("PLAYER_REGEN_DISABLED")
    assert not w.filterPanel.keyboard, "combat lets go of the keyboard"
    w.filterPanel.scripts.OnKeyDown(w.filterPanel, "W")
    assert w.filterPanel.propagate is True, "a movement key still reaches the game"
    click(w.filtersButton); click(w.filtersButton)
    assert w.filterPanel.shown and not w.filterPanel.keyboard, "reopened in combat: no keyboard"
    g.run("InCombatLockdown=function() return false end"); g.fire("PLAYER_REGEN_ENABLED")
    assert not g.eval("NS.db.errors")


def test_header_shows_the_journal_description_as_one_muted_line(style):
    g = opened(style); w = g.eval(W)
    g.run("NS.dungeonLore.dungeon=function() return nil end")
    D(g, "openDungeon")(1581)
    assert w.lore.text == "" and not w.loreText, "no journal entry: an empty line, no error"
    g.run("NS.dungeonLore.dungeon=function(area,name) if area==1581 then return {description='A  gold mine\\nturned pirate base.'} end end")
    D(g, "openDungeon")(718); D(g, "openDungeon")(1581)
    assert w.lore.text == "A gold mine turned pirate base." and w.lore.wordWrap is False
    w.loreHover.scripts.OnEnter(w.loreHover)
    assert "A gold mine turned pirate base." in "\n".join(g.eval("TOOLTIP.lines").values())
    D(g, "openDungeon")(718)
    assert w.lore.text == "", "no stale text from the last dungeon"
    g.run("NS.dungeonLore.dungeon=function() error('broken lore') end"); D(g, "openDungeon")(1581)
    g.run("NS.dungeonLore=nil"); D(g, "openDungeon")(718)
    assert w.lore.text == ""
    assert not g.eval("NS.db.errors")


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
