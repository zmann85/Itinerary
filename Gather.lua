-- Itinerary gather mode: a farming route instead of the leveling route. The arrow leads from one spot where a
-- herb or ore vein can spawn to the next (nearest first), skipping spots you've just been to; the spots of
-- the zone show on the minimap and the world map. Only nodes your skill can gather count.
-- The spawn spots come from the Itinerary_Data add-on (GPL, separate from Itinerary); every
-- node you gather that it doesn't know yet is remembered (ItineraryDB.gatherFound, for all characters) and
-- used from then on - tools/bake_nodes.py adds those to the shipped data.
local ADDON, ns = ...

local REACH = 18          -- yards: close enough to see whether a node is there
local RESET = 10 * 60     -- seconds until a spot you've been to counts again (nodes respawn)
local MINIPINS = 60       -- the nearest spots get a minimap pin
local PROF = { herb = "herbalism", ore = "mining" }

local function C() return ItineraryCharDB end
function ns.gatherOn() local c = C() return c and c.gather and c.gather.on end

---------------------------------------------------------------- data
local function loadData()
    return ns.GATHER_DATA
end

-- what you can gather: { herb = skill, ore = skill } (nil: not that profession)
local function skills()
    local out = {}
    for kind, prof in pairs(PROF) do
        local known, rank = ns.profKnown(prof)
        if known then out[kind] = rank or 1 end
    end
    return out
end

local function parse(s, out, name, src)
    for x, y in (s or ""):gmatch("([%d%.]+),([%d%.]+)") do
        out[#out + 1] = { x = tonumber(x), y = tonumber(y), name = name, src = src }
    end
end

-- the spots of a zone you can gather, cached per zone and skill
local cache = {}
local function spots(map)
    local D = loadData()
    local sk = skills()
    local key = map .. ":" .. tostring(sk.herb) .. ":" .. tostring(sk.ore)
    if cache.key == key then return cache.list end
    local list = {}
    local function want(name)
        local k = D and D.kinds[name]
        return k and sk[k[1]] and sk[k[1]] >= k[2]
    end
    for name, s in pairs(D and D.zones[map] or {}) do
        if want(name) then parse(s, list, name, "data") end
    end
    for name, s in pairs(ItineraryDB.gatherFound and ItineraryDB.gatherFound[map] or {}) do
        if want(name) then parse(s, list, name, "found") end
    end
    for _, p in ipairs(list) do p.id = map .. ":" .. p.x .. ":" .. p.y end
    cache.key, cache.list = key, list
    return list
end
function ns.gatherForget() cache.key = nil end

---------------------------------------------------------------- where you are, what's next
local state = { target = nil, visited = {}, gathered = 0, since = nil }

local function here()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return map, x * 100, y * 100
end
local function yards(map, p)
    local pc, px, py = ns.playerWorld()
    if not pc then return nil end
    local c, wx, wy = ns.worldPos(map, p.x / 100, p.y / 100)
    if c ~= pc then return nil end
    return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
end
local function seen(p)
    local t = state.visited[p.id]
    return t and GetTime() - t < RESET
end

local function pick(map)
    local best, bd
    for _, p in ipairs(spots(map)) do
        if not seen(p) then
            local d = yards(map, p)
            if d and (not bd or d < bd) then best, bd = p, d end
        end
    end
    -- every spot visited lately: start over with the oldest visits
    if not best then
        local any = false
        for _, p in ipairs(spots(map)) do
            if state.visited[p.id] then any = true end
        end
        if any then wipe(state.visited) return pick(map) end
    end
    state.target, state.targetMap = best, map
    return best, bd
end

-- the step the panel shows in gather mode (the arrow follows it like a trainer detour)
function ns.gatherStep()
    if not ns.gatherOn() then return nil end
    local map = here()
    local sk = skills()
    local base = { t = "gather", detour = true, gather = true }
    if not (sk.herb or sk.ore) then
        base.name = "Learn Herbalism or Mining to gather"
        base.note = "Gather mode leads you from node to node for the gathering professions you know."
        return base
    end
    if not loadData() then
        base.name = "Gather data missing"
        base.note = "Install the Itinerary_Data folder next to Itinerary (and restart the game)."
        return base
    end
    if not map then base.name = "No map here" return base end
    local p = state.targetMap == map and state.target or nil
    if not p or seen(p) then p = pick(map) end
    local list = spots(map)
    if not p then
        base.name = #list == 0 and "No known spots in this zone" or "Every spot visited"
        base.note = #list == 0 and "Nodes you gather here are remembered and show up next time." or nil
        return base
    end
    local d = yards(map, p)
    local left = 0
    for _, q in ipairs(list) do if not seen(q) then left = left + 1 end end
    base.name = p.name
    base.m, base.x, base.y, base.dist = map, p.x, p.y, d
    base.note = "Where it can spawn" .. (p.src == "found" and " (found in game)" or "")
        .. ". Being there moves on to the next spot; › skips this one."
    local rate = ""
    if state.since and state.gathered > 0 then
        local h = (GetTime() - state.since) / 3600
        if h > 0.05 then rate = string.format("  ·  %d/h", math.floor(state.gathered / h + 0.5)) end
    end
    base.where = string.format("%d of %d spots left  ·  %d gathered%s", left, #list, state.gathered, rate)
    return base
end

function ns.gatherSkip()
    if state.target then state.visited[state.target.id] = GetTime() end
    state.target = nil
    if ns.refresh then ns.refresh() end
    if ns.gatherPins then ns.gatherPins(true) end
end

---------------------------------------------------------------- on and off
function ns.gatherToggle(on)
    local c = C()
    if not c then return end
    c.gather = c.gather or {}
    if on == nil then on = not c.gather.on end
    c.gather.on = on and true or false
    state.target = nil
    if on then
        if not loadData() then
            ns.print("gather mode needs the Itinerary_Data folder next to Itinerary (restart the game after adding it)")
        end
        state.since, state.gathered = GetTime(), 0
        ns.print("gather mode on: the arrow leads to the next spot where a node can spawn. /iti gather turns it off")
    else
        ns.print("gather mode off: back to your route")
    end
    if ns.gatherPins then ns.gatherPins(true) end
    if ns.refreshPins then ns.refreshPins() end -- the route's own pins go (and come back)
    if ns.refresh then ns.refresh() end
    if ns.refreshArrow then ns.refreshArrow() end
    if ns.refreshSettings then ns.refreshSettings() end
end

---------------------------------------------------------------- map pins
local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
local PINREF = {}
local pool, used = {}, 0
local COLOR = { herb = { 0.35, 0.95, 0.45 }, ore = { 1, 0.62, 0.25 } }
local function pin(kind, dim, size)
    used = used + 1
    local f = pool[used]
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.tex:SetTexture("Interface\\AddOns\\Itinerary\\dot")
        pool[used] = f
    end
    f:SetSize(size, size)
    local c = COLOR[kind] or COLOR.herb
    f.tex:SetVertexColor(c[1], c[2], c[3], dim and 0.35 or 0.95)
    return f
end
local lastPin = { x = nil, y = nil, key = nil }
function ns.gatherPins(force)
    if not HBDP then return end
    HBDP:RemoveAllMinimapIcons(PINREF)
    HBDP:RemoveAllWorldMapIcons(PINREF)
    for k = 1, used do pool[k]:Hide() end
    used = 0
    if not ns.gatherOn() then return end
    local map = here()
    local D = loadData()
    if not (map and D) then return end
    local list = spots(map)
    -- the nearest ones on the minimap, every one on the world map
    local near = {}
    for _, p in ipairs(list) do
        local d = yards(map, p)
        if d then near[#near + 1] = { p = p, d = d } end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for k, e in ipairs(near) do
        if k > MINIPINS then break end
        local kind = D.kinds[e.p.name] and D.kinds[e.p.name][1]
        HBDP:AddMinimapIconMap(PINREF, pin(kind, seen(e.p), 9), map, e.p.x / 100, e.p.y / 100, true, true)
    end
    for _, p in ipairs(list) do
        local kind = D.kinds[p.name] and D.kinds[p.name][1]
        HBDP:AddWorldMapIconMap(PINREF, pin(kind, seen(p), 8), map, p.x / 100, p.y / 100)
    end
end

---------------------------------------------------------------- live: arriving at spots, gathering nodes
local function remember(name, map, x, y)
    local D = loadData()
    if not (D and D.kinds[name] and map) then return end
    -- already known within a few yards (shipped or found): nothing new
    for _, p in ipairs(spots(map)) do
        if p.name == name and math.abs(p.x - x) < 0.6 and math.abs(p.y - y) < 0.6 then
            state.visited[p.id] = GetTime()
            return
        end
    end
    -- known for a skill you don't have yet: look there too
    for n, s in pairs(D.zones[map] or {}) do
        if n == name then
            for px, py in s:gmatch("([%d%.]+),([%d%.]+)") do
                if math.abs(tonumber(px) - x) < 0.6 and math.abs(tonumber(py) - y) < 0.6 then return end
            end
        end
    end
    ItineraryDB.gatherFound = ItineraryDB.gatherFound or {}
    local z = ItineraryDB.gatherFound[map] or {}
    ItineraryDB.gatherFound[map] = z
    z[name] = (z[name] and (z[name] .. ";") or "") .. string.format("%.2f,%.2f", x, y)
    cache.key = nil
    ns.print("new " .. name .. " spot remembered")
end

local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("SKILL_LINES_CHANGED")
local casting = {}
f:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if not (ItineraryDB and ItineraryCharDB) then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, target name, cast GUID, spell ID): picking a herb or mining a vein names the node
        if unit ~= "player" or not a2 then return end
        local D = ns.GATHER_DATA
        if D and D.kinds[a2] then casting[a3 or "?"] = a2 end
        -- remembered even outside gather mode once the data is loaded; without it, only the name is kept
        if D and D.kinds[a2] then
            local map, x, y = here()
            if map then remember(a2, map, x, y) end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unit, cast GUID, spell ID)
        if unit == "player" and a2 and casting[a2] then
            casting[a2] = nil
            if ns.gatherOn() then
                state.gathered = state.gathered + 1
                if ns.refresh then ns.refresh() end
            end
        end
    else
        cache.key = nil
        if ns.gatherOn() then
            state.target = nil
            ns.gatherPins(true)
            if ns.refresh then ns.refresh() end
        end
    end
end)

-- every half second: arrived at the spot? then the next one. Pins follow you every few seconds.
local acc, pinAcc = 0, 0
f:SetScript("OnUpdate", function(_, elapsed)
    if not ns.gatherOn() then return end
    acc, pinAcc = acc + elapsed, pinAcc + elapsed
    if acc < 0.5 then return end
    acc = 0
    local p, map = state.target, state.targetMap
    if p and map then
        local d = yards(map, p)
        if d and d < REACH then
            state.visited[p.id] = GetTime()
            state.target = nil
            if ns.refresh then ns.refresh() end
            pinAcc = 99
        end
    end
    if pinAcc > 4 then
        pinAcc = 0
        local m, x, y = here()
        if m and (lastPin.key ~= m or not lastPin.x or math.abs(lastPin.x - x) + math.abs(lastPin.y - y) > 0.8) then
            lastPin.key, lastPin.x, lastPin.y = m, x, y
            ns.gatherPins()
        end
    end
end)

local lf = CreateFrame("Frame")
lf:RegisterEvent("PLAYER_LOGIN")
lf:SetScript("OnEvent", function()
    if ns.gatherOn() then
        state.since = GetTime()
        C_Timer.After(2, function() ns.gatherPins(true); if ns.refresh then ns.refresh() end end)
    end
end)
