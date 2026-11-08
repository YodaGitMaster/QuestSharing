-- Marker.lua: showing each other where you are.
--   * my position to the other Quest Sharing users (every 10 seconds while I move), and theirs as a class icon on my
--     world map
--   * a map pin where a teammate says they found the items of a quest I still work on
-- (There is no raid star over your head any more: the game refuses raid marks set by an addon, even outside combat.)
local ADDON, ns = ...
local C = ns.compat
local key = ns.memberKey

-- My position to the other Quest Sharing users ---------------------------------------------------------------------------
local lastSent = { map = nil, x = -1, y = -1, at = -1000 }

function ns.sendPosition()
    local d = ns.db
    if not (d.enabled and d.mapPins and d.sync and C.inGroup() and next(ns.peers)) then return false end
    local map, x, y = C.playerPos()
    if not x then return false end
    local now = GetTime()
    local moved = map ~= lastSent.map or math.abs(x - lastSent.x) > 0.003 or math.abs(y - lastSent.y) > 0.003
    if not moved and now - lastSent.at < 60 then return false end         -- standing still: once a minute is enough
    lastSent = { map = map, x = x, y = y, at = now }
    ns.syncUpdate(string.format("M|%d|%.4f|%.4f", map, x, y))
    return true
end

local function tick()
    ns.sendPosition()
    ns.after(10, tick)
end
ns.after(10, tick)

-- Their positions on my world map ----------------------------------------------------------------------------------------
local pins = {}
local FRESH = 120              -- a position older than this is not shown

local function canvas()
    local wm = WorldMapFrame
    if not (wm and wm.GetMapID and wm.ScrollContainer and wm.ScrollContainer.Child) then return nil end
    return wm, wm.ScrollContainer.Child
end

local function classOf(k)
    for _, m in ipairs(C.members()) do
        if key(m.name) == k and UnitClass then local _, file = UnitClass(m.unit); return file end
    end
end

local function newPin(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetWidth(18)
    pin:SetHeight(18)
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints(pin)
    pin:EnableMouse(true)
    pin:SetScript("OnEnter", function(self)
        if GameTooltip then pcall(function()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((self.who or "?") .. " (Quest Sharing)")
            GameTooltip:Show()
        end) end
    end)
    pin:SetScript("OnLeave", function() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end)
    return pin
end

function ns.refreshMapPins()
    local wm, cv = canvas()
    if not wm or ns.isBlocked("mappins") then return end
    local shownMap = wm:IsShown() and wm:GetMapID()
    local used = {}
    if ns.db.enabled and ns.db.mapPins and shownMap then
        local now = GetTime()
        for k, peer in pairs(ns.peers) do
            local p = peer.pos
            if p and p.map == shownMap and now - p.at < FRESH then
                ns.trying("drawing party members on the world map", "mappins")
                local pin = pins[k] or newPin(cv)
                pins[k] = pin
                local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classOf(k) or ""]
                if c then
                    pin.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    pin.icon:SetTexCoord(c[1], c[2], c[3], c[4])
                else
                    pin.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    pin.icon:SetTexCoord(0, 1, 0, 1)
                end
                pin.who = peer.name
                local scale = (cv.GetScale and cv:GetScale()) or 1
                pin:SetScale(1 / ((scale > 0) and scale or 1))           -- the same size at every zoom level
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", cv, "TOPLEFT", p.x * cv:GetWidth() * scale, -p.y * cv:GetHeight() * scale)
                pin:Show()
                used[k] = true
            end
        end
    end
    for k, pin in pairs(pins) do if not used[k] then pin:Hide() end end
end

function ns._mapPins() return pins end                                  -- for the tests

-- someone's addon told us where they are
function ns.onPeerPosition(peer, map, x, y)
    peer.pos = { map = map, x = x, y = y, at = GetTime() }
    ns.refreshMapPins()
end

local function hookMap()
    ns.hooks = ns.hooks or {}
    local wm = WorldMapFrame
    if ns.hooks.worldMap or not (wm and wm.HookScript) then return end
    ns.hooks.worldMap = true
    pcall(wm.HookScript, wm, "OnShow", function() ns.refreshMapPins() end)
    if wm.OnMapChanged then pcall(hooksecurefunc, wm, "OnMapChanged", function() ns.refreshMapPins() end) end
end
ns.on("PLAYER_LOGIN", hookMap)
ns.on("ADDON_LOADED", hookMap)                 -- the world map can load after us

-- A teammate found the quest items here --------------------------------------------------------------------------------
function ns.onPeerSpot(peer, id, map, x, y, what)
    local d = ns.db
    if not (d.enabled and d.teamWaypoint) then return false end
    local e = C.findEntry(id)
    if not e or e.complete then return false end                      -- not my quest, or I am done with it
    if not C.setWaypoint(map, x, y) then return false end
    ns.print(string.format("%s found %s for %s at %.1f, %.1f - there is a pin on your map", peer.name,
        (what and what ~= "") and what or "the items", C.link(e), x * 100, y * 100))
    return true
end
