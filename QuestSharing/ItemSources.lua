-- Small, optional QuestieDB hints on item tooltips: vendor categories and known mining nodes.
local ADDON, ns = ...
ns.inModule("items")          -- Modules.lua: Settings > General > Tools can switch this off
local Q, U = ns.questie, ns.optionalUI
local I = {}
ns.itemSources = I

local function containsMiningName(name)
    if type(name) ~= "string" then return false end
    local s = string.lower(name)
    -- Questie stores localized object names, not a gathering-profession field. These common node words are
    -- a conservative hint; an unmatched object remains unlabelled instead of being called Mining.
    for _, word in ipairs({ "vein", "deposit", "vorkommen", "erzader", "filon", "yacimiento", "veta", "veio", "жила", "광맥", "矿脉", "礦脈" }) do
        if string.find(s, word, 1, true) then return true end
    end
    return false
end

function I.sources(itemID)
    if not (Q and Q.available() and itemID) then return {} end
    local out, seen = {}, {}
    local vendors = Q.get("item", itemID, "vendors")
    for _, id in ipairs(type(vendors) == "table" and vendors or {}) do
        local category = Q.get("npc", id, "subName")
        category = type(category) == "string" and string.gsub(category, "^%s*(.-)%s*$", "%1") or ""
        if category == "" then category = "Vendor" end
        local key = string.lower(category)
        if not seen[key] then seen[key] = true; out[#out + 1] = category end
    end
    local objects = Q.get("item", itemID, "objectDrops")
    for _, id in ipairs(type(objects) == "table" and objects or {}) do
        if containsMiningName(Q.get("object", id, "name")) and not seen.mining then
            seen.mining = true; out[#out + 1] = "Mining"
        end
    end
    table.sort(out)
    return out
end

local function itemID(link)
    if type(link) ~= "string" then return nil end
    return tonumber(string.match(link, "|Hitem:(%d+)"))
end

local function update(tooltip, data)
    if not (ns.db.enabled and ns.db.itemSources and not ns.isBlocked("itemsources")) then return end
    local name, link = U.call(tooltip.GetItem, tooltip)
    -- Tooltips built from tooltip data (Professions recipe/reagent items) may not expose GetItem; data.id is the item then.
    local id = itemID(link) or (type(data) == "table" and tonumber(data.id)) or nil
    if not id or tooltip.questSharingSourceID == id then return end
    tooltip.questSharingSourceID = id
    local sources = I.sources(id)
    if #sources == 0 then return end
    -- Seller types on one line, "Mined from veins" on its own; "Where to gather" (GatherSources) is the place heading.
    local sellers, mined = {}, false
    for _, source in ipairs(sources) do
        if source == "Mining" then mined = true else sellers[#sellers + 1] = source end
    end
    if #sellers > 0 then tooltip:AddLine("Sold by: " .. table.concat(sellers, ", "), 0.95, 0.78, 0.30, true) end
    if mined then tooltip:AddLine("Mined from veins", 0.95, 0.78, 0.30, true) end
    tooltip:Show()
end

local hooked
local function install()
    if hooked or not GameTooltip then return end
    hooked = true
    -- Modern clients no longer fire OnTooltipSetItem for every item tooltip (e.g. the Professions window), so
    -- prefer the tooltip-data post-call, exactly as Professions.lua does, and keep the script hook as fallback.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip == GameTooltip then update(tooltip, data) end
        end)
    else
        GameTooltip:HookScript("OnTooltipSetItem", update)
    end
    GameTooltip:HookScript("OnTooltipCleared", function(self) self.questSharingSourceID = nil end)
end

I.refresh = install
ns.on("PLAYER_LOGIN", install)
ns.on("ADDON_LOADED", install)
