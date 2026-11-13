-- Small shared controls for the optional tools; no dependency on client-specific dropdown templates.
local ADDON, ns = ...
local U, S = {}, ns.style
ns.optionalUI = U

function U.text(parent, text, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    t:SetJustifyH("LEFT")
    if width then t:SetWidth(width) end
    t:SetText(text)
    return t
end

function U.box(parent, label, x, y, width, value, max)
    U.text(parent, label, x, y, width)
    local b = CreateFrame("EditBox", nil, parent)
    b:SetWidth(width); b:SetHeight(22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + 17))
    S.fill(b, "BACKGROUND", 0, 0, 0, 0.7):SetAllPoints(b)
    if ChatFontNormal then b:SetFontObject(ChatFontNormal) end
    b:SetAutoFocus(false); b:SetMaxLetters(max or 100)
    if b.SetTextInsets then b:SetTextInsets(5, 5, 0, 0) end
    b:SetText(tostring(value or ""))
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

function U.scrollText(parent, x, y, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    scroll:SetWidth(width); scroll:SetHeight(height)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(width); content:SetHeight(height)
    scroll:SetScrollChild(content)
    local text = U.text(content, "", 0, 0, width)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local pos = self:GetVerticalScroll() - delta * 24
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), pos)))
    end)
    return text, function(value)
        text:SetText(value)
        local size = text.GetStringHeight and text:GetStringHeight() or math.ceil(#value / 32) * 14
        content:SetHeight(math.max(height, size + 4))
    end
end

function U.window(name, width, height, title)
    local f = S.window(name, width, height, title, "dialog")
    if not f then return end
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    S.closeButton(f, function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

function U.tip(owner, title, lines)
    if not GameTooltip then return end
    pcall(function()
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
end

function U.hideTip() if GameTooltip then pcall(function() GameTooltip:Hide() end) end end

function U.call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

function U.mapHint(map)
    if not map then return false end
    -- Opening or redrawing Blizzard's map from addon code can taint its protected pin creation on Forever.
    local data = C_Map and U.call(C_Map.GetMapInfo, map)
    ns.print("open your world map (M) and choose " .. (data and data.name or ("map " .. tostring(map))))
    return true
end
