-- Embedded Forever profession views. Own frames are children of Blizzard's existing window;
-- known recipes still use CraftingPage:SelectRecipe and its native crafting controls.
local _,ns=...
local V,P,U,S,D={},ns.professions,ns.optionalUI,ns.style,ns.professionReference
ns.professionUI=V
local w,tab,selected,offset,side=nil,"cooking",nil,0,"Both"
local ROW=44
local drawing=false
local function show(f,on) if on then f:Show() else f:Hide() end end
local function font(parent,value,x,y,width,size,gold)
    local t=parent:CreateFontString(nil,"OVERLAY",gold and "GameFontNormal" or "GameFontHighlight")
    t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y);t:SetWidth(width);t:SetJustifyH("LEFT");t:SetWordWrap(true)
    if t.SetFont then t:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size or 14,"") end
    t:SetText(value or "");return t
end
local function colour(t,r,g,b) if t.SetTextColor then t:SetTextColor(r,g,b,1) end end
local function height(t,min) return math.max(min or 18,t.GetStringHeight and t:GetStringHeight() or 18) end
local function panel(parent)
    local ok,f=pcall(CreateFrame,"Frame",nil,parent,"InsetFrameTemplate")
    if not ok then f=CreateFrame("Frame",nil,parent) end
    S.fill(f,"BACKGROUND",0.065,0.055,0.04,1):SetAllPoints(f)
    local level=parent.GetFrameLevel and parent:GetFrameLevel() or 100
    f:SetFrameLevel(level+40);f:EnableMouse(true);return f
end
local function button(parent,label,width,fn,template)
    local ok,b=pcall(CreateFrame,"Button",nil,parent,template or "UIPanelButtonTemplate")
    if not ok then b=CreateFrame("Button",nil,parent) end
    b:SetWidth(width);b:SetHeight(24);b:SetText(label);b:SetScript("OnClick",fn)
    if b.SetNormalFontObject then b:SetNormalFontObject("GameFontNormal") end
    return b
end
local function scroll(parent,x,y,width,h)
    local ok,f=pcall(CreateFrame,"ScrollFrame",nil,parent,"UIPanelScrollFrameTemplate")
    if not ok then f=CreateFrame("ScrollFrame",nil,parent) end
    f:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y);f:SetWidth(width);f:SetHeight(h)
    local content=CreateFrame("Frame",nil,f);content:SetWidth(width);content:SetHeight(h);f:SetScrollChild(content)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*ROW)))
    end)
    return f,content
end
local function isCooking()
    return w and P.active() and P.ownCooking() and w.host:IsShown() and w.native:IsShown()
end
function V.activeCooking() return isCooking() and tab=="cooking" end
local function stopNativeRecipe()
    local form=w.native.SchematicForm
    if form.ClearTransaction then form:ClearTransaction() end
    if form.Init then form:Init(nil) end
    if w.native.ValidateControls then w.native:ValidateControls() end
end
local function hideDetails()
    w.missing:Hide();w.nativeSource:Hide();w.upgrade:Hide()
end
local function recipeTip(self)
    if not self.recipe then return end
    local r=self.recipe
    local lines={"Requires Cooking "..tostring(r.skill or "unknown"),P.state(r)==true and "Learned" or P.state(r)==false and "Not learned" or "Learned status unavailable"}
    for _,v in ipairs(P.acquisition(r)) do lines[#lines+1]=v end
    U.tip(self,P.name(r),lines)
end
local function drawRows()
    if not w or drawing then return end
    drawing=true
    local first=math.floor(w.listScroll:GetVerticalScroll()/ROW)+1
    for i,row in ipairs(w.rows) do
        local index=first+i-1
        local r=w.results[index];row.recipe=r
        if r then
            row:ClearAllPoints();row:SetPoint("TOPLEFT",w.listContent,"TOPLEFT",0,-((index-1)*ROW))
            row.name:SetText(P.name(r));row.skill:SetText(tostring(r.skill or "?"));row.source:SetText(P.shortSource(r))
            local known=P.state(r)==true
            colour(row.name,known and 1 or 0.66,known and 0.82 or 0.66,known and 0.38 or 0.66)
            colour(row.skill,known and 1 or 0.72,known and 0.82 or 0.72,known and 0.38 or 0.72)
            colour(row.source,0.76,0.73,0.65)
            show(row.selected,selected==r);row:Show()
        else row:Hide() end
    end
    drawing=false
end
local function fillMissing(r)
    local width=w.missing:GetWidth()-48
    w.title:SetText(P.name(r));w.title:SetWidth(width-52)
    local info=P.live(r)
    w.icon:SetTexture(info and info.icon or "Interface\\Icons\\INV_Misc_Food_15")
    local y=math.max(62,height(w.title,26)+24)
    w.status:ClearAllPoints();w.status:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y)
    w.status:SetText(P.state(r)==false and "Not learned" or "Learned status unavailable")
    y=y+26
    w.requirement:ClearAllPoints();w.requirement:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y)
    w.requirement:SetText("Requires Cooking "..tostring(r.skill or "unknown"));y=y+34
    w.sourceHeading:ClearAllPoints();w.sourceHeading:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y)
    y=y+26
    w.sourceText:ClearAllPoints();w.sourceText:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y);w.sourceText:SetWidth(width)
    w.sourceText:SetText(table.concat(P.acquisition(r),"\n\n"));y=y+height(w.sourceText)+28
    w.ingredientHeading:ClearAllPoints();w.ingredientHeading:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y);y=y+28
    for i,b in ipairs(w.ingredients) do
        local reagent=r.ingredients[i]
        if reagent then
            b.itemID=reagent[1];b:ClearAllPoints();b:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-y)
            b.label:SetWidth(width-8);b.label:SetText(reagent[2].." x "..P.itemName(reagent[1]))
            b:SetHeight(math.max(30,height(b.label)+10));y=y+b:GetHeight()+4;b:Show()
        else b.itemID=nil;b:Hide() end
    end
    w.detailContent:SetHeight(math.max(w.detailScroll:GetHeight(),y+20))
    w.detailScroll:SetVerticalScroll(0);w.missing:Show()
end
function V.select(r)
    if not w or not r or not isCooking() then return end
    selected=r
    hideDetails()
    local info=P.live(r)
    if P.state(r)==true and info and info.learned==true and w.native.SelectRecipe then
        -- Skip selection in Blizzard's filtered list: its unlearned visibility remains untouched.
        w.selecting=true
        local ok=pcall(w.native.SelectRecipe,w.native,info,true)
        w.selecting=false
        if ok then
            w.nativeSource:SetText("Cooking "..tostring(r.skill or "?").."  |  "..P.shortSource(r))
            w.nativeSource:Show();drawRows();return
        end
    end
    stopNativeRecipe();fillMissing(r);drawRows()
end
local function refreshUpgrades()
    local p=w.profession or D.professions[1]
    local out={}
    for _,r in ipairs(p.ranks) do
        out[#out+1]=S.GOLD..r.name.."  -  maximum skill "..r.cap.."|r"
        out[#out+1]=r.skill==0 and "No prior skill required" or ("Requires "..p.name.." "..r.skill..(r.level>0 and (" and character level "..r.level) or ""))
        out[#out+1]=r.method
        for _,f in ipairs({"Alliance","Horde"}) do
            if side=="Both" or side==f then out[#out+1]=f..": "..r[f] end
        end
        out[#out+1]=""
    end
    w.upgradeTitle:SetText(p.name.." - training and upgrades")
    w.upgradeText:SetText(table.concat(out,"\n\n"))
    w.upgradeContent:SetHeight(height(w.upgradeText)+12);w.upgradeScroll:SetVerticalScroll(0)
    for _,b in ipairs(w.professions) do colour(b.label,b.profession==p and 1 or 0.8,b.profession==p and 0.82 or 0.8,b.profession==p and 0.3 or 0.8) end
    for i,f in ipairs({"Both","Alliance","Horde"}) do w.factions[i]:SetText((side==f and S.GOLD or S.WHITE)..f.."|r") end
end
function V.refresh()
    if not w then return end
    local active=P.active() and w.host:IsShown()
    show(w.tabs,active)
    U.call(tab=="cooking" and PanelTemplates_SelectTab or PanelTemplates_DeselectTab,w.recipesTab)
    U.call(tab=="upgrades" and PanelTemplates_SelectTab or PanelTemplates_DeselectTab,w.upgradesTab)
    hideDetails()
    if not active then w.list:Hide();return end
    if tab=="upgrades" then
        w.list:Hide();if w.native:IsShown() then stopNativeRecipe() end
        refreshUpgrades();w.upgrade:Show();return
    end
    if not w.native:IsShown() or (w.host.BookPage and w.host.BookPage:IsShown()) then w.list:Hide();return end
    local cooking=isCooking()
    show(w.list,cooking and tab=="cooking")
    if not cooking then return end
    local previous=selected
    w.results=P.recipes(w.search:GetText())
    w.listContent:SetHeight(math.max(w.listScroll:GetHeight(),#w.results*ROW))
    local known=0
    local valid=false
    for _,r in ipairs(w.results) do if r==previous then valid=true end;if P.state(r)==true then known=known+1 end end
    w.count:SetText(#w.results.." recipes  -  "..known.." learned")
    w.empty:SetText(#w.results==0 and "No recipes match your search." or "")
    local max=math.max(0,#w.results*ROW-w.listScroll:GetHeight())
    if w.listScroll:GetVerticalScroll()>max then w.listScroll:SetVerticalScroll(max) end
    if not valid then selected=w.results[1] end
    drawRows()
    if selected then V.select(selected) end
end
function V.open(which)
    if not w then return end
    local previous=tab
    tab=which=="upgrades" and "upgrades" or "cooking"
    if tab=="cooking" and w.host.BookPage and w.host.BookPage:IsShown() then
        -- Do not switch the native profession book by hand; its right-hand profession tabs own selection.
        ns.print("Choose a profession on the right to use Recipes or Upgrades.");return
    end
    if previous=="upgrades" and tab=="cooking" and not P.ownCooking() and w.native.Refresh then
        local info=U.call(C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo)
        if info then w.native:Refresh(info) end
    end
    V.refresh()
    if V.activeCooking() then P.scan() end
end
function V.close()
    if not w then return end
    hideDetails();w.list:Hide();w.tabs:Hide()
    if not P.active() and w.native:IsShown() and w.native.Refresh then
        local info=U.call(C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo)
        if info then w.native:Refresh(info) end
    end
end
function V.attach()
    if w then return true end
    local host=ProfessionsFrame
    local native=host and host.CraftingPage
    if not (native and native.RecipeList and native.SchematicForm and native.SelectRecipe) or U.call(InCombatLockdown) then return false end
    w={frame=host,host=host,native=native,rows={},ingredients={},professions={},results={}}
    local list=panel(native.RecipeList);list:SetAllPoints(native.RecipeList);w.list=list
    local listWidth=native.RecipeList:GetWidth()
    list:SetWidth(listWidth);list:SetHeight(native.RecipeList:GetHeight())
    local sw=listWidth-40
    local search=CreateFrame("EditBox",nil,list,"SearchBoxTemplate");w.search=search
    search:SetPoint("TOPLEFT",list,"TOPLEFT",12,-10);search:SetWidth(sw);search:SetHeight(24);search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlight");search:SetText("")
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    w.count=font(list,"",12,44,sw,13)
    font(list,"Recipe",12,70,sw-50,13,true)
    local skillHeader=font(list,"Skill",listWidth-64,70,44,13,true);skillHeader:SetJustifyH("RIGHT")
    w.listScroll,w.listContent=scroll(list,10,94,listWidth-36,list:GetHeight()-106)
    w.empty=font(w.listContent,"",2,12,sw,14)
    local rows=math.ceil(w.listScroll:GetHeight()/ROW)+1
    for i=1,rows do
        local row=CreateFrame("Button",nil,w.listContent);row:SetWidth(listWidth-38);row:SetHeight(ROW)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected=S.fill(row,"BACKGROUND",0.40,0.28,0.10,0.7);row.selected:SetAllPoints(row)
        row.name=font(row,"",5,3,listWidth-102,14);row.name:SetWordWrap(false)
        row.skill=font(row,"",listWidth-92,3,48,14);row.skill:SetJustifyH("RIGHT");row.skill:SetWordWrap(false)
        row.source=font(row,"",5,24,listWidth-52,12);row.source:SetWordWrap(false)
        row:SetScript("OnClick",function(self) V.select(self.recipe) end)
        row:SetScript("OnEnter",recipeTip);row:SetScript("OnLeave",U.hideTip);w.rows[i]=row
    end
    w.listScroll:HookScript("OnVerticalScroll",drawRows)
    w.search:SetScript("OnTextChanged",function() w.listScroll:SetVerticalScroll(0);V.refresh() end)
    w.missing=panel(native)
    w.missing:SetPoint("TOPLEFT",native.SchematicForm,"TOPLEFT",0,0)
    w.missing:SetPoint("BOTTOMRIGHT",native,"BOTTOMRIGHT",-8,4)
    local detailWidth=math.max(300,host:GetWidth()-listWidth-24)
    w.missing:SetWidth(detailWidth);w.missing:SetHeight(list:GetHeight())
    w.detailScroll,w.detailContent=scroll(w.missing,4,8,detailWidth-28,list:GetHeight()-22)
    w.icon=w.detailContent:CreateTexture(nil,"ARTWORK");w.icon:SetPoint("TOPLEFT",w.detailContent,"TOPLEFT",14,-8);w.icon:SetWidth(42);w.icon:SetHeight(42)
    w.title=font(w.detailContent,"",68,10,detailWidth-100,18,true)
    w.status=font(w.detailContent,"",14,62,detailWidth-48,14)
    w.requirement=font(w.detailContent,"",14,88,detailWidth-48,14,true)
    w.sourceHeading=font(w.detailContent,"Where to learn",14,122,detailWidth-48,16,true)
    w.sourceText=font(w.detailContent,"",14,148,detailWidth-48,14)
    w.ingredientHeading=font(w.detailContent,"Ingredients",14,260,detailWidth-48,16,true)
    for i=1,6 do
        local b=CreateFrame("Button",nil,w.detailContent);b:SetWidth(detailWidth-48)
        b.label=font(b,"",4,4,detailWidth-56,14)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b:SetScript("OnEnter",function(self) if self.itemID then U.tip(self,P.itemName(self.itemID),P.materialLines(self.itemID)) end end)
        b:SetScript("OnLeave",U.hideTip);w.ingredients[i]=b
    end
    -- A compact caption above the native schematic keeps the selected learned recipe's skill/source visible.
    w.nativeSource=font(native,"",listWidth+20,53,detailWidth-18,12)
    w.upgrade=panel(host);w.upgrade:SetPoint("TOPLEFT",host,"TOPLEFT",8,-72)
    w.upgrade:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",-8,6)
    w.upgrade:SetFrameLevel((native.GetFrameLevel and native:GetFrameLevel() or 100)+60)
    w.upgrade:SetWidth(host:GetWidth()-16);w.upgrade:SetHeight(list:GetHeight())
    w.upgradeTitle=font(w.upgrade,"",215,14,host:GetWidth()-250,18,true)
    w.factions={}
    for i,f in ipairs({"Both","Alliance","Horde"}) do
        local b=button(w.upgrade,f,86,function() side=f;refreshUpgrades() end)
        b:SetPoint("TOPLEFT",w.upgrade,"TOPLEFT",215+(i-1)*92,-46);w.factions[i]=b
    end
    w.upgradeScroll,w.upgradeContent=scroll(w.upgrade,215,88,host:GetWidth()-270,list:GetHeight()-130)
    w.upgradeText=font(w.upgradeContent,"",0,0,host:GetWidth()-280,14)
    for i,p in ipairs(D.professions) do
        local b=CreateFrame("Button",nil,w.upgrade);b.profession=p;b:SetWidth(185);b:SetHeight(32)
        b:SetPoint("TOPLEFT",w.upgrade,"TOPLEFT",12,-(14+(i-1)*34))
        b.label=font(b,p.name,8,6,174,14)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b:SetScript("OnClick",function() w.profession=p;refreshUpgrades() end);w.professions[i]=b
    end
    local note=font(w.upgrade,"Guide checked "..D.date.." - confirm availability with your trainer.",215,list:GetHeight()-32,host:GetWidth()-270,12)
    note:SetWordWrap(true)
    w.tabs=CreateFrame("Frame",nil,host);w.tabs:SetWidth(260);w.tabs:SetHeight(28)
    w.tabs:SetPoint("TOPLEFT",host,"BOTTOMLEFT",14,0)
    w.recipesTab=button(w.tabs,"Recipes",110,function() V.open("cooking") end,"PanelTabButtonTemplate")
    w.recipesTab:SetPoint("TOPLEFT",w.tabs,"TOPLEFT",0,0)
    w.upgradesTab=button(w.tabs,"Upgrades",110,function() V.open("upgrades") end,"PanelTabButtonTemplate")
    w.upgradesTab:SetPoint("LEFT",w.recipesTab,"RIGHT",2,0)
    host:HookScript("OnHide",function() P.close() end)
    native:HookScript("OnHide",function()
        w.list:Hide();w.missing:Hide();w.nativeSource:Hide()
        if w.host:IsShown() then V.refresh() else V.close() end
    end)
    if hooksecurefunc then
        if native.Refresh then hooksecurefunc(native,"Refresh",function() V.refresh() end) end
        hooksecurefunc(native,"SelectRecipe",function(_,info)
            if w.selecting or not V.activeCooking() then return end
            -- Blizzard may auto-select its first learned recipe while rebuilding its hidden list.
            -- The visible list's selected row remains authoritative until the player clicks another.
            if selected and P.state(selected)~=true then stopNativeRecipe();return end
            drawRows()
        end)
    end
    V.close();return true
end
function V._view() return w end
