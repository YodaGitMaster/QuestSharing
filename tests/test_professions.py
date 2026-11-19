"""Embedded profession GUI, native craft handoff, source model and lifecycle regression checks."""
import inspect
from test_optional import game as base_game, STYLES

API = r'''
READS,FILTER_WRITES,RECIPE_ENUMERATIONS,CRAFT_CALLS,NATIVE_SELECTIONS=0,0,0,0,{}
PROFESSION,LINKED,CHANGING=185,false,false
RECIPE_INFO={[7751]={recipeID=7751,name="Brilliant Smallfish",learned=true,icon="fish"},[7752]={recipeID=7752,name="Slitherskin Mackerel",learned=false}}
C_TradeSkillUI={
 GetBaseProfessionInfo=function()return {professionID=PROFESSION}end,
 GetRecipeInfo=function(id)READS=READS+1;return RECIPE_INFO[id]end,
 IsTradeSkillLinked=function()return LINKED end,
 IsDataSourceChanging=function()return CHANGING end,
 GetRecipeSourceText=function(id)return id==7752 and "Live recipe seller" or nil end,
 SetShowUnlearned=function()FILTER_WRITES=FILTER_WRITES+1 end,
 GetAllRecipeIDs=function()RECIPE_ENUMERATIONS=RECIPE_ENUMERATIONS+1;return {7751,7752}end,
 IsRecipeInSkillLine=function(id,skill)return id==999999 and skill==185 end,
 CraftRecipe=function()CRAFT_CALLS=CRAFT_CALLS+1 end,
}
local create=CreateFrame
CreateFrame=function(kind,name,parent,template)
 local f=create(kind,name,parent,template)
 f.template=template
 local makeText=f.CreateFontString
 f.CreateFontString=function(self,...)
  local t=makeText(self,...)
  function t:SetFont(path,size,flags)self.fontPath=path;self.fontSize=size end
  function t:SetTextColor(r,g,b,a)self.color={r,g,b,a} end
  return t
 end
 if kind=="ScrollFrame"then
  function f:GetVerticalScrollRange()return self.scrollRange or math.max(0,(self.scrollChild and self.scrollChild:GetHeight()or 0)-self:GetHeight())end
  function f:SetVerticalScroll(value)
   self.vscroll=math.max(0,math.min(self:GetVerticalScrollRange(),value))
   for _,fn in ipairs(self.posthooks and self.posthooks.OnVerticalScroll or {})do fn(self,self.vscroll)end
  end
 end
 return f
end
ProfessionsFrame=CreateFrame("Frame","ProfessionsFrame",UIParent)
ProfessionsFrame:SetWidth(750);ProfessionsFrame:SetHeight(594)
ProfessionsFrame:Hide()
local page=CreateFrame("Frame",nil,ProfessionsFrame);ProfessionsFrame.CraftingPage=page
page:SetWidth(750);page:SetHeight(594)
page.RecipeList=CreateFrame("Frame",nil,page);page.RecipeList:SetWidth(304);page.RecipeList:SetHeight(516)
page.SchematicForm=CreateFrame("Frame",nil,page);page.SchematicForm:SetWidth(360);page.SchematicForm:SetHeight(490)
page.CreateButton=CreateFrame("Button",nil,page)
page.SchematicForm.ClearTransaction=function(self)self.cleared=true end
page.SchematicForm.Init=function(self,info)self.recipe=info end
page.SchematicForm.GetRecipeInfo=function(self)return self.recipe end
page.ValidateControls=function(self)self.CreateButton:SetEnabled(self.SchematicForm.recipe and self.SchematicForm.recipe.learned==true)end
page.SelectRecipe=function(self,info,skipSelectInList)
 assert(info and info.learned,"Only actual learned recipeInfo may reach the native schematic")
 NATIVE_SELECTIONS[#NATIVE_SELECTIONS+1]={id=info.recipeID,skip=skipSelectInList}
 self.SchematicForm:Init(info);self:ValidateControls()
end
page.Refresh=function()end
'''


def game(style,extra="",native=True):
    return base_game(style,(API if native else "")+extra)


def joined(rows):
    return "\n".join(rows.values())


def open_cooking(g):
    g.run('ProfessionsFrame:Show()');g.fire("TRADE_SKILL_SHOW");g.advance(3)
    return g.eval("NS.professions._window()")


def select(g,spell):
    g.run(f"NS.professionUI.select(NS.professions.record({spell}))")


def test_login_attaches_only_child_frames_without_recipe_reads(style):
    g=game(style)
    assert g.eval("READS")==0 and g.eval("ENUMERATIONS")==0
    assert not g.eval("QuestSharingProfessions")
    assert g.eval("NS.professions._window().frame==ProfessionsFrame")
    assert g.eval("NS.professions._window().list.parent==ProfessionsFrame.CraftingPage.RecipeList")
    assert not g.eval("NS.professions._window().list.shown")


def test_missing_native_window_never_creates_a_new_window(style):
    g=game(style,native=False);g.slash("cooking");g.slash("professions")
    assert g.eval("NS.professions._window()") is None
    assert g.eval("QuestSharingProfessions") is None
    assert "profession window" in "\n".join(g.printed())


def test_open_cooking_uses_embedded_list_and_live_states(style):
    g=game(style);w=open_cooking(g)
    assert w.list.shown and w.frame.name=="ProfessionsFrame"
    assert g.eval("NS.professions._learned()[7751]") is True
    assert g.eval("NS.professions._learned()[7752]") is False
    assert g.eval("NS.professions._learned()[7753]") is None
    assert g.eval('#NS.professions.recipes("", "Missing")')==1
    assert g.eval("READS")==133 and g.eval("FILTER_WRITES")==0


def test_list_scrolls_through_every_recipe_without_paging(style):
    g=game(style);w=open_cooking(g)
    assert len(w.results)==133 and w.listContent.GetHeight(w.listContent)==133*44
    assert len(w.rows)>=10
    first=w.rows[1].recipe.id
    w.listScroll.SetVerticalScroll(w.listScroll,44*12)
    assert w.rows[1].recipe.id!=first
    w.listScroll.SetVerticalScroll(w.listScroll,w.listScroll.GetVerticalScrollRange(w.listScroll))
    ids=[r.recipe.id for r in w.rows.values() if r.shown]
    assert w.results[len(w.results)].id in ids
    assert w.previous is None and w.nextPage is None


def test_row_has_separate_name_skill_source_and_readable_fonts(style):
    g=game(style);w=open_cooking(g)
    row=w.rows[1]
    assert row.name.text=="Brilliant Smallfish" and row.skill.text=="1"
    assert "Vendor" in row.source.text and "|" not in row.name.text
    assert row.name.fontSize==14 and row.skill.fontSize==14 and row.source.fontSize==12
    assert w.title.fontSize==18 and w.sourceText.fontSize==14
    assert row.GetHeight(row)==44


def test_unlearned_rows_are_gray_but_clickable(style):
    g=game(style);w=open_cooking(g)
    unknown=next(r for r in w.rows.values() if r.recipe and r.recipe.id==7752)
    known=next(r for r in w.rows.values() if r.recipe and r.recipe.id==7751)
    assert unknown.name.color[1]==unknown.name.color[2]==unknown.name.color[3]
    assert known.name.color[1]!=known.name.color[3]
    unknown.scripts.OnClick(unknown)
    assert w.missing.shown and "Not learned" in w.status.text
    assert w.requirement.text=="Requires Cooking 1"
    assert "Live recipe seller" in w.sourceText.text
    assert "Data:" not in w.sourceText.text and "Reference checked" not in w.sourceText.text


def test_known_recipe_uses_actual_native_crafting_controls(style):
    g=game(style);w=open_cooking(g);select(g,7751)
    assert not w.missing.shown and w.native.CreateButton.enabled
    assert g.eval("NATIVE_SELECTIONS[#NATIVE_SELECTIONS].id")==7751
    assert g.eval("NATIVE_SELECTIONS[#NATIVE_SELECTIONS].skip") is True
    assert w.nativeSource.shown and "Cooking 1" in w.nativeSource.text
    assert g.eval("CRAFT_CALLS")==0


def test_unknown_selection_clears_previous_native_recipe_and_disables_crafting(style):
    g=game(style);w=open_cooking(g);select(g,7751);select(g,7752)
    assert w.native.SchematicForm.recipe is None
    assert not w.native.CreateButton.enabled and w.missing.shown
    assert g.eval("CRAFT_CALLS")==0
    select(g,7753)
    assert "unavailable" in w.status.text and w.missing.shown


def test_search_filters_all_recipes_without_native_filter_mutation(style):
    g=game(style);w=open_cooking(g)
    w.search.SetText(w.search,"nightfin");w.search.scripts.OnTextChanged(w.search)
    assert len(w.results)==1 and "Nightfin Soup"==w.results[1].name
    assert "Gikkix" in w.sourceText.text and "Tanaris" in w.sourceText.text
    assert g.eval("FILTER_WRITES")==0
    w.search.SetText(w.search,"unfindable-text");w.search.scripts.OnTextChanged(w.search)
    assert "No recipes" in w.empty.text


def test_native_background_selection_cannot_replace_visible_unlearned_selection(style):
    g=game(style);w=open_cooking(g);select(g,7752)
    g.run('ProfessionsFrame.CraftingPage:SelectRecipe(RECIPE_INFO[7751],true)')
    assert w.missing.shown and w.title.text=="Slitherskin Mackerel"
    assert not w.native.CreateButton.enabled


def test_native_refresh_preserves_selected_unlearned_recipe(style):
    g=game(style,'page.Refresh=function(self)self:SelectRecipe(RECIPE_INFO[7751],true)end');w=open_cooking(g);select(g,7752)
    g.run('ProfessionsFrame.CraftingPage:Refresh()')
    assert w.missing.shown and w.title.text=="Slitherskin Mackerel"
    assert not w.native.CreateButton.enabled


def test_short_source_returns_one_text_value_for_drop_recipes(style):
    g=game(style)
    text=g.eval('NS.professions.shortSource(NS.professions.record(1249957))')
    assert isinstance(text,str) and text.startswith('Drop - ')


def test_short_vendor_source_prefers_current_faction_location(style):
    g=game(style)
    text=g.eval('NS.professions.shortSource(NS.professions.record(18247))')
    assert 'Feathermoon' in text and '(Horde)' not in text


def test_fish_hover_has_zone_levels_skill_and_explicit_unknowns(style):
    g=game(style);w=open_cooking(g);select(g,7753)
    b=w.ingredients[1];b.scripts.OnEnter(b)
    text=joined(g.eval("TOOLTIP.lines"))
    assert "Stormwind" in text and "Fish stay hooked from skill 75" in text
    text=joined(g.eval("NS.professions.materialLines(13759)"))
    assert "Feralas" in text and "12:00-18:00" in text and "Fishing skill needed: not known" in text


def test_meat_drop_tooltip_has_mob_levels_locations_and_zone_range(style):
    g=game(style,r'''
      local old=ItemDB.Get;ItemDB.Get=function(id,key)if id==769 and key=="npcDrops"then return {197}end;return old(id,key)end
      local old=NpcDB.Get;NpcDB.Get=function(id,key)if id==197 and key=="minLevel"then return 5 end;if id==197 and key=="maxLevel"then return 6 end;return old(id,key)end
    ''')
    text=joined(g.eval("NS.professions.materialLines(769)"))
    assert "Drops from:" in text and "mob level 5-6" in text and "zone levels 1-12" in text
    assert g.eval("ENUMERATIONS")==0


def test_cooking_sources_cover_both_factions_without_questie(style):
    g=game(style);w=open_cooking(g);select(g,7751)
    r=g.eval('NS.professions.record(7751)')
    text=joined(g.eval('NS.professions.recipeSources')(r))
    assert "Harn Longcast" in text and "Tharynn Bouden" in text
    # Main pane prioritizes the current faction; complete data remains in hover/reference methods.
    assert "Tharynn Bouden" in joined(g.eval('NS.professions.acquisition')(r))
    assert "Harn Longcast" not in joined(g.eval('NS.professions.acquisition')(r))


def test_linked_or_other_profession_does_not_gain_cooking_overlay(style):
    g=game(style,"PROFESSION=171");w=open_cooking(g)
    assert not w.list.shown and g.eval("READS")==0
    g.run("PROFESSION=185;LINKED=true");g.fire("TRADE_SKILL_DATA_SOURCE_CHANGED");g.advance(3)
    assert not w.list.shown and g.eval("READS")==0


def test_switching_to_cooking_inside_open_window_attaches_without_popup(style):
    g=game(style,"PROFESSION=171");w=open_cooking(g)
    g.run("PROFESSION=185;CHANGING=true");g.fire("TRADE_SKILL_DATA_SOURCE_CHANGED");g.advance(0.2)
    assert g.eval("READS")==0
    g.run("CHANGING=false");g.advance(3)
    assert w.list.shown and g.eval("READS")==133 and not g.eval("QuestSharingProfessions")


def test_combat_pauses_reads_and_close_cancels_slices(style):
    g=game(style,"IN_COMBAT=true");g.run('ProfessionsFrame:Show()');g.fire("TRADE_SKILL_SHOW");g.advance(2)
    assert g.eval("READS")==0
    g.run("IN_COMBAT=false");g.fire("PLAYER_REGEN_ENABLED");g.slash("cooking")
    assert g.eval("READS")==12
    g.fire("TRADE_SKILL_CLOSE");g.advance(4)
    assert g.eval("READS")==12


def test_pending_native_open_cancels_on_close(style):
    g=game(style);g.fire("TRADE_SKILL_SHOW");g.fire("TRADE_SKILL_CLOSE");g.advance(3)
    assert g.eval("READS")==0 and not g.eval("NS.professions._window().list.shown")


def test_disable_hides_overlays_and_restores_native_view(style):
    g=game(style);w=open_cooking(g);select(g,7752);g.slash("professions off")
    assert not w.list.shown and not w.missing.shown
    before=g.eval("READS");g.fire("TRADE_SKILL_SHOW");g.advance(3);assert g.eval("READS")==before
    g.slash("professions");assert g.eval("NS.db.professionGuide") and w.list.shown
    g.slash("off");assert not w.list.shown


def test_new_live_cooking_recipe_is_included_without_cross_profession_leaks(style):
    g=game(style,'RECIPE_INFO[999999]={recipeID=999999,name="New Hotfix Dish",learned=true};C_TradeSkillUI.GetAllRecipeIDs=function()return {7751,7752,999999}end')
    w=open_cooking(g)
    assert len(w.results)==134 and g.eval('#NS.professions.recipes("new hotfix dish")')==1
    g.run('RECIPE_INFO[999999].learned=false');g.fire('SPELLS_CHANGED');g.advance(3)
    assert g.eval('NS.professions._learned()[999999]') is False


def test_fishing_button_uses_existing_profession_frame(style):
    g=game(style);g.slash('fishing')
    g.run('for _,f in ipairs(FRAMES)do if f.text=="Cooking / recipes"then f.scripts.OnClick(f);break end end')
    assert g.eval('NS.professions._window().frame==ProfessionsFrame')
    assert not g.eval('QuestSharingProfessions')


def test_modern_item_tooltips_are_bounded_and_dont_decorate_recipe_books(style):
    g=game(style,r'''
      Enum=Enum or {};Enum.TooltipDataType={Item=0}
      TooltipDataProcessor={AddTooltipPostCall=function(kind,fn)FARM_CALLBACK=fn end}
    ''')
    g.run('GameTooltip:SetOwner(UIParent);FARM_CALLBACK(GameTooltip,{id=6291})')
    assert "Crystal Lake" in joined(g.eval('TOOLTIP.lines'))
    count=len(g.eval('TOOLTIP.lines'));g.run('FARM_CALLBACK(GameTooltip,{id=6291})');assert len(g.eval('TOOLTIP.lines'))==count
    g.run('GameTooltip:SetOwner(UIParent);FARM_CALLBACK(GameTooltip,{id=6325})');assert len(g.eval('TOOLTIP.lines'))==0


def test_item_source_hint_uses_tooltip_data_so_professions_items_get_it(style):
    g=game(style,r"""
      Enum=Enum or {};Enum.TooltipDataType={Item=0}
      POST={}
      TooltipDataProcessor={AddTooltipPostCall=function(kind,fn)POST[#POST+1]=fn end}
      QUESTIE_NPCS[9901]={name="Test Trader",subName="Cook Supplies"}
      QUESTIE_ITEMS[9900]={name="Test Herb",vendors={9901}}
    """)
    g.run('NS.db.itemSources=true;NS.itemSources.refresh()')
    # The Professions window hands the tooltip data only (no GetItem link); the hint must still appear.
    g.run('GameTooltip:SetOwner(UIParent);for _,fn in ipairs(POST) do fn(GameTooltip,{id=9900}) end')
    assert "Sold by: Cook Supplies" in joined(g.eval('TOOLTIP.lines'))
    count=len(g.eval('TOOLTIP.lines'));g.run('for _,fn in ipairs(POST) do fn(GameTooltip,{id=9900}) end')
    assert len(g.eval('TOOLTIP.lines'))==count


def test_long_sources_and_ingredients_flow_vertically_in_scroll_content(style):
    g=game(style);w=open_cooking(g)
    g.run('NS.professions.acquisition=function()return {string.rep("Long source name ",100)}end')
    select(g,7752)
    assert -w.ingredients[1].point[5]>-w.sourceText.point[5]+w.sourceText.GetStringHeight(w.sourceText)
    assert w.detailContent.GetHeight(w.detailContent)>w.detailScroll.GetHeight(w.detailScroll)
    assert w.detailScroll.GetVerticalScroll(w.detailScroll)==0


def test_ingredient_tooltip_leaves_drops_to_the_ranked_gather_block(style):
    g=game(style)
    f=g.eval("NS.professions._withoutDrops")
    rows=g.eval("""{ "Fish: Stormwind canals; zone levels 1-12", "Drops from: Boar; mob level 5-6", "  Elwynn Forest 40, 50",
        "  +3 other recorded spawn points.", "More drop sources exist in Questie.", "Buy from: Tharynn", "  Stormwind 70, 60",
        "Loot this ingredient from slain mobs; a loot drop does not require Skinning." }""")
    out=[str(v) for v in f(rows).values()]
    assert out==["Fish: Stormwind canals; zone levels 1-12","Buy from: Tharynn","  Stormwind 70, 60"],out


if __name__=="__main__":
    failed=total=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total+=1
            try:fn(style)if style else fn();print("ok  ",f"{name}[{style}]")
            except Exception as e:failed+=1;print("FAIL",f"{name}[{style}]",type(e).__name__,str(e)[:800])
    print(f"\n{total-failed}/{total} passed")
    raise SystemExit(1 if failed else 0)
