"""Cooking reference and profession companion through the real Lua modules."""
import inspect
from test_optional import game, STYLES

API = r'''
READS, FILTER_WRITES, RECIPE_ENUMERATIONS = 0,0,0
PROFESSION, LINKED, CHANGING = 185,false,false
RECIPE_INFO = {[7751]={name="Brilliant Smallfish",learned=true},[7752]={learned=false}}
C_TradeSkillUI={
 GetBaseProfessionInfo=function() return {professionID=PROFESSION} end,
 GetRecipeInfo=function(id) READS=READS+1;return RECIPE_INFO[id] end,
 IsTradeSkillLinked=function()return LINKED end,
 IsDataSourceChanging=function()return CHANGING end,
 GetRecipeSourceText=function(id)return id==7752 and "Live recipe seller" or nil end,
 SetShowUnlearned=function() FILTER_WRITES=FILTER_WRITES+1 end,
 GetAllRecipeIDs=function() RECIPE_ENUMERATIONS=RECIPE_ENUMERATIONS+1;return {7751,7752,999999} end,
}
ProfessionsFrame=CreateFrame("Frame","ProfessionsFrame",UIParent)
'''


def joined(rows):
    return "\n".join(rows.values())


def test_login_never_reads_profession_recipes_or_enumerates_database(style):
    g=game(style,API)
    assert g.eval("READS")==0 and g.eval("ENUMERATIONS")==0
    assert g.eval("NS.professions._window()") is None


def test_catalogue_search_has_forever_dishes_and_unknown_states(style):
    g=game(style)
    assert g.eval("#NS.cookingReference.recipes")==133
    g.slash("cooking")
    w=g.eval("NS.professions._window()")
    assert w.frame.shown and "133 recipes" in w.counter.text
    assert "Unconfirmed" in w.detail.text
    assert g.eval('#NS.professions.recipes("peace tea")')>0
    assert g.eval('#NS.professions.recipes("raw brilliant smallfish")')>0
    assert g.eval('#NS.professions.recipes("", "Missing")')==0


def test_live_cooking_confirms_known_missing_and_does_not_change_filters(style):
    g=game(style,API);g.fire("TRADE_SKILL_SHOW");g.advance(3)
    assert g.eval("NS.professions._learned()[7751]") is True
    assert g.eval("NS.professions._learned()[7752]") is False
    assert g.eval("NS.professions._learned()[7753]") is None
    assert g.eval('#NS.professions.recipes("", "Missing")')==1
    assert g.eval("FILTER_WRITES")==0 and g.eval("RECIPE_ENUMERATIONS")==0
    assert g.eval("READS")==133
    assert g.eval("NS.professions._window().frame.shown")


def test_other_or_linked_profession_cannot_mark_cooking_recipes_missing(style):
    g=game(style,API+"PROFESSION=171")
    g.fire("TRADE_SKILL_SHOW");g.advance(3)
    assert g.eval("READS")==0 and g.eval("NS.professions._window()") is None
    g.run("PROFESSION=185;LINKED=true");g.slash("cooking");g.advance(3)
    assert g.eval("READS")==0 and g.eval("NS.professions._learned()[7751]") is None


def test_scan_pauses_in_combat_and_cancel_on_master_off(style):
    g=game(style,API+"IN_COMBAT=true")
    g.slash("cooking");g.advance(1)
    assert g.eval("READS")==0
    g.run("IN_COMBAT=false");g.advance(0.3)
    assert g.eval("READS")>0
    g.slash("off");before=g.eval("READS");g.advance(4)
    assert g.eval("READS")==before
    assert not g.eval("NS.professions._window().frame.shown")


def test_scan_close_cancels_remaining_slices(style):
    g=game(style,API);g.slash("cooking")
    assert g.eval("READS")==12
    g.eval("NS.professions.close")();g.advance(4)
    assert g.eval("READS")==12


def test_pending_native_open_is_cancelled_if_profession_closes(style):
    g=game(style,API);g.fire("TRADE_SKILL_SHOW");g.fire("TRADE_SKILL_CLOSE");g.advance(3)
    assert g.eval("NS.professions._window()") is None and g.eval("READS")==0


def test_switching_to_cooking_inside_open_profession_window_opens_reference(style):
    g=game(style,API+"PROFESSION=171");g.fire("TRADE_SKILL_SHOW");g.advance(1)
    assert g.eval("NS.professions._window()") is None
    g.run("PROFESSION=185;CHANGING=true");g.fire("TRADE_SKILL_DATA_SOURCE_CHANGED");g.advance(0.2)
    assert g.eval("READS")==0
    g.run("CHANGING=false");g.advance(3)
    assert g.eval("NS.professions._window().frame.shown") and g.eval("READS")==133
    g.run("PROFESSION=171");g.fire("TRADE_SKILL_DATA_SOURCE_CHANGED");g.advance(1)
    assert not g.eval("NS.professions._window().frame.shown")


def test_all_professions_have_both_factions_and_four_rank_requirements(style):
    g=game(style);g.slash("professions")
    assert g.eval("#NS.professionReference.professions")==12
    g.run('''for _,p in ipairs(NS.professionReference.professions) do
      assert(#p.ranks==4)
      for _,r in ipairs(p.ranks) do assert(r.Alliance and r.Horde and r.cap and r.skill) end
    end''')
    w=g.eval("NS.professions._window()")
    assert "Alliance:" in w.upgradeDetail.text and "Horde:" in w.upgradeDetail.text
    assert "Ainethil" in w.upgradeDetail.text and "Rogvar" in w.upgradeDetail.text
    w.faction.scripts.OnClick(w.faction)
    assert "Alliance:" in w.upgradeDetail.text and "Horde:" not in w.upgradeDetail.text
    w.professions[3].scripts.OnClick(w.professions[3])
    assert "Clamlette Surprise" in w.upgradeDetail.text and "12 Giant Eggs" in w.upgradeDetail.text


def test_cooking_sources_cover_starter_fish_for_both_factions_without_questie(style):
    g=game(style);g.slash("cooking")
    text=g.eval("NS.professions._window().detail.text")
    assert "Tharynn Bouden" in text and "Harn Longcast" in text
    assert "Elwynn Forest" in text and "Mulgore" in text


def test_fish_hover_has_zone_level_and_skill_unknowns_are_explicit(style):
    g=game(style);g.slash("cooking")
    b=g.eval("NS.professions._window().ingredients[1]");b.scripts.OnEnter(b)
    text=joined(g.eval("TOOLTIP.lines"))
    assert "Crystal Lake" in text and "zone levels 1-12" in text
    assert "Fishing minimum: 1" in text and "no-getaway: unknown" in text
    text=joined(g.eval("NS.professions.materialLines(13759)"))
    assert "Feralas" in text and "12:00-18:00" in text and "minimum: unknown" in text


def test_meat_hover_reads_only_item_drops_and_shows_mob_and_zone_levels(style):
    g=game(style,r'''
    local old=ItemDB.Get
    ItemDB.Get=function(id,key) if id==769 and key=="npcDrops" then return {197} end;return old(id,key) end
    local oldNpc=NpcDB.Get
    NpcDB.Get=function(id,key) if id==197 and key=="minLevel" then return 5 end;if id==197 and key=="maxLevel" then return 6 end;return oldNpc(id,key) end
    ''')
    text=joined(g.eval("NS.professions.materialLines(769)"))
    assert "Drops from:" in text and "mob level 5-6" in text and "zone levels 1-12" in text
    assert "does not require Skinning" in text and g.eval("ENUMERATIONS")==0


def test_paging_filter_search_and_recipe_selection(style):
    g=game(style,API);g.slash("cooking");g.advance(3)
    w=g.eval("NS.professions._window()")
    first=w.rows[1].recipe.id;w.nextPage.scripts.OnClick(w.nextPage)
    assert w.rows[1].recipe.id!=first
    w.search.SetText(w.search,"nightfin");w.search.scripts.OnTextChanged(w.search)
    assert "1 recipes" in w.counter.text
    w.rows[1].scripts.OnClick(w.rows[1]);assert "Gikkix" in w.detail.text and "Tanaris" in w.detail.text
    w.search.SetText(w.search,"");w.search.scripts.OnTextChanged(w.search)
    w.mode.scripts.OnClick(w.mode)
    assert "1 recipes" in w.counter.text and "Slitherskin" in w.rows[1].text
    assert "Live recipe seller" in w.detail.text


def test_disabled_integration_hides_buttons_and_prevents_automatic_open(style):
    g=game(style,API);g.slash("professions off")
    g.fire("TRADE_SKILL_SHOW");g.advance(2)
    assert g.eval("NS.professions._window()") is None and g.eval("READS")==0
    g.slash("professions");assert g.eval("NS.db.professionGuide")


def test_fishing_panel_opens_cooking_reference(style):
    g=game(style);g.slash("fishing")
    g.run('for _,f in ipairs(FRAMES) do if f.text=="Cooking / recipes" then f.scripts.OnClick(f);break end end')
    assert g.eval("NS.professions._window().frame.shown")


def test_tooltip_supports_modern_processor_and_does_not_label_recipe_books_as_ingredients(style):
    g=game(style,r'''
      Enum=Enum or {};Enum.TooltipDataType={Item=0}
      TooltipDataProcessor={AddTooltipPostCall=function(kind,fn) FARM_CALLBACK=fn end}
    ''')
    g.run('GameTooltip:SetOwner(UIParent);FARM_CALLBACK(GameTooltip,{id=6291})')
    assert "Crystal Lake" in joined(g.eval("TOOLTIP.lines"))
    count=len(g.eval("TOOLTIP.lines"));g.run('FARM_CALLBACK(GameTooltip,{id=6291})')
    assert len(g.eval("TOOLTIP.lines"))==count
    g.run('GameTooltip:SetOwner(UIParent);FARM_CALLBACK(GameTooltip,{id=6325})')
    assert len(g.eval("TOOLTIP.lines"))==0


def test_faction_switch_cooking_to_upgrades_and_back_hides_correct_controls(style):
    g=game(style);g.slash("cooking");w=g.eval("NS.professions._window()")
    w.upgradesTab.scripts.OnClick(w.upgradesTab)
    assert not w.search.shown and not w.searchLabel.shown and w.faction.shown
    assert not w.rows[1].shown and w.professions[1].shown
    w.cookingTab.scripts.OnClick(w.cookingTab)
    assert w.search.shown and not w.faction.shown and w.rows[1].shown


if __name__=="__main__":
    failed=total=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"): continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total+=1
            try: fn(style) if style else fn();print("ok  ",f"{name}[{style}]")
            except Exception as e: failed+=1;print("FAIL",f"{name}[{style}]",type(e).__name__,str(e)[:800])
    print(f"\n{total-failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
