-- ChatLock.lua: while you are in a fight the chat box cannot be opened (chatLock). A box that is already open is closed
-- when the fight starts. It works again as soon as the fight is over. Only the typing box is blocked: you still read chat,
-- and the quick chat ring still sends its messages directly.
local ADDON, ns = ...
ns.inModule("combat")          -- Modules.lua: Settings > General > Tools can switch this off

local L = {}
ns.chatLock = L

local SAY_EVERY = 20
local lastSaid

local function fighting()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

function L.active()
    return ns.db.enabled and ns.db.chatLock and fighting() and true or false
end

local function say()
    local now = GetTime and GetTime() or 0
    if lastSaid and now - lastSaid < (tonumber(ns.db.chatLockNotice) or SAY_EVERY) then return end
    lastSaid = now
    ns.print("the chat box is locked while you fight (Settings > General > Block the chat box during combat)")
end

-- close the given box, or the one that is open; true when there was one
function L.close(box)
    box = box or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    if not box then return false end
    if box.IsShown and not box:IsShown() then return false end
    ns.trying("closing the chat box during a fight", "chatlock")
    local ok = false
    if ChatEdit_DeactivateChat then ok = pcall(ChatEdit_DeactivateChat, box) end
    if not ok and box.ClearFocus then pcall(box.ClearFocus, box) end
    ns.log("chat lock", "chat box closed")
    return true
end

function L.guard(box)
    if L.active() and L.close(box) then say() end
end

-- Enter, "/" and a click on the box all end in one of these two
local hookedActivate, hookedBoxes = false, {}
local function hook()
    if not hookedActivate and hooksecurefunc and ChatEdit_ActivateChat then
        hookedActivate = pcall(hooksecurefunc, "ChatEdit_ActivateChat", function(box) L.guard(box) end)
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and box.HookScript and not hookedBoxes[box] then
            hookedBoxes[box] = pcall(box.HookScript, box, "OnEditFocusGained", function(self) L.guard(self) end)
        end
    end
end
ns.on("PLAYER_LOGIN", hook)
ns.on("PLAYER_ENTERING_WORLD", hook)
hook()

ns.on("PLAYER_REGEN_DISABLED", function() L.guard() end)

function L.refresh() L.guard() end                       -- switched on in the middle of a fight
