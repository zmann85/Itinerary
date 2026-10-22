-- Itinerary route editor (/iti edit, right-click on the route list button in the panel footer).
-- Your changes are a layer on top of a route (ItineraryDB.edits[routeId].ops): add a step, hide one, change
-- one. The generated routes stay as they are, so a rebuilt route keeps your edits. A step is found by what
-- it is ("accept:313:Grelin Whitebeard#1"), not by its number. Your own routes are the same layer on an
-- empty route (ItineraryDB.customRoutes).
local ADDON, ns = ...

---------------------------------------------------------------- the edit layer
-- every step type the route runs on, in two rows of the editor
local TYPES = { "accept", "complete", "turnin", "go", "do", "train", "xp",
                "fly", "fp", "hearth", "sethearth", "dungeon", "abandon", "junk" }
local TYPE_TIP = {
    accept = "Accept: pick up the quests in Quest IDs from the NPC.",
    complete = "Quest: the quests' objectives (kill, loot, use an item). Mobs go on the target button.",
    turnin = "Turn in: hand in the quests in Quest IDs at the NPC.",
    go = "Go: travel to the step's point. Done when you get there.",
    ["do"] = "Do: anything else - the Text says what. Done when you have its Collect items, open its NPC as a vendor, get to its point, or skip it. A bank step: its Deposit / Withdraw items (More).",
    train = "Train: visit a trainer (NPC). A class trainer visit is done when nothing new is waiting.",
    xp = "XP: grind to the Level.",
    fly = "Fly: take a flight at the NPC (the flight master). Text = where to (\"Menethil Harbor\"): talking to the flight master takes that flight for you (Settings > Travel). Done when you're in the air or there.",
    fp = "Flight path: get the flight path at the NPC (the flight master). Text = the town (\"Menethil Harbor\"). Done when you learn it, or have it already.",
    hearth = "Hearth: use your hearthstone (it gets an item button). Text = where it takes you, your home inn (\"Stormwind City\"). Done when you cast it or are there.",
    sethearth = "Home: make an inn your home at the NPC (the innkeeper; the question is answered for you, Settings > Travel). Text = the place as the game names your home (\"Goldshire\"). Done when it's your home.",
    dungeon = "Dungeon: enter a dungeon (Text = its name; the step's point = the entrance). Done when you're inside.",
    abandon = "Abandon: drop the quests in Quest IDs from your log (one the route won't finish). Done once none of them is in your log - also when you never took it, or when it's finished and the route hands it in later.",
    junk = "Sell junk: sell your grey items at any vendor (they're sold when you open one). An instruction next to the next few steps, done when you open a vendor.",
}
-- the editor's kind of a step: its type, or one of the special to-do steps
local function kindOf(s)
    if s.t == "do" and s.abandon then return "abandon" end
    if s.t == "do" and s.vendor then return "junk" end
    return s.t
end

local function anchorKey(s)
    local what = s.q and table.concat(s.q, ",") or (s.name or s.lvl or "")
    return s.t .. ":" .. tostring(what) .. ":" .. (s.npc or "")
end
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end
-- The editor's key for each of a route's own steps (what an edit is anchored to: "kind:quests:npc#n"), worked
-- out the first time the editor or an edit needs one - not at every login for each of the 4,000+ steps (a
-- string per step that most sessions never use)
local keyedLists = setmetatable({}, { __mode = "k" })
local function keyList(base)
    if not base or keyedLists[base] then return end
    keyedLists[base] = true
    local seen = {}
    for _, s in ipairs(base) do
        local k = anchorKey(s)
        seen[k] = (seen[k] or 0) + 1
        s.edKey = k .. "#" .. seen[k]
    end
end
-- the id the editor uses for a step: "+n" for one you added, its key for one from the route
local function sid(s)
    if not s then return nil end
    if s.edAdd then return "+" .. s.edAdd end
    if not s.edKey then local r = ns.route(); if r then keyList(r.editBase) end end
    return s.edKey
end
ns.editId = sid

-- Your own routes' edits (recorded routes are hundreds of added steps with their trails: a recorded 1-30 run is
-- ~650 KB of tables) are kept packed - one compact string each, ItineraryDB.editsPacked[id] - except the route
-- you're on. Only that one is unpacked (the first time something reads ItineraryDB.edits[id]); switching to
-- another of your routes reloads the interface, like switching to a route pack's route. Before the game saves
-- (logout, reload) every unpacked one is packed again; a route you leave is packed at once.
local LibSerialize = LibStub and LibStub("LibSerialize", true)
local LibDeflate = LibStub and LibStub("LibDeflate", true)
local PACK_V = "1:"
local function unpackEdits(str)
    if not (LibSerialize and LibDeflate and type(str) == "string" and str:sub(1, #PACK_V) == PACK_V) then return nil end
    local z = LibDeflate:DecodeForPrint(str:sub(#PACK_V + 1))
    local ser = z and LibDeflate:DecompressDeflate(z)
    if not ser then return nil end
    local ok, E = LibSerialize:Deserialize(ser)
    if ok and type(E) == "table" and type(E.ops) == "table" then return E end
    return nil
end
local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function packStore()
    ItineraryDB.editsPacked = ItineraryDB.editsPacked or {}
    return ItineraryDB.editsPacked
end
-- (an own route's edits only, and only when the packed string unpacks to exactly the same: else they stay
-- as they are)
function ns.packEdits(id)
    local E = ItineraryDB and ItineraryDB.edits and rawget(ItineraryDB.edits, id)
    if not (E and type(E.ops) == "table" and ItineraryDB.customRoutes and ItineraryDB.customRoutes[id]) then return false end
    if not (LibSerialize and LibDeflate) then return false end
    local ok, str = pcall(function()
        return PACK_V .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(LibSerialize:Serialize(E), { level = 1 }))
    end)
    if not ok or not str then return false end
    local back = unpackEdits(str)
    if not (back and same(back, E)) then return false end
    packStore()[id] = str
    rawset(ItineraryDB.edits, id, nil)
    return true
end
function ns.packAllEdits(except)
    for _, id in ipairs((function() local l = {} for k in pairs(ItineraryDB.edits or {}) do l[#l + 1] = k end return l end)()) do
        if id ~= except then ns.packEdits(id) end
    end
end
-- packed and not unpacked yet (switching to it reloads)
function ns.editsPacked(id)
    local P = ItineraryDB and ItineraryDB.editsPacked
    return P and P[id] ~= nil and not (ItineraryDB.edits and rawget(ItineraryDB.edits, id)) or false
end
-- reading ItineraryDB.edits[id] unpacks that route's edits (the string goes: the tables are the one copy until
-- they're packed again)
local function unpackOnRead()
    ItineraryDB.edits = ItineraryDB.edits or {}
    setmetatable(ItineraryDB.edits, { __index = function(t, id)
        local P = ItineraryDB.editsPacked
        local str = P and P[id]
        if not str then return nil end
        local E = unpackEdits(str)
        if not E then return nil end -- (a string this version can't read stays as it is)
        rawset(t, id, E)
        P[id] = nil
        return E
    end })
end
-- your route's edits are gone for good (reset, deleted route): the packed copy too
local function dropEdits(id)
    if ItineraryDB.edits then rawset(ItineraryDB.edits, id, nil) end
    if ItineraryDB.editsPacked then ItineraryDB.editsPacked[id] = nil end
end

local function editsFor(id, create)
    ItineraryDB.edits = ItineraryDB.edits or {}
    local e = ItineraryDB.edits[id]
    if not e and create then e = { ops = {}, n = 0 }; ItineraryDB.edits[id] = e end
    return e
end

function ns.applyEdits(r, base, chapters)
    local id = ItineraryCharDB and ItineraryCharDB.route
    r.editBase = base
    local E = id and ItineraryDB.edits and ItineraryDB.edits[id]
    if not E or #E.ops == 0 then
        r.editList = base
        return base, chapters
    end
    keyList(base)
    -- numbers in the route (along "till", chapter starts) become step references while the list changes
    local chapRef = {}
    for n, c in ipairs(chapters) do chapRef[n] = base[c.first] end
    for _, s in ipairs(base) do if s.till then s.tillRef = base[s.till] end end

    local list, byKey, index = {}, {}, {}
    for j, s in ipairs(base) do list[#list + 1] = s; byKey[s.edKey] = s; index[s.edKey] = j end
    -- the route's own steps stay untouched: a step you hide or change is a copy in this list
    local function own(key)
        local s = byKey[key]
        if s and not s.edCopy then
            local c = {}
            for f, v in pairs(s) do c[f] = v end
            c.edCopy = true
            c.tillRef = s.tillRef
            for n, ref in pairs(chapRef) do if ref == s then chapRef[n] = c end end
            for _, x in ipairs(list) do if x.tillRef == s then x.tillRef = c end end
            byKey[key], list[index[key]] = c, c
            s = c
        end
        return s
    end
    for _, op in ipairs(E.ops) do
        local s = op.at and byKey[op.at] and own(op.at)
        if s and op.k == "hide" then s.edHidden = true
        elseif s and op.k == "set" then
            for f, v in pairs(op.f) do if v == false then s[f] = nil else s[f] = type(v) == "table" and copy(v) or v end end
            s.edChanged = true
        end
    end
    local added = {}
    for _, op in ipairs(E.ops) do
        if op.k == "add" then
            local s = copy(op.s)
            s.edAdd = op.id
            local at
            if op.after == "^" then at = 0
            else
                local target = op.after:sub(1, 1) == "+" and added[tonumber(op.after:sub(2))] or byKey[op.after]
                if target then for j, x in ipairs(list) do if x == target then at = j break end end end
            end
            if not at then s.edOrphan = true; at = #list end
            table.insert(list, at + 1, s)
            added[op.id] = s
        end
    end
    r.editList = list
    -- "Ends at step" set in the editor: a reference to that step (a route step's key, or "+n" for one you added)
    for _, s in ipairs(list) do
        if s.tillKey then
            local k = s.tillKey
            s.tillEnd = k:sub(1, 1) == "+" and added[tonumber(k:sub(2))] or byKey[k]
            s.tillRef = nil
        end
    end

    local steps, pos = {}, {}
    for _, s in ipairs(list) do
        if not s.edHidden then steps[#steps + 1] = s; pos[s] = #steps end
    end
    -- a reference to a hidden step moves to the next step that's still there
    local order = {}
    for j, s in ipairs(list) do order[s] = j end
    local function at(ref)
        if not ref then return nil end
        if pos[ref] then return pos[ref] end
        for j = (order[ref] or #list) + 1, #list do if pos[list[j]] then return pos[list[j]] end end
        return #steps
    end
    for _, s in ipairs(steps) do
        if s.tillRef then s.till = at(s.tillRef); s.tillRef = nil end
        -- shown up to the step before the end step: gone once you get there
        if s.tillEnd then s.till = math.max(1, (at(s.tillEnd) or #steps) - 1); s.tillEnd = nil end
    end
    local ch = {}
    for n, c in ipairs(chapters) do ch[#ch + 1] = { name = c.name, first = at(chapRef[n]) or 1 } end
    for j, s in ipairs(steps) do if s.chapter and s.chapter ~= "" then ch[#ch + 1] = { name = s.chapter, first = j, own = true } end end
    table.sort(ch, function(a, b) if a.first ~= b.first then return a.first < b.first end return (a.own and 1 or 0) > (b.own and 1 or 0) end)
    local out = {}
    for _, c in ipairs(ch) do if not out[1] or out[#out].first ~= c.first then out[#out + 1] = c end end
    if not out[1] and steps[1] then out[1] = { name = r.name or "Route", first = 1 } end
    return steps, out
end

local function rebuild()
    if ns.rebuildRoute then ns.rebuildRoute() end
    if ns.refreshEditor then ns.refreshEditor() end
end

-- The routes that come with the addon are never changed: the first change to one makes your own copy of
-- it (same steps, you stay on the same step) and the change goes there.
local function editable()
    local r = ns.route()
    if r and not r.custom and ns.newCustomRoute then
        ns.newCustomRoute(nil, ItineraryCharDB.route)
        return false
    end
    return true
end
ns.editEnsureOwn = editable

-- add a step after the step with editor id `after` ("^" = at the start); returns its id ("+n")
function ns.editAdd(s, after)
    editable()
    local id = ItineraryCharDB.route
    local E = editsFor(id, true)
    E.n = E.n + 1
    E.ops[#E.ops + 1] = { k = "add", id = E.n, after = after or "^", s = s }
    rebuild()
    return "+" .. E.n
end
local function addOp(key)
    local E = editsFor(ItineraryCharDB.route, true)
    local n = tonumber(key:match("^%+(%d+)$") or "")
    for i, op in ipairs(E.ops) do if op.k == "add" and op.id == n then return op, i, E end end
end
-- change fields of a step (false removes a field)
function ns.editSet(key, fields)
    editable()
    local op, _, E = addOp(key)
    if op then
        for f, v in pairs(fields) do if v == false then op.s[f] = nil else op.s[f] = v end end
    else
        E = editsFor(ItineraryCharDB.route, true)
        local set
        for _, o in ipairs(E.ops) do if o.k == "set" and o.at == key then set = o end end
        if not set then set = { k = "set", at = key, f = {} }; E.ops[#E.ops + 1] = set end
        for f, v in pairs(fields) do set.f[f] = v end
    end
    rebuild()
end
function ns.editHide(key, hide)
    editable()
    local E = editsFor(ItineraryCharDB.route, true)
    for i = #E.ops, 1, -1 do if E.ops[i].k == "hide" and E.ops[i].at == key then table.remove(E.ops, i) end end
    if hide then E.ops[#E.ops + 1] = { k = "hide", at = key } end
    rebuild()
end
-- undo your changes to a step from the route
function ns.editRevert(key)
    local E = editsFor(ItineraryCharDB.route, true)
    for i = #E.ops, 1, -1 do if (E.ops[i].k == "set" or E.ops[i].k == "hide") and E.ops[i].at == key then table.remove(E.ops, i) end end
    rebuild()
end
function ns.editDelete(key)
    local op, i, E = addOp(key)
    if not op then return end
    table.remove(E.ops, i)
    -- steps that were added after this one now follow what it followed
    for _, o in ipairs(E.ops) do if o.k == "add" and o.after == key then o.after = op.after end end
    rebuild()
end
-- move a step you added one place up or down
function ns.editMove(key, dir)
    local op, _, E = addOp(key)
    local r = ns.route()
    if not (op and r and r.editList) then return end
    local list, p = r.editList, nil
    for j, s in ipairs(list) do if sid(s) == key then p = j end end
    if not p then return end
    local newAfter
    if dir < 0 then
        if p == 1 then return end
        newAfter = p >= 3 and sid(list[p - 2]) or "^"
    else
        if p == #list then return end
        newAfter = sid(list[p + 1])
    end
    for _, o in ipairs(E.ops) do if o.k == "add" and o.after == key then o.after = op.after end end
    op.after = newAfter
    rebuild()
end
function ns.editReset()
    dropEdits(ItineraryCharDB.route)
    rebuild()
end

---------------------------------------------------------------- your own routes
-- the route a copy is built on: the version it was made from, else the newest installed version of that route
-- (a build that no longer ships the old version; your edits go on top of the new one)
local function originOf(from)
    if not from then return nil end
    if ns.routes[from] then return from end
    local base, best = (from:gsub("@.*$", "")), nil
    for oid, o in pairs(ns.routes) do
        if not o.custom and (oid:gsub("@.*$", "")) == base and (not best or ns.versionCompare(o, ns.routes[best]) > 0) then best = oid end
    end
    return best
end
ns.copyOriginOf = originOf
local function registerCustom()
    for id, def in pairs(ItineraryDB.customRoutes or {}) do
        local fid = originOf(def.from)
        local src = fid and ns.routes[fid]
        if not ns.routes[id] then
            ns.routes[id] = { custom = true, from = src and fid or nil, faction = def.faction,
                              chapters = src and (src.baseChapters or src.chapters) or {}, staticSteps = {} }
        end
        -- older copies were named after the long route names ("... 1-60 (<source> Forever + dungeons) (my copy)")
        if def.name then def.name = def.name:gsub(" %([^()]- Forever %+ dungeons%)", "") end
        local r = ns.routes[id]
        -- a copy whose original comes in a route pack loaded after Itinerary: link it up now
        if src and not r.from and not r.built then
            r.from, r.chapters = fid, src.baseChapters or src.chapters or {}
        end
        r.name, r.match = def.name, def.match
        r.ref = def.ref -- a reference run's level times (pace), when the route has them
        r.version = def.from and "your copy" or "your route"
    end
end
-- edits made to a shipped route by earlier versions move into a copy of it ("... (my copy)")
-- Recordings made before chapters followed the map's zone started a chapter each time you walked into a
-- building with a name of its own (Anvilmar) and again on the way out. Those are taken out once: a chapter
-- whose zone isn't where its step is, or the same zone as the chapter before it.
local function fixRecordedChapters()
    if ItineraryDB.recChaptersFixed then return end
    ItineraryDB.recChaptersFixed = true
    local n = 0
    for id, def in pairs(ItineraryDB.customRoutes or {}) do
        local E = ItineraryDB.edits and ItineraryDB.edits[id]
        if E and def.name and def.name:match("^Recorded") then
            local last
            for _, op in ipairs(E.ops) do
                local st = op.k == "add" and op.s
                if st and st.chapter and st.chapter ~= "" then
                    local zone = st.chZone or st.chapter:gsub("%s+%d+$", "")
                    if (st.z and st.z ~= "" and zone ~= st.z) or zone == last then
                        st.chapter, st.chZone = nil, nil
                        n = n + 1
                    else
                        st.chZone, last = zone, zone
                    end
                end
            end
        end
    end
    if n > 0 then C_Timer.After(3, function() ns.print(n .. " stray chapter start(s) taken out of your recorded routes (a building like Anvilmar counted as a new zone)") end) end
end

local function migrateShippedEdits()
    ItineraryDB.editMoved = ItineraryDB.editMoved or {}
    local todo = {}
    for id, E in pairs(ItineraryDB.edits or {}) do todo[#todo + 1] = id end
    for _, id in ipairs(todo) do
        local E, src = ItineraryDB.edits[id], ns.routes[id]
        if src and not src.custom and E.ops and #E.ops > 0 then
            ItineraryDB.customRoutes = ItineraryDB.customRoutes or {}
            local n = 1
            while ItineraryDB.customRoutes["my-route-" .. n] do n = n + 1 end
            local newId = "my-route-" .. n
            ItineraryDB.customRoutes[newId] = { name = (src.name or id) .. " (my copy)", faction = src.faction,
                                                match = src.match, from = src.from or id }
            ItineraryDB.edits[newId], ItineraryDB.edits[id] = E, nil
            ItineraryDB.editMoved[id] = newId
        end
    end
    -- a character that was on the changed route goes on with the copy (same steps, same place)
    local c = ItineraryCharDB
    if c and c.route and ItineraryDB.editMoved[c.route] then
        c.editMovedDone = c.editMovedDone or {}
        if not c.editMovedDone[c.route] then
            local to = ItineraryDB.editMoved[c.route]
            c.editMovedDone[c.route] = true
            if ItineraryDB.customRoutes and ItineraryDB.customRoutes[to] then c.route = to; c.routeChosen = true end
        end
    end
end

ns.registerCustomRoutes = function() registerCustom() end
local function myClassMatch()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    return { race = { race }, class = class }
end
-- a new route of your own: empty, or a copy of the one you're on (with your edits of it)
function ns.newCustomRoute(name, copyOf)
    ItineraryDB.customRoutes = ItineraryDB.customRoutes or {}
    local n = 1
    while ItineraryDB.customRoutes["my-route-" .. n] do n = n + 1 end
    local id = "my-route-" .. n
    local def = { name = name or ("My route " .. n), faction = UnitFactionGroup and UnitFactionGroup("player"), match = myClassMatch() }
    if copyOf then
        local src = ns.routes[copyOf]
        def.from = src and (src.from or copyOf)
        def.name = name or ((src and src.name or "Route") .. " (my copy)")
        local E = ItineraryDB.edits and ItineraryDB.edits[copyOf]
        if E then ItineraryDB.edits = ItineraryDB.edits or {}; ItineraryDB.edits[id] = copy(E) end
    end
    ItineraryDB.customRoutes[id] = def
    registerCustom()
    local c = ItineraryCharDB
    local cur = copyOf and sid(ns.steps()[c.step])
    local manual = copyOf and {}
    if manual then for i, v in pairs(c.manual or {}) do local k = sid(ns.steps()[i]); if k then manual[k] = v end end end
    -- (a copy has the same steps with the same ids: the editor keeps the step you're looking at)
    ns.editorKeepSelection = copyOf and true or nil
    ns.switchRoute(id, true)
    ns.editorKeepSelection = nil
    -- a copy keeps you where you were (same steps, same ids)
    if cur then
        for j, x in ipairs(ns.steps()) do
            local k = sid(x)
            if k == cur then c.step = j end
            if k and manual[k] then c.manual[j] = manual[k] end
        end
    end
    rebuild()
    ns.print((copyOf and "copied to " or "new route ") .. "\"" .. def.name .. "\" - change it in the editor; pick routes with the list button in the panel footer")
    return id
end
function ns.deleteCustomRoute(id)
    if not (ItineraryDB.customRoutes and ItineraryDB.customRoutes[id]) then return end
    ItineraryDB.customRoutes[id] = nil
    dropEdits(id)
    if ItineraryCharDB.route == id then ItineraryCharDB.route = nil; ItineraryCharDB.picked = nil end
    ns.routes[id] = nil
    ns.print("route deleted")
    if not ItineraryCharDB.route and ns.askReload then ns.askReload("The route you were on is deleted.") end
end
function ns.renameCustomRoute(id, name)
    local def = ItineraryDB.customRoutes and ItineraryDB.customRoutes[id]
    if not def or not name or name == "" then return end
    def.name = name
    if ns.routes[id] then ns.routes[id].name = name end
    if ns.refresh then ns.refresh() end
end

---------------------------------------------------------------- where you are
local function here()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local p = m and C_Map.GetPlayerMapPosition(m, "player")
    if not p then return nil end
    local x, y = p:GetXY()
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    return { m = m, x = math.floor(x * 10000 + 0.5) / 100, y = math.floor(y * 10000 + 0.5) / 100, z = info and info.name or nil }
end
ns.editorHere = here

---------------------------------------------------------------- recording
local recording = false
local lastNpc
local function prevId()
    local c, steps = ItineraryCharDB, ns.steps()
    local prev = steps[(c.step or 1) - 1]
    return prev and sid(prev) or "^"
end
local function routeHas(t, q)
    local c, steps = ItineraryCharDB, ns.steps()
    for j = math.max(1, c.step - 3), math.min(#steps, c.step + 40) do
        local s = steps[j]
        if s.t == t and s.q then for _, x in ipairs(s.q) do if x == q then return true end end end
    end
    return false
end
local function questName(q)
    local f = C_QuestLog and C_QuestLog.GetTitleForQuestID
    return (f and f(q)) or ("Quest " .. q)
end
local function record(t, q)
    if not (recording and q and q > 0) or routeHas(t, q) then return end
    local p = here() or {}
    local s = { t = t, q = { q }, n = { questName(q) }, npc = lastNpc, targets = lastNpc and { lastNpc } or nil, m = p.m, x = p.x, y = p.y, z = p.z }
    ns.editAdd(s, prevId())
    ns.print("recorded: " .. (t == "accept" and "accept " or "turn in ") .. s.n[1] .. (lastNpc and (" at " .. lastNpc) or ""))
end

function ns.setRecording(on)
    if on == nil then on = not recording end
    recording = on and true or false
    ns.print(recording and "recording: quests you accept or turn in that the route doesn't have here are added as steps"
        or "recording stopped")
    if ns.refreshEditor then ns.refreshEditor() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING",
                     "QUEST_ACCEPTED", "QUEST_TURNED_IN" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 == ADDON and ItineraryDB then
            unpackOnRead()
            migrateShippedEdits(); fixRecordedChapters(); registerCustom()
            -- (saved before this came in: your other routes' edits are packed now)
            ns.packAllEdits(ItineraryCharDB and ItineraryCharDB.route)
        end
    elseif event == "PLAYER_LOGIN" then
        if ItineraryDB and ItineraryDB.reopenEditor then
            ItineraryDB.reopenEditor = nil
            C_Timer.After(1, function() if ns.openEditor then ns.openEditor() end end)
        end
    elseif event == "QUEST_ACCEPTED" then
        local q = (type(a2) == "number" and a2 > 0) and a2 or a1
        C_Timer.After(0.3, function() record("accept", q) end)
    elseif event == "QUEST_TURNED_IN" then
        record("turnin", a1)
    else
        lastNpc = ns.unitName("npc") or lastNpc
    end
end)

---------------------------------------------------------------- window
local W, H, PAD = 900, 696, 16
local ROWS, ROW_H = 16, 20
local LIST_W = 360
local win, rows, sel, offset, refresh = nil, {}, nil, 0, nil
local chap = nil -- the chapter the list shows (0 = all steps)
local page = 1   -- the page of the step details: 1 the step, 2 conditions, 3 more
local view = {}  -- the steps of that chapter
local fields = {}
local query = "" -- the step list's search (lower case; "" = none)
local resultsOpen, resOff = false, 0 -- the search's list of matches: shown, scrolled by

local function U() return ns.ui end
local VERB = { accept = "ACCEPT", complete = "QUEST", turnin = "TURN IN", go = "GO", ["do"] = "DO", train = "TRAIN", xp = "XP",
               fly = "FLY", hearth = "HEARTH", sethearth = "HOME", fp = "FP", dungeon = "DUNGEON", abandon = "ABANDON",
               junk = "SELL JUNK" }
-- quest names the route knows (from its accept / turn in steps), for steps that only have the quest's ID
local qnames, qnamesFor = {}, nil
local function routeQuestName(q)
    local steps = ns.steps()
    if qnamesFor ~= steps then
        qnames, qnamesFor = {}, steps
        for _, x in ipairs(steps) do
            if x.q and x.n then for k, id in ipairs(x.q) do if x.n[k] and x.n[k] ~= "" then qnames[id] = x.n[k] end end end
        end
    end
    if qnames[q] then return qnames[q] end
    local f = C_QuestLog and C_QuestLog.GetTitleForQuestID
    return f and f(q) or nil
end
local function label(s)
    if s.n and s.n[1] then return s.n[1] end
    if s.t == "complete" and s.q and s.q[1] then
        local qn = routeQuestName(s.q[1])
        local objs = {}
        for _, o in ipairs(s.obj or {}) do if o and o ~= "" then objs[#objs + 1] = o end end
        if qn then return qn .. (#objs > 0 and ("  |cff999999" .. table.concat(objs, ", ") .. "|r") or "") end
        if #objs > 0 then return table.concat(objs, ", ") end
    end
    if s.name then return s.name end
    if s.t == "complete" and s.obj and s.obj[1] then return s.obj[1] end
    if s.t == "xp" and s.lvl then return "Level " .. s.lvl end
    return s.npc or ""
end
-- the search over the step list: a step's text - its Text, and for quest steps the quests' names (and a quest
-- step's objectives), as the list shows them
local function matches(s)
    if query == "" then return false end
    local function has(t) return t and t ~= "" and tostring(t):lower():find(query, 1, true) ~= nil end
    if has(s.name) then return true end
    for _, n in ipairs(s.n or {}) do if has(n) then return true end end
    for _, q in ipairs(s.q or {}) do if has(routeQuestName(q)) then return true end end
    for _, o in ipairs(s.obj or {}) do if has(o) then return true end end
    return false
end
ns.editorSearchMatches = matches -- (tests)
-- the quest name a search found when it isn't the one the list shows (a step with two quests)
local function otherMatch(s)
    local names = {}
    for _, n in ipairs(s.n or {}) do names[#names + 1] = n end
    for _, q in ipairs(s.q or {}) do names[#names + 1] = routeQuestName(q) end
    for _, n in ipairs(names) do
        if n and n ~= "" and n:lower():find(query, 1, true) then return n end
    end
end
local function clearSearch()
    query, resultsOpen, resOff = "", false, 0
    if win and win.search then win.search:SetText("") end
end

local function button(parent, txt, w, onClick, tip)
    local b = U().segment(parent, txt)
    b:SetSize(w, 22)
    b:SetActive(false)
    b.tip = tip
    b:SetScript("OnClick", onClick)
    return b
end

local function editbox(parent, w, onCommit)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetFont(U().fontPath(), 12, "")
    e:SetTextColor(1, 1, 1, 0.9)
    e:SetTextInsets(6, 6, 0, 0)
    local bg = e:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.05, 0.6)
    U().addEdges(e, 1, 1, 1, 0.15)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); if refresh then refresh() end end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- (back to the start when you leave it, changed or not: a long text you moved through to its end showed
    -- only its end from then on)
    e:SetScript("OnEditFocusLost", function(self)
        if self.dirty then self.dirty = false; onCommit(self:GetText()) end
        self:SetCursorPosition(0)
    end)
    e:SetScript("OnTextChanged", function(self, user) if user then self.dirty = true end end)
    return e
end

-- Shift-click an item (bags, chat link, loot) while an item field is active: its ID goes in (Items, Collect, and
-- on Conditions the Item and Until buff fields; one item only in those two)
local itemBox, colBox
local ITEM_BOXES = {} -- box -> { count = " x1" after the item, one = only one item }
if hooksecurefunc and HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", function(link)
    local box
    for b in pairs(ITEM_BOXES) do if b:HasFocus() then box = b end end
    if not (box and link and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id then return end
    local how = ITEM_BOXES[box]
    local cur = how.one and "" or (box:GetText() or "")
    local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    box:SetText(cur .. (cur:match("%S") and ", " or "") .. id .. (n and (" " .. n) or "") .. (how.count or ""))
    box.dirty = true
end) end

local function selected()
    local r = ns.route()
    if not (r and r.editList) then return nil end
    for j, s in ipairs(r.editList) do if sid(s) == sel then return s, j end end
end
local function stepNumber(s)
    for j, x in ipairs(ns.steps()) do if x == s then return j end end
end

-- chapter number of each entry of the edit list; a hidden step belongs with the step before it
local function chapterMap(r)
    local num, out, c = {}, {}, 1
    for j, s in ipairs(ns.steps()) do num[s] = j end
    local chs = r.chapters or {}
    local k = 1
    for j, s in ipairs(r.editList or {}) do
        local n = num[s]
        if n then
            while chs[k + 1] and chs[k + 1].first <= n do k = k + 1 end
            c = (chs[1] and chs[1].first <= n) and k or 1
        end
        out[j] = c
    end
    return out
end

-- show the chapter of the selected step and scroll to it
local function showSelected()
    local r = ns.route()
    if not (r and r.editList and sel) then return end
    local map = chapterMap(r)
    for j, s in ipairs(r.editList) do if sid(s) == sel then if chap ~= 0 then chap = map[j] end end end
    local k = 0
    for j, s in ipairs(r.editList) do
        if chap == 0 or map[j] == chap then
            k = k + 1
            if sid(s) == sel and (k <= offset or k > offset + ROWS) then offset = math.max(0, k - 4) end
        end
    end
end

local function scrollToCurrent()
    local r = ns.route()
    if not (r and r.editList) then return end
    local cur = ns.steps()[ItineraryCharDB.step]
    local map = chapterMap(r)
    local c = nil
    for j, s in ipairs(r.editList) do if s == cur then c = map[j]; sel = sid(s) end end
    chap = c or chap or 1
    local k = 0
    for j, s in ipairs(r.editList) do
        if chap == 0 or map[j] == chap then
            k = k + 1
            if s == cur then offset = math.max(0, k - 4) end
        end
    end
end

local function numbers(text)
    local out = {}
    for n in tostring(text or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end
local function names(text)
    local out = {}
    for part in tostring(text or ""):gmatch("[^,]+") do
        local n = part:gsub("^%s+", ""):gsub("%s+$", "")
        if n ~= "" then out[#out + 1] = n end
    end
    return out
end

local function build()
    local ui = U()
    local ar, ag, ab = ui.accent()
    win = CreateFrame("Frame", "ItineraryEditorWindow", UIParent)
    win:SetSize(W, H)
    local pos = ItineraryDB.editorPos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER") end
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local p, _, rp, x, y = win:GetPoint()
        ItineraryDB.editorPos = { p, rp, x, y }
    end)
    tinsert(UISpecialFrames, "ItineraryEditorWindow")
    local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.97))
    ui.addEdges(win, 1, 1, 1, 0.15)
    local top = win:CreateTexture(nil, "ARTWORK"); top:SetColorTexture(ar, ag, ab, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)

    local eyebrow = ui.text(win, 12, ar, ag, ab, 0.9); eyebrow:SetPoint("TOPLEFT", PAD, -14); eyebrow:SetText("ITINERARY")
    local title = ui.text(win, 18, 1, 1, 1, 1); title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -3); title:SetText("Route editor")
    win.routeName = ui.text(win, 12, 1, 1, 1, 0.5); win.routeName:SetPoint("LEFT", title, "RIGHT", 12, -1)
    win.routeName:SetWidth(W - 380); win.routeName:SetWordWrap(false)
    -- (the full story on hover: the line itself is short so it isn't cut off)
    win.routeTip = CreateFrame("Frame", nil, win)
    win.routeTip:SetAllPoints(win.routeName)
    win.routeTip:EnableMouse(true)
    win.routeTip:SetScript("OnEnter", function(self)
        local r = ns.route()
        if not r or r.custom then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(r.name or "?", 1, 1, 1)
        GameTooltip:AddLine("This route comes with a route pack and is never changed. Your first change makes your own copy of it, and this character goes on with the copy. The original stays in the route list (Change route).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    win.routeTip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.nameEdit = editbox(win, 360, function(t) ns.renameCustomRoute(ItineraryCharDB.route, t) end)
    win.nameEdit:HookScript("OnEditFocusLost", function(self) self:SetCursorPosition(0) end) -- a long name shows its start
    win.nameEdit:SetPoint("LEFT", title, "RIGHT", 12, -1)
    -- which route the editor shows: the routes list (switching this character to the one you pick)
    win.routeSel = button(win, "Change route", 104, function(self) if ns.toggleRoutePicker then ns.toggleRoutePicker(self, true) end end,
        "Pick the route to look at and change: every version, your own routes, and (at the bottom) all routes. This character follows the route you pick (a generated route loads with a quick reload; the editor opens again).")
    win.routeSel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -40, -30)
    -- your changes count right away; the game writes them to disk on a reload or logout (not on a crash)
    win.save = button(win, "Save", 64, function()
        for _, f in pairs(fields) do if f.box:HasFocus() then f.box:ClearFocus() end end -- a field you're typing in counts too
        ItineraryDB.reopenEditor = true
        ReloadUI()
    end, "Your edits work in the route the moment you make them. Save writes them to disk now (a quick reload, the editor opens again) - otherwise that happens when you log out, and a game crash before that would lose them.")
    win.save:SetPoint("RIGHT", win.routeSel, "LEFT", -6, 0)

    local close = CreateFrame("Button", nil, win)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -8, -8)
    local x = ui.text(close, 18, 1, 1, 1, 0.5); x:SetPoint("CENTER"); x:SetJustifyH("CENTER"); x:SetText("×")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 0.9) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.5) end)
    close:SetScript("OnClick", function() win:Hide() end)

    -- toolbar
    local tb = {}
    tb.rec = button(win, "Record", 82, function() ns.setRecording() end, "While on, every quest you accept or turn in that the route doesn't have around your step is added as a step, at your position and NPC. A route that comes with the addon isn't changed: the first added step makes your own copy of it, and you go on with the copy.")
    tb.rec:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    tb.here = button(win, "Add step here", 104, function()
        local p = here() or {}
        local s = { t = "go", name = (GetSubZoneText and GetSubZoneText() ~= "" and GetSubZoneText()) or p.z or "Here", m = p.m, x = p.x, y = p.y, z = p.z, r = 15 }
        local cur = selected()
        sel = ns.editAdd(s, cur and sid(cur) or prevId())
        showSelected(); refresh()
    end, "Adds a travel step at your position after the selected step. Change its type and text on the right.")
    tb.here:SetPoint("LEFT", tb.rec, "RIGHT", 6, 0)
    tb.cur = button(win, "Current step", 100, function() scrollToCurrent(); refresh() end, "Show the step you're on.")
    tb.cur:SetPoint("LEFT", tb.here, "RIGHT", 6, 0)
    tb.new = button(win, "New route", 92, function() ns.newCustomRoute(); offset, sel, chap = 0, nil, nil; refresh() end,
        "Starts an empty route of your own and switches this character to it. The list button in the panel footer switches back.")
    tb.new:SetPoint("LEFT", tb.cur, "RIGHT", 6, 0)
    tb.copy = button(win, "Make a copy", 100, function() ns.newCustomRoute(nil, ItineraryCharDB.route); offset, sel, chap = 0, nil, nil; scrollToCurrent(); refresh() end,
        "Your own copy of this route with your edits so far: change it freely, the original stays as it is. Switch between them with the list button in the panel footer.")
    tb.copy:SetPoint("LEFT", tb.new, "RIGHT", 6, 0)
    tb.reset = button(win, "Undo all edits", 108, function(self)
        if self.armed then self.armed = false; ns.editReset(); ns.print("all your edits of this route are undone"); refresh(); return end
        self.armed = true; self.text:SetText("Click again"); C_Timer.After(3, function() self.armed = false; refresh() end)
    end, "Removes every change you made to this route (two clicks).")
    tb.reset:SetPoint("LEFT", tb.copy, "RIGHT", 6, 0)
    tb.recorder = button(win, "Recorder", 82, function() if ns.openRecorder then ns.openRecorder(true) end end,
        "Opens the recorder: it writes whatever you do with this character into a new route of its own (quests, trainers, flights, hearthstone), with hints and instructions you add.")
    tb.recorder:SetPoint("LEFT", tb.reset, "RIGHT", 6, 0)
    tb.export = button(win, "Export", 70, function() if ns.openShare then ns.openShare("export", ItineraryCharDB.route) end end,
        "A text you can give to others (copy it with Ctrl+C): your own route, with all your changes.")
    tb.export:SetPoint("LEFT", tb.recorder, "RIGHT", 6, 0)
    tb.import = button(win, "Import", 70, function() if ns.openShare then ns.openShare("import") end end,
        "Paste a route someone shared (Ctrl+V). It's saved as a new route of your own.")
    tb.import:SetPoint("LEFT", tb.export, "RIGHT", 6, 0)
    win.tb = tb

    -- chapter selector over the list
    local cb = CreateFrame("Frame", nil, win)
    cb:SetPoint("TOPLEFT", tb.rec, "BOTTOMLEFT", 0, -12)
    cb:SetSize(LIST_W, 24)
    local function pickChapter(n)
        chap, offset, resOff = n, 0, 0
        if win.chMenu then win.chMenu:Hide() end
        refresh()
    end
    cb.prev = button(cb, "<", 28, function()
        local r = ns.route(); local n = r and #(r.chapters or {}) or 0
        if n == 0 then return end
        pickChapter(((chap or 1) <= 1) and n or (chap - 1))
    end, "Previous chapter")
    cb.prev:SetPoint("LEFT", 0, 0)
    cb.next = button(cb, ">", 28, function()
        local r = ns.route(); local n = r and #(r.chapters or {}) or 0
        if n == 0 then return end
        pickChapter(((chap or 0) >= n) and 1 or ((chap or 0) + 1))
    end, "Next chapter")
    cb.next:SetPoint("RIGHT", 0, 0)
    cb.name = button(cb, "", LIST_W - 68, function()
        if win.chMenu:IsShown() then win.chMenu:Hide() else win.chMenu:Show(); win.chMenu.refresh() end
    end, "Pick the chapter the list shows")
    cb.name:SetPoint("LEFT", cb.prev, "RIGHT", 6, 0)
    cb.name.text:SetJustifyH("LEFT")
    win.cb = cb

    -- the chapter list (drops down over the step list)
    local MENU_ROWS = 16
    local menu = CreateFrame("Frame", nil, win)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", cb.name, "BOTTOMLEFT", 0, -2)
    menu:SetSize(LIST_W - 68, MENU_ROWS * ROW_H + 4)
    menu:EnableMouse(true)
    local mbg = menu:CreateTexture(nil, "BACKGROUND"); mbg:SetAllPoints(); mbg:SetColorTexture(0.05, 0.045, 0.04, 0.98)
    ui.addEdges(menu, ar, ag, ab, 0.5)
    menu.off, menu.rows = 0, {}
    for i = 1, MENU_ROWS do
        local b = CreateFrame("Button", nil, menu)
        b:SetSize(LIST_W - 72, ROW_H)
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:SetColorTexture(ar, ag, ab, 0.2); b.hl:Hide()
        b.txt = ui.text(b, 12, 1, 1, 1, 0.85); b.txt:SetPoint("LEFT", 8, 0); b.txt:SetPoint("RIGHT", -40, 0); b.txt:SetWordWrap(false)
        b.n = ui.text(b, 11, 1, 1, 1, 0.35); b.n:SetPoint("RIGHT", -6, 0)
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:SetShown(self.cur) end)
        b:SetScript("OnClick", function(self) pickChapter(self.ch) end)
        menu.rows[i] = b
    end
    menu.refresh = function()
        local r = ns.route()
        local chs = r and r.chapters or {}
        local entries = { { name = "All steps", ch = 0 } }
        for k, c in ipairs(chs) do
            local nxt = chs[k + 1]
            entries[#entries + 1] = { name = c.name, ch = k, count = (nxt and nxt.first or (#ns.steps() + 1)) - c.first }
        end
        menu.off = math.max(0, math.min(menu.off, #entries - MENU_ROWS))
        for i, b in ipairs(menu.rows) do
            local e = entries[menu.off + i]
            b:SetShown(e ~= nil)
            if e then
                b.ch, b.cur = e.ch, e.ch == chap
                b.txt:SetText(e.ch > 0 and (e.ch .. ".  " .. e.name) or e.name)
                b.n:SetText(e.count and tostring(e.count) or "")
                b.hl:SetShown(b.cur)
            end
        end
        menu:SetHeight(math.min(MENU_ROWS, #entries) * ROW_H + 4)
    end
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, d) menu.off = menu.off - d * 3; menu.refresh() end)
    menu:Hide()
    win.chMenu = menu

    -- search: the chapter's steps whose text has it, as a list under the box (as you type); a click on one takes
    -- the step list to that step and selects it - the list itself stays whole, to work around that step
    local search = editbox(win, LIST_W - 30, function() end)
    search:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -6)
    search:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        query = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        resultsOpen, resOff = query ~= "", 0
        refresh()
    end)
    search:SetScript("OnEditFocusGained", function(self)
        self.ph:Hide()
        if query ~= "" and not resultsOpen then resultsOpen = true; refresh() end
    end)
    search:SetScript("OnEditFocusLost", function() refresh() end)
    -- Enter: to the first match
    search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if win.results and win.results.found and win.results.found[1] then win.results.jump(win.results.found[1]) end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); resultsOpen = false; refresh() end)
    search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Search the chapter's steps by their text (quest steps: the quest's name). Click a match to go to that step in the list (Enter: the first one). All steps in the chapter list searches the whole route.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    search.ph = ui.text(search, 12, 1, 1, 1, 0.3); search.ph:SetPoint("LEFT", 8, 0)
    win.search = search
    local clearB = button(win, "×", 24, function() clearSearch(); search:ClearFocus(); refresh() end, "Clear the search")
    clearB:SetPoint("LEFT", search, "RIGHT", 6, 0)
    win.searchClear = clearB

    -- step list
    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    list:SetSize(LIST_W, ROWS * ROW_H)
    ui.addEdges(list, 1, 1, 1, 0.08)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, d)
        offset = math.max(0, math.min(math.max(0, #view - ROWS), offset - d * 3))
        refresh()
    end)
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LIST_W, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints(); row.hl:SetColorTexture(ar, ag, ab, 0.18); row.hl:Hide()
        row.cur = row:CreateTexture(nil, "ARTWORK"); row.cur:SetColorTexture(ar, ag, ab, 0.95)
        row.cur:SetPoint("TOPLEFT", 0, -2); row.cur:SetPoint("BOTTOMLEFT", 0, 2); row.cur:SetWidth(3); row.cur:Hide()
        row.num = ui.text(row, 11, 1, 1, 1, 0.35); row.num:SetPoint("LEFT", 4, 0); row.num:SetWidth(38); row.num:SetJustifyH("RIGHT")
        row.verb = ui.text(row, 10, ar, ag, ab, 0.8); row.verb:SetPoint("LEFT", row.num, "RIGHT", 6, 0); row.verb:SetWidth(58)
        row.verb:SetWordWrap(false)
        row.txt = ui.text(row, 12, 1, 1, 1, 0.85); row.txt:SetPoint("LEFT", row.verb, "RIGHT", 4, 0); row.txt:SetPoint("RIGHT", -4, 0)
        row.txt:SetWordWrap(false)
        row:SetScript("OnClick", function(self) sel = self.id; resultsOpen = false; refresh() end)
        rows[i] = row
    end
    win.list = list
    win.rows = rows -- (tests)

    -- the search's matches (drops down over the step list)
    local RES_ROWS = 10
    local res = CreateFrame("Frame", nil, win)
    res:SetFrameStrata("FULLSCREEN_DIALOG")
    res:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -2)
    res:SetSize(LIST_W, RES_ROWS * ROW_H + 24)
    res:EnableMouse(true)
    local rbg = res:CreateTexture(nil, "BACKGROUND"); rbg:SetAllPoints(); rbg:SetColorTexture(0.05, 0.045, 0.04, 0.98)
    ui.addEdges(res, ar, ag, ab, 0.5)
    res.rows = {}
    -- to that step in the list: select it, scroll so it's in view (a few steps above it showing)
    function res.jump(s)
        sel = sid(s)
        for k, x in ipairs(view) do
            if x == s then offset = math.max(0, k - 4) end
        end
        resultsOpen = false
        search:ClearFocus()
        refresh()
    end
    for i = 1, RES_ROWS do
        local b = CreateFrame("Button", nil, res)
        b:SetSize(LIST_W - 4, ROW_H)
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        b.hl = b:CreateTexture(nil, "BACKGROUND"); b.hl:SetAllPoints(); b.hl:SetColorTexture(ar, ag, ab, 0.2); b.hl:Hide()
        b.num = ui.text(b, 11, 1, 1, 1, 0.35); b.num:SetPoint("LEFT", 2, 0); b.num:SetWidth(38); b.num:SetJustifyH("RIGHT")
        b.verb = ui.text(b, 10, ar, ag, ab, 0.8); b.verb:SetPoint("LEFT", b.num, "RIGHT", 6, 0); b.verb:SetWidth(58); b.verb:SetWordWrap(false)
        b.txt = ui.text(b, 12, 1, 1, 1, 0.85); b.txt:SetPoint("LEFT", b.verb, "RIGHT", 4, 0); b.txt:SetPoint("RIGHT", -4, 0); b.txt:SetWordWrap(false)
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", function(self) if self.s then res.jump(self.s) end end)
        res.rows[i] = b
    end
    res.info = ui.text(res, 11, 1, 1, 1, 0.4); res.info:SetPoint("BOTTOMLEFT", 8, 5)
    res:EnableMouseWheel(true)
    res:SetScript("OnMouseWheel", function(_, d)
        resOff = math.max(0, math.min(math.max(0, #(res.found or {}) - RES_ROWS), resOff - d * 3))
        refresh()
    end)
    res:Hide()
    win.results = res
    win.listInfo = ui.text(win, 11, 1, 1, 1, 0.35)
    win.listInfo:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)

    -- details of the selected step
    local d = CreateFrame("Frame", nil, win)
    d:SetPoint("TOPLEFT", cb, "BOTTOMRIGHT", 16, -6)
    d:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 40)
    win.d = d
    -- three pages: the step itself, when it's for you (conditions), and the rest
    d.pages, d.tabs = {}, {}
    local PAGES = { "Step", "Conditions", "More" }
    for k, name in ipairs(PAGES) do
        local pg = CreateFrame("Frame", nil, d)
        pg:SetAllPoints(d)
        d.pages[k] = pg
        local b = ui.segment(d, name)
        b.text:SetFont(ui.fontPath(), 11, "")
        b:SetSize(96, 20)
        b:SetPoint("TOPRIGHT", d, "TOPRIGHT", -(#PAGES - k) * 98, 4)
        b:SetScript("OnClick", function() page = k; refresh() end)
        d.tabs[k] = b
    end
    d.tabs[2].tip = "When the step is for you: quests in your log, your level, where you are, items, professions, money, your weapon, level jumps, your Hearthstone, group quests. Empty: always."
    d.tabs[3].tip = "The trainer kind, when a travel step counts as done, dialogue, a macro button, bank items, and waypoints / kill-area spots."
    d.head = ui.text(d, 12, 1, 1, 1, 0.55); d.head:SetPoint("TOPLEFT", 0, 0); d.head:SetPoint("RIGHT", d.tabs[1], "LEFT", -8, 0)
    d.head:SetWordWrap(false)
    local P1, P2, P3 = d.pages[1], d.pages[2], d.pages[3]
    d.types = {}
    local PER_ROW = 7
    local tw = math.floor((W - LIST_W - PAD * 2 - 16) / PER_ROW)
    for k, t in ipairs(TYPES) do
        local b = ui.segment(P1, VERB[t])
        b.text:SetFont(ui.fontPath(), 11, "")
        b:SetSize(tw + 1, 22)
        b:SetPoint("TOPLEFT", d.head, "BOTTOMLEFT", ((k - 1) % PER_ROW) * tw, -8 - math.floor((k - 1) / PER_ROW) * 23)
        b.tip = TYPE_TIP[t]
        b:SetScript("OnClick", function()
            local s = selected()
            if not (s and kindOf(s) ~= t) then return end
            local was = kindOf(s)
            -- abandon and sell junk are to-do steps with a mark; the others drop those marks
            local set = { t = (t == "abandon" or t == "junk") and "do" or t, abandon = false, vendor = false }
            -- the quests go along between quest steps and abandon steps
            local QK = { accept = true, complete = true, turnin = true }
            if t == "abandon" then
                set.abandon = (s.q and #s.q > 0 and s.q) or s.abandon or {}
                set.q, set.n, set.qo, set.obj = false, false, false, false
            elseif QK[t] and was == "abandon" and s.abandon and #s.abandon > 0 then
                set.q = s.abandon
                local n = {}
                for k, q in ipairs(s.abandon) do n[k] = routeQuestName(q) or questName(q) end
                set.n = n
            end
            if t == "junk" then set.vendor = true end
            -- a new step's placeholder text becomes what the type needs: your home for a hearth, the place
            -- you stand for a flight path or a new home, "Abandon <quest>", "Sell junk"
            local blank = not s.name or s.name == "" or s.name == "New step" or s.name == "Sell junk"
                or (was == "abandon" and s.name:find("^Abandon "))
            if blank then
                if t == "hearth" then set.name = (GetBindLocation and GetBindLocation()) or false
                elseif t == "fp" or t == "sethearth" then
                    local sub = GetSubZoneText and GetSubZoneText() or ""
                    set.name = sub ~= "" and sub or ((GetZoneText and GetZoneText()) or false)
                elseif t == "junk" then set.name = "Sell junk"
                elseif t == "abandon" then
                    local nm = {}
                    for _, q in ipairs(set.abandon) do nm[#nm + 1] = routeQuestName(q) or questName(q) end
                    set.name = #nm > 0 and ("Abandon " .. table.concat(nm, ", ")) or "Abandon the quest"
                else set.name = false end
            end
            ns.editSet(sid(s), set)
            refresh()
        end)
        d.types[t] = b
    end
    local FW = W - LIST_W - PAD * 2 - 16
    local y = -87
    local fparent = P1 -- the page the next field goes on
    local function field(key, lbl, tip, get, set)
        local l = ui.text(fparent, 11, 1, 1, 1, 0.45); l:SetPoint("TOPLEFT", 0, y); l:SetText(lbl)
        -- (what you typed goes to the step the box shows - box.forId, set with its text - not to whatever step is
        -- selected when you leave the box)
        local e
        e = editbox(fparent, FW - 90, function(text)
            local s = selected()
            if e.forId and e.forId ~= sel then
                s = nil
                local r = ns.route()
                for _, x in ipairs(r and r.editList or {}) do if sid(x) == e.forId then s = x break end end
            end
            if s then set(s, text); refresh() end
        end)
        e:SetPoint("TOPLEFT", 90, y + 5)
        e:SetScript("OnEnter", function() GameTooltip:SetOwner(e, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fields[key] = { box = e, get = get, label = l }
        if key == "item" then itemBox = e; ITEM_BOXES[e] = {} end
        if key == "col" then colBox = e; ITEM_BOXES[e] = { count = " x1" } end
        if key == "need" then ITEM_BOXES[e] = { count = " x1", one = true } end
        if key == "buffItem" then ITEM_BOXES[e] = { one = true } end
        if key == "bankIn" or key == "bankOut" then ITEM_BOXES[e] = {} end
        y = y - 30
    end
    -- (a text of several lines shows its line breaks as \n in the one-line box, and \n typed there is one)
    local function toBox(t) return (t:gsub("\n", "\\n")) end
    local function fromBox(t) return (t:gsub("\\n", "\n")) end
    field("name", "Text", "What the step says (travel and to-do steps). Quest steps show the quest's name. Fly: where to. Flight path: the town. Hearth: your home inn. Home: the inn's place. Dungeon: its name. \\n starts a new line.",
        function(s) return toBox(s.name or "") end,
        function(s, t) t = fromBox(t); ns.editSet(sid(s), { name = t ~= "" and t or false }) end)
    field("note", "Hint", "A hint: a line under the step (\"Unequip your shirt so you can sell it\"). \\n starts a new line.",
        function(s) return toBox(s.note or "") end,
        function(s, t) t = fromBox(t); ns.editSet(sid(s), { note = t ~= "" and t or false }) end)
    field("q", "Quest IDs", "The quests of an accept / quest / turn in / abandon step, comma separated (the ID is in the quest's Wowhead link). For a Quest step, 12:2 means only objective 2 of quest 12 (12:1, 12:2 for both).",
        function(s)
            if kindOf(s) == "abandon" then return table.concat(s.abandon or {}, ", ") end
            local out = {}
            for k, q in ipairs(s.q or {}) do
                local o = s.t == "complete" and s.qo and s.qo[k] or 0
                out[#out + 1] = o > 0 and (q .. ":" .. o) or tostring(q)
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            local q, qo, anyObj = {}, {}, false
            for part in (t or ""):gmatch("[^,]+") do
                local id, o = part:match("^%s*(%d+)%s*:%s*(%d+)")
                id = tonumber(id or part:match("(%d+)"))
                if id then q[#q + 1] = id; qo[#q] = tonumber(o) or 0; if tonumber(o) then anyObj = true end end
            end
            local n = {}
            for k, id in ipairs(q) do n[k] = routeQuestName(id) or questName(id) end
            if kindOf(s) == "abandon" then
                local set = { abandon = q }
                if not s.name or s.name == "" or s.name:find("^Abandon ") then
                    set.name = #n > 0 and ("Abandon " .. table.concat(n, ", ")) or "Abandon the quest"
                end
                ns.editSet(sid(s), set)
            elseif #q > 0 then
                ns.editSet(sid(s), { q = q, n = s.t ~= "complete" and n or false, qo = (s.t == "complete" and anyObj) and qo or false, obj = false })
            else
                ns.editSet(sid(s), { q = false, n = false, qo = false, obj = false })
            end
        end)
    field("npc", "NPC", "Who to talk to (the target button targets them). \"Use target\" fills it in. Several, comma separated: the first is the one to talk to, the target button looks for all of them.",
        function(s)
            if s.targets and #s.targets > 1 then return table.concat(s.targets, ", ") end
            return s.npc or ""
        end,
        function(s, t)
            local list = names(t)
            ns.editSet(sid(s), { npc = list[1] or false, targets = #list > 0 and list or false })
        end)
    field("mobs", "Mobs", "Mobs for the target button, comma separated. \"Use target\" adds yours.",
        function(s) return s.mobs and table.concat(s.mobs, ", ") or "" end,
        function(s, t) local m = names(t); ns.editSet(sid(s), { mobs = #m > 0 and m or false }) end)
    field("item", "Items", "Items for the quest item buttons while this step is up, comma separated: Shift-click an item in your bags while this field is active, or type item IDs. Only usable items get a button.",
        function(s)
            local ids = s.item and (type(s.item) == "table" and s.item or { s.item }) or {}
            local out = {}
            for _, id in ipairs(ids) do
                local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
                out[#out + 1] = n and (id .. " " .. n) or tostring(id)
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            -- each entry's first number is the ID ("6948 Hearthstone"); item links count too
            local ids, seen = {}, {}
            for part in (t or ""):gmatch("[^,]+") do
                local id = tonumber(part:match("item:(%d+)") or part:match("^%s*(%d+)"))
                if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
            end
            ns.editSet(sid(s), { item = #ids > 0 and ids or false })
        end)
    field("col", "Collect", "Items to have in your bags, with how many: Shift-click an item while this field is active, then change x1 to the count (\"2886 Crag Boar Rib x6\"). A to-do step with this is done once you have them; with Along the way it shows the count while you go.",
        function(s)
            local out = {}
            for _, c in ipairs(s.col or {}) do
                local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(c[1])) or (GetItemInfo and GetItemInfo(c[1]))
                out[#out + 1] = c[1] .. (n and (" " .. n) or "") .. " x" .. (c[2] or 1)
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            -- each entry: the item (its first number, or a link) and "x<count>" (1 when left out)
            local col = {}
            for part in (t or ""):gmatch("[^,]+") do
                local id = tonumber(part:match("item:(%d+)") or part:match("^%s*(%d+)"))
                local n = tonumber(part:match("[xX]%s*(%d+)%s*$")) or 1
                if id then col[#col + 1] = { id, math.max(1, n) } end
            end
            ns.editSet(sid(s), { col = #col > 0 and col or false })
        end)
    field("lvl", "Level", "For an XP step: 5 = reach level 5. 3 1200xp = 1200 XP into level 3. 3 50% = halfway through level 3. 4 -300xp = 300 XP or less before level 4. For an Accept step: the level the quest needs (shown as NEEDS LEVEL until then).",
        function(s)
            if s.t == "accept" then return s.minlv and tostring(s.minlv) or "" end
            if not s.lvl then return "" end
            local level, xpIn, xpPct, xpLeft = ns.xpTarget(s)
            if xpIn then return string.format("%d %dxp", level, xpIn) end
            if xpPct then return string.format("%d %d%%", level, xpPct) end
            if xpLeft then return string.format("%d -%dxp", level, xpLeft) end
            return tostring(level)
        end,
        function(s, t)
            if s.t == "accept" then
                local n = tonumber((t or ""):match("%d+"))
                ns.editSet(sid(s), { minlv = n or false })
                return
            end
            -- the level, then (optional) an amount: "1200xp" (or a bare number) into the level, "50%" of it,
            -- "-300xp" before reaching it
            t = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local lv, rest = t:match("^(%d+)%s*(.*)$")
            local clear = { xpIn = false, xpPct = false, xpLeft = false, xpoff = false }
            if not lv then clear.lvl = false; ns.editSet(sid(s), clear); return end
            clear.lvl = tonumber(lv)
            rest = rest:gsub("%s", "")
            local pct = rest:match("^(%d+)%%$")
            local left = rest:match("^%-(%d+)x?p?$")
            local into = rest:match("^%+?(%d+)x?p?$")
            if pct then clear.xpPct = math.min(99, tonumber(pct))
            elseif left then clear.xpLeft = tonumber(left)
            elseif into then clear.xpIn = tonumber(into) end
            ns.editSet(sid(s), clear)
        end)
    field("till", "Ends at step", "For an Along the way step: the step number where it stops showing (it's gone once you reach that step). Empty: until it's done, the chapter ends, or a later step completes or turns in its quest.",
        function(s)
            if not s.along or not s.till then return "" end
            return tostring(s.till + 1)
        end,
        function(s, t)
            local n = tonumber((t or ""):match("%d+"))
            local steps = ns.steps()
            local me = stepNumber(s)
            if not n then ns.editSet(sid(s), { till = false, tillKey = false }) return end
            n = math.min(n, #steps)
            if me and n <= me then n = me + 1 end
            local target = steps[n]
            if target then ns.editSet(sid(s), { till = false, tillKey = sid(target) }) end
        end)
    field("chapter", "New chapter", "Starts a chapter at this step (shown in the chapter list).",
        function(s) return s.chapter or "" end,
        function(s, t) ns.editSet(sid(s), { chapter = t ~= "" and t or false }) end)

    d.posText = ui.text(P1, 11, 1, 1, 1, 0.55); d.posText:SetPoint("TOPLEFT", 0, y); d.posText:SetPoint("RIGHT", 0, 0)
    y = y - 22
    local bw = math.floor((FW - 12) / 3)
    local function act(txt, col, row, fn, tip)
        local b = button(P1, txt, bw, fn, tip)
        b:SetPoint("TOPLEFT", (col - 1) * (bw + 6), y - (row - 1) * 28)
        return b
    end
    d.setPos = act("My position", 1, 1, function()
        local s, p = selected(), here()
        if s and p then ns.editSet(sid(s), { m = p.m, x = p.x, y = p.y, z = p.z or false, wx = false, wy = false, path = false, way = false, wp = false, area = false }); refresh() end
    end, "Moves the step's point to where you stand.")
    d.useTarget = act("Use target", 2, 1, function()
        local s = selected()
        local n = ns.unitName("target")
        if not (s and n) then return end
        if s.t == "complete" or UnitCanAttack("player", "target") then
            local m = s.mobs and copy(s.mobs) or {}
            local have = false
            for _, x in ipairs(m) do if x == n then have = true end end
            if not have then m[#m + 1] = n end
            ns.editSet(sid(s), { mobs = m })
        else
            ns.editSet(sid(s), { npc = n, targets = { n } })
        end
        refresh()
    end, "Your target becomes the step's NPC, or one of its mobs if it's an enemy.")
    d.insert = act("Insert after", 3, 1, function()
        local s = selected()
        local p = here() or {}
        sel = ns.editAdd({ t = "do", name = "New step", m = p.m, x = p.x, y = p.y, z = p.z }, s and sid(s) or "^")
        showSelected(); refresh()
    end, "Adds a new step after this one (at your position; change it on the right).")
    d.hide = act("Hide", 1, 2, function()
        local s = selected()
        if not s then return end
        if s.edAdd then ns.editDelete(sid(s)); sel = nil else ns.editHide(sid(s), not s.edHidden) end
        refresh()
    end, "Hides a step of the route (shown dimmed here, Show brings it back), or deletes a step you added.")
    d.up = act("Move up", 2, 2, function() local s = selected(); if s then ns.editMove(sid(s), -1); showSelected(); refresh() end end, "Steps you added can be moved.")
    d.down = act("Move down", 3, 2, function() local s = selected(); if s then ns.editMove(sid(s), 1); showSelected(); refresh() end end, "Steps you added can be moved.")
    d.revert = act("Undo changes", 1, 3, function() local s = selected(); if s then ns.editRevert(sid(s)); refresh() end end,
        "Back to how the route has this step.")
    d.along = act("Along the way", 3, 3, function()
        local s = selected()
        if not s then return end
        ns.editSet(sid(s), { along = not s.along, till = false, tillKey = false })
        refresh()
    end, "Runs this step alongside the ones after it, from its place in the route until it's done (or the chapter ends). A Complete step with a quest: its objectives with live counts (\"Rockjaw Trogg slain 3/10\"); when a later step completes or turns in that quest, that step takes over from there. A To-do step with Collect: the items in your bags (\"Crag Boar Rib 2/6\"). A To-do step with only text: an instruction.")
    d.gotoBtn = act("Go to step", 2, 3, function()
        local s = selected()
        local n = s and stepNumber(s)
        if n and ns.setStep then ns.setStep(n) end
        refresh()
    end, "Makes this the step you're on.")
    -- auction house steps (Settings > Route > Auction house steps): left out when you play self-found;
    -- a self-found step is the other way round (only then)
    d.market = act("For everyone", 1, 4, function()
        local s = selected()
        if not s then return end
        if s.ah then ns.editSet(sid(s), { ah = false, ssf = true })
        elseif s.ssf then ns.editSet(sid(s), { ah = false, ssf = false })
        else ns.editSet(sid(s), { ah = true, ssf = false }) end
        refresh()
    end, "Who gets this step (click to switch). For everyone. Auction house: left out when Settings > Route > Auction house steps is on Skip (self-found play). Self-found only: shown only then, e.g. buying a vendor item instead of the auction house one.")
    d.opt = act("Optional", 2, 4, function()
        local s = selected()
        if not s then return end
        ns.editSet(sid(s), { opt = (not s.opt) and true or false })
        refresh()
    end, "An optional step: shown as OPTIONAL, and passed by itself once you're done with a later quest step (you went on without it).")
    d.death = act("Death skip", 3, 4, function()
        local s = selected()
        if not s then return end
        if s.death then
            ns.editSet(sid(s), { death = false, deathRec = false, along = false })
        else
            local blank = not s.name or s.name == "" or s.name == "New step"
            ns.editSet(sid(s), { t = "go", death = true, name = blank and "Die and respawn at the spirit healer" or nil })
        end
        refresh()
    end, "Die and respawn at the spirit healer: an instruction next to the steps after it (always over the arrow), done once you're alive again. With a point, the arrow leads there first (the place to die).")

    ---------------------------------------------------------------- page 2: when the step is for you
    local intro2 = ui.text(P2, 11, 1, 1, 1, 0.45)
    intro2:SetPoint("TOPLEFT", 0, -30); intro2:SetPoint("RIGHT", 0, 0); intro2:SetWordWrap(true)
    intro2:SetText("The step is only for you while all of these hold (empty: always). It's left out otherwise. Hover a field for how to write it.")
    fparent, y = P2, -66
    local COND_WORD = { has = "on", nothas = "not on", ready = "ready", notready = "not ready", done = "done", open = "not done" }
    local function trim(x) return (tostring(x or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    local cdText, cdParse
    -- a cooldown condition { kind, id, seconds } as text: "ready", "ready in 5m" (the Hearthstone; another item
    -- or a spell goes first: "spell 1259686 ready")
    function cdText(c, lead)
        local who = (c[1] == "item" and c[2] == 6948) and "" or (c[1] .. " " .. c[2] .. " ")
        local secs = c[3] or 2
        if secs <= 2 then return who .. "ready" end
        local d = (secs % 60 == 0) and ((secs / 60) .. "m") or (secs .. "s")
        return who .. lead .. d
    end
    -- and back: "ready", "ready in 5m", "<25m", "90s", "spell 1259686 ready" (a number alone: minutes)
    function cdParse(t)
        local low = trim(t):lower()
        if low == "" then return nil end
        local kind, id = "item", 6948
        local k2, n2 = low:match("^(%a+)%s+(%d+)")
        if (k2 == "item" or k2 == "spell") and n2 then kind, id, low = k2, tonumber(n2), low:gsub("^%a+%s+%d+", "") end
        low = low:gsub("hearthstone", ""):gsub("hearth", "")
        local v, unit = low:match("(%d+%.?%d*)%s*([ms]?)")
        local secs = 2
        if v then secs = tonumber(v) * ((unit == "s") and 1 or 60) end
        secs = math.max(2, math.floor(secs + 0.5))
        return { kind, id, secs }
    end
    local function itemName(id)
        return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or nil
    end
    local function coinText(c)
        local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
        local out = {}
        if g > 0 then out[#out + 1] = g .. "g" end
        if sv > 0 then out[#out + 1] = sv .. "s" end
        if cp > 0 or #out == 0 then out[#out + 1] = cp .. "c" end
        return table.concat(out, " ")
    end
    local function coinValue(t)
        t = t:lower()
        local g, sv, cp = tonumber(t:match("(%d+)%s*g")), tonumber(t:match("(%d+)%s*s")), tonumber(t:match("(%d+)%s*c"))
        if not (g or sv or cp) then return tonumber(t:match("(%d+)")) end
        return (g or 0) * 10000 + (sv or 0) * 100 + (cp or 0)
    end
    local function profKey(name)
        name = trim(name):lower()
        if name == "" then return nil end
        for k, p in pairs(ns.PROF or {}) do
            if k == name or (p.name and p.name:lower() == name) then return k end
        end
        return (name:gsub("%s+", ""))
    end
    local function profLabel(k) return (ns.PROF and ns.PROF[k] and ns.PROF[k].name) or k end
    field("cond", "Quests", "Quests in your log, comma separated: on 123 (in your log), not on 123, ready 123 (finished, not handed in), not ready 123, done 123 (handed in), not done 123. The ID is in the quest's Wowhead link.",
        function(s)
            local out = {}
            for _, c in ipairs(s.cond or {}) do if COND_WORD[c[1]] then out[#out + 1] = COND_WORD[c[1]] .. " " .. tostring(c[2]) end end
            return table.concat(out, ", ")
        end,
        function(s, t)
            local list = {}
            for part in (t or ""):lower():gmatch("[^,]+") do
                local x = trim(part)
                local neg = x:find("^not%s+") ~= nil
                x = x:gsub("^not%s+", "")
                local w, id = x:match("^(%a+)%s*(%d+)$")
                id = tonumber(id)
                local kind = id and ((w == "on" and (neg and "nothas" or "has")) or (w == "ready" and (neg and "notready" or "ready"))
                    or (w == "done" and (neg and "open" or "done")))
                if kind then list[#list + 1] = { kind, id } end
            end
            ns.editSet(sid(s), { cond = #list > 0 and list or false })
        end)
    field("lvskip", "Level", "Your level: 20+ (from 20 on), <20 (below 20), 10-19 (from 10 to 19).",
        function(s)
            local l = s.lvskip
            if not l then return "" end
            if l.below and l.atleast then return l.below .. "-" .. (l.atleast - 1) end
            if l.below then return l.below .. "+" end
            if l.atleast then return "<" .. l.atleast end
            return ""
        end,
        function(s, t)
            t = (t or ""):gsub("%s", "")
            local a, b = t:match("^(%d+)%-(%d+)$")
            local v
            if a then v = { below = tonumber(a), atleast = tonumber(b) + 1 }
            elseif t:match("^%d+%+$") then v = { below = tonumber(t:match("^(%d+)")) }
            elseif t:match("^<%d+$") then v = { atleast = tonumber(t:match("^<(%d+)$")) } end
            ns.editSet(sid(s), { lvskip = v or false })
        end)
    field("zskip", "Zone", "Where you are, comma separated: in Darkshore (only there), not in Stormwind City (not there). A subzone by its area ID: in area 150.",
        function(s)
            local out = {}
            for _, z in ipairs(s.zskip or {}) do
                out[#out + 1] = (z.inv and "in " or "not in ") .. (z.sub and ("area " .. z.sub) or tostring(z.zone))
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            local list = {}
            for part in (t or ""):gmatch("[^,]+") do
                local x = trim(part)
                local low = x:lower()
                local neg = low:find("^not%s+in%s+") ~= nil
                local rest = neg and x:gsub("^%a+%s+%a+%s+", "") or (low:find("^in%s+") and x:gsub("^%a+%s+", "")) or nil
                if rest then
                    rest = trim(rest)
                    local area = tonumber(rest:lower():match("^area%s+(%d+)$"))
                    if area then list[#list + 1] = { sub = area, inv = not neg }
                    elseif rest ~= "" then list[#list + 1] = { zone = rest, inv = not neg } end
                end
            end
            ns.editSet(sid(s), { zskip = #list > 0 and list or false })
        end)
    field("need", "Item", "Only while you have an item: 5000 x3 (at least 3 of it), or <5000 x3 (fewer than 3). Shift-click an item while this field is active.",
        function(s)
            local n = s.need
            if not n then return "" end
            local nm = itemName(n[1])
            return (n[3] == "lt" and "<" or "") .. n[1] .. (nm and (" " .. nm) or "") .. " x" .. (n[2] or 1)
        end,
        function(s, t)
            t = t or ""
            local lt = t:find("^%s*<") ~= nil
            local id = tonumber(t:match("item:(%d+)") or t:match("(%d+)"))
            local c = tonumber(t:match("[xX]%s*(%d+)%s*$")) or 1
            ns.editSet(sid(s), { need = id and (lt and { id, c, "lt" } or { id, c }) or false })
        end)
    field("buffItem", "Until buff", "Something you eat or use for its buff (Herb Baked Egg): the step shows while the buff is missing. The item's ID, or Shift-click it.",
        function(s)
            if not s.buffItem then return "" end
            local nm = itemName(s.buffItem)
            return s.buffItem .. (nm and (" " .. nm) or "")
        end,
        function(s, t)
            local id = tonumber((t or ""):match("item:(%d+)") or (t or ""):match("(%d+)"))
            ns.editSet(sid(s), { buffItem = id or false })
        end)
    field("prof", "Profession", "A profession: mining (you know it), cooking 50+ (skill 50 or more), cooking <50 (below 50, or not learned), cooking 10-49.",
        function(s)
            local sk, sk2 = s.skill, s.skill2
            if sk and sk2 and sk[1] == sk2[1] and sk[3] ~= "lt" and sk2[3] == "lt" then
                return profLabel(sk[1]):lower() .. " " .. sk[2] .. "-" .. (sk2[2] - 1)
            end
            local out = {}
            if s.needProf then out[#out + 1] = profLabel(s.needProf):lower() end
            for _, x in ipairs({ sk, sk2 }) do
                if x then out[#out + 1] = profLabel(x[1]):lower() .. " " .. (x[3] == "lt" and ("<" .. x[2]) or (x[2] .. "+")) end
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            t = trim(t)
            local name = t:gsub("[%d%+%-<]", ""):gsub("%s+$", "")
            local k = profKey(name)
            local set = { needProf = false, skill = false, skill2 = false }
            if k then
                local a, b = t:match("(%d+)%s*%-%s*(%d+)")
                if a then set.skill, set.skill2 = { k, tonumber(a) }, { k, tonumber(b) + 1, "lt" }
                elseif t:match("<%s*%d+") then set.skill = { k, tonumber(t:match("<%s*(%d+)")), "lt" }
                elseif t:match("%d+") then set.skill = { k, tonumber(t:match("(%d+)")) }
                else set.needProf = k end
            end
            ns.editSet(sid(s), set)
        end)
    field("money", "Money", "Your money: 1g 50s+ (at least that much), <50s (less than that).",
        function(s)
            local m = s.money
            if not m then return "" end
            if m[1] == "<" then return coinText(m[2]) .. "+" end
            return "<" .. coinText(m[2])
        end,
        function(s, t)
            t = trim(t)
            local c = t ~= "" and coinValue(t) or nil
            -- (as the guides have it: "<" = skipped while you have less, ">" = skipped once you have that much)
            ns.editSet(sid(s), { money = c and (t:find("^<") and { ">", c } or { "<", c }) or false })
        end)
    field("dps", "Weapon", "Only while your weapon is weaker: <10.5 (main hand DPS below 10.5); ranged <8, off hand <6 for the other slots.",
        function(s)
            local d0 = s.dps
            if not d0 then return "" end
            return (d0[1] == 18 and "ranged " or d0[1] == 17 and "off hand " or "") .. "<" .. d0[2]
        end,
        function(s, t)
            local low = (t or ""):lower()
            local v = tonumber(low:match("(%d+%.?%d*)"))
            local slot = low:find("ranged") and 18 or low:find("off") and 17 or 16
            ns.editSet(sid(s), { dps = v and { slot, v } or false })
        end)
    field("gate", "Level jump", "A section to leave out above a level: 14 Westfall end. The steps with the same name form the section; get to its first step above level 14 and the whole section is skipped (decided once).",
        function(s) return s.gateL and ((s.gateMax or "?") .. " " .. s.gateL) or "" end,
        function(s, t)
            local n, label = (t or ""):match("^%s*(%d+)%s+(.-)%s*$")
            if n and label ~= "" then ns.editSet(sid(s), { gateMax = tonumber(n), gateL = label })
            else ns.editSet(sid(s), { gateMax = false, gateL = false }) end
        end)
    field("cdSkip", "Hearthstone", "Only while your Hearthstone is ready: ready (a hearth step: passed while it's on cooldown), or ready in 5m (5 minutes or less left; m minutes, s seconds). A step that waits for it: Done in, on More.",
        function(s) return s.cdSkip and cdText(s.cdSkip, "ready in ") or "" end,
        function(s, t) ns.editSet(sid(s), { cdSkip = cdParse(t) or false }) end)
    field("bind", "Hearth set to", "Where your Hearthstone is set: Stormwind City (only while it's set there), not Stormwind City (only while it isn't) - the place as the game names your home. A place by its area ID: area 1519.",
        function(s)
            local v = s.bindAt or s.bindNot
            if not v then return "" end
            local name = type(v) == "number" and (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(v)) or nil
            local txt = type(v) == "number" and (name or ("area " .. v)) or tostring(v)
            return (s.bindNot and "not " or "") .. txt
        end,
        function(s, t)
            t = trim(t)
            local neg = t:lower():match("^not%s+") ~= nil
            if neg then t = trim(t:gsub("^[Nn][Oo][Tt]%s+", "")) end
            local v = tonumber(t:lower():match("^area%s+(%d+)$") or t:match("^(%d+)$")) or (t ~= "" and t or nil)
            ns.editSet(sid(s), { bindAt = (v and not neg) and v or false, bindNot = (v and neg) and v or false })
        end)
    field("grp", "Group", "group: a group quest - only with Settings > Route > Group quests on. solo: the guide's version for playing alone - only with it off. Empty: always.",
        function(s) return s.grp and "group" or (s.solo and "solo" or "") end,
        function(s, t)
            local low = (t or ""):lower()
            local solo = low:find("solo") ~= nil
            local grp = not solo and low:find("group") ~= nil
            ns.editSet(sid(s), { grp = grp or false, solo = solo or false })
        end)

    ---------------------------------------------------------------- page 3: the rest
    fparent, y = P3, -40
    field("trainer", "Trainer", "For a Train step: class (your class trainer; done when nothing new is waiting), weapons 202, 196 (a weapon master; done when you know them - the skills' spell IDs), any of 202, 196 (one of them is enough). Empty: another trainer (a profession, riding).",
        function(s)
            if s.cls then return "class" end
            if s.wpn then return (s.wany and "any of " or "weapons ") .. table.concat(s.wpn, ", ") end
            return ""
        end,
        function(s, t)
            local low = (t or ""):lower()
            local ids = numbers(low)
            if low:find("class") then ns.editSet(sid(s), { cls = true, wpn = false, wany = false })
            elseif #ids > 0 then ns.editSet(sid(s), { cls = false, wpn = ids, wany = low:find("any") and true or false })
            else ns.editSet(sid(s), { cls = false, wpn = false, wany = false }) end
        end)
    field("arrive", "Done in", "When a Go or Do step counts as done: a zone (Redridge Mountains - once you're in it), a subzone by its area ID (area 150), how close to its point counts as there (20 yd; 15 when not set), or your Hearthstone: hearthstone ready, hearthstone <25m (\"grind until your Hearthstone is ready\"). Comma separated for more than one.",
        function(s)
            local out = {}
            if s.zone then out[#out + 1] = s.zone end
            if s.sub then out[#out + 1] = "area " .. s.sub end
            if s.r then out[#out + 1] = s.r .. " yd" end
            if s.cdDone then
                local c = s.cdDone
                local who = (c[1] == "item" and c[2] == 6948) and "hearthstone " or (c[1] .. " " .. c[2] .. " ")
                out[#out + 1] = (c[3] or 2) <= 2 and (who .. "ready") or (who .. "<" .. cdText(c, ""):match("(%d+[ms])$"))
            end
            return table.concat(out, ", ")
        end,
        function(s, t)
            local set = { zone = false, sub = false, r = false, cdDone = false }
            for part in (t or ""):gmatch("[^,]+") do
                local x = trim(part)
                local low = x:lower()
                if low:find("hearth") or low:match("^item%s+%d+") or low:match("^spell%s+%d+") then set.cdDone = cdParse(low) or false
                elseif low:match("^%d+%s*y") or low:match("^%d+$") then set.r = tonumber(low:match("(%d+)"))
                elseif low:match("^area%s+%d+$") then set.sub = tonumber(low:match("(%d+)"))
                elseif x ~= "" then set.zone = x end
            end
            ns.editSet(sid(s), set)
        end)
    field("gossip", "Dialogue", "What to say to the step's NPC (Settings > Quests > Quest dialogue): talk (when there's just the one option), or the options' IDs, comma separated.",
        function(s)
            if s.gossip == true then return "talk" end
            if type(s.gossip) == "table" then return table.concat(s.gossip, ", ") end
            return ""
        end,
        function(s, t)
            local low = (t or ""):lower()
            local ids = numbers(low)
            ns.editSet(sid(s), { gossip = (low:find("talk") and true) or (#ids > 0 and ids) or false })
        end)
    field("macro", "Macro", "A button next to the panel that runs a macro while this step is up: /sit, /emote salutes the flag. Several lines separated by ;",
        function(s) return s.macro and tostring(s.macro[3] or ""):gsub("\n", "; ") or "" end,
        function(s, t)
            local text = trim((t or ""):gsub("%s*;%s*", "\n"))
            if text == "" then ns.editSet(sid(s), { macro = false }) return end
            local first = text:match("^[^\n]+")
            ns.editSet(sid(s), { macro = { first, (s.macro and s.macro[2]) or 134400, text } })
        end)
    -- a bank step: a Do step whose items go into the bank / come out of it when you open it there
    local function itemList(ids)
        local out = {}
        for _, id in ipairs(ids or {}) do
            local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
            out[#out + 1] = n and (id .. " " .. n) or tostring(id)
        end
        return table.concat(out, ", ")
    end
    local function bankSet(s, key, t)
        local ids, seen = {}, {}
        for part in (t or ""):gmatch("[^,]+") do
            local id = tonumber(part:match("item:(%d+)") or part:match("^%s*(%d+)"))
            if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
        local set = { [key] = #ids > 0 and ids or false }
        -- a new step's text says what to do: "Withdraw [Musquash Root] from your bank, then deposit [Turtle Meat]"
        local auto = not s.name or s.name == "" or s.name == "New step" or s.name:find("^Deposit ") or s.name:find("^Withdraw ")
        if auto then
            local function list(x)
                local nm = {}
                for _, id in ipairs(x or {}) do
                    local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
                    nm[#nm + 1] = "[" .. (n or ("item " .. id)) .. "]"
                end
                return #nm > 0 and table.concat(nm, ", ") or nil
            end
            local inL = list(key == "bankIn" and ids or s.bankIn)
            local outL = list(key == "bankOut" and ids or s.bankOut)
            if outL and inL then set.name = "Withdraw " .. outL .. " from your bank, then deposit " .. inL
            elseif outL then set.name = "Withdraw " .. outL .. " from your bank"
            elseif inL then set.name = "Deposit " .. inL .. " into your bank"
            elseif s.name and s.name ~= "New step" then set.name = false end
        end
        ns.editSet(sid(s), set)
    end
    field("bankIn", "Deposit", "A bank step (a Do step at the banker): items to put into your bank - Shift-click them in your bags while this field is active, or type item IDs. Opening the bank on this step puts them in (Settings > Quests > Bank steps); the step is done once none of them is in your bags.",
        function(s) return itemList(s.bankIn) end,
        function(s, t) bankSet(s, "bankIn", t) end)
    field("bankOut", "Withdraw", "A bank step: items to take out of your bank - Shift-click them in the open bank while this field is active, or type item IDs. Opening the bank on this step takes them out; the step is done once the bank has none of them left (also the ones you never had).",
        function(s) return itemList(s.bankOut) end,
        function(s, t) bankSet(s, "bankOut", t) end)
    ---------------------------------------------------------------- waypoints and kill-area spots
    -- The step's point, the waypoints on the way to it and its kill-area spots, as an editable list here and as
    -- pins on the world map (Pins.lua: drag to move, right-click to remove, "Add on map" to click new ones in).
    local HBDl = LibStub and LibStub("HereBeDragons-2.0", true)
    local function mapName(m)
        local info = m and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        return info and info.name or nil
    end
    -- a route point { map, x, y, world?, radius } in zone coordinates (the guides keep some as world positions)
    local function toZone(p)
        if p[4] == 1 then
            local x, yy = nil, nil
            if HBDl then x, yy = HBDl:GetZoneCoordinatesFromWorld(p[2], p[3], p[1], true) end
            if not (x and yy) then return nil end
            return { m = p[1], x = math.floor(x * 10000 + 0.5) / 100, y = math.floor(yy * 10000 + 0.5) / 100, r = p[5] }
        end
        return { m = p[1], x = p[2], y = p[3], r = p[5] }
    end
    -- zones by name, for typing one in: every map HereBeDragons knows, else the world map's tree. Zones and cities
    -- (map type 3) and dungeons (4); not continents, caves or buildings.
    local zoneIndex
    local function zones()
        if zoneIndex then return zoneIndex end
        local idx, seen, n = {}, {}, 0
        local function add(id)
            if not id or seen[id] then return end
            seen[id] = true
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
            if type(info) == "table" and type(info.name) == "string" and info.name ~= "" and (info.mapType == 3 or info.mapType == 4) then
                local k = info.name:lower()
                idx[k] = idx[k] or {}
                table.insert(idx[k], { id = id, type = info.mapType, name = info.name })
                n = n + 1
            end
        end
        if HBDl and HBDl.GetAllMapIDs then for _, id in ipairs(HBDl:GetAllMapIDs() or {}) do add(id) end end
        local kids = C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, nil, true)
        if type(kids) == "table" then for _, info in ipairs(kids) do add(type(info) == "table" and info.mapID) end end
        for _, l in pairs(idx) do
            table.sort(l, function(a, b) if a.type ~= b.type then return a.type < b.type end return a.id < b.id end)
        end
        if n > 0 then zoneIndex = idx end
        return idx
    end
    -- a zone from what you typed: its name (any case; the start or a part of it when only one zone fits),
    -- or its map ID (1436, #1436, map 1436). Not found: nil and the names that fit
    local function findZone(text)
        local t = trim(text)
        if t == "" then return nil end
        local n = tonumber(t:match("^#?(%d+)$") or t:lower():match("^map%s*#?(%d+)$"))
        if n then return mapName(n) and n or nil end
        local low, idx = t:lower(), zones()
        if idx[low] then return idx[low][1].id end
        local hits = {}
        for k in pairs(idx) do if k:sub(1, #low) == low then hits[#hits + 1] = k end end
        if #hits == 0 then for k in pairs(idx) do if k:find(low, 1, true) then hits[#hits + 1] = k end end end
        if #hits == 1 then return idx[hits[1]][1].id end
        table.sort(hits)
        for i, k in ipairs(hits) do hits[i] = idx[k][1].name end
        return nil, hits
    end
    ns.editorFindZone = findZone
    local function noZone(t, hits)
        if hits and #hits > 0 then
            ns.print("which zone? " .. table.concat(hits, ", ", 1, math.min(6, #hits)) .. (#hits > 6 and ", ..." or ""))
        else
            ns.print("no zone called \"" .. t .. "\" (a zone's name, or its map ID: map 1436)")
        end
    end
    -- the zone you're in (a cave or building: the zone around it), for a new point typed in without a zone
    local function playerZone()
        local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local guard = 0
        while id and guard < 10 do
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
            if type(info) ~= "table" then break end
            if info.mapType == 3 or info.mapType == 4 then return id end
            if info.mapType and info.mapType < 3 then break end
            id, guard = info.parentMapID, guard + 1
        end
        return nil
    end
    -- what you typed into a coordinates box: "45.2, 61.8", with a zone before or after it if you like
    -- ("Westfall 56.3, 47.5", "56.3 47.5 Westfall", "/way Westfall 56.3 47.5 Sentinel Hill", "/way #1436 56 47").
    -- Returns x, y, the zone's map (nil: none typed), and when a typed zone isn't found: its text and the names that fit
    local function parseSpot(text)
        local t = tostring(text or ""):gsub("^%s*/way%s*", "")
        local m = tonumber(t:match("#(%d+)"))
        if m then t = t:gsub("#%d+", " ") end
        local before, x, yy, after = t:match("^(.-)(%d+%.?%d*)%s*[,%s]%s*(%d+%.?%d*)(.*)$")
        x, yy = tonumber(x), tonumber(yy)
        if not (x and yy) or x > 100 or yy > 100 then return nil end
        local function clean(s) return trim((s or ""):gsub("^[%s,;:%-]+", ""):gsub("[%s,;:%-]+$", "")) end
        -- (a zone before the numbers, else after them: TomTom puts a description after)
        local zt = clean(before)
        if zt == "" then zt = clean(after) end
        if not m and zt ~= "" then
            local hits
            m, hits = findZone(zt)
            if not m then return x, yy, nil, zt, hits end
        end
        return x, yy, m
    end
    ns.editorParseSpot = parseSpot
    -- { point, way = the waypoints before the point, area = the kill-area spots }
    local function geometry(s)
        local g = { way = {}, area = {} }
        if s.m and s.x then g.point = { m = s.m, x = s.x, y = s.y }
        elseif s.m and s.wx then g.point = toZone({ s.m, s.wx, s.wy, 1 }) end
        for _, p in ipairs(s.path or {}) do local z = toZone(p); if z then g.way[#g.way + 1] = z end end
        -- (a way ends at the step's point)
        if #g.way > 0 then local last = table.remove(g.way); if not g.point then g.point = last end end
        for _, p in ipairs(s.wp or {}) do local z = toZone(p); if z then g.area[#g.area + 1] = z end end
        return g
    end
    ns.editorGeometry = geometry
    local function writeGeometry(s, g)
        local set = { way = false, area = false }
        local p = g.point
        if p then set.m, set.x, set.y, set.z, set.wx, set.wy = p.m, p.x, p.y, mapName(p.m) or false, false, false end
        if #g.way > 0 then
            local path = {}
            for _, w in ipairs(g.way) do path[#path + 1] = { w.m, w.x, w.y, 0, w.r or 15 } end
            if p then path[#path + 1] = { p.m, p.x, p.y, 0, s.r or 0 } end
            set.path = path
        else
            set.path = false
        end
        if #g.area > 0 then
            local wp = {}
            for _, a in ipairs(g.area) do wp[#wp + 1] = { a.m, a.x, a.y, 0 } end
            set.wp = wp
        else
            set.wp = false
        end
        ns.editSet(sid(s), set)
    end
    local listMode, wOff = "way", 0 -- which list shows (waypoints or kill area), scrolled by
    local function curList(g) return listMode == "area" and g.area or g.way end
    -- change one entry (k: its number in the list, or "point") and save the step's geometry
    local function editGeo(k, fn)
        local s = selected()
        if not s then return end
        local g = geometry(s)
        local list = curList(g)
        if fn(g, list, k == "point" and g.point or list[k]) == false then return end
        writeGeometry(s, g)
        refresh()
    end

    y = y - 4
    d.modeWay = button(P3, "Waypoints", 130, function() listMode, wOff = "way", 0
        if ns.editorMapIsPlacing and ns.editorMapIsPlacing() then ns.editorMapPlacing("way") end
        refresh() end, "The points the arrow leads through, in this order, on the way to the step's point (P).")
    d.modeWay:SetPoint("TOPLEFT", 0, y)
    d.modeArea = button(P3, "Kill area", 130, function() listMode, wOff = "area", 0
        if ns.editorMapIsPlacing and ns.editorMapIsPlacing() then ns.editorMapPlacing("area") end
        refresh() end, "The spots of the area where the step's mobs are. From two spots on, the arrow goes from one to the next.")
    d.modeArea:SetPoint("LEFT", d.modeWay, "RIGHT", 6, 0)
    d.showMap = button(P3, "Show on map", 110, function()
        local s = selected()
        local g = s and geometry(s)
        local p = g and (g.point or g.way[1] or g.area[1])
        if p and ns.showOnMap then ns.showOnMap(p.m) else ns.print("this step has no point yet") end
    end, "Opens the world map at the step. There you see its point (P), its waypoints and kill area: drag a pin to move it, right-click a waypoint or spot to remove it.")
    d.showMap:SetPoint("TOPRIGHT", P3, "TOPRIGHT", 0, y)
    y = y - 30
    local WROWS = 6
    local listFrame = CreateFrame("Frame", nil, P3)
    listFrame:SetPoint("TOPLEFT", 0, y); listFrame:SetSize(FW, WROWS * 26)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta) wOff = math.max(0, wOff - delta); refresh() end)
    d.wrows = {}
    local function row(i, isPoint)
        local r = CreateFrame("Frame", nil, isPoint and P3 or listFrame)
        r:SetSize(FW, 24)
        r.n = ui.text(r, 11, 1, 1, 1, 0.5); r.n:SetPoint("LEFT", 0, 0); r.n:SetWidth(22)
        local key = function() return isPoint and "point" or (wOff + i) end
        r.coord = editbox(r, 96, function(text)
            local x, yy, m, bad, hits = parseSpot(text)
            if not x then refresh() return end
            if bad then noZone(bad, hits); refresh() return end
            editGeo(key(), function(g, _, p)
                if not p and isPoint then
                    -- (a step without a point: this is it, in the zone typed with it or the one you're in)
                    m = m or playerZone()
                    if not m then return false end
                    g.point = { m = m, x = x, y = yy }
                    return
                end
                if not p then return false end
                p.x, p.y = x, yy
                if m then p.m = m end
            end)
            refresh()
        end)
        r.coord:SetPoint("LEFT", 24, 0)
        r.coord:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("x, y on the zone's map (as /way or a map addon shows them). A zone may come with it: Westfall 56.3, 47.5 - or paste a /way line.", 1, 1, 1, true); GameTooltip:Show() end)
        r.coord:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.zone = editbox(r, 108, function(text)
            local t = trim(text)
            local m, hits = findZone(t)
            if not m then if t ~= "" then noZone(t, hits) end; refresh() return end
            editGeo(key(), function(_, _, p)
                if not p then ns.print("type the coordinates first (with the zone if you like: Westfall 56.3, 47.5)") return false end
                p.m = m
            end)
            refresh()
        end)
        r.zone:SetPoint("LEFT", r.coord, "RIGHT", 4, 0)
        r.zone:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("The zone these coordinates are on. Type its name (Westfall, elwynn, stormwind) or its map ID (map 1436); the coordinates stay as they are.", 1, 1, 1, true); GameTooltip:Show() end)
        r.zone:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.ph = ui.text(r, 10, 1, 1, 1, 0.4); r.ph:SetPoint("LEFT", r.zone, "LEFT", 6, 0); r.ph:Hide()
        r.here = button(r, "Here", 48, function()
            local h = here()
            if not h then return end
            editGeo(key(), function(g, _, p)
                if not p and isPoint then g.point = { m = h.m, x = h.x, y = h.y } return end
                if not p then return false end
                p.m, p.x, p.y = h.m, h.x, h.y
            end)
        end, isPoint and "Puts the step's point where you stand (its waypoints and kill area stay)." or "Moves this one to where you stand.")
        if isPoint then
            r.here:SetPoint("LEFT", r.zone, "RIGHT", 52, 0)
            return r
        end
        r.rad = editbox(r, 44, function(text)
            local n = tonumber((text or ""):match("%d+"))
            editGeo(key(), function(_, _, p) if not p then return false end; p.r = n end)
        end)
        r.rad:SetPoint("LEFT", r.zone, "RIGHT", 4, 0)
        r.rad:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("How close counts as reached, in yards (15 when empty)", 1, 1, 1, true); GameTooltip:Show() end)
        r.rad:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.here:SetPoint("LEFT", r.rad, "RIGHT", 4, 0)
        r.up = button(r, "Up", 36, function()
            editGeo(key(), function(_, list) local k = wOff + i; if k < 2 or not list[k] then return false end; list[k - 1], list[k] = list[k], list[k - 1] end)
        end, "Earlier in the order.")
        r.up:SetPoint("LEFT", r.here, "RIGHT", 4, 0)
        r.down = button(r, "Down", 44, function()
            editGeo(key(), function(_, list) local k = wOff + i; if not list[k + 1] then return false end; list[k + 1], list[k] = list[k], list[k + 1] end)
        end, "Later in the order.")
        r.down:SetPoint("LEFT", r.up, "RIGHT", 4, 0)
        r.del = button(r, "×", 24, function()
            editGeo(key(), function(_, list) if not list[wOff + i] then return false end; table.remove(list, wOff + i) end)
        end, "Removes it.")
        r.del:SetPoint("LEFT", r.down, "RIGHT", 4, 0)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        return r
    end
    for i = 1, WROWS do d.wrows[i] = row(i) end
    y = y - WROWS * 26
    d.wEmpty = ui.text(listFrame, 11, 1, 1, 1, 0.4); d.wEmpty:SetPoint("TOPLEFT", 24, -4); d.wEmpty:SetPoint("RIGHT", 0, 0)
    d.wpoint = row(0, true)
    d.wpoint:SetPoint("TOPLEFT", 0, y)
    y = y - 30
    local function act3(txt, col, fn, tip)
        local b = button(P3, txt, bw, fn, tip)
        b:SetPoint("TOPLEFT", (col - 1) * (bw + 6), y)
        return b
    end
    d.addHere = act3("Add here", 1, function()
        local h = here()
        if not h then return end
        editGeo(nil, function(g, list)
            if listMode == "area" then list[#list + 1] = { m = h.m, x = h.x, y = h.y }
            elseif not g.point then g.point = { m = h.m, x = h.x, y = h.y }
            else list[#list + 1] = { m = h.m, x = h.x, y = h.y, r = 15 } end
        end)
        wOff = math.max(0, #curList(geometry(selected())) - WROWS)
        refresh()
    end, "Adds where you stand at the end of the list (a waypoint goes before the step's point).")
    d.addMap = act3("Add on map", 2, function()
        if not (ns.editorMapPlacing and ns.editorMapIsPlacing) then return end
        if ns.editorMapIsPlacing() then ns.editorMapPlacing(false) return end
        local s = selected()
        local g = s and geometry(s)
        local p = g and (g.point or g.way[1] or g.area[1])
        if not (WorldMapFrame and WorldMapFrame:IsShown()) and ns.showOnMap then
            if p then ns.showOnMap(p.m) else ns.showOnMap(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")) end
        end
        ns.editorMapPlacing(listMode)
    end, "Opens the world map: every click on it adds a waypoint (or kill area spot) there; right-click on the map or this button again stops.")
    d.clearList = act3("Clear all", 3, function(self)
        if not self.armed then
            self.armed = true; self.text:SetText("Click again")
            C_Timer.After(3, function() self.armed = false; refresh() end)
            return
        end
        self.armed = false
        editGeo(nil, function(_, list) if #list == 0 then return false end; for k = #list, 1, -1 do list[k] = nil end end)
    end, "Removes every waypoint (or every kill area spot) of the step (two clicks).")
    y = y - 30
    d.mapHint = ui.text(P3, 10, 1, 1, 1, 0.4); d.mapHint:SetPoint("TOPLEFT", 0, y); d.mapHint:SetPoint("RIGHT", 0, 0); d.mapHint:SetWordWrap(true)
    d.mapHint:SetText("On the world map (M) while the editor is open: the step's point (P), its waypoints (numbered, with the line) and its kill area. Drag a pin to move it, right-click to remove it.")

    -- what the map does with your clicks and drags
    local mapHandlers = {
        move = function(kind, k, m, x, yy)
            local s = selected()
            if not s then return end
            local g = geometry(s)
            local p = kind == "point" and g.point or (kind == "way" and g.way[k]) or g.area[k]
            if not p then return end
            p.m, p.x, p.y = m, x, yy
            writeGeometry(s, g); refresh()
        end,
        remove = function(kind, k)
            local s = selected()
            if not s then return end
            local g = geometry(s)
            local list = kind == "way" and g.way or g.area
            if not list[k] then return end
            table.remove(list, k)
            writeGeometry(s, g); refresh()
        end,
        add = function(m, x, yy)
            local s = selected()
            if not s then return end
            local g = geometry(s)
            local what = (ns.editorMapIsPlacing and ns.editorMapIsPlacing()) or listMode
            if what == "area" then g.area[#g.area + 1] = { m = m, x = x, y = yy }
            elseif not g.point then g.point = { m = m, x = x, y = yy } -- (a step without a point: the first click is it)
            else g.way[#g.way + 1] = { m = m, x = x, y = yy, r = 15 } end
            writeGeometry(s, g); refresh()
        end,
        placingChanged = function() if refresh then refresh() end end,
    }
    -- the list's rows, buttons and the map from the selected step
    d.refreshWay = function(s)
        local g = geometry(s)
        local list = curList(g)
        wOff = math.max(0, math.min(wOff, #list - WROWS))
        d.modeWay:SetActive(listMode == "way"); d.modeArea:SetActive(listMode == "area")
        d.modeWay.text:SetText("Waypoints (" .. #g.way .. ")")
        d.modeArea.text:SetText("Kill area (" .. #g.area .. ")")
        for i, r in ipairs(d.wrows) do
            local p = list[wOff + i]
            r:SetShown(p ~= nil)
            if p then
                r.n:SetText(tostring(wOff + i))
                if not r.coord:HasFocus() then r.coord:SetText(string.format("%.1f, %.1f", p.x, p.y)) end
                if not r.zone:HasFocus() then r.zone:SetText(mapName(p.m) or ("map " .. tostring(p.m))) end
                r.rad:SetShown(listMode == "way")
                if listMode == "way" and not r.rad:HasFocus() then r.rad:SetText(p.r and p.r > 0 and tostring(p.r) or "") end
                r.up:SetAlpha(wOff + i > 1 and 1 or 0.35)
                r.down:SetAlpha(list[wOff + i + 1] and 1 or 0.35)
            end
        end
        d.wEmpty:SetShown(#list == 0)
        d.wEmpty:SetText(listMode == "area" and "No kill area: the arrow leads to the step's point."
            or "No waypoints: the arrow goes straight to the step's point.")
        -- the step's point closes the way
        d.wpoint:SetShown(listMode == "way")
        d.wpoint.n:SetText("P")
        if not d.wpoint.coord:HasFocus() then d.wpoint.coord:SetText(g.point and string.format("%.1f, %.1f", g.point.x, g.point.y) or "") end
        if not d.wpoint.zone:HasFocus() then d.wpoint.zone:SetText(g.point and (mapName(g.point.m) or ("map " .. tostring(g.point.m))) or "") end
        d.wpoint.ph:SetText("no point yet")
        d.wpoint.ph:SetShown(not g.point and not d.wpoint.zone:HasFocus())
        local placing = ns.editorMapIsPlacing and ns.editorMapIsPlacing()
        d.addMap:SetActive(placing and true or false)
        d.addMap.text:SetText(placing and "Click the map..." or "Add on map")
        if not d.clearList.armed then d.clearList.text:SetText("Clear all") end
        if ns.setEditorMap then ns.setEditorMap(g, mapHandlers) end
    end

    win.hint = ui.text(win, 11, 1, 1, 1, 0.3)
    win.hint:SetPoint("BOTTOMLEFT", PAD, 14); win.hint:SetWidth(W - PAD * 2); win.hint:SetWordWrap(true)
    win.hint:SetText("Green = added by you, yellow = changed, dim = hidden, bar = your step. Edits are saved per route for all your characters and stay when the routes are updated.")

    refresh = function()
        if not win:IsShown() then return end
        local r = ns.route()
        local all = r and r.editList or {}
        local chs = r and r.chapters or {}
        if chap and chap > #chs then chap = #chs > 0 and 1 or 0 end
        if not chap then chap = #chs > 0 and 1 or 0 end
        local map = r and chapterMap(r) or {}
        local list, found = {}, {}
        for j, s in ipairs(all) do
            if chap == 0 or map[j] == chap then
                list[#list + 1] = s
                if matches(s) then found[#found + 1] = s end
            end
        end
        view = list
        local searching = query ~= ""
        win.search.ph:SetText(chap == 0 and "Search all steps" or "Search this chapter")
        win.search.ph:SetShown(not searching and not win.search:HasFocus() and (win.search:GetText() or "") == "")
        win.searchClear:SetAlpha(searching and 1 or 0.35)
        local cname = chap == 0 and "All steps" or (chs[chap] and chs[chap].name or "")
        win.cb.name.text:SetText(chap == 0 and ("All steps  (" .. #all .. ")") or string.format("%d/%d  %s", chap, #chs, cname))
        win.cb.prev:SetAlpha(#chs > 0 and 1 or 0.35); win.cb.next:SetAlpha(#chs > 0 and 1 or 0.35)
        if win.chMenu:IsShown() then win.chMenu.refresh() end
        local custom = r and r.custom
        win.routeName:SetShown(not custom)
        win.nameEdit:SetShown(custom and true or false)
        if custom and not win.nameEdit:HasFocus() then win.nameEdit:SetText(r.name or ""); win.nameEdit:SetCursorPosition(0) end
        win.routeName:SetText(r and ((r.name or "?") .. (r.custom and "" or ((r.version and ("  " .. r.version) or "") .. "  ·  edits make your own copy"))) or "no route")
        win.routeTip:SetShown(not custom)
        tb.rec:SetActive(recording)
        tb.rec.text:SetText(recording and "Recording" or "Record")
        if not tb.reset.armed then tb.reset.text:SetText("Undo all edits") end
        offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
        local cur = ns.steps()[ItineraryCharDB.step]
        local num = {}
        for j, s in ipairs(ns.steps()) do num[s] = j end
        for i, row in ipairs(rows) do
            local s = list[offset + i]
            row:SetShown(s ~= nil)
            if s then
                row.id = sid(s)
                row.num:SetText(num[s] and tostring(num[s]) or "-")
                row.verb:SetText(VERB[kindOf(s)] or s.t)
                row.cur:SetShown(s == cur)
                row.txt:SetText(label(s))
                local a = s.edHidden and 0.3 or 0.85
                if s.edAdd then row.txt:SetTextColor(ar, ag, ab, a)
                elseif s.edChanged then row.txt:SetTextColor(1, 0.85, 0.3, a)
                else row.txt:SetTextColor(1, 1, 1, a) end
                row.verb:SetAlpha(s.edHidden and 0.4 or 1)
                row.hl:SetShown(row.id == sel)
            end
        end
        win.listInfo:SetText(#list > 0 and string.format("%d-%d of %d %s (mouse wheel scrolls)", offset + 1, math.min(#list, offset + ROWS), #list,
            chap == 0 and "steps" or "in this chapter")
            or (#all > 0 and "No steps in this chapter" or "No steps yet: Record, Add step here, or the Recorder"))
        -- the search's matches
        local res = win.results
        res.found = found
        res:SetShown(searching and resultsOpen)
        if searching and resultsOpen then
            local n = #res.rows
            resOff = math.max(0, math.min(resOff, #found - n))
            for i, b in ipairs(res.rows) do
                local s = found[resOff + i]
                b.s = s
                b:SetShown(s ~= nil)
                if s then
                    b.num:SetText(num[s] and tostring(num[s]) or "-")
                    b.verb:SetText(VERB[kindOf(s)] or s.t)
                    local text = label(s)
                    -- (the quest it found, when the line shows another one of the step)
                    if not text:lower():find(query, 1, true) then
                        local other = otherMatch(s)
                        if other then text = text .. "  |cff999999+ " .. other .. "|r" end
                    end
                    b.txt:SetText(text)
                end
            end
            local shown = math.min(n, #found)
            res:SetHeight(math.max(1, shown) * ROW_H + 26)
            res.info:SetText(#found == 0 and string.format("No step %s has \"%s\"", chap == 0 and "of the route" or "in this chapter", query)
                or string.format("%d %s%s - click one to go there", #found, #found == 1 and "match" or "matches",
                    #found > n and string.format(" (%d-%d, mouse wheel)", resOff + 1, math.min(#found, resOff + n)) or ""))
        end
        tb.recorder:SetActive(ns.recorderState and ns.recorderState() == "on" or false)
        tb.export:SetAlpha(custom and 1 or 0.35)

        local s = selected()
        win.d:SetShown(s ~= nil)
        if not s then if ns.setEditorMap then ns.setEditorMap(nil) end return end
        local n = stepNumber(s)
        win.d.head:SetText((n and ("Step " .. n) or "Hidden step") .. "  ·  " ..
            (s.edAdd and "added by you" or s.edHidden and "hidden" or s.edChanged and "changed by you" or "from the route") ..
            (s.edOrphan and "  ·  its place in the route is gone, so it's at the end" or ""))
        local kind = kindOf(s)
        for t, b in pairs(win.d.types) do b:SetActive(kind == t) end
        -- another step selected while you're in one of the boxes (a click in the step list): leave the box first -
        -- what you typed goes to its own step - so it shows this step's text, not the last one's
        local left = false
        for _, f in pairs(fields) do
            if f.box:HasFocus() and f.box.forId and f.box.forId ~= sid(s) then f.box:ClearFocus(); left = true end
        end
        if left then refresh() return end -- (again with the box left and its text saved)
        for _, f in pairs(fields) do
            -- (from the start: the cursor at the end scrolls a long text out of the box)
            if not f.box:HasFocus() then f.box:SetText(f.get(s)); f.box:SetCursorPosition(0); f.box.forId = sid(s) end
        end
        local qstep = s.t == "accept" or s.t == "turnin" or s.t == "complete"
        fields.q.box:SetAlpha((qstep or kind == "abandon") and 1 or 0.4)
        fields.lvl.box:SetAlpha((s.t == "xp" or s.t == "accept") and 1 or 0.4)
        fields.till.box:SetAlpha(s.along and 1 or 0.4)
        fields.trainer.box:SetAlpha(s.t == "train" and 1 or 0.4)
        fields.arrive.box:SetAlpha((s.t == "go" or s.t == "do") and 1 or 0.4)
        -- the pages, and how much is set on the other two
        local nc = #(s.cond or {}) + #(s.zskip or {})
        for _, f in ipairs({ "lvskip", "need", "buffItem", "money", "dps", "gateL", "cdSkip" }) do if s[f] then nc = nc + 1 end end
        if s.bindAt or s.bindNot then nc = nc + 1 end
        if s.grp or s.solo then nc = nc + 1 end
        if s.needProf or s.skill then nc = nc + 1 end
        local nm = 0
        for _, f in ipairs({ "zone", "sub", "r", "gossip", "macro", "path", "wp", "cdDone", "bankIn", "bankOut" }) do if s[f] then nm = nm + 1 end end
        if s.cls or s.wpn then nm = nm + 1 end
        local counts = { nil, nc, nm }
        for k, pg in ipairs(win.d.pages) do
            pg:SetShown(k == page)
            local tab = win.d.tabs[k]
            tab:SetActive(k == page)
            local base = k == 1 and "Step" or k == 2 and "Conditions" or "More"
            tab.text:SetText(counts[k] and counts[k] > 0 and (base .. " (" .. counts[k] .. ")") or base)
        end
        win.d.refreshWay(s)
        local z = s.z or ""
        win.d.posText:SetText(s.x and string.format("Point: %s %.1f, %.1f", z, s.x, s.y) or (s.wx and ("Point: " .. z .. " (from the route)") or "No point (the arrow has nowhere to go)"))
        win.d.hide.text:SetText(s.edAdd and "Delete" or (s.edHidden and "Show" or "Hide"))
        win.d.up:SetAlpha(s.edAdd and 1 or 0.35); win.d.down:SetAlpha(s.edAdd and 1 or 0.35)
        win.d.revert:SetAlpha((s.edChanged or s.edHidden) and not s.edAdd and 1 or 0.35)
        win.d.market.text:SetText(s.ah and "Auction house" or (s.ssf and "Self-found only" or "For everyone"))
        if win.d.market.SetActive then win.d.market:SetActive((s.ah or s.ssf) and true or false) end
        if win.d.along.SetActive then win.d.along:SetActive(s.along and true or false) end
        if win.d.opt.SetActive then win.d.opt:SetActive(s.opt and true or false) end
        win.d.opt.text:SetText(s.opt and "Optional: on" or "Optional")
        if win.d.death.SetActive then win.d.death:SetActive(s.death and true or false) end
        win.d.death.text:SetText(s.death and "Death skip: on" or "Death skip")
        win.d.along.text:SetText(s.along and "Along: on" or "Along the way")
    end
    ns.refreshEditor = refresh
    ns.editorFields = fields -- (for /iti and tests: the detail fields by key)
    -- another route in the editor (picked here or in the panel): start at your step there
    ns.editorRouteChanged = function()
        if not win:IsShown() then return end
        if ns.editorKeepSelection then refresh() return end
        offset, sel, chap = 0, nil, nil
        scrollToCurrent()
        refresh()
    end
    win:SetScript("OnShow", function() refresh() end)
    win:SetScript("OnHide", function() menu:Hide(); resultsOpen = false; res:Hide(); if ns.setEditorMap then ns.setEditorMap(nil) end end)
    win:Hide()
end

---------------------------------------------------------------- the recorder: a new route from what you do
-- ItineraryCharDB.recorder = { id = route, state = "on" | "paused", last = id of the last step it added,
-- zone, bind, prog = { [quest] = { f = objectives done, pts = { {m,x,y} }, mobs = {} } } }
local function REC() return ItineraryCharDB and ItineraryCharDB.recorder end
local function recState()
    local R = REC()
    if not (R and R.id and ItineraryDB.customRoutes and ItineraryDB.customRoutes[R.id]) then return nil end
    return R.state
end
ns.recorderState = recState
local recRefresh -- the recorder window's refresh
local function recUpdate()
    if recRefresh then recRefresh() end
    if ns.refreshEditor then ns.refreshEditor() end
    if ns.refreshRecStatus then ns.refreshRecStatus() end
end
local function recOps()
    local R = REC()
    local E = R and editsFor(R.id, true)
    return E and E.ops or {}, E
end
local function recLastOp()
    local R = REC()
    if not (R and R.last) then return nil end
    for _, op in ipairs(recOps()) do if op.k == "add" and op.id == R.last then return op end end
end

-- add a step at the end of the recording; a new zone starts a chapter
local recZone
-- the zone you're in for chapters: the map's zone (Dun Morogh), never a building or cave with a name of its
-- own (Anvilmar, which the game reports as a zone while you're inside)
recZone = function()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local id = C_Map.GetBestMapForUnit("player")
        local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        local guard = 0
        while id and guard < 10 do
            local info = C_Map.GetMapInfo(id)
            if not info then break end
            if info.mapType == zoneType then return info.name end
            if info.mapType and info.mapType < zoneType then break end -- continent or world: no zone
            id, guard = info.parentMapID, guard + 1
        end
    end
    return (GetZoneText and GetZoneText()) or (GetRealZoneText and GetRealZoneText()) or ""
end
---------------------------------------------------------------- the way you walk
-- Every second while recording (not flying, dead or inside a dungeon) where you are, in zone coordinates and
-- in world yards - a new spot only once you've moved a few yards, so standing still leaves a gap in the times
-- (that's how the dock you waited at is found). A recorded step with a place gets the corners of the way you
-- walked to it as its waypoints (when it wasn't about straight) and starts a new trail.
local trail = {}
local function dist(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) end
local function sample()
    if UnitOnTaxi and UnitOnTaxi("player") then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    if IsInInstance and IsInInstance() then return end
    local p = here()
    local c, wx, wy
    if ns.playerWorld then c, wx, wy = ns.playerWorld() end
    if not (p and c and wx) then return end
    local pt = { m = p.m, x = p.x, y = p.y, z = p.z, c = c, wx = wx, wy = wy, t = GetTime and GetTime() or 0 }
    local last = trail[#trail]
    if last and last.c == c and dist(last, pt) < 3 then return end
    trail[#trail + 1] = pt
    -- a long walk: the older half thinned out
    if #trail > 600 then
        local keep = {}
        for i, q in ipairs(trail) do if i > 300 or i % 2 == 1 then keep[#keep + 1] = q end end
        trail = keep
    end
end
ns.recorderSample = sample -- (tests)
local function segDist(p, a, b)
    local dx, dy = b.wx - a.wx, b.wy - a.wy
    local l2 = dx * dx + dy * dy
    if l2 == 0 then return dist(p, a) end
    local t = math.max(0, math.min(1, ((p.wx - a.wx) * dx + (p.wy - a.wy) * dy) / l2))
    return math.sqrt((p.wx - a.wx - t * dx) ^ 2 + (p.wy - a.wy - t * dy) ^ 2)
end
-- the corners of a line of spots (Douglas-Peucker: what's more than eps yards off the line between two kept ones)
local function simplify(pts, eps)
    local keep = { [1] = true, [#pts] = true }
    local function dp(i, j)
        local best, at = 0, nil
        for k = i + 1, j - 1 do
            local d = segDist(pts[k], pts[i], pts[j])
            if d > best then best, at = d, k end
        end
        if at and best > eps then keep[at] = true; dp(i, at); dp(at, j) end
    end
    dp(1, #pts)
    local out = {}
    for i = 1, #pts do if keep[i] then out[#out + 1] = pts[i] end end
    return out
end
local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
-- out and back again (to a herb, a mob a bit off the way): you come back within 12 yards of a spot within the
-- next 60 spots after being more than 20 away - the loop goes
local function dropLoops(pts)
    local out, i = {}, 1
    while i <= #pts do
        local p = pts[i]
        out[#out + 1] = p
        local back, far = nil, 0
        for j = i + 1, math.min(#pts, i + 60) do
            local d = dist(p, pts[j])
            if d > far then far = d end
            if far > 20 and d < 12 then back = j end
        end
        i = (back or i) + 1
    end
    return out
end
-- a step's waypoints from a trail: the corners of the way you walked to its point, at most 8; nothing when the
-- way was short or about straight (the arrow's line does it), and not the detours out and back (a herb, a mob)
local function trailPath(s, tr)
    if not (s.m and s.x and s.y and ns.worldPos) then return nil end
    local c, ex, ey = ns.worldPos(s.m, s.x / 100, s.y / 100)
    if not c then return nil end
    local pts = {}
    for _, p in ipairs(tr or {}) do if p.c == c then pts[#pts + 1] = p end end
    pts = dropLoops(pts)
    if #pts < 2 then return nil end
    local goal = { m = s.m, x = s.x, y = s.y, c = c, wx = ex, wy = ey }
    pts[#pts + 1] = goal
    local first = pts[1]
    local direct, walked = dist(first, goal), 0
    for i = 2, #pts do walked = walked + dist(pts[i - 1], pts[i]) end
    if direct < 60 or walked < direct * 1.15 then return nil end
    local eps, way = 30, {}
    for _ = 1, 6 do
        local simple = simplify(pts, eps)
        local again = true
        while again do
            again = false
            for i = 2, #simple - 1 do
                local a, p, b = simple[i - 1], simple[i], simple[i + 1]
                if dist(a, b) < 0.4 * (dist(a, p) + dist(p, b)) then table.remove(simple, i); again = true; break end
            end
        end
        way = {}
        for i = 2, #simple - 1 do
            local p = simple[i]
            if dist(p, first) > 25 and dist(p, goal) > 25 then way[#way + 1] = p end
        end
        if #way <= 8 then break end
        eps = eps * 1.5
    end
    if #way == 0 or #way > 8 then return nil end
    local path = {}
    for _, p in ipairs(way) do path[#path + 1] = { p.m, r2(p.x), r2(p.y), 0, 20 } end
    path[#path + 1] = { s.m, s.x, s.y, 0, 0 }
    return path
end
ns.recorderTrailPath = trailPath -- (tests)

-- add a step at the end of the recording; a new zone starts a chapter (not inside a dungeon: chapters stay
-- with the zones). A step with a place gets the way you walked there and starts a new trail.
local NO_PATH = { complete = true, xp = true, hearth = true }
local function recAdd(s, noChapter)
    local R = REC()
    if not R then return end
    local ops, E = recOps()
    local zone = recZone()
    local inside = IsInInstance and IsInInstance()
    if not noChapter and not inside and zone ~= "" and zone ~= R.zone then
        s.chapter = zone .. " " .. (UnitLevel and UnitLevel("player") or "")
        s.chZone = zone
        R.zone = zone
    end
    if R.chapterNext then s.chapter, R.chapterNext = R.chapterNext, nil end
    if s.m and s.x and not s.path and not s.wp and not s.death and not s.errand and not NO_PATH[s.t] then
        s.path = trailPath(s, trail)
    end
    if (s.m and s.x) or s.t == "hearth" or s.t == "fly" then trail = {} end
    E.n = E.n + 1
    ops[#ops + 1] = { k = "add", id = E.n, after = R.last and ("+" .. R.last) or "^", s = s }
    R.last, R.lastT = E.n, GetTime and GetTime() or 0
    if ItineraryCharDB.route == R.id then rebuild() end
    recUpdate()
    return E.n
end
local function recOn() return recState() == "on" end

local function npcName() return (UnitExists and UnitExists("npc") and ns.unitName("npc")) or lastNpc end
local function placed(s)
    local p = here()
    if p then s.m, s.x, s.y, s.z = p.m, p.x, p.y, p.z end
    return s
end
local function at(s, p)
    if p then s.m, s.x, s.y, s.z = p.m, p.x, p.y, p.z end
    return s
end

-- accept / turn in: quests taken at the same NPC right after each other share a step
local function recQuest(t, q)
    if not (recOn() and q and q > 0) then return end
    local npc = npcName()
    local op = recLastOp()
    local now = GetTime and GetTime() or 0
    if op and op.s.t == t and op.s.npc == npc and npc and (now - (REC().lastT or 0)) < 90 then
        for _, x in ipairs(op.s.q) do if x == q then return end end
        op.s.q[#op.s.q + 1] = q
        op.s.n[#op.s.n + 1] = questName(q)
        REC().lastT = now
        if ItineraryCharDB.route == REC().id then rebuild() end
        recUpdate()
        return
    end
    recAdd(placed({ t = t, q = { q }, n = { questName(q) }, npc = npc, targets = npc and { npc } or nil }))
end

-- bags: what's where, how many
local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function bagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1 end
        return nil
    end
    if C_Container and C_Container.GetContainerItemID then
        local id = C_Container.GetContainerItemID(bag, slot)
        return id, id and 1 or nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count
    end
end
local function bagCounts()
    local out = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, bagSlots(bag) do
            local id, n = bagItem(bag, slot)
            if id then out[id] = (out[id] or 0) + (n or 1) end
        end
    end
    return out
end
local function itemClass(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local _, _, _, _, _, classID, subID = f(id)
    return classID, subID
end
local function itemName(id)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
end
local function spellName(id)
    return id and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))) or nil
end
local function itemSpell(id)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if f then return f(id) end
end

-- quest items you use: the bag item with the spell you just cast, if it's a quest item. It goes on the item
-- button of the quest whose objectives move within a minute.
local usedItems = {}
-- emotes you do (/sit at the campfire, /salute a guard): one an objective moves right after (10 s) becomes the
-- quest step's macro button
local lastEmote
if hooksecurefunc and DoEmote then
    hooksecurefunc("DoEmote", function(token, target)
        local R = REC and REC()
        if not (R and R.state == "on") or type(token) ~= "string" then return end
        local who = target
        if not who or who == "" or who == "none" then who = ns.unitName("target") or nil end
        lastEmote = { t = GetTime(), token = token:lower(), who = who }
    end)
end
local function questItemFor(spellID)
    local want = spellName(spellID)
    local qinfo = C_Container and C_Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, bagSlots(bag) do
            local id = bagItem(bag, slot)
            local quest = id and itemClass(id) == 12
            if id and not quest and qinfo then
                local a = qinfo(bag, slot)
                quest = (type(a) == "table" and a.isQuestItem) or (a == true)
            end
            if quest then
                local sn, sid = itemSpell(id)
                if (sid and sid == spellID) or (sn and want and sn == want) then return id end
            end
        end
    end
end

-- quest objectives: where they were done and what you fought; the quest done = a "complete" step there
local recentMobs = {}
local function questsInLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID > 0 then out[#out + 1] = info.questID end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local _, _, _, header, _, _, _, id = GetQuestLogTitle(i)
            if not header and id and id > 0 then out[#out + 1] = id end
        end
    end
    return out
end
-- the quest's own item (the game's "special item" of a quest), where the client knows it
local function specialItem(q)
    if not (GetQuestLogSpecialItemInfo and GetNumQuestLogEntries and GetQuestLogTitle) then return nil end
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, header, _, _, _, id = GetQuestLogTitle(i)
        if not header and id == q then
            local link = GetQuestLogSpecialItemInfo(i)
            return link and tonumber(tostring(link):match("item:(%d+)")) or nil
        end
    end
end
local function objectives(q)
    local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}
    local done, texts = 0, {}
    for _, o in ipairs(objs) do
        done = done + (o.numFulfilled or (o.finished and 1 or 0))
        if o.text and o.text ~= "" then texts[#texts + 1] = (o.text:gsub("^%s*%d+/%d+%s*", ""):gsub(":%s*%d+/%d+%s*$", "")) end
    end
    return done, texts
end
local function onQuestLog(q)
    for _, id in ipairs(questsInLog()) do if id == q then return true end end
    return false
end
-- the recorder's quest button: none, then each quest in your log
function ns.recorderPickNext(back)
    local R = REC()
    if not R then return end
    local list = questsInLog()
    local opts = { false }
    for _, q in ipairs(list) do opts[#opts + 1] = q end
    local at = 1
    for k, v in ipairs(opts) do if v == (R.pickQ or false) then at = k end end
    at = ((at - 1 + (back and -1 or 1)) % #opts) + 1
    R.pickQ = opts[at] or nil
    recUpdate()
end
local function recScan()
    local R = REC()
    if not (R and R.state) then return end
    R.prog = R.prog or {}
    local now = GetTime and GetTime() or 0
    for _, q in ipairs(questsInLog()) do
        local P = R.prog[q]
        local done, texts = objectives(q)
        if not P then
            P = { f = done, pts = {}, mobs = {} }
            R.prog[q] = P
        elseif done > (P.f or 0) then
            P.f = done
            if R.state == "on" then
                local p = here()
                if p then P.pts[#P.pts + 1] = { p.m, p.x, p.y, p.z }
                elseif IsInInstance and IsInInstance() then P.inside = true end -- (the game hides where you are in there)
                for name, t in pairs(recentMobs) do
                    if now - t < 45 then
                        local have = false
                        for _, x in ipairs(P.mobs) do if x == name then have = true end end
                        if not have and #P.mobs < 5 then P.mobs[#P.mobs + 1] = name end
                    end
                end
                -- an emote just before
                if lastEmote and now - lastEmote.t <= 10 then P.emote = lastEmote end
                -- a quest item you used just before
                for id, t in pairs(usedItems) do
                    if now - t < 60 then
                        P.items = P.items or {}
                        local have = false
                        for _, x in ipairs(P.items) do if x == id then have = true end end
                        if not have and #P.items < 3 then P.items[#P.items + 1] = id end
                    end
                end
            end
        end
        if R.state == "on" and not P.emitted and (#P.pts > 0 or P.inside) and ns.quest and ns.quest.ready(q) then
            P.emitted = true
            local s = { t = "complete", q = { q }, n = { questName(q) }, obj = #texts > 0 and texts or nil,
                        mobs = #P.mobs > 0 and P.mobs or nil }
            if #P.pts > 0 then
                -- the middle of where you did it (points on the map you finished on)
                local last = P.pts[#P.pts]
                local sx, sy, n = 0, 0, 0
                for _, p in ipairs(P.pts) do if p[1] == last[1] then sx, sy, n = sx + p[2], sy + p[3], n + 1 end end
                -- the spots where the count went up, as the step's kill area (the arrow walks them as a loop, the
                -- map shows them): the ones on the map you finished on, thinned so they're at least a bit apart
                local wp = {}
                for _, p in ipairs(P.pts) do
                    if p[1] == last[1] then
                        local near = false
                        for _, w in ipairs(wp) do
                            if (w[2] - p[2]) ^ 2 + (w[3] - p[3]) ^ 2 < 1.2 ^ 2 then near = true break end
                        end
                        if not near then wp[#wp + 1] = { p[1], r2(p[2]), r2(p[3]), 0 } end
                    end
                end
                while #wp > 10 do table.remove(wp, 2) end -- keep the first and the latest ones
                s.m, s.x, s.y, s.z, s.wp = last[1], r2(sx / n), r2(sy / n), last[4], #wp >= 2 and wp or nil
            elseif R.dungeonPt then
                -- done inside a dungeon: the arrow leads to its entrance
                at(s, R.dungeonPt)
            end
            local items = P.items or {}
            local sp = specialItem(q)
            if sp then
                local have = false
                for _, x in ipairs(items) do if x == sp then have = true end end
                if not have then table.insert(items, 1, sp) end
            end
            if #items > 0 then s.item = items end
            if P.emote then
                -- at whom, when an objective names them
                local e, line = P.emote, "/" .. P.emote.token
                if e.who and table.concat(texts, " "):lower():find(e.who:lower(), 1, true) then line = "/tar " .. e.who .. "\n" .. line end
                local icons = { sit = "Spell_Nature_Sleep", sleep = "Spell_Nature_Sleep", kneel = "Spell_Holy_PrayerOfHealing", pray = "Spell_Holy_PrayerOfHealing" }
                s.macro = { e.token:sub(1, 1):upper() .. e.token:sub(2), "Interface\\Icons\\" .. (icons[e.token] or "Ability_Warrior_BattleShout"), line }
            end
            recAdd(s)
        end
    end
end

-- flights, flight paths, hearthstone, trainers
local flightFrom
if hooksecurefunc and TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", function(i)
        if not recOn() then return end
        local dest = TaxiNodeName and TaxiNodeName(i)
        dest = dest and dest:match("^([^,]+)") or dest
        local s = flightFrom or placed({})
        recAdd({ t = "fly", name = dest or "Flight", npc = s.npc, m = s.m, x = s.x, y = s.y, z = s.z })
    end)
end
local function bindLoc() return GetBindLocation and GetBindLocation() or nil end

-- weapon masters: one you know (Itinerary_Data, or one you opened before), or one you learned a weapon skill at
local function weaponMasterNpc(npc)
    if not npc then return false end
    if ns.DATA_WEAPON_MASTERS and ns.DATA_WEAPON_MASTERS[npc] then return true end
    if ItineraryDB.weaponMasters and ItineraryDB.weaponMasters[npc] then return true end
    local cd = ns.CLASS_DATA and ns.CLASS_DATA.weaponMasters
    return (cd and cd[npc]) and true or false
end
local function weaponsKnownNow()
    local out = {}
    local known = IsPlayerSpell or IsSpellKnown
    if not (known and ns.WPN_NAME) then return out end
    for id in pairs(ns.WPN_NAME) do if known(id) then out[id] = true end end
    return out
end
local trainer -- the trainer you have open: { npc, spot, trade, wpn = weapon skills you knew }
local function trainerClosed()
    local t = trainer
    trainer = nil
    if not (t and recOn()) then return end
    local learned = {}
    for id in pairs(weaponsKnownNow()) do if not t.wpn[id] then learned[#learned + 1] = id end end
    table.sort(learned)
    if #learned > 0 or weaponMasterNpc(t.npc) then
        if #learned == 0 then return end -- (only had a look)
        local names = {}
        for _, id in ipairs(learned) do names[#names + 1] = ns.WPN_NAME[id] or tostring(id) end
        recAdd(at({ t = "train", npc = t.npc, targets = t.npc and { t.npc } or nil, wpn = learned,
                    name = "Train " .. table.concat(names, ", ") }, t.spot))
        return
    end
    local op = recLastOp()
    if op and op.s.t == "train" and op.s.npc == t.npc then return end
    recAdd(at({ t = "train", npc = t.npc, targets = t.npc and { t.npc } or nil, cls = (not t.trade) or nil,
                name = t.trade and ("Train at " .. (t.npc or "the trainer")) or nil }, t.spot))
end

-- vendors: what you sold, bought and repaired while one was open
local shop
local TOOL_ITEMS = { [2901] = true, [7005] = true, [5956] = true, [6256] = true } -- (bought for you: Settings > Professions)
local FOOD_SPELL, DRINK_SPELL = 433, 430
local function openShop()
    if shop or not recOn() then return end
    shop = { npc = npcName(), spot = here(), before = bagCounts(), bought = {} }
end
local function shopClosed()
    local v = shop
    shop = nil
    if not (v and recOn()) then return end
    local now = bagCounts()
    local food, food2 = spellName(FOOD_SPELL), spellName(DRINK_SPELL)
    local errands, stock = {}, {}
    for id, n in pairs(v.bought) do
        if not TOOL_ITEMS[id] then
            local got = (now[id] or 0) - (v.before[id] or 0)
            if got <= 0 then got = n end
            local cls, sub = itemClass(id)
            local sn = itemSpell(id)
            -- food, drink and bags are an errand (an instruction); anything else is a step that's done once you have it
            if cls == 1 or (cls == 0 and sub == 5) or (sn and (sn == food or sn == food2)) then
                errands[#errands + 1] = id
            else
                stock[#stock + 1] = { id, got }
            end
        end
    end
    table.sort(errands); table.sort(stock, function(a, b) return a[1] < b[1] end)
    local npc = v.npc
    local function names(list, key)
        local out = {}
        for _, x in ipairs(list) do out[#out + 1] = itemName(key and x[key] or x) end
        return table.concat(out, ", ")
    end
    if #stock > 0 then
        recAdd(at({ t = "do", name = "Buy " .. names(stock, 1), npc = npc, targets = npc and { npc } or nil, col = stock }, v.spot))
    end
    if #errands > 0 then
        recAdd(at({ t = "do", name = "Buy " .. names(errands), npc = npc, targets = npc and { npc } or nil, errand = true }, v.spot))
    elseif #stock == 0 and (v.sold or v.repaired) then
        local name = v.sold and (v.repaired and "Vendor trash and repair" or "Vendor trash") or "Repair"
        recAdd(at({ t = "do", name = name, npc = npc, targets = npc and { npc } or nil, errand = true }, v.spot))
    end
end
if hooksecurefunc then
    if BuyMerchantItem then
        hooksecurefunc("BuyMerchantItem", function(i, qty)
            if not shop then return end
            local link = GetMerchantItemLink and GetMerchantItemLink(i)
            local id = link and tonumber(tostring(link):match("item:(%d+)"))
            if id then shop.bought[id] = (shop.bought[id] or 0) + (tonumber(qty) or 1) end
        end)
    end
    if RepairAllItems then hooksecurefunc("RepairAllItems", function() if shop then shop.repaired = true end end) end
    -- (an item used while a vendor is open is sold)
    local function used()
        if not shop and MerchantFrame and MerchantFrame:IsShown() then openShop() end
        if shop then shop.sold = true end
    end
    if UseContainerItem then hooksecurefunc("UseContainerItem", used) end
    if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", used) end
end

-- abandoning a quest: an abandon step (several right after each other share one)
local abandonQ, abandonName
local function noteAbandon()
    local q
    if C_QuestLog and C_QuestLog.GetAbandonQuest then q = C_QuestLog.GetAbandonQuest() end
    if not (q and q > 0) and GetQuestLogSelection and GetQuestLogTitle then
        local i = GetQuestLogSelection()
        if i and i > 0 then
            local _, _, _, _, _, _, _, id = GetQuestLogTitle(i)
            q = id
        end
    end
    if q and q > 0 then
        abandonQ = q
        abandonName = (GetAbandonQuestName and GetAbandonQuestName()) or questName(q)
    end
end
local function abandoned()
    local q, n = abandonQ, abandonName
    abandonQ, abandonName = nil, nil
    if not (q and recOn()) then return end
    local R = REC()
    if R.prog then R.prog[q] = nil end
    local op = recLastOp()
    local now = GetTime and GetTime() or 0
    if op and op.s.abandon and (now - (R.lastT or 0)) < 60 then
        for _, x in ipairs(op.s.abandon) do if x == q then return end end
        op.s.abandon[#op.s.abandon + 1] = q
        op.s.name = op.s.name .. ", " .. (n or questName(q))
        R.lastT = now
        if ItineraryCharDB.route == R.id then rebuild() end
        recUpdate()
        return
    end
    recAdd({ t = "do", abandon = { q }, name = "Abandon " .. (n or questName(q)) }, true)
end
if hooksecurefunc then
    if SetAbandonQuest then hooksecurefunc("SetAbandonQuest", noteAbandon) end
    if C_QuestLog and C_QuestLog.SetAbandonQuest then hooksecurefunc(C_QuestLog, "SetAbandonQuest", noteAbandon) end
    if AbandonQuest then hooksecurefunc("AbandonQuest", abandoned) end
    if C_QuestLog and C_QuestLog.AbandonQuest then hooksecurefunc(C_QuestLog, "AbandonQuest", abandoned) end
end

-- loading screens: into a dungeon, the Deeprun Tram, a boat or a zeppelin to the other continent
local TRAM = 369 -- (the Deeprun Tram's own map)
local ZEP = { [1411] = true, [1420] = true, [1434] = true } -- Durotar, Tirisfal Glades, Stranglethorn Vale
local HARBOR = { boat = { [1437] = "Menethil Harbor", [1439] = "Auberdine", [1445] = "Theramore Isle", [1413] = "Ratchet", [1434] = "Booty Bay" },
                 zeppelin = { [1411] = "Orgrimmar", [1420] = "Undercity", [1434] = "Grom'gol" } }
local function zoneMap(m)
    local guard = 0
    while m and guard < 10 do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        if not info then return nil end
        if info.mapType == 3 then return m end
        if info.mapType and info.mapType < 3 then return nil end
        m, guard = info.parentMapID, guard + 1
    end
end
-- the dock: where you last stood still for a few seconds before the loading screen (waiting for the boat, or on
-- it while it's in), within the last 5 minutes; the trail up to there is the way to it
local function dockOf(tr, leftAt)
    for i = #tr, 1, -1 do
        local p = tr[i]
        if leftAt - p.t > 300 then break end
        local nextT = tr[i + 1] and tr[i + 1].t or leftAt
        if nextT - p.t >= 3 then
            local way = {}
            for k = 1, i do way[k] = tr[k] end
            return p, way
        end
    end
end
local leaving -- where you were when a loading screen started
local lastCast = 0
local function arrived(l)
    local R = REC()
    if not (R and recOn()) then return end
    local now = GetTime and GetTime() or 0
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    local name, inst
    if GetInstanceInfo then
        local a, _, _, _, _, _, _, id = GetInstanceInfo()
        name, inst = a, id
    end
    -- the Deeprun Tram: from the entrance in one city to the other
    if inst == TRAM then
        if l.inst ~= TRAM then R.tram = { spot = l.spot, zone = l.zone, trail = l.trail } end
        return
    end
    if l.inst == TRAM then
        local from = R.tram
        R.tram = nil
        local zone = GetRealZoneText and GetRealZoneText() or ""
        if from and from.spot and zone ~= "" and zone ~= from.zone then
            local s = at({ t = "go", name = "Take the Deeprun Tram to " .. zone, zone = zone }, from.spot)
            s.path = trailPath(s, from.trail)
            recAdd(s, true)
        end
        return
    end
    -- into a dungeon: a dungeon step at its entrance (not again when you're back in after a wipe)
    if inside and (kind == "party" or kind == "raid") then
        if l.inside then return end
        if R.dungeon == name and now - (R.dungeonLeft or 0) < 1800 then return end
        R.dungeon, R.dungeonPt = name, l.spot
        local s = at({ t = "dungeon", name = name or "the dungeon" }, l.spot)
        if l.spot then s.path = trailPath(s, l.trail) end
        recAdd(s, true)
        return
    end
    if l.inside then R.dungeonLeft = now; return end
    -- the other continent without a hearth, a teleport, a flight or a death: a boat or a zeppelin
    if not (l.inst and inst and l.inst ~= inst and (l.inst == 0 or l.inst == 1) and (inst == 0 or inst == 1)) then return end
    if l.dead or l.taxi or (l.t - (l.cast or 0)) < 6 then return end
    local dock, way = dockOf(l.trail or {}, l.t)
    dock = dock or l.spot
    if not dock then return end
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local fromZ = zoneMap(dock.m)
    local toZ = zoneMap(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local how = (fromZ and toZ and ZEP[fromZ] and ZEP[toZ]) and "zeppelin" or "boat"
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local to = (toZ and HARBOR[how][toZ]) or (sub ~= "" and sub) or zone
    local s = at({ t = "go", name = "Take the " .. how .. " to " .. to, zone = zone ~= "" and zone or nil }, dock)
    s.path = trailPath(s, way)
    recAdd(s, true)
end

-- dying: resurrected far from where you died (at the spirit healer, not at your corpse) = a death skip there
local died -- { spot, c, wx, wy }
local function unghost()
    local d = died
    died = nil
    if not (d and recOn()) then return end
    local far = d.spiritRes
    if ns.playerWorld and d.c then
        local c, wx, wy = ns.playerWorld()
        if c and wx then far = c ~= d.c or math.sqrt((wx - d.wx) ^ 2 + (wy - d.wy) ^ 2) > 60 end
    end
    if not far then return end
    recAdd(at({ t = "go", death = true, name = "Die and respawn at the spirit healer" }, d.spot), true)
    ns.print("recorded a death skip where you died (Undo last in the recorder if you didn't mean one)")
end

local rec = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_TARGET_CHANGED", "TRAINER_SHOW",
                     "TRAINER_CLOSED", "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_SYSTEM",
                     "QUEST_ACCEPTED", "QUEST_TURNED_IN", "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_LEAVING_WORLD",
                     "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_UNGHOST", "CONFIRM_XP_LOSS" }) do pcall(rec.RegisterEvent, rec, e) end
local scanQueued = false
local tick = 0
rec:SetScript("OnUpdate", function(_, e)
    tick = tick + (e or 0)
    if tick < 1 then return end
    tick = 0
    if recOn() then sample() end
end)
rec:SetScript("OnEvent", function(_, event, a1, a2, a3)
    local R = REC()
    if event == "PLAYER_LOGIN" then
        if recState() == "on" then ns.print("the recorder is on (Recorder in the route editor, or /iti recorder)") end
        if R and R.state then C_Timer.After(2, recScan) end
        return
    end
    if not (R and R.state) then return end
    if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        if not scanQueued then scanQueued = true; C_Timer.After(0.4, function() scanQueued = false; recScan() end) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        local n = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsPlayer("target") and ns.unitName("target")
        if n then recentMobs[n] = GetTime() end
    elseif not recOn() then
        return
    elseif event == "QUEST_ACCEPTED" then
        local q = (type(a2) == "number" and a2 > 0) and a2 or a1
        local npc = npcName()
        C_Timer.After(0.3, function()
            lastNpc = npc or lastNpc
            recQuest("accept", q)
            local Rr = REC()
            if Rr and Rr.prog then Rr.prog[q] = { f = (objectives(q)), pts = {}, mobs = {} } end
        end)
    elseif event == "QUEST_TURNED_IN" then
        recQuest("turnin", a1)
        if R.prog then R.prog[a1] = nil end
    elseif event == "TRAINER_SHOW" then
        trainer = { npc = npcName(), spot = here(), trade = IsTradeskillTrainer and IsTradeskillTrainer() or false, wpn = weaponsKnownNow() }
    elseif event == "TRAINER_CLOSED" then
        trainerClosed()
    elseif event == "MERCHANT_SHOW" then
        openShop()
    elseif event == "MERCHANT_CLOSED" then
        shopClosed()
    elseif event == "TAXIMAP_OPENED" then
        local npc = npcName()
        flightFrom = placed({ npc = npc })
    elseif event == "UI_INFO_MESSAGE" then
        local msg = type(a2) == "string" and a2 or a1
        if ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH then
            local npc = npcName()
            local sub = GetSubZoneText and GetSubZoneText() or ""
            recAdd(placed({ t = "fp", name = sub ~= "" and sub or GetZoneText(), npc = npc, targets = npc and { npc } or nil }))
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 ~= "player" then return end
        lastCast = GetTime and GetTime() or 0
        if a3 == 8690 then recAdd({ t = "hearth", name = bindLoc() or "Hearthstone" }, true); return end
        local id = questItemFor(a3)
        if id then usedItems[id] = lastCast end
    elseif event == "CHAT_MSG_SYSTEM" then
        local b = bindLoc()
        if b and R.bind and b ~= R.bind then
            local npc = npcName()
            recAdd(placed({ t = "sethearth", name = b, npc = npc, targets = npc and { npc } or nil }))
        end
        R.bind = b or R.bind
    elseif event == "PLAYER_LEAVING_WORLD" then
        local inside = IsInInstance and IsInInstance() or false
        local inst
        if GetInstanceInfo then local _, _, _, _, _, _, _, id = GetInstanceInfo(); inst = id end
        local spot = (not inside or inst == TRAM) and here() or nil
        leaving = { inst = inst, inside = inside and inst ~= TRAM, spot = spot, zone = GetRealZoneText and GetRealZoneText() or "",
                    trail = trail, t = GetTime and GetTime() or 0, cast = lastCast,
                    dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") or false, taxi = UnitOnTaxi and UnitOnTaxi("player") or false }
        trail = {}
    elseif event == "PLAYER_ENTERING_WORLD" then
        local l = leaving
        leaving = nil
        if a1 or a2 or not l then return end -- (logging in, a reload)
        -- (a moment later: the zone names are right by then)
        C_Timer.After(1, function() arrived(l) end)
    elseif event == "PLAYER_DEAD" then
        local inside = IsInInstance and IsInInstance()
        local p = not inside and here() or nil
        local c, wx, wy
        if p and ns.playerWorld then c, wx, wy = ns.playerWorld() end
        died = p and { spot = p, c = c, wx = wx, wy = wy } or nil
        trail = {} -- (the run back to your corpse is no way to walk)
    elseif event == "CONFIRM_XP_LOSS" then
        if died then died.spiritRes = true end
    elseif event == "PLAYER_UNGHOST" then
        unghost()
    end
end)

local function newRecordingRoute()
    ItineraryDB.customRoutes = ItineraryDB.customRoutes or {}
    local n = 1
    while ItineraryDB.customRoutes["my-route-" .. n] do n = n + 1 end
    local id = "my-route-" .. n
    local _, cls = UnitClass("player")
    local nm = string.format("Recorded %s (%s %s)", date and date("%Y-%m-%d %H:%M") or "", UnitRace("player") or "", UnitClass("player") or "")
    ItineraryDB.customRoutes[id] = { name = nm, faction = UnitFactionGroup and UnitFactionGroup("player"), match = myClassMatch(), recorded = true }
    registerCustom()
    return id
end

-- start (or resume), pause, stop
function ns.recorder(action)
    local R = REC()
    if action == "start" then
        if R and R.state then R.state = "on"; ns.print("recording again"); recUpdate(); return end
        local id = newRecordingRoute()
        ItineraryCharDB.recorder = { id = id, state = "on", bind = bindLoc(), prog = {} }
        recScan() -- the quests you have now are the starting point
        ns.print("recording into \"" .. ItineraryDB.customRoutes[id].name .. "\": quests, trainers, vendors, flights, dungeons, boats and the way you walk become steps")
    elseif action == "pause" then
        if R and R.state then R.state = "paused"; ns.print("recording paused") end
    elseif action == "stop" then
        if R and R.state then
            local def = ItineraryDB.customRoutes and ItineraryDB.customRoutes[R.id]
            ItineraryCharDB.recorder = nil
            ns.print("recording saved as \"" .. (def and def.name or "?") .. "\": pick it with the list button in the panel footer")
        end
    end
    recUpdate()
end

-- your own additions while recording
function ns.recorderAdd(kind, text)
    local R = REC()
    if not (R and R.state) then return false end
    text = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if kind == "along" then
        -- the picked quest's objectives become an ALONG THE WAY entry from here on (done with them)
        local q = R.pickQ
        if not (q and onQuestLog(q)) then ns.print("pick a quest from your log first (the Quest button)"); return false end
        local _, texts = objectives(q)
        recAdd({ t = "complete", q = { q }, n = { questName(q) }, obj = texts, along = true, note = text ~= "" and text or nil }, true)
        return true
    elseif kind == "xp" then
        -- "grind to here": a level step at your level and XP right now (the place: where you are)
        local lv = UnitLevel and UnitLevel("player") or 1
        local xp = UnitXP and UnitXP("player") or 0
        recAdd(placed({ t = "xp", lvl = lv, xpIn = xp > 0 and xp or nil, note = text ~= "" and text or nil }))
    elseif kind == "waypoint" then
        local sub = GetSubZoneText and GetSubZoneText() or ""
        recAdd(placed({ t = "go", name = text ~= "" and text or (sub ~= "" and sub) or GetZoneText(), r = 15 }))
    elseif text == "" then
        return false
    elseif kind == "note" then
        local op = recLastOp()
        if op then
            op.s.note = op.s.note and (op.s.note .. "\n" .. text) or text
            if ItineraryCharDB.route == R.id then rebuild() end
            recUpdate()
        else
            recAdd(placed({ t = "do", name = text }))
        end
    elseif kind == "step" then
        recAdd(placed({ t = "do", name = text }))
    elseif kind == "tip" then
        -- an instruction: shown in the INSTRUCTIONS card from here to the end of the chapter, or until the quest
        -- picked in the recorder is turned in (or you tick it off)
        local q = R.pickQ
        recAdd({ t = "do", name = text, along = true, untilQ = q, untilN = q and questName(q) or nil }, true)
    elseif kind == "chapter" then
        R.chapterNext = text
        ns.print("the next step starts the chapter \"" .. text .. "\"")
        recUpdate()
    end
    return true
end
function ns.recorderUndo()
    local R = REC()
    if not (R and R.last) then return end
    local ops = recOps()
    for i, op in ipairs(ops) do
        if op.k == "add" and op.id == R.last then
            table.remove(ops, i)
            R.last = tonumber(op.after:match("^%+(%d+)$") or "")
            if op.s.t == "complete" and op.s.q and R.prog and R.prog[op.s.q[1]] then R.prog[op.s.q[1]].emitted = nil end
            if op.s.chapter and op.s.chapter ~= "" then
                -- back to the zone of the chapter before (so the next step doesn't start a chapter again)
                R.zone = nil
                for j = i - 1, 1, -1 do
                    local o = ops[j]
                    if o.k == "add" and o.s and o.s.chZone then R.zone = o.s.chZone; break end
                end
            end
            break
        end
    end
    if ItineraryCharDB.route == R.id then rebuild() end
    recUpdate()
end

---------------------------------------------------------------- the recorder window
local rwin
local function buildRecorder()
    local ui = U()
    local ar, ag, ab = ui.accent()
    local RW, RH, RP = 380, 590, 14
    rwin = CreateFrame("Frame", "ItineraryRecorderWindow", UIParent)
    rwin:SetSize(RW, RH)
    local pos = ItineraryDB.recorderPos
    if pos then rwin:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else rwin:SetPoint("LEFT", 60, 0) end
    rwin:SetFrameStrata("DIALOG")
    rwin:SetClampedToScreen(true)
    rwin:EnableMouse(true)
    rwin:SetMovable(true)
    rwin:RegisterForDrag("LeftButton")
    rwin:SetScript("OnDragStart", rwin.StartMoving)
    rwin:SetScript("OnDragStop", function()
        rwin:StopMovingOrSizing()
        local p, _, rp, x, y = rwin:GetPoint()
        ItineraryDB.recorderPos = { p, rp, x, y }
    end)
    local bg = rwin:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.97))
    ui.addEdges(rwin, 1, 1, 1, 0.15)
    local top = rwin:CreateTexture(nil, "ARTWORK"); top:SetColorTexture(ar, ag, ab, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
    local eyebrow = ui.text(rwin, 12, ar, ag, ab, 0.9); eyebrow:SetPoint("TOPLEFT", RP, -12); eyebrow:SetText("ITINERARY")
    local title = ui.text(rwin, 18, 1, 1, 1, 1); title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -3); title:SetText("Recorder")
    local close = CreateFrame("Button", nil, rwin)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -8, -8)
    local x = ui.text(close, 18, 1, 1, 1, 0.5); x:SetPoint("CENTER"); x:SetJustifyH("CENTER"); x:SetText("×")
    close:SetScript("OnClick", function() rwin:Hide() end)

    -- status: a dot that blinks while recording
    local dot = rwin:CreateTexture(nil, "ARTWORK"); dot:SetSize(10, 10); dot:SetColorTexture(1, 0.25, 0.2, 1)
    dot:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    local status = ui.text(rwin, 12, 1, 1, 1, 0.85); status:SetPoint("LEFT", dot, "RIGHT", 8, 0); status:SetPoint("RIGHT", rwin, "RIGHT", -RP, 0)
    status:SetWordWrap(false)
    local blink = 0
    rwin:SetScript("OnUpdate", function(_, e)
        blink = blink + e
        dot:SetAlpha(recOn() and ((math.floor(blink * 2) % 2 == 0) and 1 or 0.25) or (recState() and 0.5 or 0.15))
    end)

    local bw = math.floor((RW - RP * 2 - 12) / 3)
    local bRec = button(rwin, "Record", bw, function() ns.recorder("start") end,
        "Starts a new recording, or carries on a paused one. Everything this character does becomes steps of a new route of yours.")
    bRec:SetPoint("TOPLEFT", dot, "BOTTOMLEFT", 0, -12)
    local bPause = button(rwin, "Pause", bw, function() ns.recorder("pause") end, "Stops adding steps until you press Record again.")
    bPause:SetPoint("LEFT", bRec, "RIGHT", 6, 0)
    local bStop = button(rwin, "Stop", bw, function(self)
        if self.armed then self.armed = false; ns.recorder("stop"); return end
        self.armed = true; self.text:SetText("Click again"); C_Timer.After(3, function() self.armed = false; if recRefresh then recRefresh() end end)
    end, "Ends the recording (two clicks). The route stays in your route list; the next Record starts a new one.")
    bStop:SetPoint("LEFT", bPause, "RIGHT", 6, 0)

    local nameL = ui.text(rwin, 11, 1, 1, 1, 0.45); nameL:SetPoint("TOPLEFT", bRec, "BOTTOMLEFT", 0, -14); nameL:SetText("Route name")
    local nameE = editbox(rwin, RW - RP * 2 - 80, function(t)
        local R = REC(); if R and R.id then ns.renameCustomRoute(R.id, t) end
        if recRefresh then recRefresh() end
    end)
    nameE:SetPoint("LEFT", nameL, "LEFT", 80, 0)

    -- the last steps it recorded
    local recentL = ui.text(rwin, 11, 1, 1, 1, 0.45); recentL:SetPoint("TOPLEFT", nameL, "BOTTOMLEFT", 0, -16); recentL:SetText("Last steps")
    local box = CreateFrame("Frame", nil, rwin)
    box:SetPoint("TOPLEFT", recentL, "BOTTOMLEFT", 0, -6)
    box:SetSize(RW - RP * 2, 8 * 18 + 4)
    ui.addEdges(box, 1, 1, 1, 0.08)
    local lines = {}
    for i = 1, 8 do
        local v = ui.text(box, 10, ar, ag, ab, 0.8); v:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 18); v:SetWidth(58); v:SetWordWrap(false)
        local t = ui.text(box, 12, 1, 1, 1, 0.85); t:SetPoint("LEFT", v, "RIGHT", 4, 0); t:SetPoint("RIGHT", box, "RIGHT", -6, 0); t:SetWordWrap(false)
        lines[i] = { v = v, t = t }
    end

    -- your own notes, tips, chapters
    local inL = ui.text(rwin, 11, 1, 1, 1, 0.45); inL:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12)
    inL:SetText("Text for a hint, instruction, step or chapter")
    local input = editbox(rwin, RW - RP * 2, function() end)
    input:SetPoint("TOPLEFT", inL, "BOTTOMLEFT", 0, -6)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local function addWith(kind)
        return function()
            if ns.recorderAdd(kind, input:GetText()) then input:SetText(""); input.dirty = false; input:ClearFocus() end
        end
    end
    local b1 = button(rwin, "Add hint", bw, addWith("note"), "HINT: a line under the last recorded step (\"Unequip your shirt so you can sell it\").")
    b1:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -8)
    local b2 = button(rwin, "Add instruction", bw, addWith("tip"), "INSTRUCTION: something to keep doing (\"Don't sell the meat\"), shown in the INSTRUCTIONS card from here on - until the end of the chapter, or with a quest picked below until that quest is turned in. You can tick it off.")
    b2:SetPoint("LEFT", b1, "RIGHT", 6, 0)
    local b3 = button(rwin, "New chapter", bw, addWith("chapter"), "The next recorded step starts a chapter with this name. (A new zone starts one by itself.)")
    b3:SetPoint("LEFT", b2, "RIGHT", 6, 0)
    local b4 = button(rwin, "Add step", bw, addWith("step"), "A to-do step at your position with the text, like \"Kill the wolves on the way\".")
    b4:SetPoint("TOPLEFT", b1, "BOTTOMLEFT", 0, -6)
    local b5 = button(rwin, "Waypoint here", bw, addWith("waypoint"), "A travel step to where you stand (the text names it; empty = the area's name).")
    b5:SetPoint("LEFT", b4, "RIGHT", 6, 0)
    local b6 = button(rwin, "Level here", bw, addWith("xp"), "LEVEL: grind to here - a step that's done at the level and XP you have right now (11 2300xp), at your position. Press it when you're done grinding.")
    b6:SetPoint("LEFT", b5, "RIGHT", 6, 0)

    -- a quest from your log: what an instruction lasts for, and what goes ALONG THE WAY
    local bQ = button(rwin, "Quest: none", RW - RP * 2 - bw - 6, function() ns.recorderPickNext(IsShiftKeyDown and IsShiftKeyDown()) end,
        "Picks a quest from your log (click: next, Shift-click: back). An instruction added while one is picked lasts until it's turned in; Along the way uses it.")
    bQ:SetPoint("TOPLEFT", b4, "BOTTOMLEFT", 0, -6)
    local b7 = button(rwin, "Along the way", bw, addWith("along"), "ALONG THE WAY: the picked quest's objectives become a side objective from here on (\"Kill boars while you go\"), with live counts, until they're done. The text box adds a hint to it.")
    b7:SetPoint("LEFT", bQ, "RIGHT", 6, 0)
    local bUndo = button(rwin, "Undo last", bw, function() ns.recorderUndo() end, "Removes the last recorded step.")
    bUndo:SetPoint("TOPLEFT", bQ, "BOTTOMLEFT", 0, -12)
    local bOpen = button(rwin, "Follow it / edit it", RW - RP * 2 - bw - 6, function()
        local R = REC(); if not (R and R.id) then return end
        ns.switchRoute(R.id, true)
        if ns.openEditor then ns.openEditor() end
    end, "Switches this character to the recorded route and opens it in the route editor. Your old route is in the list button of the panel footer.")
    bOpen:SetPoint("LEFT", bUndo, "RIGHT", 6, 0)

    local hint = ui.text(rwin, 11, 1, 1, 1, 0.3)
    hint:SetPoint("TOPLEFT", bUndo, "BOTTOMLEFT", 0, -12); hint:SetWidth(RW - RP * 2); hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    hint:SetText("Recorded: quests you accept, finish, turn in and abandon (where, what you fought, the quest items you used), trainers and weapon masters, vendors, flight paths, flights, hearthstone and where you set it, dungeons, boats, zeppelins and the tram, death skips, and the way you walk to each step. A new zone starts a chapter.")

    recRefresh = function()
        if not rwin:IsShown() then return end
        local R, st = REC(), recState()
        local def = R and R.id and ItineraryDB.customRoutes and ItineraryDB.customRoutes[R.id]
        local ops = st and recOps() or {}
        local n = 0
        for _, op in ipairs(ops) do if op.k == "add" then n = n + 1 end end
        status:SetText(st == "on" and string.format("Recording  ·  %d steps", n)
            or st == "paused" and string.format("Paused  ·  %d steps", n)
            or "Not recording  ·  Record starts a new route")
        bRec.text:SetText(st == "paused" and "Resume" or (st == "on" and "Recording" or "Record"))
        bRec:SetActive(st == "on")
        bPause:SetActive(st == "paused")
        if not bStop.armed then bStop.text:SetText("Stop") end
        for _, b in ipairs({ bPause, bStop, b1, b2, b3, b4, b5, b6, b7, bQ, bOpen, bUndo }) do b:SetAlpha(st and 1 or 0.35) end
        local pq = R and R.pickQ
        bQ.text:SetText(pq and ("Quest: " .. (questName(pq) or pq)) or "Quest: none")
        nameE:SetShown(def and true or false)
        nameL:SetShown(def and true or false)
        if def and not nameE:HasFocus() then nameE:SetText(def.name or "") end
        if R and R.chapterNext then status:SetText(status:GetText() .. "  ·  next chapter: " .. R.chapterNext) end
        -- the last steps, newest on top, in recording order
        local order, byId = {}, {}
        for _, op in ipairs(ops) do if op.k == "add" then byId[op.id] = op end end
        local id = R and R.last
        while id and byId[id] and #order < 8 do
            order[#order + 1] = byId[id]
            id = tonumber(byId[id].after:match("^%+(%d+)$") or "")
        end
        for i, l in ipairs(lines) do
            local op = order[i]
            l.v:SetText(op and (op.s.along and (op.s.t == "complete" and "ALONG" or "INSTR") or (op.s.death and "DEATH") or (op.s.errand and "VENDOR")
                or VERB[kindOf(op.s)] or VERB[op.s.t] or op.s.t) or "")
            l.t:SetText(op and (label(op.s) .. (op.s.note and ("  |cff999999" .. op.s.note:gsub("\n", " ") .. "|r") or "")) or (i == 1 and st and "nothing yet" or ""))
            l.t:SetAlpha(op and 0.85 or 0.4)
        end
    end
    rwin:SetScript("OnShow", function() recRefresh() end)
    tinsert(UISpecialFrames, "ItineraryRecorderWindow")
    rwin:Hide()
end

-- "on", "paused" or nil: for the recording light in the panel footer
function ns.recorderState() return recState() end

function ns.openRecorder(toggle)
    if not rwin then
        if not (ItineraryDB and ns.ui) then return end
        buildRecorder()
    end
    if toggle and rwin:IsShown() then rwin:Hide() return end
    rwin:Show()
    rwin:Raise()
end


function ns.openEditor(toggle)
    if not win then
        if not (ItineraryDB and ns.ui) then return end
        build()
    end
    if toggle and win:IsShown() then win:Hide() return end
    win:Show()
    win:Raise()
    if not sel then scrollToCurrent() end
    refresh()
end
