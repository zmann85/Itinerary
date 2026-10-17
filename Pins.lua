-- Itinerary map pins: your next stops, numbered in route order, on the world map (with a dotted line from one
-- to the next) and on the minimap. Steps at the same place share one pin ("2-3"). Settings > Travel: Map pins
-- (all of them), how many on the world map and on the minimap, the line. Uses HereBeDragons-Pins (libs).
local ADDON, ns = ...

local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local MAX = 5
local LOOKAHEAD = 60 -- steps searched for the next stops
local worldPins, miniPins, areaPins = {}, {}, {}
local DOT = "Interface\\AddOns\\" .. ADDON .. "\\dot"

local function accent() return ns.accent() end

local function makePin(size, fontSize)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size)
    f.base = size
    f.ring = f:CreateTexture(nil, "BACKGROUND")
    f.ring:SetTexture(DOT); f.ring:SetAllPoints(); f.ring:SetVertexColor(0, 0, 0, 0.75)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetTexture(DOT); f.dot:SetPoint("TOPLEFT", 2, -2); f.dot:SetPoint("BOTTOMRIGHT", -2, 2)
    if fontSize then
        f.num = f:CreateFontString(nil, "OVERLAY")
        f.num:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        f.num:SetPoint("CENTER", 0, 0)
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local steps = ns.steps()
        local list = self.steps or {}
        if #list == 0 or not steps[list[1]] then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for n, k in ipairs(list) do
            local s = steps[k]
            if s then
                GameTooltip:AddLine(ns.stepText.oneLine(s), 1, 1, 1)
                -- (the details of the first one; with several steps here their names are enough)
                if n == 1 and #list == 1 then GameTooltip:AddLine(ns.stepText.detail(s), 0.7, 0.7, 0.7, true) end
            end
        end
        GameTooltip:AddLine(#list > 1 and ("Steps " .. list[1] .. "-" .. list[#list]) or ("Step " .. list[1]), 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- "2-3" doesn't fit a round pin: it gets as wide as its label
local function setLabel(pin, text)
    if not pin.num then return end
    pin.num:SetText(text)
    local w = pin.base
    if text:find("-", 1, true) then w = math.max(pin.base, math.ceil((pin.num:GetStringWidth() or 0) + 8)) end
    pin:SetSize(w, pin.base)
end

-- two steps in a row at the same place (a hand-in and the follow-up at that NPC): one pin
local function worldXY(s)
    if not HBD then return nil end
    local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(s.x / 100, s.y / 100, s.m)
    return wx, wy, inst
end
local function samePlace(a, b)
    if a.m ~= b.m then return false end
    local ax, ay, ai = worldXY(a)
    local bx, by, bi = worldXY(b)
    if ax and bx and ai == bi then
        local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
        return d <= 12 or (a.npc ~= nil and a.npc == b.npc and d <= 60)
    end
    return math.abs(a.x - b.x) < 0.3 and math.abs(a.y - b.y) < 0.3
end

-- The next n places the route stops at, from your step on: { m, x, y, steps = {k, ...}, first, last, area }.
-- first/last count the stops ("2-3": the 2nd and 3rd); along-the-way steps, steps without a place, steps that
-- don't apply to you and ones already done are left out.
function ns.routePlaces(n)
    local steps, i = ns.steps(), ItineraryCharDB and ItineraryCharDB.step or 1
    local places, ord, prev = {}, 0, nil
    for k = i, math.min(#steps, i + LOOKAHEAD) do
        local s = steps[k]
        if s and s.m and s.m > 0 and s.x and s.x > 0 and not s.along and not ns.notApplicable(s)
           and (k == i or not ns.stepDone(k)) then
            ord = ord + 1
            local last = places[#places]
            if last and prev and samePlace(prev, s) then
                last.steps[#last.steps + 1] = k
                last.last = ord
            else
                if #places >= n then break end
                places[#places + 1] = { m = s.m, x = s.x, y = s.y, steps = { k }, first = ord, last = ord,
                                        area = (k == i) and s.area or nil }
            end
            prev = s
        end
    end
    return places
end

local drawEditor -- (below: the route editor's step on the world map)
function ns.refreshPins()
    ns.pinPlaces = nil
    if not HBDP then return end
    HBDP:RemoveAllWorldMapIcons(ns)
    HBDP:RemoveAllMinimapIcons(ns)
    -- the route editor shows a step: its point, waypoints and kill area instead of your next stops
    if drawEditor and drawEditor() then
        if ns.refreshRouteLine then pcall(ns.refreshRouteLine) end
        return
    end
    local g = ItineraryDB
    local on = g and g.panel.shown and g.pins ~= false and not (ns.gatherOn and ns.gatherOn()) -- (gather mode has its own pins)
    if on then
        local nWorld, nMini = g.pinsWorld or MAX, g.pinsMini or MAX
        local places = ns.routePlaces(math.max(nWorld, nMini))
        ns.pinPlaces = { list = places, n = nWorld }
        local ar, ag, ab = accent()
        local cur = ItineraryCharDB.step
        for p, pl in ipairs(places) do
            local here = pl.steps[1] == cur
            local label = pl.first == pl.last and tostring(pl.first) or (pl.first .. "-" .. pl.last)
            local wx, wy, inst = worldXY(pl)
            if p <= nWorld then
                local pin = worldPins[p] or makePin(18, 10)
                worldPins[p] = pin
                pin.steps = pl.steps
                if here then pin.dot:SetVertexColor(ar, ag, ab, 1) else pin.dot:SetVertexColor(0.75, 0.72, 0.68, 0.9) end
                setLabel(pin, label)
                -- by world position: also on the neighbouring zone's map when it shows that spot, and on the continent
                if wx then HBDP:AddWorldMapIconWorld(ns, pin, inst, wx, wy, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
                else HBDP:AddWorldMapIconMap(ns, pin, pl.m, pl.x / 100, pl.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT) end
                if here and pl.area then
                    -- the spots of the kill/loot area as small dots
                    for n, a in ipairs(pl.area) do
                        local ap = areaPins[n] or makePin(9)
                        areaPins[n] = ap
                        ap.steps = pl.steps
                        ap.dot:SetVertexColor(ar, ag, ab, 0.7)
                        HBDP:AddWorldMapIconMap(ns, ap, a[1], a[2] / 100, a[3] / 100, HBD_PINS_WORLDMAP_SHOW_PARENT)
                    end
                end
            end
            if p <= nMini then
                local pin = miniPins[p] or makePin(14, 8)
                miniPins[p] = pin
                pin.steps = pl.steps
                if here then pin.dot:SetVertexColor(ar, ag, ab, 1) else pin.dot:SetVertexColor(0.75, 0.72, 0.68, 0.85) end
                setLabel(pin, label)
                -- only the first one stays at the minimap's edge when it's out of range; the others show once
                -- they're close enough to be on it
                HBDP:AddMinimapIconMap(ns, pin, pl.m, pl.x / 100, pl.y / 100, true, p == 1)
            end
        end
    end
    if ns.refreshRouteLine then pcall(ns.refreshRouteLine) end
end

---------------------------------------------------------------- the line between the world map pins
-- Dots from one stop to the next, in your theme colour (the stretch to your next stop stronger), under the pins.
-- A data provider of the world map: redrawn when the map, its zoom or your step changes. Dots outside the map
-- shown are left out (the line runs off the edge toward a stop in another zone).
local line = { dots = {} }

local function drawLine(map)
    local P = ns.pinPlaces
    if not (P and ItineraryDB and (P.editor or ItineraryDB.pinsLine ~= false) and HBD) then return end
    local list, n = P.list, math.min(P.n or MAX, #P.list)
    if n < 2 then return end
    local mapID = map:GetMapID()
    if not mapID then return end
    -- zone and continent maps (not the whole world)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if Enum and Enum.UIMapType and info and info.mapType and info.mapType < Enum.UIMapType.Continent then return end
    local canvas = map:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    local scale = (map.GetCanvasScale and map:GetCanvasScale()) or 1
    if not line.frame then line.frame = CreateFrame("Frame", nil, canvas) end
    local f = line.frame
    f:SetParent(canvas)
    f:ClearAllPoints(); f:SetAllPoints(canvas)
    -- right under the pins, above the map itself
    local lm = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    local lvl = lm and lm.GetValidFrameLevel and lm:GetValidFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    f:SetFrameLevel(math.max(1, (lvl or (canvas:GetFrameLevel() + 100)) - 1))
    f:Show()
    local pts = {}
    for k = 1, n do
        local pl = list[k]
        local x, y = HBD:TranslateZoneCoordinates(pl.x / 100, pl.y / 100, pl.m, mapID, true)
        pts[k] = (x and y) and { x * w, y * h } or false
    end
    local ar, ag, ab = accent()
    local step, size, gap = 10 / scale, 4 / scale, 11 / scale -- every 10 px on screen, clear of the pins
    local used = 0
    for k = 1, n - 1 do
        local a, b = pts[k], pts[k + 1]
        if a and b then
            local dx, dy = b[1] - a[1], b[2] - a[2]
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 2 * gap then
                local count = math.min(300, math.floor((len - 2 * gap) / step))
                for j = 0, count do
                    local t = (gap + j * step) / len
                    local px, py = a[1] + dx * t, a[2] + dy * t
                    if px >= 0 and px <= w and py >= 0 and py <= h then
                        used = used + 1
                        local d = line.dots[used]
                        if not d then
                            d = f:CreateTexture(nil, "OVERLAY")
                            d:SetTexture(DOT)
                            line.dots[used] = d
                        end
                        d:SetSize(size, size)
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", f, "TOPLEFT", px, -py)
                        d:SetVertexColor(ar, ag, ab, (k == 1 or P.editor) and 0.95 or 0.55)
                        d:Show()
                    end
                end
            end
        end
    end
end

if WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and CreateFromMixins then
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        for _, d in ipairs(line.dots) do d:Hide() end
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        local map = self:GetMap()
        if map then pcall(drawLine, map) end
    end
    function provider:OnMapChanged() self:RefreshAllData() end
    function provider:OnCanvasScaleChanged() self:RefreshAllData() end
    WorldMapFrame:AddDataProvider(provider)
    ns.refreshRouteLine = function()
        if WorldMapFrame:IsShown() then provider:RefreshAllData() else provider:RemoveAllData() end
    end
end

---------------------------------------------------------------- the route editor on the world map
-- While the editor shows a step (ns.setEditorMap): its point (P), its waypoints (numbered, with the dotted line
-- through them to the point) and its kill-area spots, instead of your next stops. Drag a pin to move it,
-- right-click a waypoint or spot to remove it. "Add on map" in the editor: every click on the map adds one there
-- (right-click stops).
local ed = { geo = nil, h = nil, pins = { way = {}, area = {} }, placing = false }

-- where the cursor is on the world map, as a zone map and coordinates (a continent map: the zone under it)
local function cursorOnMap()
    local map = WorldMapFrame
    if not (map and map:IsShown() and map.ScrollContainer and map.ScrollContainer.GetNormalizedCursorPosition) then return nil end
    local x, y = map.ScrollContainer:GetNormalizedCursorPosition()
    local mapID = map:GetMapID()
    if not (x and y and mapID) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if info and Enum and Enum.UIMapType and info.mapType and info.mapType < Enum.UIMapType.Zone then
        local sub = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
        if not (sub and sub.mapID and HBD) then return nil end
        local zx, zy = HBD:TranslateZoneCoordinates(x, y, mapID, sub.mapID)
        if not (zx and zy) then return nil end
        mapID, x, y = sub.mapID, zx, zy
    end
    return mapID, math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100
end
ns.cursorOnMap = cursorOnMap

-- a marker that follows the cursor while you drag a pin
local ghost
local function showGhost(on)
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetSize(16, 16)
        ghost:SetFrameStrata("TOOLTIP")
        ghost.t = ghost:CreateTexture(nil, "OVERLAY"); ghost.t:SetTexture(DOT); ghost.t:SetAllPoints()
        ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
        end)
    end
    local ar, ag, ab = accent()
    ghost.t:SetVertexColor(ar, ag, ab, 0.8)
    ghost:SetShown(on)
end

local function editorPin(kind, k)
    local list = kind == "point" and ed.pins or ed.pins[kind]
    local key = kind == "point" and "point" or k
    local pin = list[key]
    if pin then return pin end
    pin = makePin(kind == "point" and 20 or (kind == "way" and 16 or 13), kind == "point" and 10 or (kind == "way" and 9 or 7))
    list[key] = pin
    pin.kind, pin.idx = kind, k
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local what = self.kind == "point" and "The step's point" or (self.kind == "way" and ("Waypoint " .. self.idx) or ("Kill area spot " .. self.idx))
        GameTooltip:AddLine(what, 1, 1, 1)
        GameTooltip:AddLine(self.kind == "point" and "Drag to move it." or "Drag to move it, right-click to remove it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    pin:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then ed.drag = self; showGhost(true) end
    end)
    pin:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and ed.drag == self then
            ed.drag = nil; showGhost(false)
            local m, x, y = cursorOnMap()
            if m and ed.h and ed.h.move then ed.h.move(self.kind, self.idx, m, x, y) end
        elseif button == "RightButton" and self.kind ~= "point" and ed.h and ed.h.remove then
            ed.h.remove(self.kind, self.idx)
        end
    end)
    return pin
end

drawEditor = function()
    local g = ed.geo
    if not g then return false end
    local ar, ag, ab = accent()
    local line = {}
    for k, w in ipairs(g.way or {}) do
        local pin = editorPin("way", k)
        pin.dot:SetVertexColor(0.85, 0.82, 0.76, 0.95)
        setLabel(pin, tostring(k))
        HBDP:AddWorldMapIconMap(ns, pin, w.m, w.x / 100, w.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
        line[#line + 1] = w
    end
    for k, a in ipairs(g.area or {}) do
        local pin = editorPin("area", k)
        pin.dot:SetVertexColor(ar, ag, ab, 0.75)
        setLabel(pin, tostring(k))
        HBDP:AddWorldMapIconMap(ns, pin, a.m, a.x / 100, a.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
    end
    if g.point then
        local pin = editorPin("point")
        pin.dot:SetVertexColor(ar, ag, ab, 1)
        setLabel(pin, "P")
        HBDP:AddWorldMapIconMap(ns, pin, g.point.m, g.point.x / 100, g.point.y / 100, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
        line[#line + 1] = g.point
    end
    ns.pinPlaces = { list = line, n = #line, editor = true }
    return true
end

-- placing on the map: a layer over the map that takes the clicks
local function placeLayer()
    if ed.layer or not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return ed.layer end
    local sc = WorldMapFrame.ScrollContainer
    local o = CreateFrame("Button", nil, sc)
    o:SetAllPoints(sc)
    o:SetFrameLevel((sc:GetFrameLevel() or 1) + 3000)
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o.bar = o:CreateTexture(nil, "BACKGROUND"); o.bar:SetColorTexture(0, 0, 0, 0.6)
    o.bar:SetPoint("TOPLEFT", 0, 0); o.bar:SetPoint("TOPRIGHT", 0, 0); o.bar:SetHeight(22)
    o.text = o:CreateFontString(nil, "OVERLAY")
    o.text:SetFont(STANDARD_TEXT_FONT, 12, "")
    o.text:SetPoint("TOP", 0, -5)
    o:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.editorMapPlacing(false) return end
        local m, x, y = cursorOnMap()
        if m and ed.h and ed.h.add then ed.h.add(m, x, y) end
    end)
    o:Hide()
    ed.layer = o
    if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnHide", function() if ed.placing then ns.editorMapPlacing(false) end end) end
    return o
end

-- what = "way" or "area" (what a click adds), false = stop
function ns.editorMapPlacing(what)
    ed.placing = what or false
    local o = placeLayer()
    if o then
        o.text:SetText(what == "area" and "Click to add a kill area spot  ·  right-click to stop" or "Click to add a waypoint  ·  right-click to stop")
        o:SetShown(ed.placing and true or false)
    end
    if ed.h and ed.h.placingChanged then ed.h.placingChanged(ed.placing) end
end
function ns.editorMapIsPlacing() return ed.placing end

-- geo = { point = {m,x,y}, way = { {m,x,y,r}, ... }, area = { {m,x,y}, ... } } in zone coordinates, or nil to stop;
-- handlers: move(kind, i, m, x, y), remove(kind, i), add(m, x, y), placingChanged(what)
function ns.setEditorMap(geo, handlers)
    ed.geo, ed.h = geo, handlers or ed.h
    if not geo and ed.placing then ns.editorMapPlacing(false) end
    ns.refreshPins()
end

-- the world map at the step's zone
function ns.showOnMap(m)
    if not (m and WorldMapFrame) then return end
    if not WorldMapFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) elseif ToggleWorldMap then ToggleWorldMap() end
    end
    if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(m) end
end
