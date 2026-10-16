-- Itinerary map pins: the current step and the next few on the world map, the current one on the minimap.
-- Uses HereBeDragons-Pins (bundled in libs).
local ADDON, ns = ...

local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local WORLD_PINS = 5
local worldPins, miniPin, areaPins = {}, nil, {}
local DOT = "Interface\\AddOns\\" .. ADDON .. "\\dot"

local function accent() return ns.accent() end

local function makePin(size, numbered)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetTexture(DOT); f.ring:SetAllPoints(); f.ring:SetVertexColor(0, 0, 0, 0.75)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetTexture(DOT); f.dot:SetPoint("TOPLEFT", 2, -2); f.dot:SetPoint("BOTTOMRIGHT", -2, 2)
    if numbered then
        f.num = f:CreateFontString(nil, "OVERLAY")
        f.num:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        f.num:SetPoint("CENTER", 0, 0)
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local s = self.step and ns.steps()[self.step]
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.stepText.oneLine(s), 1, 1, 1)
        GameTooltip:AddLine(ns.stepText.detail(s), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Step " .. self.step, 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

function ns.refreshPins()
    if not HBDP then return end
    HBDP:RemoveAllWorldMapIcons(ns)
    HBDP:RemoveAllMinimapIcons(ns)
    if not (ItineraryDB and ItineraryDB.panel.shown and ItineraryDB.pins ~= false) then return end
    if ns.gatherOn and ns.gatherOn() then return end -- gather mode has its own pins
    local ar, ag, ab = accent()
    local steps, i = ns.steps(), ItineraryCharDB.step
    local placed = 0
    for k = i, math.min(#steps, i + 12) do
        local s = steps[k]
        if s and s.m and s.m > 0 and s.x and s.x > 0 and not s.along and not ns.notApplicable(s) then
            placed = placed + 1
            if placed > WORLD_PINS then break end
            local pin = worldPins[placed] or makePin(18, true)
            worldPins[placed] = pin
            pin.step = k
            if k == i then pin.dot:SetVertexColor(ar, ag, ab, 1) else pin.dot:SetVertexColor(0.75, 0.72, 0.68, 0.9) end
            pin.num:SetText(placed)
            HBDP:AddWorldMapIconMap(ns, pin, s.m, s.x / 100, s.y / 100, HBD_PINS_WORLDMAP_SHOW_PARENT)
            if k == i and s.area then
                -- the spots of the kill/loot area as small dots
                for n, a in ipairs(s.area) do
                    local ap = areaPins[n] or makePin(9, false)
                    areaPins[n] = ap
                    ap.step = k
                    ap.dot:SetVertexColor(ar, ag, ab, 0.7)
                    HBDP:AddWorldMapIconMap(ns, ap, a[1], a[2] / 100, a[3] / 100, HBD_PINS_WORLDMAP_SHOW_PARENT)
                end
            end
            if k == i then
                miniPin = miniPin or makePin(14, false)
                miniPin.step = k
                miniPin.dot:SetVertexColor(ar, ag, ab, 1)
                HBDP:AddMinimapIconMap(ns, miniPin, s.m, s.x / 100, s.y / 100, true, true)
            end
        end
    end
end
