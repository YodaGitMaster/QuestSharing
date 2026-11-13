-- Upgrade placed player spells to learned ranks; never use the player's occupied cursor.
local ADDON, ns = ...
local R = {}
ns.spellRanks = R
local queued, running, waiting, serial = false, false, false, 0
local message = "Auto-update spell ranks is off."
local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok,a,b,c,d = pcall(fn,...)
    if ok then return a,b,c,d end
end
local function enabled() return ns.db.enabled and ns.db.autoSpellRanks and not ns.isBlocked("spellRanks") end
local function rank(text)
    return type(text)=="string" and tonumber(string.match(text,"(%d+)%D*$")) or nil
end
local function restricted()
    local function active(fn)
        if type(fn)~="function" then return false end
        local ok,value=pcall(fn)
        return not ok or value
    end
    return active(InCombatLockdown) or active(HasVehicleActionBar) or active(HasOverrideActionBar) or active(HasTempShapeshiftActionBar)
end
local function cursorState()
    if type(GetCursorInfo)~="function" then return false end
    return pcall(GetCursorInfo)
end
local function bookAPI()
    local b=C_SpellBook
    if b and type(b.GetNumSpellBookSkillLines)=="function" and type(b.GetSpellBookSkillLineInfo)=="function"
        and type(b.GetSpellBookItemInfo)=="function" then
        local bank=Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        local spellType=Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        if bank==nil or spellType==nil then return end
        return {
            count=function() return call(b.GetNumSpellBookSkillLines) end,
            line=function(i)
                local t=call(b.GetSpellBookSkillLineInfo,i)
                if t and not t.shouldHide and (not t.offSpecID or t.offSpecID==0) then return t.itemIndexOffset,t.numSpellBookItems end
            end,
            entry=function(i)
                local t=call(b.GetSpellBookItemInfo,i,bank)
                if t and t.itemType==spellType and not t.isPassive and not t.isOffSpec then
                    return t.name,rank(t.subName),t.spellID or t.actionID
                end
            end,
            pickup=function(i) if type(b.PickupSpellBookItem)=="function" then return pcall(b.PickupSpellBookItem,i,bank) end end,
            bank=bank,
        }
    end
    if type(GetNumSpellTabs)~="function" or type(GetSpellTabInfo)~="function"
        or type(GetSpellBookItemInfo)~="function" or type(GetSpellBookItemName)~="function" then return end
    local bank=BOOKTYPE_SPELL or "spell"
    return {
        count=function() return call(GetNumSpellTabs) end,
        line=function(i)
            local ok,_,_,offset,count,_,offspec=pcall(GetSpellTabInfo,i)
            if ok and (not offspec or offspec==0) then return offset,count end
        end,
        entry=function(i)
            local kind,id=call(GetSpellBookItemInfo,i,bank)
            if kind~="SPELL" or call(IsPassiveSpell,i,bank) then return end
            local name,text=call(GetSpellBookItemName,i,bank)
            return name,rank(text),id
        end,
        pickup=function(i) if type(PickupSpellBookItem)=="function" then return pcall(PickupSpellBookItem,i,bank) end end,
        bank=bank,
    }
end
local function catalogue(api)
    local families,known={},{}
    local count=api.count()
    if type(count)~="number" or count<1 or count>100 then return end
    for tab=1,count do
        local offset,size=api.line(tab)
        if type(offset)=="number" and type(size)=="number" and size>=0 and size<=2000 then
            for i=offset+1,offset+size do
                local name,n,id=api.entry(i)
                if type(name)=="string" and name~="" and n and n>0 and type(id)=="number" and id>0 then
                    local e={id=id,name=name,rank=n,index=i}
                    known[id]=e
                    local best=families[name]
                    if not best or n>best.rank then families[name]=e
                    elseif n==best.rank and id~=best.id then best.ambiguous=true end
                end
            end
        end
    end
    return families,known
end
local function spell(id,known)
    if known[id] then return known[id] end
    local name,text
    if C_Spell and type(C_Spell.GetSpellInfo)=="function" then
        local t=call(C_Spell.GetSpellInfo,id)
        if type(t)=="table" then name=t.name end
        text=call(C_Spell.GetSpellSubtext,id)
    end
    if not name or not rank(text) then
        local n,r=call(GetSpellInfo,id)
        name,text=n or name,r or text
    end
    return {id=id,name=name,rank=rank(text)}
end
local function stop(text)
    message=text;waiting=false
    ns.blockedFeatures.spellRanks=true
    ns.print(text.." Auto-update is paused until /reload; /qs errors has any client errors.")
end
local function replace(slot,old,best,api)
    local readable,cursor=cursorState()
    if not readable then stop("The client could not confirm that the cursor is clear.");return false end
    if restricted() or cursor then waiting=true;return false end
    local kind,id,subtype=call(GetActionInfo,slot)
    if kind~="spell" or id~=old.id or subtype=="pet" then return false end
    ns.trying("updating action-bar spell ranks", "spellRanks")
    local pickup=(C_Spell and C_Spell.PickupSpell) or PickupSpell
    local ok
    if type(pickup)=="function" then ok=pcall(pickup,best.id) else ok=api.pickup(best.index) end
    local readable,cursor,index,bank,spellID=cursorState()
    local expected=cursor=="spell" and (spellID==best.id or (spellID==nil and (index==best.id or (index==best.index and bank==api.bank))))
    if not ok or not readable or not expected or ns.isBlocked("spellRanks") then
        -- The cursor was empty on entry; anything here came from our pickup.
        if cursor then call(ClearCursor) end
        stop("The client could not pick up the learned spell rank.");return false
    end
    if restricted() then call(ClearCursor);waiting=true;return false end
    local beforeKind,beforeID,beforeSubtype=call(GetActionInfo,slot)
    if beforeKind~=kind or beforeID~=id or beforeSubtype=="pet" then call(ClearCursor);return false end
    local placed=pcall(PlaceAction,slot)
    local newKind,newID=call(GetActionInfo,slot)
    if newKind=="spell" and newID==best.id then
        call(ClearCursor) -- PlaceAction swaps the previous rank onto the cursor.
        if not placed or ns.isBlocked("spellRanks") then stop("The client interrupted a spell-rank update.") end
        return true
    end
    if newKind==kind and newID==id then call(ClearCursor) end
    -- If an unexpected action replaced the slot, retain the cursor for manual recovery.
    stop("The client did not confirm the spell-rank update.");return false
end
function R.update(report)
    if running then return 0 end
    serial=serial+1;queued=false
    if not enabled() then message=ns.isBlocked("spellRanks") and "Spell-rank updates are paused until /reload." or "Auto-update spell ranks is off.";if report then ns.print(message) end;return 0 end
    local api=bookAPI()
    if not api or type(GetActionInfo)~="function" or type(PlaceAction)~="function" or type(GetCursorInfo)~="function" or type(ClearCursor)~="function" or type(InCombatLockdown)~="function" then
        message="This client does not expose the spell-book/action-bar APIs needed for rank updates."
        if report then ns.print(message) end;return 0
    end
    local readable,cursor=cursorState()
    if not readable then message="The client could not read the cursor; no spell buttons were changed.";if report then ns.print(message) end;return 0 end
    if restricted() or cursor then
        waiting=true;message="Spell-rank update queued until combat/temporary bars end and your cursor is clear."
        if report then ns.print(message) end;return 0
    end
    local families,known=catalogue(api)
    if not families then message="Spell book is not ready; updates will retry on spell changes.";if report then ns.print(message) end;return 0 end
    running,waiting=true,false
    local total=0
    -- Visible page counts omit bonus/form bars on some clients. Read all standard slots;
    -- unsupported slots return no action (or are caught by the protected reader).
    local slots=math.max(180,tonumber(MAX_ACTION_BUTTONS) or 0)
    slots=math.min(1000,math.max(1,math.floor(slots)))
    for slot=1,slots do
        if not enabled() or restricted() then waiting=enabled();break end
        local kind,id,subtype=call(GetActionInfo,slot)
        if kind=="spell" and type(id)=="number" and subtype~="pet" then
            local old=spell(id,known)
            local best=old.name and families[old.name]
            if best and not best.ambiguous and old.rank and best.rank>old.rank then
                if replace(slot,old,best,api) then total=total+1 end
                if waiting or not enabled() then break end
            end
        end
    end
    running=false
    if ns.isBlocked("spellRanks") then return total end
    message=total>0 and ("Updated "..total.." spell button"..(total==1 and "" or "s").." to the highest learned rank.") or "No confirmed lower-ranked spell buttons found."
    if waiting then message=message.." Remaining updates are queued." end
    if report or total>0 then ns.print(message) end
    return total
end
function R.schedule(report)
    if running or not enabled() or queued then return end
    queued=true;serial=serial+1;local token=serial
    ns.after(0.5,function() if token~=serial then return end;queued=false;R.update(report) end)
end
function R.settingChanged()
    serial=serial+1;queued,waiting=false,false
    if enabled() then R.schedule(true) else message="Auto-update spell ranks is off." end
end
function R.status() return message end
for _,event in ipairs({"PLAYER_ENTERING_WORLD","SPELLS_CHANGED","LEARNED_SPELL_IN_TAB","LEARNED_SPELL_IN_SKILL_LINE","SPELL_TEXT_UPDATE","ACTIONBAR_SLOT_CHANGED","PLAYER_SPECIALIZATION_CHANGED"}) do
    ns.on(event,function() R.schedule(false) end)
end
for _,event in ipairs({"PLAYER_REGEN_ENABLED","CURSOR_CHANGED","UPDATE_VEHICLE_ACTIONBAR","UPDATE_OVERRIDE_ACTIONBAR","UPDATE_SHAPESHIFT_FORM"}) do
    ns.on(event,function() if waiting then R.schedule(false) end end)
end
