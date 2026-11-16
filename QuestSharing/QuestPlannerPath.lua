-- Optional bridge to Shortest Path Forever. Quest Sharing still owns quest selection and dependencies.
local ADDON, ns = ...
local Path = {}
ns.questPlannerPath = Path

local OWNER = "QuestSharing"
local MAX_TARGETS = 256
local requestID, cancelActive = 0, nil

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

function Path.cancelWalkEstimates()
    requestID = requestID + 1
    local cancel = cancelActive
    cancelActive = nil
    if type(cancel) == "function" then pcall(cancel) end
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

local function estimateAPI()
    local value = api()
    if not (value and value.version == 2 and (tonumber(value.minor) or 0) >= 3
        and type(value.EstimateWalks) == "function") then return nil end
    return value
end

-- Runs ordered chunks because SPF accepts at most 256 same-map targets in one search.
function Path.estimateWalks(from, targets, callback)
    Path.cancelWalkEstimates()
    if not validPoint(from) or type(targets) ~= "table" or type(callback) ~= "function" then
        return nil, "invalid"
    end
    local value = estimateAPI()
    if not value then return nil, "unavailable" end
    for _, point in ipairs(targets) do
        if not validPoint(point) or point.map ~= from.map then return nil, "invalid" end
    end
    if #targets == 0 then return nil, "invalid" end

    local token, allCosts, first = requestID, {}, 1
    local function finish(costs, reason)
        if token ~= requestID then return end
        cancelActive = nil
        local ok = pcall(callback, costs, reason)
        if not ok and ns.logError then ns.logError("Quest planner paths", "estimate callback failed") end
    end
    local nextChunk
    nextChunk = function()
        if token ~= requestID then return end
        if first > #targets then return finish(allCosts) end
        local last = math.min(#targets, first + MAX_TARGETS - 1)
        local chunk, indices = {}, {}
        for i = first, last do
            chunk[#chunk + 1], indices[#indices + 1] = targets[i], i
        end
        first = last + 1
        local callbackCalled = false
        local function onChunk(costs, reason)
            if callbackCalled or token ~= requestID then return end
            callbackCalled = true
            cancelActive = nil
            if reason ~= nil or type(costs) ~= "table" then return finish(nil, reason or "error") end
            for i, targetIndex in ipairs(indices) do
                local cost = costs[i]
                if type(cost) == "number" and cost == cost and cost >= 0 and cost < math.huge then
                    allCosts[targetIndex] = cost
                else
                    allCosts[targetIndex] = false
                end
            end
            nextChunk()
        end
        local ok, cancel, reason = pcall(value.EstimateWalks, OWNER, from, chunk, onChunk)
        if not ok then return finish(nil, "error") end
        if not callbackCalled then
            if type(cancel) ~= "function" then return finish(nil, reason or "unavailable") end
            cancelActive = cancel
        end
    end
    nextChunk()
    return function()
        if token == requestID then Path.cancelWalkEstimates() end
    end
end

-- Reorder only whole outings, and only promote a stop whose prerequisites are already clear.
function Path.prioritizeFirstOuting(stops, from, callback)
    if type(stops) ~= "table" or not validPoint(from) or type(callback) ~= "function" then
        return nil, "invalid"
    end
    local candidates, seen = {}, {}
    for _, stop in ipairs(stops) do
        if stop.outingID and not seen[stop.outingID] and stop.point and validPoint(stop.point)
            and stop.point.map == from.map and not next(stop.deps or {}) then
            seen[stop.outingID] = true
            candidates[#candidates + 1] = { outingID = stop.outingID, point = stop.point }
        end
    end
    if #candidates == 0 then return nil, "no-candidate" end
    local targets = {}
    for i, candidate in ipairs(candidates) do targets[i] = candidate.point end
    return Path.estimateWalks(from, targets, function(costs, reason)
        if not costs then callback(false, reason); return end
        local chosen, best
        for i, cost in ipairs(costs) do
            if type(cost) == "number" and (not best or cost < best) then
                chosen, best = candidates[i].outingID, cost
            end
        end
        if not chosen then callback(false, "unreachable"); return end
        if stops[1] and stops[1].outingID ~= chosen then
            local first, rest = {}, {}
            for _, stop in ipairs(stops) do
                if stop.outingID == chosen then first[#first + 1] = stop else rest[#rest + 1] = stop end
            end
            for i = #stops, 1, -1 do stops[i] = nil end
            for _, stop in ipairs(first) do stops[#stops + 1] = stop end
            for _, stop in ipairs(rest) do stops[#stops + 1] = stop end
        end
        callback(true, chosen, best)
    end)
end
