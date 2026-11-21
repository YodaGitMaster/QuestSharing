-- Optional bridge to Shortest Path Forever, used only for the Follow arrow. The quest guide plans with
-- straight-line travel and never asks SPF for walking estimates, so it behaves the same with or without SPF.
local ADDON, ns = ...
ns.inModule("guide")          -- Modules.lua: Settings > General > Tools can switch this off
local Path = {}
ns.questPlannerPath = Path

local OWNER = "QuestSharing"

local function api()
    local provider = ShortestPathForever
    local value = type(provider) == "table" and provider.API
    if type(value) ~= "table" then return nil end
    if value.version ~= 1 and value.version ~= 2 then return nil end
    return value
end

local function validPoint(point)
    return type(point) == "table" and type(point.map) == "number" and point.map > 0
        and point.map % 1 == 0
        and type(point.x) == "number" and point.x == point.x and point.x >= 0 and point.x <= 1
        and type(point.y) == "number" and point.y == point.y and point.y >= 0 and point.y <= 1
end

function Path.available()
    local value = api()
    return value ~= nil and type(value.Navigate) == "function"
end

function Path.follow(point, title, kind)
    if not validPoint(point) then return false, "invalid" end
    local value = api()
    if not (value and type(value.Navigate) == "function") then return false, "unavailable" end
    local ok, accepted = pcall(value.Navigate, OWNER, point.map, point.x, point.y, title, kind)
    if not ok then return false, "error" end
    if accepted == true then return true end
    return false, "refused"
end
