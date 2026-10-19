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

-- which data: "ship" (Itinerary_Data's spawn spots), "own" (ours: the spots baked from beta finds plus every
-- node gathered or passed on this account) or "both"
function ns.gatherSource() return (ItineraryDB and ItineraryDB.gatherSrc) or "both" end

-- our own spots of a zone and node: { {x, y}, ... } from the baked own data, gathered nodes and sightings
local function ownPoints(map, name)
    local out = {}
    local O = ns.GATHER_OWN and ns.GATHER_OWN.zones and ns.GATHER_OWN.zones[map]
    local function add(str)
        for x, y in (str or ""):gmatch("([%d%.]+),([%d%.]+)") do
            x, y = tonumber(x), tonumber(y)
            local dup = false
            for _, p in ipairs(out) do if math.abs(p[1] - x) < 0.6 and math.abs(p[2] - y) < 0.6 then dup = true break end end
            if not dup then out[#out + 1] = { x, y } end
        end
    end
    add(O and O[name])
    local F = ItineraryDB.gatherFound and ItineraryDB.gatherFound[map]
    add(F and F[name])
    local S = ItineraryDB.gatherSeen and ItineraryDB.gatherSeen[map]
    add(S and S[name])
    return out
end
local function ownNames(map)
    local names = {}
    local O = ns.GATHER_OWN and ns.GATHER_OWN.zones and ns.GATHER_OWN.zones[map]
    for n in pairs(O or {}) do names[n] = true end
    for _, t in ipairs({ ItineraryDB.gatherFound, ItineraryDB.gatherSeen }) do
        for n in pairs(t and t[map] or {}) do names[n] = true end
    end
    return names
end

-- the spots of a zone you can gather, cached per zone, skill and data choice. p.src: "ship" (only in the
-- shipped data) or "own" (in ours; with both, a shipped spot we confirmed counts as ours)
local cache = {}
local function spots(map)
    local D = loadData()
    local sk = skills()
    local src = ns.gatherSource()
    local key = map .. ":" .. tostring(sk.herb) .. ":" .. tostring(sk.ore) .. ":" .. src
    if cache.key == key then return cache.list end
    local list = {}
    local function want(name)
        local k = D and D.kinds[name]
        return k and sk[k[1]] and sk[k[1]] >= k[2]
    end
    if src ~= "own" then
        for name, s in pairs(D and D.zones[map] or {}) do
            if want(name) then parse(s, list, name, "ship") end
        end
    end
    if src ~= "ship" then
        for name in pairs(ownNames(map)) do
            if want(name) then
                for _, o in ipairs(ownPoints(map, name)) do
                    local merged = false
                    if src == "both" then
                        for _, p in ipairs(list) do
                            if p.name == name and p.src == "ship" and math.abs(p.x - o[1]) < 1 and math.abs(p.y - o[2]) < 1 then
                                p.src, merged = "own", true
                                break
                            end
                        end
                    end
                    if not merged then list[#list + 1] = { x = o[1], y = o[2], name = name, src = "own" } end
                end
            end
        end
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
-- (a spot's world position is worked out once and kept on the spot: zones have up to ~2,000 of them)
local function spotWorld(map, p)
    if p.wc == nil then
        local c, wx, wy = ns.worldPos(map, p.x / 100, p.y / 100)
        p.wc, p.wx, p.wy = c or false, wx, wy
    end
    return p.wc, p.wx, p.wy
end
local function yards(map, p, pc, px, py)
    if not pc then pc, px, py = ns.playerWorld() end
    if not pc then return nil end
    local c, wx, wy = spotWorld(map, p)
    if c ~= pc then return nil end
    local dx, dy = wx - px, wy - py
    return math.sqrt(dx * dx + dy * dy)
end
local function seen(p)
    local t = state.visited[p.id]
    return t and GetTime() - t < RESET
end

local function pick(map)
    local best, bd
    local pc, px, py = ns.playerWorld()
    for _, p in ipairs(spots(map)) do
        if not seen(p) then
            local d = yards(map, p, pc, px, py)
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
    base.note = "Where it can spawn" .. (p.src == "own" and " (our own data)" or "")
        .. ". Being there moves on to the next spot; › skips this one."
    local rate = ""
    if state.since and state.gathered > 0 then
        local h = (GetTime() - state.since) / 3600
        if h > 0.05 then rate = string.format("  ·  %d/h", math.floor(state.gathered / h + 0.5)) end
    end
    base.where = string.format("%d of %d spots left  ·  %d gathered%s", left, #list, state.gathered, rate)
    return base
end

function ns.setGatherSource(v)
    ItineraryDB.gatherSrc = v
    cache.key, state.target = nil, nil
    if ns.gatherPins then ns.gatherPins(true) end
    if ns.refresh then ns.refresh() end
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
-- shipped data: herbs green, ore orange; our own data: herbs blue, ore pink
local COLOR = { ship = { herb = { 0.35, 0.95, 0.45 }, ore = { 1, 0.62, 0.25 } },
                own = { herb = { 0.35, 0.75, 1 }, ore = { 1, 0.45, 0.85 } } }
local function pin(kind, dim, size, src)
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
    local set = COLOR[src] or COLOR.ship
    local c = set[kind] or set.herb
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
    -- the nearest ones on the minimap: kept in order as the spots go by (no sort of the whole zone, and the
    -- distance on the spot itself instead of a table per spot)
    local pc, px, py = ns.playerWorld()
    local near, n = {}, 0
    for _, p in ipairs(list) do
        local d = yards(map, p, pc, px, py)
        if d and (n < MINIPINS or d < near[n].d) then
            p.d = d
            local k = n < MINIPINS and n + 1 or n
            n = k
            while k > 1 and near[k - 1].d > d do near[k] = near[k - 1]; k = k - 1 end
            near[k] = p
        end
    end
    for k, p in ipairs(near) do
        local kind = D.kinds[p.name] and D.kinds[p.name][1]
        HBDP:AddMinimapIconMap(PINREF, pin(kind, seen(p), 9, p.src), map, p.x / 100, p.y / 100, true, true)
    end
    -- every one on the world map, but only while it's open (the pin library places each pin on the map the
    -- world map last showed even when it's closed: ~2,000 of them every few seconds in Arathi)
    if WorldMapFrame and WorldMapFrame:IsShown() then
        for _, p in ipairs(list) do
            local kind = D.kinds[p.name] and D.kinds[p.name][1]
            HBDP:AddWorldMapIconMap(PINREF, pin(kind, seen(p), 8, p.src), map, p.x / 100, p.y / 100)
        end
    end
end
if WorldMapFrame and WorldMapFrame.HookScript then
    WorldMapFrame:HookScript("OnShow", function() if ns.gatherOn() then ns.gatherPins(true) end end)
end

---------------------------------------------------------------- live: arriving at spots, gathering nodes
local function remember(name, map, x, y)
    local D = loadData()
    if not (D and D.kinds[name] and map) then return end
    -- the spot you're at counts as visited (gather mode moves on)
    for _, p in ipairs(spots(map)) do
        if p.name == name and math.abs(p.x - x) < 0.6 and math.abs(p.y - y) < 0.6 then state.visited[p.id] = GetTime() end
    end
    -- our own data is built from what's really there: only the shipped data doesn't count here. Known to us
    -- within a few yards (gathered before): nothing new; a sighting there becomes the exact spot
    local F = ItineraryDB.gatherFound and ItineraryDB.gatherFound[map]
    for px, py in ((F and F[name]) or ""):gmatch("([%d%.]+),([%d%.]+)") do
        if math.abs(tonumber(px) - x) < 0.6 and math.abs(tonumber(py) - y) < 0.6 then return end
    end
    ItineraryDB.gatherFound = ItineraryDB.gatherFound or {}
    local z = ItineraryDB.gatherFound[map] or {}
    ItineraryDB.gatherFound[map] = z
    z[name] = (z[name] and (z[name] .. ";") or "") .. string.format("%.2f,%.2f", x, y)
    cache.key = nil
    if ns.gatherOn() then ns.print("new " .. name .. " spot remembered") end
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

---------------------------------------------------------------- silent: herbs and veins you pass close by
-- Every character, any profession, gather mode on or off: when a herb or ore vein becomes your soft
-- interact target (it's within about 20 yards), where you stood is noted (ItineraryDB.gatherSeen, the
-- average of where you were while it stayed targeted). Not as exact as gathering it, so it's kept apart and
-- merged more loosely when the data is rebuilt (tools/bake_nodes.py). Nothing is said in chat.
do
    local cur -- { guid, name, map, sx, sy, n, t }
    local done = {} -- GUIDs already noted this session
    local function nodeOf(guid)
        local D = ns.GATHER_DATA
        if not (D and guid) then return nil end
        local kind, _, _, _, _, id = strsplit("-", guid)
        if kind ~= "GameObject" then return nil end
        local name = D.ids and D.ids[tonumber(id)]
        if not name and UnitName then
            local n = ns.unitName("softinteract")
            if n and D.kinds[n] then name = n end
        end
        return name
    end
    local function commit()
        local c = cur
        cur = nil
        if not (c and c.n > 0) or done[c.guid] then return end
        done[c.guid] = true
        local x, y = c.sx / c.n, c.sy / c.n
        local D = ns.GATHER_DATA
        -- known to our own data already (baked, gathered or seen) within ~25 yards: nothing new
        local function near(str)
            for px, py in (str or ""):gmatch("([%d%.]+),([%d%.]+)") do
                if math.abs(tonumber(px) - x) < 1 and math.abs(tonumber(py) - y) < 1 then return true end
            end
        end
        local O = ns.GATHER_OWN and ns.GATHER_OWN.zones and ns.GATHER_OWN.zones[c.map]
        if near(O and O[c.name]) then return end
        if near(ItineraryDB.gatherFound and ItineraryDB.gatherFound[c.map] and ItineraryDB.gatherFound[c.map][c.name]) then return end
        ItineraryDB.gatherSeen = ItineraryDB.gatherSeen or {}
        local z = ItineraryDB.gatherSeen[c.map] or {}
        ItineraryDB.gatherSeen[c.map] = z
        if near(z[c.name]) then return end
        z[c.name] = (z[c.name] and (z[c.name] .. ";") or "") .. string.format("%.2f,%.2f", x, y)
        cache.key = nil
    end
    local function look()
        if not (ItineraryDB and UnitGUID) then return end
        local guid = ns.unitGUID("softinteract")
        if cur and cur.guid ~= guid then commit() end
        if not guid or done[guid] then return end
        if not cur then
            local name = nodeOf(guid)
            if not name then done[guid] = true return end -- not a node: don't look again
            cur = { guid = guid, name = name, sx = 0, sy = 0, n = 0 }
        end
        local map, x, y = here()
        if not map then return end
        if cur.map and cur.map ~= map then commit() return end
        cur.map, cur.sx, cur.sy, cur.n = map, cur.sx + x, cur.sy + y, cur.n + 1
        if cur.n >= 20 then commit() end -- ten seconds next to it is plenty
    end
    local sf = CreateFrame("Frame")
    pcall(sf.RegisterEvent, sf, "PLAYER_SOFT_INTERACT_CHANGED")
    sf:SetScript("OnEvent", function() pcall(look) end)
    local acc = 0
    sf:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.5 then return end
        acc = 0
        pcall(look)
    end)
end
