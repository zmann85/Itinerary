-- Itinerary route editor (/iti edit, right-click on the route list button in the panel footer).
-- Your changes are a layer on top of a route (ItineraryDB.edits[routeId].ops): add a step, hide one, change
-- one. The generated routes stay as they are, so a rebuilt route keeps your edits. A step is found by what
-- it is ("accept:313:Grelin Whitebeard#1"), not by its number. Your own routes are the same layer on an
-- empty route (ItineraryDB.customRoutes).
local ADDON, ns = ...

---------------------------------------------------------------- the edit layer
-- every step type the route runs on, in two rows of the editor
local TYPES = { "accept", "complete", "turnin", "go", "do", "train", "xp", "fly", "fp", "hearth", "sethearth", "dungeon" }
local TYPE_TIP = {
    accept = "Accept: pick up the quests in Quest IDs from the NPC.",
    complete = "Quest: the quests' objectives (kill, loot, use an item). Mobs go on the target button.",
    turnin = "Turn in: hand in the quests in Quest IDs at the NPC.",
    go = "Go: travel to the step's point. Done when you get there.",
    ["do"] = "Do: anything else - the Text says what. Done when you have its Collect items, open its NPC as a vendor, get to its point, or skip it.",
    train = "Train: visit a trainer (NPC). A class trainer visit is done when nothing new is waiting.",
    xp = "XP: grind to the Level.",
    fly = "Fly: take a flight at the NPC (the flight master). Text = where to (\"Menethil Harbor\"): talking to the flight master takes that flight for you (Settings > Travel). Done when you're in the air or there.",
    fp = "Flight path: get the flight path at the NPC (the flight master). Text = the town (\"Menethil Harbor\"). Done when you learn it, or have it already.",
    hearth = "Hearth: use your hearthstone (it gets an item button). Text = where it takes you, your home inn (\"Stormwind City\"). Done when you cast it or are there.",
    sethearth = "Home: make an inn your home at the NPC (the innkeeper; the question is answered for you, Settings > Travel). Text = the place as the game names your home (\"Goldshire\"). Done when it's your home.",
    dungeon = "Dungeon: enter a dungeon (Text = its name; the step's point = the entrance). Done when you're inside.",
}

local function anchorKey(s)
    local what = s.q and table.concat(s.q, ",") or (s.name or s.lvl or "")
    return s.t .. ":" .. tostring(what) .. ":" .. (s.npc or "")
end
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end
-- the id the editor uses for a step: "+n" for one you added, its key for one from the route
local function sid(s) return s and (s.edAdd and ("+" .. s.edAdd) or s.edKey) end
ns.editId = sid

local function editsFor(id, create)
    ItineraryDB.edits = ItineraryDB.edits or {}
    local e = ItineraryDB.edits[id]
    if not e and create then e = { ops = {}, n = 0 }; ItineraryDB.edits[id] = e end
    return e
end

function ns.applyEdits(r, base, chapters)
    local id = ItineraryCharDB and ItineraryCharDB.route
    local seen = {}
    for _, s in ipairs(base) do
        local k = anchorKey(s)
        seen[k] = (seen[k] or 0) + 1
        s.edKey = k .. "#" .. seen[k]
    end
    local E = id and ItineraryDB.edits and ItineraryDB.edits[id]
    if not E or #E.ops == 0 then
        r.editList = base
        return base, chapters
    end
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
    if ItineraryDB.edits then ItineraryDB.edits[ItineraryCharDB.route] = nil end
    rebuild()
end

---------------------------------------------------------------- your own routes
local function registerCustom()
    for id, def in pairs(ItineraryDB.customRoutes or {}) do
        local src = def.from and ns.routes[def.from]
        if not ns.routes[id] then
            ns.routes[id] = { custom = true, from = src and def.from or nil, faction = def.faction,
                              chapters = src and (src.baseChapters or src.chapters) or {}, staticSteps = {} }
        end
        -- older copies were named after the long route names ("... 1-60 (RestedXP Forever + dungeons) (my copy)")
        if def.name then def.name = def.name:gsub(" %(RestedXP Forever %+ dungeons%)", "") end
        local r = ns.routes[id]
        -- a copy whose original comes in a route pack loaded after Itinerary: link it up now
        if src and not r.from and not r.built then
            r.from, r.chapters = def.from, src.baseChapters or src.chapters or {}
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
    ns.switchRoute(id, true)
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
    if ItineraryDB.edits then ItineraryDB.edits[id] = nil end
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
        if a1 == ADDON and ItineraryDB then migrateShippedEdits(); fixRecordedChapters(); registerCustom() end
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
        lastNpc = UnitName("npc") or lastNpc
    end
end)

---------------------------------------------------------------- window
local W, H, PAD = 900, 696, 16
local ROWS, ROW_H = 16, 20
local LIST_W = 360
local win, rows, sel, offset, refresh = nil, {}, nil, 0, nil
local chap = nil -- the chapter the list shows (0 = all steps)
local view = {}  -- the steps of that chapter
local fields = {}

local function U() return ns.ui end
local VERB = { accept = "ACCEPT", complete = "QUEST", turnin = "TURN IN", go = "GO", ["do"] = "DO", train = "TRAIN", xp = "XP",
               fly = "FLY", hearth = "HEARTH", sethearth = "HOME", fp = "FP", dungeon = "DUNGEON" }
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
    e:SetScript("OnEditFocusLost", function(self) if self.dirty then self.dirty = false; onCommit(self:GetText()) end end)
    e:SetScript("OnTextChanged", function(self, user) if user then self.dirty = true end end)
    return e
end

-- Shift-click an item (bags, chat link, loot) while the Items field is active: its ID goes in
local itemBox, colBox
if hooksecurefunc and HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", function(link)
    local box = (itemBox and itemBox:HasFocus() and itemBox) or (colBox and colBox:HasFocus() and colBox)
    if not (box and link and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id then return end
    local cur = box:GetText() or ""
    local n = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
    box:SetText(cur .. (cur:match("%S") and ", " or "") .. id .. (n and (" " .. n) or "") .. (box == colBox and " x1" or ""))
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
    win.nameEdit = editbox(win, 220, function(t) ns.renameCustomRoute(ItineraryCharDB.route, t) end)
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
        chap, offset = n, 0
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

    -- step list
    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -6)
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
        row:SetScript("OnClick", function(self) sel = self.id; refresh() end)
        rows[i] = row
    end
    win.list = list
    win.listInfo = ui.text(win, 11, 1, 1, 1, 0.35)
    win.listInfo:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -6)

    -- details of the selected step
    local d = CreateFrame("Frame", nil, win)
    d:SetPoint("TOPLEFT", list, "TOPRIGHT", 16, 0)
    d:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -PAD, 40)
    win.d = d
    d.head = ui.text(d, 12, 1, 1, 1, 0.55); d.head:SetPoint("TOPLEFT", 0, 0); d.head:SetPoint("RIGHT", 0, 0)
    d.types = {}
    local PER_ROW = 6
    local tw = math.floor((W - LIST_W - PAD * 2 - 16) / PER_ROW)
    for k, t in ipairs(TYPES) do
        local b = ui.segment(d, VERB[t])
        b.text:SetFont(ui.fontPath(), 11, "")
        b:SetSize(tw + 1, 22)
        b:SetPoint("TOPLEFT", d.head, "BOTTOMLEFT", ((k - 1) % PER_ROW) * tw, -8 - math.floor((k - 1) / PER_ROW) * 23)
        b.tip = TYPE_TIP[t]
        b:SetScript("OnClick", function()
            local s = selected()
            if not (s and s.t ~= t) then return end
            local set = { t = t }
            -- a new step's placeholder text becomes what the type needs: your home for a hearth, the place
            -- you stand for a flight path or a new home
            local blank = not s.name or s.name == "" or s.name == "New step"
            if blank and t == "hearth" then set.name = (GetBindLocation and GetBindLocation()) or false
            elseif blank and (t == "fp" or t == "sethearth") then
                local sub = GetSubZoneText and GetSubZoneText() or ""
                set.name = sub ~= "" and sub or ((GetZoneText and GetZoneText()) or false)
            elseif blank and (t == "fly" or t == "dungeon") then set.name = false end
            ns.editSet(sid(s), set)
            refresh()
        end)
        d.types[t] = b
    end
    local FW = W - LIST_W - PAD * 2 - 16
    local y = -87
    local function field(key, lbl, tip, get, set)
        local l = ui.text(d, 11, 1, 1, 1, 0.45); l:SetPoint("TOPLEFT", 0, y); l:SetText(lbl)
        local e = editbox(d, FW - 90, function(text) local s = selected(); if s then set(s, text); refresh() end end)
        e:SetPoint("TOPLEFT", 90, y + 5)
        e:SetScript("OnEnter", function() GameTooltip:SetOwner(e, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show() end)
        e:SetScript("OnLeave", function() GameTooltip:Hide() end)
        fields[key] = { box = e, get = get, label = l }
        if key == "item" then itemBox = e end
        if key == "col" then colBox = e end
        y = y - 30
    end
    field("name", "Text", "What the step says (travel and to-do steps). Quest steps show the quest's name. Fly: where to. Flight path: the town. Hearth: your home inn. Home: the inn's place. Dungeon: its name.",
        function(s) return s.name or "" end,
        function(s, t) ns.editSet(sid(s), { name = t ~= "" and t or false }) end)
    field("note", "Hint", "A hint: a line under the step (\"Unequip your shirt so you can sell it\").",
        function(s) return s.note or "" end,
        function(s, t) ns.editSet(sid(s), { note = t ~= "" and t or false }) end)
    field("q", "Quest IDs", "The quests of an accept / do / turn in step, comma separated (the ID is in the quest's Wowhead link).",
        function(s) return s.q and table.concat(s.q, ", ") or "" end,
        function(s, t)
            local q = numbers(t)
            local n = {}
            for k, id in ipairs(q) do n[k] = questName(id) end
            if #q > 0 then ns.editSet(sid(s), { q = q, n = n, qo = false, obj = false }) else ns.editSet(sid(s), { q = false, n = false }) end
        end)
    field("npc", "NPC", "Who to talk to (the target button targets them). \"Use target\" fills it in.",
        function(s) return s.npc or "" end,
        function(s, t) ns.editSet(sid(s), { npc = t ~= "" and t or false, targets = t ~= "" and { t } or false }) end)
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
    field("lvl", "Level", "For an XP step: 5 = reach level 5. 3 1200xp = 1200 XP into level 3. 3 50% = halfway through level 3. 4 -300xp = 300 XP or less before level 4.",
        function(s)
            if not s.lvl then return "" end
            local level, xpIn, xpPct, xpLeft = ns.xpTarget(s)
            if xpIn then return string.format("%d %dxp", level, xpIn) end
            if xpPct then return string.format("%d %d%%", level, xpPct) end
            if xpLeft then return string.format("%d -%dxp", level, xpLeft) end
            return tostring(level)
        end,
        function(s, t)
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

    d.posText = ui.text(d, 11, 1, 1, 1, 0.55); d.posText:SetPoint("TOPLEFT", 0, y); d.posText:SetPoint("RIGHT", 0, 0)
    y = y - 22
    local bw = math.floor((FW - 12) / 3)
    local function act(txt, col, row, fn, tip)
        local b = button(d, txt, bw, fn, tip)
        b:SetPoint("TOPLEFT", (col - 1) * (bw + 6), y - (row - 1) * 28)
        return b
    end
    d.setPos = act("My position", 1, 1, function()
        local s, p = selected(), here()
        if s and p then ns.editSet(sid(s), { m = p.m, x = p.x, y = p.y, z = p.z or false, wx = false, wy = false, path = false, way = false, wp = false, area = false }); refresh() end
    end, "Moves the step's point to where you stand.")
    d.useTarget = act("Use target", 2, 1, function()
        local s = selected()
        local n = UnitName("target")
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
    -- auction house steps (Settings > Quests > Auction house steps): left out when you play self-found;
    -- a self-found step is the other way round (only then)
    d.market = act("For everyone", 1, 4, function()
        local s = selected()
        if not s then return end
        if s.ah then ns.editSet(sid(s), { ah = false, ssf = true })
        elseif s.ssf then ns.editSet(sid(s), { ah = false, ssf = false })
        else ns.editSet(sid(s), { ah = true, ssf = false }) end
        refresh()
    end, "Who gets this step (click to switch). For everyone. Auction house: left out when Settings > Quests > Auction house steps is on Skip (self-found play). Self-found only: shown only then, e.g. buying a vendor item instead of the auction house one.")
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
        local list = {}
        for j, s in ipairs(all) do if chap == 0 or map[j] == chap then list[#list + 1] = s end end
        view = list
        local cname = chap == 0 and "All steps" or (chs[chap] and chs[chap].name or "")
        win.cb.name.text:SetText(chap == 0 and ("All steps  (" .. #all .. ")") or string.format("%d/%d  %s", chap, #chs, cname))
        win.cb.prev:SetAlpha(#chs > 0 and 1 or 0.35); win.cb.next:SetAlpha(#chs > 0 and 1 or 0.35)
        if win.chMenu:IsShown() then win.chMenu.refresh() end
        local custom = r and r.custom
        win.routeName:SetShown(not custom)
        win.nameEdit:SetShown(custom and true or false)
        if custom and not win.nameEdit:HasFocus() then win.nameEdit:SetText(r.name or "") end
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
                row.verb:SetText(VERB[s.t] or s.t)
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
        tb.recorder:SetActive(ns.recorderState and ns.recorderState() == "on" or false)
        tb.export:SetAlpha(custom and 1 or 0.35)

        local s = selected()
        win.d:SetShown(s ~= nil)
        if not s then return end
        local n = stepNumber(s)
        win.d.head:SetText((n and ("Step " .. n) or "Hidden step") .. "  ·  " ..
            (s.edAdd and "added by you" or s.edHidden and "hidden" or s.edChanged and "changed by you" or "from the route") ..
            (s.edOrphan and "  ·  its place in the route is gone, so it's at the end" or ""))
        for t, b in pairs(win.d.types) do b:SetActive(s.t == t) end
        for _, f in pairs(fields) do
            if not f.box:HasFocus() then f.box:SetText(f.get(s)) end
        end
        local qstep = s.t == "accept" or s.t == "turnin" or s.t == "complete"
        fields.q.box:SetAlpha(qstep and 1 or 0.4)
        fields.lvl.box:SetAlpha(s.t == "xp" and 1 or 0.4)
        fields.till.box:SetAlpha(s.along and 1 or 0.4)
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
    -- another route in the editor (picked here or in the panel): start at your step there
    ns.editorRouteChanged = function()
        if not win:IsShown() then return end
        offset, sel, chap = 0, nil, nil
        scrollToCurrent()
        refresh()
    end
    win:SetScript("OnShow", function() refresh() end)
    win:SetScript("OnHide", function() menu:Hide() end)
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
local function recAdd(s, noChapter)
    local R = REC()
    if not R then return end
    local ops, E = recOps()
    local zone = recZone()
    if not noChapter and zone ~= "" and zone ~= R.zone then
        s.chapter = zone .. " " .. (UnitLevel and UnitLevel("player") or "")
        s.chZone = zone
        R.zone = zone
    end
    if R.chapterNext then s.chapter, R.chapterNext = R.chapterNext, nil end
    E.n = E.n + 1
    ops[#ops + 1] = { k = "add", id = E.n, after = R.last and ("+" .. R.last) or "^", s = s }
    R.last, R.lastT = E.n, GetTime and GetTime() or 0
    if ItineraryCharDB.route == R.id then rebuild() end
    recUpdate()
    return E.n
end
local function recOn() return recState() == "on" end

local function npcName() return (UnitExists and UnitExists("npc") and UnitName("npc")) or lastNpc end
local function placed(s)
    local p = here()
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
                if p then P.pts[#P.pts + 1] = { p.m, p.x, p.y, p.z } end
                for name, t in pairs(recentMobs) do
                    if now - t < 45 then
                        local have = false
                        for _, x in ipairs(P.mobs) do if x == name then have = true end end
                        if not have and #P.mobs < 5 then P.mobs[#P.mobs + 1] = name end
                    end
                end
            end
        end
        if R.state == "on" and not P.emitted and #P.pts > 0 and ns.quest and ns.quest.ready(q) then
            P.emitted = true
            -- the middle of where you did it (points on the map you finished on)
            local last = P.pts[#P.pts]
            local sx, sy, n = 0, 0, 0
            for _, p in ipairs(P.pts) do if p[1] == last[1] then sx, sy, n = sx + p[2], sy + p[3], n + 1 end end
            -- the spots where the count went up, as the step's kill area (the arrow walks them as a loop, the
            -- map shows them): the ones on the map you finished on, thinned so they're at least a bit apart
            local wp = {}
            local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
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
            local s = { t = "complete", q = { q }, n = { questName(q) }, obj = #texts > 0 and texts or nil,
                        mobs = #P.mobs > 0 and P.mobs or nil, m = last[1],
                        x = r2(sx / n), y = r2(sy / n), z = last[4], wp = #wp >= 2 and wp or nil }
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

local rec = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_TARGET_CHANGED", "TRAINER_SHOW",
                     "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_SYSTEM", "QUEST_ACCEPTED",
                     "QUEST_TURNED_IN" }) do pcall(rec.RegisterEvent, rec, e) end
local scanQueued = false
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
        if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsPlayer("target") then
            recentMobs[UnitName("target")] = GetTime()
        end
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
        local npc = npcName()
        local op = recLastOp()
        if op and op.s.t == "train" and op.s.npc == npc then return end
        local trade = IsTradeskillTrainer and IsTradeskillTrainer()
        recAdd(placed({ t = "train", npc = npc, targets = npc and { npc } or nil, cls = (not trade) or nil,
                        name = trade and ("Train at " .. (npc or "the trainer")) or nil }))
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
        if a1 == "player" and a3 == 8690 then recAdd({ t = "hearth", name = bindLoc() or "Hearthstone" }, true) end
    elseif event == "CHAT_MSG_SYSTEM" then
        local b = bindLoc()
        if b and R.bind and b ~= R.bind then
            local npc = npcName()
            recAdd(placed({ t = "sethearth", name = b, npc = npc, targets = npc and { npc } or nil }))
        end
        R.bind = b or R.bind
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
        ns.print("recording into \"" .. ItineraryDB.customRoutes[id].name .. "\": quests, trainers, flights and hearthstone become steps")
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
    local RW, RH, RP = 380, 566, 14
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
    local b6 = button(rwin, "Undo last", bw, function() ns.recorderUndo() end, "Removes the last recorded step.")
    b6:SetPoint("LEFT", b5, "RIGHT", 6, 0)

    -- a quest from your log: what an instruction lasts for, and what goes ALONG THE WAY
    local bQ = button(rwin, "Quest: none", RW - RP * 2 - bw - 6, function() ns.recorderPickNext(IsShiftKeyDown and IsShiftKeyDown()) end,
        "Picks a quest from your log (click: next, Shift-click: back). An instruction added while one is picked lasts until it's turned in; Along the way uses it.")
    bQ:SetPoint("TOPLEFT", b4, "BOTTOMLEFT", 0, -6)
    local b7 = button(rwin, "Along the way", bw, addWith("along"), "ALONG THE WAY: the picked quest's objectives become a side objective from here on (\"Kill boars while you go\"), with live counts, until they're done. The text box adds a hint to it.")
    b7:SetPoint("LEFT", bQ, "RIGHT", 6, 0)
    local bOpen = button(rwin, "Follow it / edit it", RW - RP * 2, function()
        local R = REC(); if not (R and R.id) then return end
        ns.switchRoute(R.id, true)
        if ns.openEditor then ns.openEditor() end
    end, "Switches this character to the recorded route and opens it in the route editor. Your old route is in the list button of the panel footer.")
    bOpen:SetPoint("TOPLEFT", bQ, "BOTTOMLEFT", 0, -12)

    local hint = ui.text(rwin, 11, 1, 1, 1, 0.3)
    hint:SetPoint("TOPLEFT", bOpen, "BOTTOMLEFT", 0, -12); hint:SetWidth(RW - RP * 2); hint:SetWordWrap(true)
    hint:SetJustifyH("LEFT")
    hint:SetText("Recorded: quests you accept, finish and turn in (with where and what you fought), trainers, flight paths, flights, hearthstone and where you set it. A new zone starts a chapter.")

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
        for _, b in ipairs({ bPause, bStop, b1, b2, b3, b4, b5, b6, b7, bQ, bOpen }) do b:SetAlpha(st and 1 or 0.35) end
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
            l.v:SetText(op and (op.s.along and (op.s.t == "complete" and "ALONG" or "INSTR") or VERB[op.s.t] or op.s.t) or "")
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
