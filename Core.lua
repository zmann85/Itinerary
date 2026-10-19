-- Itinerary: follows a leveling route step by step.
-- Core: saved data, quest state helpers, the step engine and slash commands. UI.lua draws it.
local ADDON, ns = ...
ns.routes = ns.routes or {}
-- Route packs are addons of their own (Itinerary ships without routes): they add theirs through this
ItineraryAPI = ns
-- what a character follows when there's no route for it yet
ns.routes["none"] = { name = "No route", chapters = { { name = "No route", first = 1 } }, staticSteps = {
    { t = "do", name = "No route loaded",
      note = "Record your own (Editor > Recorder), import a route someone shared (Editor > Import), or install a route pack." } } }

local P = "|cff33ff99Itinerary|r "
function ns.print(msg) DEFAULT_CHAT_FRAME:AddMessage(P .. msg) end

---------------------------------------------------------------- color schemes
-- Settings > Panel > Color scheme. accent: bars, highlights, the arrow; warm: the INSTRUCTIONS card and
-- tooltip headers; hint: hint text under a step; bg / card / btn: window, instructions card and button
-- backgrounds; onAccent: text on an accent-coloured button. Applied when the UI loads (the setting reloads it).
ns.THEMES = {
    { key = "itinerary", name = "Itinerary", accent = { 0.05, 0.82, 0.62 }, warm = { 1, 0.82, 0.45 }, hint = "d9b26f",
      bg = { 0.077, 0.068, 0.058 }, card = { 0.11, 0.085, 0.05 }, btn = { 0.075, 0.113, 0.141 }, onAccent = { 0.05, 0.05, 0.05 },
      ellesmere = true },
    { key = "amethyst", name = "Amethyst", accent = { 0.47, 0.27, 0.76 }, warm = { 0.80, 0.72, 1 }, hint = "b9b0cc",
      bg = { 0.075, 0.07, 0.085 }, card = { 0.10, 0.085, 0.13 }, btn = { 0.15, 0.145, 0.16 }, onAccent = { 1, 1, 1 } },
    { key = "frost", name = "Frost", accent = { 0.30, 0.65, 1 }, warm = { 0.72, 0.87, 1 }, hint = "a9c4dc",
      bg = { 0.05, 0.065, 0.085 }, card = { 0.06, 0.09, 0.13 }, btn = { 0.075, 0.113, 0.141 }, onAccent = { 0.03, 0.05, 0.08 } },
    { key = "ember", name = "Ember", accent = { 1, 0.45, 0.15 }, warm = { 1, 0.78, 0.48 }, hint = "d9a070",
      bg = { 0.08, 0.06, 0.05 }, card = { 0.13, 0.08, 0.05 }, btn = { 0.15, 0.10, 0.08 }, onAccent = { 0.06, 0.03, 0.02 } },
    { key = "slate", name = "Slate", accent = { 0.86, 0.86, 0.86 }, warm = { 1, 1, 1 }, hint = "b4b4b4",
      bg = { 0.06, 0.06, 0.065 }, card = { 0.10, 0.10, 0.11 }, btn = { 0.14, 0.14, 0.15 }, onAccent = { 0.05, 0.05, 0.05 } },
}
local themeCache
function ns.theme()
    local key = ItineraryDB and ItineraryDB.panel and ItineraryDB.panel.scheme or "itinerary"
    if themeCache and themeCache.key == key then return themeCache end
    local t = ns.THEMES[1]
    for _, x in ipairs(ns.THEMES) do if x.key == key then t = x end end
    themeCache = t
    return t
end
-- the accent colour (the default scheme follows EllesmereUI's when it's installed)
function ns.accent()
    local t = ns.theme()
    if t.ellesmere then
        local g = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
        if g and g.r then return g.r, g.g, g.b end
    end
    return t.accent[1], t.accent[2], t.accent[3]
end
function ns.themeBg(a) local c = ns.theme().bg; return c[1], c[2], c[3], a end
function ns.themeCard(a) local c = ns.theme().card; return c[1], c[2], c[3], a end
function ns.themeBtn(a) local c = ns.theme().btn; return c[1], c[2], c[3], a end
function ns.hintHex() return "|cff" .. ns.theme().hint end
-- the warm colour as a table that always reads the current scheme: WARM[1], WARM[2], WARM[3]
ns.WARM = setmetatable({}, { __index = function(_, k) return ns.theme().warm[k] end })

---------------------------------------------------------------- saved data
-- ItineraryDB (account): panel/arrow position and look. ItineraryCharDB: route progress.
local function defaults()
    ItineraryDB = ItineraryDB or {}
    local g = ItineraryDB
    g.panel = g.panel or {}
    g.arrow = g.arrow or {}
    g.minimap = g.minimap or {}
    if g.panel.shown == nil then g.panel.shown = true end
    if g.panel.locked == nil then g.panel.locked = false end
    if g.arrow.shown == nil then g.arrow.shown = true end
    if g.arrow.locked == nil then g.arrow.locked = false end
    if g.nextCount == nil then g.nextCount = 3 end
    -- the shipped look (panel and arrow; positions keep their own defaults)
    local function def(t, k, v) if t[k] == nil then t[k] = v end end
    def(g.panel, "style", "card")
    def(g.panel, "alpha", 0.15)
    def(g.panel, "scale", 1.05)
    def(g.panel, "textEdge", "shadow")
    def(g.panel, "grow", "down")
    def(g.panel, "recCard", true)
    def(g.arrow, "instr", true)
    def(g.arrow, "deathInstr", true) -- death skips above the arrow even with the other instructions hidden
    def(g, "pinsWorld", 5) -- map pins: your next stops on the world map, on the minimap, the line between them
    def(g, "pinsMini", 5)
    def(g, "pinsLine", true)
    def(g.arrow, "instrSize", 14)

    ItineraryCharDB = ItineraryCharDB or {}
    local c = ItineraryCharDB
    c.step = c.step or 1
    c.manual = c.manual or {}   -- [stepIndex] = true: done by hand (skip) or by an event (flew, hearthed...)
    c.unavail = c.unavail or {} -- [stepIndex] = true: the quest giver doesn't offer these quests to you
    c.arrived = c.arrived or {} -- [stepIndex] = true: you reached the spot a travel step leads to ("at" for a death skip's place)
    c.unavailQ = c.unavailQ or {} -- [questID] = true: ...and the later steps for those quests don't apply
    c.levelAt = c.levelAt or {} -- [level] = /played seconds when this character reached it
    -- the old built-in Ghaan run now lives in your own routes: a character that followed it keeps following it
    if c.route == "ghaan-run2" and g.ghaanMovedTo then c.route = g.ghaanMovedTo end
    if ns.autoDefaults then ns.autoDefaults() end
end

-- Everything back to a first install: all settings, edits, own routes, and every character's progress
-- (other characters are wiped when they next log in). Reloads the UI. /iti factoryreset yes.
function ns.factoryReset()
    ItineraryDB = { epoch = time() }
    ItineraryCharDB = { epoch = ItineraryDB.epoch }
    ns.askReload("Everything is back to a first install.")
end

-- Forget everything about this character: route progress, trainer and profession data, picked route.
-- (Account-wide settings stay.) /iti wipe, or Settings > Quests > This character.

function ns.wipeCharacter(why)
    local guid = UnitGUID and UnitGUID("player")
    ItineraryCharDB = { epoch = ItineraryDB and ItineraryDB.epoch }
    defaults()
    ItineraryCharDB.guid = guid
    if ns.routes and next(ns.routes) and ns.pickRoute then
        ns.pickRoute()
        ns.prepareRoute(ns.route())
        if ns.advance then ns.advance() end
    end
    if ns.refresh then ns.refresh() end
    if ns.updateItems then ns.updateItems() end
    if ns.refreshSettings then ns.refreshSettings() end
    ns.print(why or "this character's route progress, trainer and profession data were wiped")
    -- ask for the professions again
    if ns.showProfPicker and C_Timer then C_Timer.After(1, ns.showProfPicker) end
end

---------------------------------------------------------------- quest state (modern API with fallbacks)
local turnedIn = {} -- quests turned in this session (the server flag can lag a moment behind the event)

local function flaggedDone(q)
    if turnedIn[q] then return true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(q) and true or false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(q) and true or false end
    return false
end
local function onQuest(q)
    -- two ways to ask; either one saying yes is enough
    if C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q) then return true end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID and (C_QuestLog.GetLogIndexForQuestID(q) or 0) > 0 then return true end
    return false
end
local function readyToTurnIn(q)
    if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(q) and true or false end
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(q) and true or false end
    return false
end
ns.quest = { flaggedDone = flaggedDone, onQuest = onQuest, ready = readyToTurnIn }

---------------------------------------------------------------- route pack options
-- A route pack can offer on/off choices of its own (shown in Settings > General under Route packs) and leave
-- steps of its routes out by them. Itinerary only shows the list, keeps your choices (per character) and asks
-- the pack's filter about each step when one of its routes is built; what a choice means is up to the pack.
--   ns.registerPackOptions(pack, { id = "dungeons", title = "Dungeons", text = "...",
--       items = { { key = "STOCKS", label = "The Stockade", tip = "...", default = true }, ... } })
--   ns.registerStepFilter(pack, function(step, on) return <keep the step?> end)   -- on(key) -> true/false
-- pack is the route pack's add-on folder name (its files get it as the first value of "...").
ns.packGroups = ns.packGroups or {}
ns.stepFilters = ns.stepFilters or {}
function ns.registerPackOptions(pack, spec)
    if type(pack) ~= "string" or type(spec) ~= "table" then return end
    local id = tostring(spec.id or spec.title or "options")
    local g = { pack = pack, id = id, title = spec.title or "Options", text = spec.text, items = {} }
    for _, it in ipairs(spec.items or {}) do
        if type(it) == "table" and it.key ~= nil then
            g.items[#g.items + 1] = { key = tostring(it.key), label = it.label or tostring(it.key), tip = it.tip,
                                      default = it.default and true or false }
        end
    end
    for i, o in ipairs(ns.packGroups) do
        if o.pack == pack and o.id == id then ns.packGroups[i] = g; return g end -- registered again: replaced
    end
    ns.packGroups[#ns.packGroups + 1] = g
    return g
end
function ns.registerStepFilter(pack, fn)
    if type(pack) == "string" and type(fn) == "function" then ns.stepFilters[pack] = fn end
end
local function packItem(pack, key)
    for _, g in ipairs(ns.packGroups) do
        if g.pack == pack then for _, it in ipairs(g.items) do if it.key == key then return it end end end
    end
end
function ns.packOption(pack, key)
    local mine = ItineraryCharDB and ItineraryCharDB.packOptions and ItineraryCharDB.packOptions[pack]
    if mine and mine[key] ~= nil then return mine[key] end
    local it = packItem(pack, key)
    return it and it.default or false
end
function ns.setPackOption(pack, key, on)
    if not ItineraryCharDB then return end
    on = on and true or false
    if ns.packOption(pack, key) == on then return end
    ItineraryCharDB.packOptions = ItineraryCharDB.packOptions or {}
    local mine = ItineraryCharDB.packOptions[pack] or {}
    ItineraryCharDB.packOptions[pack] = mine
    local it = packItem(pack, key)
    if it and it.default == on then mine[key] = nil else mine[key] = on end -- (the pack's default isn't stored)
    -- the route you follow was built with the old choice: building it again takes a reload (only for a choice
    -- the pack's filter asked about while building it - any other one leaves your route as it is)
    local r = ItineraryCharDB.route and ns.routes[ItineraryCharDB.route]
    local src = r and r.from and ns.routes[r.from] or r
    if src and src.pack == pack and src.base and ns.stepFilters[pack] and ns.askReload
       and (not src.packKeysUsed or src.packKeysUsed[tostring(key)]) then
        ns.askReload("Your route changes with that choice.")
    end
end
-- The choices of a pack your route depends on: the keys its filter asked about when your route was built (a
-- route of another pack, or your own, depends on none). nil: not known yet (the route isn't built).
function ns.packKeysOfRoute(pack)
    local c = ItineraryCharDB
    local r = c and c.route and ns.routes[c.route]
    if not r then return nil end
    local src = r.from and ns.routes[r.from] or r
    if src.pack ~= pack then return {} end
    return src.base and src.packKeysUsed or nil
end
-- the groups of the installed packs, in your pack order
function ns.packOptionGroups()
    local out = {}
    for _, p in ipairs(ns.packList and ns.packList() or {}) do
        for _, g in ipairs(ns.packGroups) do
            if g.pack == p.name and #g.items > 0 then out[#out + 1] = { group = g, packTitle = p.title } end
        end
    end
    return out
end
-- a pack route's steps after its pack's filter; the along-the-way steps and chapters that pointed at a step
-- that's left out move on to the next one kept (a chapter with nothing left goes)
function ns.filterPackSteps(r, steps)
    local f = r and r.pack and ns.stepFilters[r.pack]
    if not f or not steps or #steps == 0 then return steps end
    local pack = r.pack
    -- (which choices the filter asks about: the ones this route depends on, given the others)
    local used = {}
    r.packKeysUsed = used
    local function on(key) key = tostring(key); used[key] = true; return ns.packOption(pack, key) end
    local keep, at = {}, {}
    for i, s in ipairs(steps) do
        at[i] = #keep + 1
        local ok, res = pcall(f, s, on)
        if not ok or res ~= false then keep[#keep + 1] = s end -- (a filter error keeps the step)
    end
    -- chapters can carry the pack's marks too: the filter decides about them like about a step (a pack with
    -- two versions of a stretch gives each its own chapters)
    local chs = r.chapters
    local chOut = {}
    for k, c in ipairs(chs or {}) do
        local ok, res = pcall(f, c, on)
        if ok and res == false then chOut[k] = true end
    end
    if #keep == #steps and not next(chOut) then return steps end
    local n = #keep
    for _, s in ipairs(keep) do
        if s.till then s.till = math.min(at[s.till] or n, n) end
    end
    if chs and #chs > 0 then
        local out = {}
        for k, c in ipairs(chs) do
            local first = at[c.first or 1] or (n + 1)
            if first <= n and not chOut[k] then
                c.first = first
                if out[#out] and out[#out].first == first then out[#out] = c else out[#out + 1] = c end
            end
        end
        if #out == 0 then out[1] = chs[1]; out[1].first = 1 end
        out[1].first = 1
        for k = #chs, 1, -1 do chs[k] = nil end -- the same table (copies of the route share it)
        for k, c in ipairs(out) do chs[k] = c end
    end
    return keep
end

---------------------------------------------------------------- route + steps
-- A pooled route ("seq" over its faction's step pool): "a" = pool entry a, "a-n" = n entries from a,
-- "a+d" = entry a running along until d steps later. Each step is its own copy (the same pool entry can
-- show up twice in one route).
local function decodeRoute(r)
    local poolFn = ns.pools and ns.pools[r.pool]
    if not poolFn then return nil end
    local pool, steps = poolFn(), {}
    local function add(k, d)
        local src, s = pool[k], {}
        if not src then return end
        for f, v in pairs(src) do s[f] = v end
        steps[#steps + 1] = s
        if d then s.till = #steps + d end
    end
    for tok in r.seq:gmatch("%S+") do
        local a, n = tok:match("^(%d+)%-(%d+)$")
        if a then
            for k = tonumber(a), tonumber(a) + tonumber(n) - 1 do add(k) end
        else
            local b, d = tok:match("^(%d+)%+(%d+)$")
            if b then add(tonumber(b), tonumber(d)) else add(tonumber(tok)) end
        end
    end
    return steps
end
ns.decodeRoute = decodeRoute

-- Memory: the route you use is built once (r.base); after that the faction's step pool and the other
-- routes' step lists are let go. Switching to another generated route therefore reloads the UI.
local function releasePools(keep)
    for _, rr in pairs(ns.routes) do
        if rr ~= keep and rr.seq then rr.seq = nil; rr.needsReload = true end
    end
    if ns.pools then for k in pairs(ns.pools) do ns.pools[k] = nil end end
    collectgarbage("collect")
end

-- A reload only works from a click on a button the game trusts (a reload started by an addon on its own,
-- or a moment after a click, is silently ignored): ask with the game's own popup, whose button does it.
if StaticPopupDialogs then
    StaticPopupDialogs["ITINERARY_RELOAD"] = {
        text = "Itinerary: %s|nThis needs a quick reload of the interface.",
        button1 = "Reload now", button2 = "Not now",
        OnAccept = function(self, data) if data and data.before then data.before() end; ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end
function ns.askReload(why, before)
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.ITINERARY_RELOAD then
        StaticPopup_Show("ITINERARY_RELOAD", why, nil, { before = before })
        ns.print(why .. " Reload the interface to finish it (the popup, or /reload).")
    else
        if before then before() end
        ReloadUI()
    end
end

-- The route's own steps (built once; your edits from the editor go on top without changing them)
local baseSteps
baseSteps = function(r)
    if not r.base and r.needsReload then
        -- its steps were let go when another route was built: load them with a reload
        if not ns.reloadAsked then
            ns.reloadAsked = true
            ns.askReload("This character's route isn't loaded yet.")
        end
        return {}
    end
    if not r.base and r.from and ns.routes[r.from] then
        -- your copy of a route: its steps are the original's (built once, shared), your edits go on top
        local src = ns.routes[r.from]
        local b = baseSteps(src)
        if src.base then r.base = b end
        return b
    end
    if not r.base then
        if r.seq then r.base = decodeRoute(r) or {}; releasePools(r)
        elseif r.stepsFn then r.base = r.stepsFn(); r.stepsFn = nil
        else r.base = r.staticSteps or {} end
        r.base = ns.filterPackSteps(r, r.base)
        for _, s in ipairs(r.base) do s.till0 = s.till end
    end
    for _, s in ipairs(r.base) do s.till = s.till0 end
    return r.base
end

function ns.route()
    local r = ItineraryCharDB and ns.routes[ItineraryCharDB.route]
    if not r then return nil end
    -- big generated routes build their step list on first use (only the route this character follows)
    if r.steps and not r.built then r.staticSteps, r.steps = r.steps, nil end
    if not r.steps then
        r.baseChapters = r.baseChapters or r.chapters or {}
        local steps, chapters = baseSteps(r), r.baseChapters
        if ns.applyEdits then steps, chapters = ns.applyEdits(r, steps, chapters) end
        r.steps, r.chapters, r.built = steps, chapters, true
    end
    return r
end

-- switch this character to another route (a reload when its steps aren't in memory any more)
function ns.switchRoute(id, chosen)
    local c, r = ItineraryCharDB, ns.routes[id]
    if not r then return false end
    local src = r.from and ns.routes[r.from]
    local function take()
        c.routeChosen = chosen and true or c.routeChosen
        c.parked, c.gates = nil, nil -- you picked another route: a missing one isn't brought back over it
        c.route, c.step, c.manual, c.unavail, c.unavailQ, c.arrived = id, 1, {}, {}, {}, {}
        c.routeSig = nil
    end
    if (r.needsReload and not r.base) or (src and src.needsReload and not src.base) then
        -- the route you're on stays until the reload actually happens (nothing breaks if you say "Not now")
        local reopen = ItineraryEditorWindow and ItineraryEditorWindow:IsShown()
        ns.askReload("Switching to " .. (r.name or id) .. (r.version and (" " .. r.version) or "") .. ".", function()
            take()
            if reopen then ItineraryDB.reopenEditor = true end
        end)
        return true
    end
    take()
    ns.prepareRoute(ns.route())
    ns.advance()
    if ns.refresh then ns.refresh() end
    if ns.editorRouteChanged then ns.editorRouteChanged() end
    return true
end

-- after an edit: build the route again and stay on the same step
function ns.rebuildRoute()
    local c, r = ItineraryCharDB, ns.route()
    if not r then return end
    local function id(s) return s and (s.edAdd and ("+" .. s.edAdd) or s.edKey) end
    local cur = id(r.steps[c.step])
    -- per-step notes (done by hand, not available, arrived) follow their step, not its number
    local keep = {}
    for _, f in ipairs({ "manual", "unavail", "arrived" }) do
        keep[f] = {}
        for i, v in pairs(c[f] or {}) do local k = id(r.steps[i]); if k then keep[f][k] = v end end
    end
    r.steps, r.prepared = nil, nil
    r = ns.route()
    ns.prepareRoute(r)
    local pos = {}
    for j, s in ipairs(r.steps) do local k = id(s); if k and not pos[k] then pos[k] = j end end
    if cur and pos[cur] then c.step = pos[cur] end
    for f, t in pairs(keep) do
        c[f] = {}
        for k, v in pairs(t) do if pos[k] then c[f][pos[k]] = v end end
    end
    if c.step > #r.steps + 1 then c.step = #r.steps + 1 end
    if ns.refresh then ns.refresh() end
    if ns.update then ns.update() end
end

-- Pick the route made for this race/class once per character (or when the saved one is gone).
-- How well a route fits this character: its starting zone (race) matters most, then the class.
-- 0 = made for another starting zone.
local function routeFit(r, race, class)
    local m = r and r.match
    if not m then return 0 end
    if r.faction and UnitFactionGroup then
        local f = UnitFactionGroup("player")
        if (f == "Alliance" or f == "Horde") and f ~= r.faction then return 0 end
    end
    local races = type(m.race) == "table" and m.race or { m.race }
    local raceOk = not m.race
    for _, x in ipairs(races) do if x == race then raceOk = true end end
    -- a race no route knows (a new one): the faction's catch-all start (Skyborne) is the best guess
    if not raceOk then return (r.fallback and r.faction and m.class == class) and 1 or 0 end
    return 2 + ((not m.class or m.class == class) and 1 or 0)
end
ns.routeFit = routeFit

-- route versions: numbered ones (vn = 1, 2, ...) by number, anything else by its label
function ns.versionCompare(a, b)
    local x, y = a.vn, b.vn
    if x and y then return x == y and 0 or (x > y and 1 or -1) end
    if x or y then return x and 1 or -1 end
    local p, q = a.version or "", b.version or ""
    return p == q and 0 or (p > q and 1 or -1)
end

---------------------------------------------------------------- which route a new character gets
-- Route packs: each route remembers the add-on it came from (tagged when that add-on has loaded), and you
-- put the installed packs in an order (Settings > General > Route packs). A pack seen for the first time
-- goes to the bottom, so installing another pack never changes what new characters get.
local function tagPack(name)
    if not (ns.routes and name) then return end
    local seen = false
    for id, r in pairs(ns.routes) do
        if not r.custom and id ~= "none" and not r.pack then r.pack = name end
        if r.pack == name and not r.custom then seen = true end
    end
    if seen and ItineraryDB then
        ItineraryDB.packOrder = ItineraryDB.packOrder or {}
        for _, n in ipairs(ItineraryDB.packOrder) do if n == name then return end end
        table.insert(ItineraryDB.packOrder, name)
    end
end
ns.tagPack = tagPack

local function packRank(r)
    if r.custom then return 100000 end -- your own routes: after every pack (unless you made one the default)
    if not r.pack then return 99999 end
    for i, n in ipairs(ItineraryDB and ItineraryDB.packOrder or {}) do if n == r.pack then return i end end
    return 99998
end

-- the installed route packs in your order: { { name, title, routes }, ... }
function ns.packList()
    local counts = {}
    for _, r in pairs(ns.routes or {}) do if r.pack and not r.custom then counts[r.pack] = (counts[r.pack] or 0) + 1 end end
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local out = {}
    for _, name in ipairs(ItineraryDB and ItineraryDB.packOrder or {}) do
        if counts[name] then
            local title = meta and meta(name, "Title") or nil
            out[#out + 1] = { name = name, title = (title and title ~= "") and title or name, routes = counts[name] }
        end
    end
    return out
end
-- move an installed pack one place up (d = -1) or down (1) among the installed ones
function ns.movePack(name, d)
    local order = ItineraryDB and ItineraryDB.packOrder
    if not order then return end
    local installed, pos = {}, nil
    local have = {}
    for _, p in ipairs(ns.packList()) do have[p.name] = true end
    for i, n in ipairs(order) do
        if have[n] then
            installed[#installed + 1] = i
            if n == name then pos = #installed end
        end
    end
    local other = pos and installed[pos + d]
    if not other then return end
    local i = installed[pos]
    order[i], order[other] = order[other], order[i]
end

-- Your default route for a race and class (account-wide), set in the route list: a pack route counts for
-- that route's line in any version (the newest one is used), your own route as it is
local function baseRouteId(id) return id and (id:gsub("@.*$", "")) end
function ns.charRouteKey()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    return (race or "?") .. ":" .. (class or "?")
end
function ns.isRouteDefault(id)
    local d = ItineraryDB and ItineraryDB.routeDefault and ItineraryDB.routeDefault[ns.charRouteKey()]
    if not (d and id) then return false end
    if type(d) == "table" then
        if d.id then return d.id == id end
        local r = ns.routes[id]
        return d.line ~= nil and not (r and r.custom) and baseRouteId(id) == d.line
    end
    return d == id or d == baseRouteId(id) -- (saved by the first version of this)
end
-- the newest version of a pack route's line marks the line (later versions take over); an older version
-- marks just that one; your own route itself
function ns.setRouteDefault(id)
    ItineraryDB.routeDefault = ItineraryDB.routeDefault or {}
    local key = ns.charRouteKey()
    if not id then ItineraryDB.routeDefault[key] = nil return end
    local r = ns.routes[id]
    if not r or r.custom then ItineraryDB.routeDefault[key] = { id = id } return end
    local base, newest = baseRouteId(id), id
    for oid, o in pairs(ns.routes) do
        if not o.custom and baseRouteId(oid) == base and ns.versionCompare(o, ns.routes[newest]) > 0 then newest = oid end
    end
    ItineraryDB.routeDefault[key] = (newest == id) and { line = base } or { id = id }
end
-- the route your default stands for right now (one route, also when it marks a line of versions)
function ns.defaultRouteId()
    local best
    local myFaction = UnitFactionGroup and UnitFactionGroup("player")
    for id, r in pairs(ns.routes) do
        if ns.isRouteDefault(id) and not (r.faction and myFaction and r.faction ~= myFaction) then
            if not best or ns.routeOrder(r, ns.routes[best], id, best) > 0 then best = id end
        end
    end
    return best
end

-- The order of routes that fit a character equally well (same starting zone, same class): your default
-- for this race and class first, then the route packs in your order, within a pack its own `priority`
-- (higher first). Without priorities the built-in order: full generated routes before hand-made partial
-- ones (a reference run), the normal route before a variant (the crowded start), the newest version, then
-- the id. > 0: a goes first.
function ns.routeOrder(a, b, ida, idb)
    if ida and idb then
        local da, db = ns.isRouteDefault(ida), ns.isRouteDefault(idb)
        if da ~= db then return da and 1 or -1 end
    end
    local ka, kb = packRank(a), packRank(b)
    if ka ~= kb then return ka < kb and 1 or -1 end
    local pa, pb = a.priority or 0, b.priority or 0
    if pa ~= pb then return pa > pb and 1 or -1 end
    local ga, gb = (a.pool or a.seq) and 1 or 0, (b.pool or b.seq) and 1 or 0
    if ga ~= gb then return ga > gb and 1 or -1 end
    local va, vb = a.variant and 0 or 1, b.variant and 0 or 1
    if va ~= vb then return va > vb and 1 or -1 end
    local vc = ns.versionCompare(a, b)
    if vc ~= 0 then return vc end
    if ida and idb and ida ~= idb then return ida < idb and 1 or -1 end
    return 0
end

function ns.pickRoute()
    local c = ItineraryCharDB
    -- your own routes, now that every route pack is loaded too (copies of a pack's route need it)
    if ns.registerCustomRoutes then ns.registerCustomRoutes() end
    -- the route this character was on comes from a route pack that is back: go on where you were
    if c.parked and ns.routes[c.parked.route] then
        local p = c.parked
        c.route, c.step, c.manual, c.unavail, c.unavailQ, c.arrived = p.route, p.step, p.manual or {}, p.unavail or {}, p.unavailQ or {}, p.arrived or {}
        c.parked = nil
        ns.print("route pack found: back on " .. (ns.routes[c.route].name or c.route) .. " at step " .. (c.step or 1))
    end
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local best, bestFit = nil, 0
    -- a route that isn't loaded (its route pack is missing): keep where you were on it for when it's back
    if c.route and c.route ~= "none" and not ns.routes[c.route] and not c.parked then
        c.parked = { route = c.route, step = c.step, manual = c.manual, unavail = c.unavail, unavailQ = c.unavailQ, arrived = c.arrived }
        local route = c.route
        C_Timer.After(5, function()
            ns.print("your route (" .. route .. ") isn't installed - it comes in a route pack. Your place on it is kept for when it's back.")
        end)
    end
    local myFaction = UnitFactionGroup and UnitFactionGroup("player")
    for id, r in pairs(ns.routes) do
        -- how well it fits decides first (the add-on's call); among equally fitting routes the order above
        local f = routeFit(r, race, class)
        -- the route you made the default for this race and class wins (any of your faction's)
        if ns.isRouteDefault(id) and not (r.faction and myFaction and r.faction ~= myFaction) then f = 4 end
        if f > 0 and (f > bestFit or (f == bestFit and best and ns.routeOrder(r, ns.routes[best], id, best) > 0)) then
            best, bestFit = id, f
        end
    end
    local cur = ns.routes[c.route or ""]
    -- a new character, or one sitting on a route for another starting zone (unless you chose it with /iti route)
    local wrong = cur and best and not c.routeChosen and routeFit(cur, race, class) == 0
    if best and (not c.picked or wrong or not cur) and c.route ~= best and not c.parked then
        c.route, c.step, c.manual, c.unavail, c.unavailQ, c.arrived = best, 1, {}, {}, {}, {}
        local r = ns.routes[best]
        ns.print("using the route for your character: " .. (r.name or best) .. (bestFit == 4 and " (your default for this race and class)" or ""))
        if math.floor(bestFit) == 2 then
            local _, loc = UnitClass("player")
            ns.print("no route for " .. (loc or class) .. " yet: class quests and trainer visits on it are for "
                .. ((r.match and r.match.class) or "another class") .. " and are left out where the route knows they don't apply")
        end
    end
    c.picked = true
    if not ns.routes[c.route or ""] then
        c.route = best or "none"
        c.step, c.manual, c.unavail, c.unavailQ, c.arrived = 1, {}, {}, {}, {}
    end
end

-- Some routes store positions as world coordinates (wx/wy); turn them into zone coordinates once the map
-- data is there.
function ns.trainerAsRec()
    return not (ItineraryDB and ItineraryDB.auto and ItineraryDB.auto.trainerSteps == "step")
end

function ns.prepareRoute(r)
    if not r or r.prepared then return end
    -- "Sell junk" steps: any vendor will do, so they're a recommendation next to the next few steps
    -- (done when you open a vendor) instead of a stop the arrow walks you to
    -- trainer visits (Settings > Trainer): a recommendation next to the next steps, done when you've trained,
    -- instead of a stop the arrow walks you to
    local trainRec = ns.trainerAsRec()
    -- errands at a vendor ("Vendor trash" at Rallic Finn, "Buy Ice Cold Milk" at the Thelsamar inn, food, water,
    -- bags, repairs): an instruction next to the next few steps that you can click to point the arrow at that
    -- vendor, done when you open them - not a stop of their own. So is every optional buy ("Buy a Wooden Mallet
    -- if you can afford it", quest items for later, potions if in stock, the auction house's "buy these for quicker
    -- turn-ins"): done once you have the items or when you close that vendor / the auction house. Buying what
    -- the route needs (not optional) and a hunter's arrows stay a step.
    local function ammo(n)
        local l = n:lower()
        return l:find("arrow") or l:find("shot") or l:find("ammo") or l:find("quiver")
    end
    local function optionalBuy(s)
        if s.t ~= "do" or not s.opt or s.item or s.death or s.untilQ or s.abandon or s.vendor then return false end
        local n = s.name or ""
        if not (n:find("^Buy ") or n:find("^Stock up")) or ammo(n) then return false end
        local auction = s.ah or (s.npc and s.npc:find("^Auctioneer")) or false
        if not (s.npc or auction) then return false end
        return true, (s.col or s.need or auction) and true or false
    end
    local function errand(s)
        local buy, onClose = optionalBuy(s)
        if buy then s.errandBuy = onClose or nil; return true end
        if s.t ~= "do" or not s.npc or s.col or s.need or s.ah or s.item or s.death or s.untilQ or s.abandon or s.vendor then return false end
        if s.errand then return true end -- (marked as one: the recorder's food, drink and bags)
        local n = s.name or ""
        if n:find("^Vendor") or n:find("^Sell ") or n:find("^Repair ") then return true end
        if n:find("^Buy ") or n:find("^Stock up") then
            local l = n:lower()
            if ammo(n) then return false end -- (a hunter's ammo stays a stop)
            for _, w in ipairs({ "food", "water", "milk", "bread", "dalaran sharp", "mushroom", "pouch", "satchel" }) do
                if l:find(w, 1, true) then return true end
            end
        end
        return false
    end
    -- a "class trainer" stop at someone known as a profession trainer is a profession stop: the guides train
    -- a first aid recipe on a class-only step (Mary Edras in Undercity, for paladins), and the trainer
    -- instruction then sent you there for your class skills
    local _, myClass = UnitClass("player")
    local function profNotClass(s)
        if not (s.t == "train" and s.cls and s.npc and ns.profOfNpc and ns.profOfNpc(s.npc)) then return false end
        local rec = ItineraryDB and ItineraryDB.trainers and ItineraryDB.trainers[myClass]
        local data = ns.DATA_CLASS_TRAINERS and ns.DATA_CLASS_TRAINERS[myClass]
        return not ((rec and rec[s.npc]) or (data and data[s.npc]))
    end
    for j, s in ipairs(r.steps) do
        -- (a quest step made in the editor before its quest IDs are in: an empty list, not none)
        if (s.t == "accept" or s.t == "complete" or s.t == "turnin") and not s.q then s.q = {} end
        if profNotClass(s) then s.cls = nil end
        if s.vendor then
            s.along, s.till, s.rec = true, j + 6, true
            s.note = "At any vendor you pass - the grey items are sold when you open one"
        elseif errand(s) then
            s.errand = true
            -- (a guide's along-the-way errand without an end - "Vendor trash" until you sell - would stay with you
            -- across the world: next to the next few steps, like the others)
            if not s.along then s.along, s.till, s.rec = true, j + 6, true
            elseif not s.till then s.till, s.rec = j + 6, true end
        elseif trainRec and s.t == "train" and not s.along then
            s.along, s.till, s.rec, s.trainRec = true, j + 8, true, true
        elseif not trainRec and s.trainRec then
            s.along, s.till, s.rec, s.trainRec = nil, s.till0, nil, nil -- back to a step of its own
        end
    end
    -- death skips ("die and respawn at the spirit healer") are always an instruction next to the steps after
    -- them, never a stop of their own: after the respawn the arrow leads on to the next step anyway. Routes
    -- write most of them that way (along the way until the next step), some as a step of their own. It lasts
    -- until the next step that is always there - a conditional one may not be (a walking alternative that is
    -- only for low levels) - at most 8 steps past the next stop. With a place to die at, it still leads the
    -- arrow there first.
    local steps = r.steps
    -- (what can leave a step out for you; "skip while in Ironforge" and optional steps still show)
    local COND = { "cond", "lvskip", "gateL", "need", "needProf", "skill", "skill2", "money", "dps", "ah", "ssf", "buffItem" }
    local function conditional(x)
        for _, f in ipairs(COND) do if x[f] ~= nil then return true end end
        return false
    end
    local function ownStep(x) return x.death and (x.deathRec or not x.along) end
    for j, s in ipairs(steps) do
        if ownStep(s) then
            local k, first = j + 1, nil
            while steps[k] do
                local x = steps[k]
                if not x.along and not ownStep(x) then
                    first = first or k
                    if not conditional(x) or k >= first + 8 then break end
                end
                k = k + 1
            end
            s.along, s.deathRec, s.till = true, true, math.min(k, #steps)
        end
    end
    -- a hearth the guide skips in the very zone you're in when you get to it, while the route goes on somewhere
    -- else ("Hearth to Stormwind" after the last Darkshore turn-ins, skipped "in Darkshore"): a slip in the
    -- guide that would leave you without the way there. That zone no longer skips it (already being where the
    -- hearth takes you still does).
    local function zoneFrom(k, dir)
        while steps[k] do
            local x = steps[k]
            if not x.along and x.z and x.z ~= "" then return x.z end
            k = k + dir
        end
    end
    for j, s in ipairs(steps) do
        if s.t == "hearth" and s.zskip then
            local before, after = zoneFrom(j - 1, -1), zoneFrom(j + 1, 1)
            if before and before ~= after then
                local keep = {}
                for _, z in ipairs(s.zskip) do
                    if not (z.zone == before and not z.inv) then keep[#keep + 1] = z end
                end
                if #keep < #s.zskip then s.zskip = #keep > 0 and keep or nil end
            end
        end
    end
    -- "Abandon X" for a quest the route still hands in later ("if it's done by then"): with X ready to hand in,
    -- there's nothing to abandon (the quests handed in after each abandon step)
    local turnedLater = {}
    for j = #steps, 1, -1 do
        local s = steps[j]
        if s.abandon then
            s.keepIfReady = nil
            for _, q in ipairs(s.abandon) do
                if turnedLater[q] then s.keepIfReady = s.keepIfReady or {}; s.keepIfReady[q] = true end
            end
        end
        if s.t == "turnin" and s.q then for _, q in ipairs(s.q) do turnedLater[q] = true end end
    end

    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if not HBD then return end
    for _, s in ipairs(r.steps) do
        if s.wx and s.m and not s.x then
            local x, y = HBD:GetZoneCoordinatesFromWorld(s.wx, s.wy, s.m, true)
            if x and y then s.x, s.y = x * 100, y * 100 end
        end
        -- the way to the target: { {map, x, y, radius}, ... } in zone coordinates
        if s.path and not s.way then
            local way = {}
            for _, p in ipairs(s.path) do
                local m, a, b = p[1], p[2], p[3]
                if p[4] == 1 then
                    local x, y = HBD:GetZoneCoordinatesFromWorld(a, b, m, true)
                    if x and y then way[#way + 1] = { m, x * 100, y * 100, p[5] or 0 } end
                else
                    way[#way + 1] = { m, a, b, p[5] or 0 }
                end
            end
            if #way >= 1 then s.way = way end
        end
        -- the area to walk for kill/loot steps: { {map, x, y}, ... } in zone coordinates
        if s.wp and not s.area then
            local area = {}
            for _, p in ipairs(s.wp) do
                local m, a, b = p[1], p[2], p[3]
                if p[4] == 1 then
                    local x, y = HBD:GetZoneCoordinatesFromWorld(a, b, m, true)
                    if x and y then area[#area + 1] = { m, x * 100, y * 100 } end
                else
                    area[#area + 1] = { m, a, b }
                end
            end
            if #area >= 2 then s.area = area end
        end
    end
    r.prepared = true
end
function ns.steps() local r = ns.route(); return r and r.steps or {} end

-- chapters: { name, first } from the route; a step belongs to the last chapter starting at or before it
function ns.chapters() local r = ns.route(); return r and r.chapters or {} end
function ns.chapterOf(i)
    local ch, idx = nil, nil
    for n, c in ipairs(ns.chapters()) do if c.first <= i then ch, idx = c, n else break end end
    if not ch then return nil end
    local nxt = ns.chapters()[idx + 1]
    local last = nxt and (nxt.first - 1) or #ns.steps()
    return idx, ch, ch.first, last
end
function ns.gotoChapter(n)
    local c = ns.chapters()[n]
    if not c then return end
    ItineraryCharDB.step = c.first
    ns.advance()
    if ns.refresh then ns.refresh() end
end

local QUEST_STEP = { accept = true, complete = true, turnin = true }
ns.QUEST_STEP = QUEST_STEP

-- quest steps you skipped by hand whose quests still aren't done (worth going back for)
local EMPTY = {}
-- What the list needs from a route's steps, worked out once per step list (it changes only when the route is
-- built again): the last turn-in of each quest, and the turn-ins that are a quest's last one (an earlier one
-- of the same quest never counts: the route still hands it in later).
local skipIndex = setmetatable({}, { __mode = "k" })
local function skipInfo(steps)
    local e = skipIndex[steps]
    if e and e.n == #steps then return e end
    local last, list = {}, {}
    for j = 1, #steps do
        local t = steps[j]
        if t.t == "turnin" and t.q then for _, x in ipairs(t.q) do last[x] = j end end
    end
    for j = 1, #steps do
        local t = steps[j]
        if t.t == "turnin" and t.q then
            -- (a turn-in "only if it's done by now" that wasn't isn't worth going back for)
            local ifReady = false
            if t.cond then for _, cd in ipairs(t.cond) do if cd[1] == "ready" then ifReady = true end end end
            if not ifReady then
                for k, x in ipairs(t.q) do if last[x] == j then list[#list + 1] = { j, k, x } end end
            end
        end
    end
    e = { n = #steps, last = last, list = list }
    skipIndex[steps] = e
    return e
end
local doneSeen = {} -- quests the server has said are done (that doesn't change back)
function ns.skippedBehind()
    local out, c, steps = {}, ItineraryCharDB, ns.steps()
    local n = math.min(c.step - 1, #steps)
    local info = skipInfo(steps)
    -- what may go on the list, in route order: quest steps behind you that you skipped by hand, and turn-ins
    -- behind you for quests that are ready in your log and not handed in later on the route either (passed
    -- while the route thought they were done)
    local cand = {}
    for i in pairs(c.manual) do
        local s = type(i) == "number" and i <= n and steps[i]
        if s and QUEST_STEP[s.t] and s.q then
            for k, q in ipairs(s.q) do if not doneSeen[q] then cand[#cand + 1] = { i, k, q } end end
        end
    end
    for _, e in ipairs(info.list) do
        local i, q = e[1], e[3]
        if i > n then break end
        if not c.manual[i] and not doneSeen[q] then
            if onQuest(q) and readyToTurnIn(q) then cand[#cand + 1] = { i, e[2], q, true }
            elseif flaggedDone(q) then doneSeen[q] = true end
        end
    end
    table.sort(cand, function(x, y) return x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]) end)
    -- quests you said you're not doing (right-click on the line) stay out; a skipped quest of an earlier chapter
    -- (zone) too - you've moved on - unless it's ready to hand in
    local ignored = c.skipIgnored or EMPTY
    local curCh = ns.chapterOf(c.step)
    local seen = {}
    for _, e in ipairs(cand) do
        local i, k, q = e[1], e[2], e[3]
        local ready = e[4] or (onQuest(q) and readyToTurnIn(q))
        local oldCh = curCh and (ns.chapterOf(i) or curCh) < curCh
        if ignored[q] or (oldCh and not ready) then
            -- not doing it / left behind
        elseif not seen[q] then
            if flaggedDone(q) then doneSeen[q] = true
            else
                seen[q] = true
                local s = steps[i]
                out[#out + 1] = { step = i, q = q, name = s.n and s.n[k] or ("Quest " .. q), t = s.t }
            end
        end
    end
    return out
end

-- "I'm not doing these": the skipped quests leave the list for good (their steps stay skipped)
function ns.ignoreSkipped(list)
    local c = ItineraryCharDB
    c.skipIgnored = c.skipIgnored or {}
    for _, e in ipairs(list or {}) do c.skipIgnored[e.q] = true end
end

-- where you are, for zone checks (names from the client, so they match the client language)
local function inZone(z)
    if type(z) == "number" or tonumber(z) then
        local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        return m == tonumber(z)
    end
    return GetRealZoneText() == z or GetZoneText() == z
end
local function areaName(id)
    return C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
end
local function inArea(id)
    local n = areaName(id)
    if not n then return false end
    return GetSubZoneText() == n or GetRealZoneText() == n or GetMinimapZoneText() == n
end
local function startsWith(a, b) return a and b and a ~= "" and a:sub(1, #b) == b end
local function at(dest)
    if not dest then return false end
    for _, z in ipairs({ GetSubZoneText(), GetRealZoneText(), GetMinimapZoneText() }) do
        if z == dest or startsWith(z, dest) then return true end
    end
    return false
end

local function objectiveDone(q, idx)
    local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q)
    local o = objs and objs[idx]
    if o then return o.finished and true or false end
    return readyToTurnIn(q)
end

-- Worthwhile class spells (damage; see ns.trainWorth) you can learn at your level and haven't yet:
-- the cheapest one's price, and all of them together (what the gathering tools have to wait for).
-- Known exactly after one trainer visit; before that, guessed: from level 4 on, 10c per level.
function ns.pendingSpellCost(all)
    local c = ItineraryCharDB
    local lvl = UnitLevel("player") or 1
    -- a trainer visit recorded under an older rule (every skill counted for a while): look at the spellbook
    -- again until the next visit
    if c.trainedLevel and not c.trainWorthOnly then c.trainedLevel, c.trainOwed, c.trainOwedAll = nil, nil, nil end
    -- what the class's trainer list (recorded at a visit) holds that your spellbook doesn't have: the same
    -- source as the READY TO LEARN tooltip, so the instruction and its tooltip always agree
    local _, class = UnitClass("player")
    local cs = ItineraryDB.classSpells and ItineraryDB.classSpells[class]
    if cs and next(cs) and ns.learnableSpells then
        local cheapest, sum = nil, 0
        for _, e in ipairs(ns.learnableSpells()) do
            if e.worth and not e.skip and e.level <= lvl then
                sum = sum + e.cost
                if not cheapest or e.cost < cheapest then cheapest = e.cost end
            end
        end
        if all then return cheapest and sum or nil end
        return cheapest
    end
    if not c.trainedLevel then
        -- never at the trainer with Itinerary: what's missing from the spellbook, if the class is known
        local known = ns.unknownSpellCost and ns.unknownSpellCost(lvl)
        if known ~= nil then return known > 0 and known or nil end
        -- nothing known: class trainers have new spells at even levels (4, 6, 8 ...)
        return (lvl >= 4 and lvl % 2 == 0) and 10 * lvl or nil
    end
    local need = all and c.trainOwedAll or c.trainOwed
    if c.trainedLevel < lvl then
        local tbl = all and (c.trainTotals or c.trainCosts) or c.trainCosts
        for l, cost in pairs(tbl or {}) do
            if l <= lvl and l > c.trainedLevel then
                if all then need = (need or 0) + cost
                elseif not need or cost < need then need = cost end
            end
        end
    end
    return need
end
-- Worth a trip to the trainer: a worthwhile spell is waiting and you can pay for it.
function ns.spellsWaiting()
    local need = ns.pendingSpellCost()
    -- with automatic buying on, the money it keeps (ns.trainReserve) isn't there to spend
    local keep = (ItineraryDB.auto and ItineraryDB.auto.train and ns.trainReserve) and ns.trainReserve() or 0
    return need ~= nil and (GetMoney and GetMoney() or 0) - keep >= need
end


-- An XP step's target: level `lvl`, and optionally xpIn (that much XP into the level), xpPct (that share of
-- the level) or xpLeft (within that much XP of reaching the level). Steps saved by older versions carried one
-- signed number (xpoff); it's read the same way.
function ns.xpTarget(s)
    if s.xpIn or s.xpPct or s.xpLeft then return s.lvl or 1, tonumber(s.xpIn), tonumber(s.xpPct), tonumber(s.xpLeft) end
    local off = tonumber(s.xpoff)
    if not off or off == 0 then return s.lvl or 1 end
    if off < 0 then return s.lvl or 1, nil, nil, -off end
    if off >= 1 then return s.lvl or 1, off end
    return s.lvl or 1, nil, off * 100
end
function ns.xpReached(s)
    local lvl = UnitLevel("player") or 1
    local level, xpIn, xpPct, xpLeft = ns.xpTarget(s)
    if lvl >= level and not (xpIn or xpPct) then return true end
    local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
    if xpLeft then return lvl == level - 1 and max - cur <= xpLeft end
    if xpIn then return lvl > level or (lvl == level and cur >= xpIn) end
    if xpPct then return lvl > level or (lvl == level and cur >= max * xpPct / 100) end
    return false
end

-- Objective progress for a complete step: { {text, done}, ... } straight from the quest log
function ns.objectiveLines(s)
    local out, seen = {}, {}
    if not (s and s.t == "complete" and s.q and C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    for k, q in ipairs(s.q) do
        local oi = s.qo and s.qo[k] or 0
        local objs = onQuest(q) and C_QuestLog.GetQuestObjectives(q) or nil
        for i, o in ipairs(objs or {}) do
            if (oi == 0 or oi == i) and o.text and o.text ~= "" and not seen[o.text] then
                seen[o.text] = true
                out[#out + 1] = { o.text, o.finished and true or false }
            end
        end
    end
    return out
end

-- A step that doesn't apply to you right now (its conditions): treated as done.
---------------------------------------------------------------- dropped quests and their chains
-- A quest you skipped at its accept step (or abandoned) is dropped: its later steps leave the route, and so
-- do the quests that need it first (ns.QUEST_PRE from QuestieDB), all the way down the chain. Taking the
-- quest after all (or going back to its accept step) brings them back.
local dropCache = nil
function ns.dropChanged() dropCache = nil end
-- WoW Forever's profession quests ("Camping 101: Mining") are for the professions you picked (or know): the
-- others count as skipped. Which profession a quest is for: from its name in the route.
local profQ, profQFor = nil, nil
local function profOfQuest(q)
    local steps = ns.steps()
    if profQFor ~= steps then
        profQ, profQFor = {}, steps
        local byName = {}
        for k, p in pairs(ns.PROF or {}) do if p.name then byName[p.name] = k end end
        for _, st in ipairs(steps) do
            for n, id in ipairs(st.q or {}) do
                local nm = st.n and st.n[n]
                local prof = nm and nm:match("^Camping 101: (.+)$")
                if prof and byName[prof] then profQ[id] = byName[prof] end
            end
        end
    end
    return profQ[q]
end
local function explicitDrop(q)
    local d = ItineraryCharDB and ItineraryCharDB.droppedQ
    if d and d[q] then return true end
    local k = profOfQuest(q)
    if k and ns.profIsChosen and ns.profKnown then
        local c = ItineraryCharDB
        -- (no professions picked yet: nothing is decided)
        if c and c.prof and c.prof.list and #c.prof.list > 0 and not ns.profIsChosen(k) and not ns.profKnown(k) then
            return true
        end
    end
    return false
end
local dropSig
local dropped
function ns.questDropped(q) return dropped(q) end
function dropped(q, depth)
    if not q then return false end
    -- (another set of professions: the profession quests change)
    local sig = ns.profChosen and table.concat(ns.profChosen(), ",") or ""
    if sig ~= dropSig then dropSig, dropCache = sig, nil end
    dropCache = dropCache or {}
    local hit = dropCache[q]
    if hit ~= nil then return hit end
    local r = false
    if onQuest(q) or flaggedDone(q) then
        r = false
    elseif explicitDrop(q) then
        r = true
    elseif (depth or 0) < 12 then
        dropCache[q] = false -- (guards against loops in the data)
        local pre = ns.QUEST_PRE and ns.QUEST_PRE[q]
        if pre then
            if pre.g then for _, p in ipairs(pre.g) do if dropped(p, (depth or 0) + 1) then r = true break end end end
            if not r and pre.s and #pre.s > 0 then
                local all = true
                for _, p in ipairs(pre.s) do if not dropped(p, (depth or 0) + 1) then all = false break end end
                r = all
            end
        end
    end
    dropCache[q] = r
    return r
end
ns.questDropped = dropped
-- the dropped quests that follow from q (for "The Public Servant (+2 follow-ups)")
function ns.followUpsOf(q)
    local n = 0
    for x, pre in pairs(ns.QUEST_PRE or {}) do
        if dropped(x) and not explicitDrop(x) then
            local function needs(y, d)
                local p = ns.QUEST_PRE[y]
                if not p or d > 12 then return false end
                for _, list in ipairs({ p.g or {}, p.s or {} }) do
                    for _, z in ipairs(list) do if z == q or needs(z, d + 1) then return true end end
                end
                return false
            end
            if needs(x, 0) then n = n + 1 end
        end
    end
    return n
end
function ns.dropQuests(list)
    local c = ItineraryCharDB
    c.droppedQ = c.droppedQ or {}
    for _, q in ipairs(list) do if not (onQuest(q) or flaggedDone(q)) then c.droppedQ[q] = true end end
    dropCache = nil
end
function ns.undropQuests(list)
    local c = ItineraryCharDB
    if not c.droppedQ then return end
    for _, q in ipairs(list) do c.droppedQ[q] = nil end
    dropCache = nil
end

-- an auction house step: tagged by the guide, or one that sends you to an auctioneer
local function isAH(s)
    if s.ah then return true end
    if s.npc and s.npc:find("^Auctioneer") then return true end
    if s.targets then for _, t in ipairs(s.targets) do if t:find("^Auctioneer") then return true end end end
    return false
end
ns.isAH = isAH
-- weapon skills (Two-Handed Swords is spell 202): known when the spell is
function ns.weaponsKnown(ids, any)
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return false end
    local n = 0
    for _, id in ipairs(ids) do if known(id) then n = n + 1 end end
    if any then return n > 0 end
    return n == #ids
end

-- Steps for when you have an item ("Eat the Herb Baked Eggs": need), and food buffs: which buff
-- eating an item gives is learned the first time you eat it (ItineraryDB.itemBuffs[item] = aura spell ID)
local function itemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and (f(id) or 0) or 0
end
local function eachBuff(fn)
    for k = 1, 40 do
        local name, spellId, expires
        if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
            local a = C_UnitAuras.GetBuffDataByIndex("player", k)
            if not a then break end
            name, spellId, expires = a.name, a.spellId, a.expirationTime
        elseif UnitBuff then
            local r = { UnitBuff("player", k) }
            if not r[1] then break end
            name, spellId, expires = r[1], r[10], r[6]
        else break end
        if fn(name, spellId, expires) then return true end
    end
    return false
end
-- the buff from eating this item is up (and won't run out within a minute), or you're eating it right now
function ns.itemBuffUp(item)
    local known = ItineraryDB and ItineraryDB.itemBuffs and ItineraryDB.itemBuffs[item]
    local eating = GetItemSpell and GetItemSpell(item)
    local now = GetTime()
    return eachBuff(function(name, spellId, expires)
        if known and spellId == known then return not expires or expires == 0 or expires - now > 60 end
        if eating and name == eating then return true end
    end)
end
do
    -- learning: you use the item, and a new buff lasting minutes shows up within half a minute
    local watch
    local buffItems = {}
    local f = CreateFrame("Frame")
    -- (only your own casts and auras: the client then doesn't call this for every mob around you)
    for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_AURA" }) do
        if f.RegisterUnitEvent then f:RegisterUnitEvent(e, "player") else f:RegisterEvent(e) end
    end
    f:SetScript("OnEvent", function(_, event, unit, _, spellId)
        if unit ~= "player" or not ItineraryDB then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- an item a route step wants you to eat for its buff (the route's few such items, found once per step list)
            local steps = ns.steps and ns.steps() or {}
            if buffItems.steps ~= steps or buffItems.n ~= #steps then
                local list, seen = {}, {}
                for _, s in ipairs(steps) do
                    if s.buffItem and not seen[s.buffItem] then seen[s.buffItem] = true; list[#list + 1] = s.buffItem end
                end
                buffItems.steps, buffItems.n, buffItems.list = steps, #steps, list
            end
            for _, item in ipairs(buffItems.list) do
                if not (ItineraryDB.itemBuffs and ItineraryDB.itemBuffs[item]) then
                    local _, sid = GetItemSpell and GetItemSpell(item)
                    if sid and sid == spellId then
                        local before = {}
                        eachBuff(function(_, id) if id then before[id] = true end end)
                        watch = { item = item, before = before, untilT = GetTime() + 40 }
                        break
                    end
                end
            end
        elseif watch then
            if GetTime() > watch.untilT then watch = nil return end
            local eating = GetItemSpell and GetItemSpell(watch.item)
            local now = GetTime()
            eachBuff(function(name, id, expires)
                if id and not watch.before[id] and name ~= eating and expires and expires - now > 120 then
                    ItineraryDB.itemBuffs = ItineraryDB.itemBuffs or {}
                    ItineraryDB.itemBuffs[watch.item] = id
                    watch = nil
                    if ns.update then ns.update() end
                    return true
                end
            end)
        end
    end)
end
-- the panel follows the buff: gone, about to run out (a minute left: eat again) or back up
do
    local last = {}
    C_Timer.NewTicker(5, function()
        if not (ItineraryCharDB and ns.steps and ns.update) then return end
        local steps, i = ns.steps(), ItineraryCharDB.step
        local changed = false
        for j = math.max(1, i - 40), math.min(#steps, i) do
            local s = steps[j]
            if s and s.buffItem and s.along then
                local up = ns.itemBuffUp(s.buffItem) and true or false
                if last[s.buffItem] ~= up then last[s.buffItem] = up; changed = true end
            end
        end
        if changed then ns.update() end
    end)
end
-- an item step you can't follow (no eggs) or don't need to (the buff is up)
-- { item, count } = at least that many; { item, count, "lt" } = fewer than that
-- damage per second of the weapon in an equipment slot (16 main hand, 17 off hand, 18 ranged); nil: empty
-- or unknown
function ns.slotDps(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link then return 0 end
    local stats = (C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)) or (GetItemStats and GetItemStats(link))
    if not stats then return nil end
    return stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0
end
function ns.itemNeedMet(need)
    local have = itemCount(need[1])
    if need[3] == "lt" then return have < (need[2] or 1) end
    return have >= (need[2] or 1)
end
function ns.itemStepIdle(s)
    if s.need and not ns.itemNeedMet(s.need) then return true end
    if s.buffItem and ns.itemBuffUp(s.buffItem) then return true end
    return false
end

-- a ".skill" condition { key, n, "lt" } that rules the step out right now
local function skillOff(sk)
    if not (sk and ns.profKnown) then return false end
    local known, rank = ns.profKnown(sk[1])
    if known == nil then return false end -- a skill we can't read: no condition
    if sk[3] == "lt" then
        -- (a profession you didn't pick and don't know: its steps aren't for you; riding is no profession)
        if ns.PROF and ns.PROF[sk[1]] and ns.profIsChosen and not ns.profIsChosen(sk[1]) and not known then return true end
        if known and (rank or 0) >= sk[2] then return true end
    elseif not known or (rank or 0) < sk[2] then return true end
    return false
end

local function notApplicable(s)
    -- Settings > Quests > "Auction house": playing without it (self-found), its steps are left out
    if ItineraryDB and ItineraryDB.skipAH and isAH(s) then return true end
    -- ...and the self-found versions of steps (a vendor stop without the auction house hint) only then
    if s.ssf and not (ItineraryDB and ItineraryDB.skipAH) then return true end
    -- a step for when you have an item ("cook the Small Eggs") without it
    if s.need and not s.along and not ns.itemNeedMet(s.need) then return true end
    -- a quest step whose quests are all dropped (skipped, or their pre-quest was)
    if s.q and #s.q > 0 and QUEST_STEP[s.t] then
        local all = true
        for _, q in ipairs(s.q) do if not dropped(q) then all = false break end end
        if all then return true end
    end
    if s.cls then
        local r = ns.route()
        local _, class = UnitClass("player")
        local rc = r and (r.class or (r.match and r.match.class))
        if rc and rc ~= class then return true end
    end
    if ns.profStepIrrelevant and ns.profStepIrrelevant(s) then return true end
    -- a step only for those who know a profession (the guide's ".train 2018,3": Blacksmith your Rough Stones)
    if s.needProf and ns.profKnown and not ns.profKnown(s.needProf) then return true end
    -- ".skill cooking,50,1": only while you're below 50 in a profession you picked (or not learned yet);
    -- without "lt": only from that skill on. Two of them (skill2) make a range
    if skillOff(s.skill) or skillOff(s.skill2) then return true end
    -- money {"<", c}: skipped while you have less than that (the step is for when you can afford it);
    -- {">", c}: skipped once you have that much (grind / sell until you have it)
    if s.money then
        local m = GetMoney and GetMoney() or 0
        if s.money[1] == "<" and m < s.money[2] then return true end
        if s.money[1] == ">" and m >= s.money[2] then return true end
    end
    -- ".itemStat 16,...DPS,<4.2": only while the weapon in that slot is weaker (a better one dropped: skip)
    if s.dps and ns.slotDps then
        local d = ns.slotDps(s.dps[1])
        if d and d >= s.dps[2] then return true end
    end
    if s.cond then
        -- getting back (hearth, "Return to ...") is still needed when the quest it waits for was skipped
        local travel = s.t == "hearth" or (s.t == "go" and s.name and s.name:find("^Return to"))
        for _, c in ipairs(s.cond) do
            local kind, q = c[1], c[2]
            -- has: the quest is in your log; ready: in your log and ready to turn in; done: turned in;
            -- open: not turned in yet (being on it counts)
            if travel and (kind == "has" or kind == "ready") and dropped(q) then
                -- keep it
            elseif kind == "has" and not onQuest(q) then return true end
            if kind == "done" and not flaggedDone(q) then return true end
            if kind == "ready" and not (onQuest(q) and readyToTurnIn(q)) and not (travel and dropped(q)) then return true end
            if kind == "open" and flaggedDone(q) then return true end
            -- notready: not finished in your log (not taken, still on it, or handed in already - the
            -- counterpart of "ready"); nothas: not in your log
            if kind == "notready" and onQuest(q) and readyToTurnIn(q) then return true end
            if kind == "nothas" and onQuest(q) then return true end
        end
    end
    -- a level jump in the guide ("above 19 here: skip to Level20Check"), decided when you got there
    if s.gateL then
        local c = ItineraryCharDB
        if c and c.gates and c.gates[s.gateL] then return true end
    end
    if s.lvskip then
        local lvl = UnitLevel("player") or 1
        if s.lvskip.atleast and lvl >= s.lvskip.atleast then return true end
        if s.lvskip.below and lvl < s.lvskip.below then return true end
    end
    if s.zskip then
        for _, z in ipairs(s.zskip) do
            local here
            if z.sub then here = inArea(z.sub) else here = inZone(z.zone) end
            if here ~= (z.inv and true or false) then return true end
        end
    end
    return false
end
ns.notApplicable = notApplicable

-- timed quests ("return within 5 minutes"): seconds left on the quest's timer, the one Blizzard's quest
-- timer frame shows; nil when the quest has none running
function ns.questTimeLeft(q)
    if not q then return nil end
    if GetQuestTimers and GetQuestIndexForTimer and GetQuestLogTitle then
        local t = { GetQuestTimers() }
        for k, left in ipairs(t) do
            local idx = GetQuestIndexForTimer(k)
            local id = idx and select(8, GetQuestLogTitle(idx))
            if id == q and left then return left end
        end
    end
    if C_QuestLog and C_QuestLog.GetTimeAllowed and onQuest(q) then
        local total, elapsed = C_QuestLog.GetTimeAllowed(q)
        if total and elapsed and total > 0 then return math.max(0, total - elapsed) end
    end
    return nil
end
-- the timer for a step: its own quests, or (an instruction like "You have 5 minutes to return") the quests of
-- the step it runs until
function ns.stepTimeLeft(s)
    if not s then return nil end
    local best
    local function look(st)
        for _, q in ipairs(st and st.q or {}) do
            local l = ns.questTimeLeft(q)
            if l and (not best or l < best) then best = l end
        end
    end
    look(s)
    if not best and s.till then look(ns.steps()[s.till]) end
    return best
end
function ns.timeText(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Is step i finished? Quest steps read the quest log; the rest are marked by events or by hand.
function ns.stepDone(i)
    local s = ns.steps()[i]
    if not s then return true end
    if ItineraryCharDB.manual[i] or ItineraryCharDB.unavail[i] then return true end
    if notApplicable(s) then return true end
    -- "Equip the [Ironwood Maul]": done once it's on you, and not for you if you don't have it (another
    -- reward picked, or it didn't drop)
    if s.t == "do" and s.item and s.name and s.name:find("^Equip") then
        local ids = type(s.item) == "table" and s.item or { s.item }
        local count = (C_Item and C_Item.GetItemCount) or GetItemCount
        local worn = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
        local anyWorn, anyHave = false, false
        for _, id in ipairs(ids) do
            if worn and worn(id) then anyWorn = true end
            if count and (count(id) or 0) > 0 then anyHave = true end
        end
        if anyWorn or not anyHave then return true end
    end
    -- a quest step without its quests yet (just made one in the editor): done when you skip it
    if QUEST_STEP[s.t] and (not s.q or #s.q == 0) then return false end
    if QUEST_STEP[s.t] and s.t ~= "accept" then
        local all = true
        -- ("not offered" only counts while you don't have it: you may have got it later after all)
        for _, q in ipairs(s.q) do if not ItineraryCharDB.unavailQ[q] or onQuest(q) then all = false break end end
        if all then return true end
    end
    if s.t == "accept" then
        for _, q in ipairs(s.q) do if not (onQuest(q) or flaggedDone(q)) then return false end end
        return true
    elseif s.t == "complete" then
        for k, q in ipairs(s.q) do
            local oi = s.qo and s.qo[k] or 0
            local ok = flaggedDone(q) or (onQuest(q) and (oi > 0 and objectiveDone(q, oi) or (oi == 0 and readyToTurnIn(q))))
            if not ok then return false end
        end
        -- items to loot on the way that aren't quest objectives (the Fang that starts the next quest): in
        -- your bags, or their quest already started
        if s.col then
            local count = (C_Item and C_Item.GetItemCount) or GetItemCount
            for _, c in ipairs(s.col) do
                if (count(c[1]) or 0) < c[2] and not ns.itemQuestStarted(c[1], i) then return false end
            end
        end
        return true
    elseif s.t == "turnin" then
        for _, q in ipairs(s.q) do if not flaggedDone(q) then return false end end
        return true
    elseif s.t == "hearth" or s.t == "fly" then
        -- already where the step would take you
        local dest = s.name and s.name:match("^([^,]+)")
        if at(dest) then return true end
    elseif s.t == "fp" then
        -- a flight path you have already (seen on the flight map)
        if ns.fpKnown and ns.fpKnown(s) then return true end
    elseif s.t == "sethearth" then
        local bind = GetBindLocation and GetBindLocation()
        if bind and ((s.name and bind == s.name) or (s.bind and bind == areaName(s.bind))) then return true end
    elseif s.t == "train" and s.wpn then
        -- a weapon master visit: done once you know the weapon skill (any of them for a choice)
        return ns.weaponsKnown(s.wpn, s.wany)
    elseif s.t == "train" and not s.cls and ns.profStepDone and ns.profStepDone(s) ~= nil then
        return ns.profStepDone(s)
    elseif s.t == "train" and s.cls then
        -- a class trainer visit with nothing new to learn is skipped
        if not ns.spellsWaiting() then return true end
    elseif s.t == "xp" then
        return ns.xpReached(s)
    elseif s.t == "go" then
        -- "die and respawn at the spirit healer": done once you're alive again after it was up. Reaching the
        -- place to die at ("at", ns.arrived) only moves the arrow on - the instruction stays until the respawn
        if s.death then return ItineraryCharDB.arrived[i] == true end
        if s.sub then return inArea(s.sub) end
        if s.zone then return inZone(s.zone) end
        if s.r and ItineraryCharDB.arrived[i] then return true end
    elseif s.t == "do" and s.untilQ then
        -- an instruction that lasts until a quest is turned in
        return flaggedDone(s.untilQ) and true or false
    elseif s.t == "do" and s.abandon then
        -- "Abandon X": done once none of them is in your log (also when you never had it), and when X is ready
        -- to hand in and the route hands it in later
        for _, q in ipairs(s.abandon) do
            if onQuest(q) and not (s.keepIfReady and s.keepIfReady[q] and readyToTurnIn(q)) then return false end
        end
        return true
    elseif s.t == "do" and s.r and not s.col then
        return ItineraryCharDB.arrived[i] and true or false
    elseif s.t == "do" and s.col then
        local count = (C_Item and C_Item.GetItemCount) or GetItemCount
        for _, c in ipairs(s.col) do if (count(c[1]) or 0) < c[2] then return false end end
        return true
    end
    return false
end

-- A step further ahead that is done for good already: a quest taken or handed in, its objectives done, a quest
-- to abandon you don't have (never took it, or handed it in), a level you have, a hearth set there, a flight path
-- you have, or left out for you. The list of next steps leaves it out - the route passes it when it gets there.
-- (Not the ones that depend on where you are now or on your spells: a hearth, a trainer visit.)
local LASTING = { accept = true, complete = true, turnin = true, xp = true, sethearth = true, fp = true }
function ns.doneAhead(j)
    local s = ns.steps()[j]
    if not s then return true end
    local c = ItineraryCharDB
    if c.manual[j] or c.unavail[j] or notApplicable(s) then return true end
    if LASTING[s.t] or (s.t == "do" and s.abandon) then return ns.stepDone(j) end
    return false
end

-- How much of a multi-quest step is done, for the panel ("2/3")
function ns.stepProgress(i)
    local s = ns.steps()[i]
    if not s or not s.q or #s.q < 2 then return nil end
    local n = 0
    for _, q in ipairs(s.q) do
        if s.t == "accept" and (onQuest(q) or flaggedDone(q)) then n = n + 1
        elseif s.t == "complete" and (flaggedDone(q) or (onQuest(q) and readyToTurnIn(q))) then n = n + 1
        elseif s.t == "turnin" and flaggedDone(q) then n = n + 1 end
    end
    return n, #s.q
end

local LOOKAHEAD = 12
-- Move forward past finished steps. Travel steps (fly, hearth...) can't be checked afterwards,
-- so they count as done when a quest step shortly after them already is. Optional steps work the same
-- way, and "along the way" steps never hold you up (the panel lists them while they matter).
-- why a step counts as done (for the jump log below)
local function whyDone(i)
    local s, c = ns.steps()[i], ItineraryCharDB
    if c.manual[i] then return "manual" end
    if c.unavail[i] then return "unavail" end
    if notApplicable(s) then return "n/a" end
    local t = {}
    for _, q in ipairs(s.q or {}) do
        t[#t + 1] = q .. (onQuest(q) and ":onQuest" or "") .. (flaggedDone(q) and ":flagged" or "") .. (readyToTurnIn(q) and ":ready" or "")
    end
    return "done " .. table.concat(t, " ")
end
function ns.advance()
    local steps, c = ns.steps(), ItineraryCharDB
    local moved = false
    local from, log = c.step, {}
    while c.step <= #steps do
        local i = c.step
        -- reaching the first step behind a level jump decides it once: above its level, the steps up to
        -- the jump's end are skipped
        local g = steps[i].gateL
        if g then
            c.gates = c.gates or {}
            if c.gates[g] == nil then c.gates[g] = (UnitLevel("player") or 1) > (steps[i].gateMax or 99) end
        end
        if steps[i].along or ns.stepDone(i) then
            if not steps[i].along and #log < 40 then log[#log + 1] = i .. " " .. steps[i].t .. ": " .. whyDone(i) end
            c.step = i + 1; moved = true
        elseif not QUEST_STEP[steps[i].t] or steps[i].opt then
            local later, lj = false, nil
            for j = i + 1, math.min(#steps, i + LOOKAHEAD) do
                local sj = steps[j]
                if QUEST_STEP[sj.t] and not sj.opt and not sj.along and not notApplicable(sj) then later, lj = ns.stepDone(j), j break end
            end
            -- travel (tram, flight, hearth, setting the hearth) is only behind you when you are where the route
            -- goes on: quests from further along already in your log don't carry you past the trip itself
            local t = steps[i].t
            if later and (t == "go" or t == "fly" or t == "hearth" or t == "sethearth") then
                local there = steps[lj].z
                if there and there ~= "" and not inZone(there) then later = false end
            end
            if later then
                if #log < 40 then log[#log + 1] = i .. " " .. steps[i].t .. ": passed, step " .. lj .. " " .. whyDone(lj) end
                c.step = i + 1; moved = true
            else break end
        else
            break
        end
    end
    -- a big jump is written down (ItineraryCharDB.lastJump) so it can be looked at afterwards
    if c.step - from >= 6 then
        c.lastJump = { from = from, to = c.step, at = date and date("%H:%M:%S") or "", why = log }
    end
    -- landed on a turn-in while its kill/loot step just before is still open (an older saved position, a
    -- resync): go back to that step
    local cur = steps[c.step]
    if cur and cur.t == "turnin" and cur.q then
        local open = {}
        for _, q in ipairs(cur.q) do if onQuest(q) and not readyToTurnIn(q) then open[q] = true end end
        if next(open) then
            for j = c.step - 1, math.max(1, c.step - 8), -1 do
                local sj = steps[j]
                -- (its variant condition doesn't matter here: the quest itself is open and not done)
                if sj.t == "complete" and not sj.along and sj.q and not ns.stepDone(j) then
                    for _, q in ipairs(sj.q) do if open[q] then c.step, moved = j, true break end end
                end
            end
        end
    end
    return moved
end

-- "along the way" steps that still matter at step i: started before it, not done, not past their end
-- An along-the-way quest objective ends where the route gets a step of its own for that quest: from
-- there the main step shows the objectives, so it isn't repeated underneath.
local function takenOver(s, cur)
    if not cur or cur.along or not cur.q then return false end
    -- a collect for one quest ("4 Chunks of Boar Meat" for Pie for Billy, ended by that quest's turn-in): the
    -- quest's own step shows the same objective
    if s.t == "do" and s.col and not s.q and s.cond and (cur.t == "complete" or cur.t == "turnin") then
        for _, c in ipairs(s.cond) do
            if c[1] == "open" then
                for _, b in ipairs(cur.q) do if c[2] == b then return true end end
            end
        end
        return false
    end
    if not s.q then return false end
    if s.t ~= "complete" and not s.col then return false end
    if cur.t ~= "complete" and cur.t ~= "turnin" then return false end
    for _, a in ipairs(s.q) do
        for _, b in ipairs(cur.q) do
            -- a turn-in only takes over once the quest is finished: before that the along-the-way entry keeps
            -- its counts (and the target button its mobs) - the turn-in itself shows none
            if a == b and (cur.t == "complete" or (onQuest(a) and readyToTurnIn(a))) then return true end
        end
    end
    return false
end
ns.alongTakenOver = takenOver
-- A "while you're there" turn-in or accept (along the way until the next step) that the route does as a step of
-- its own right after: that step is in the upcoming list already, so it isn't an instruction as well.
local function comingUp(s, steps, i)
    if not ((s.t == "accept" or s.t == "turnin") and s.q) then return false end
    local seen = 0
    for k = i, #steps do
        local x = steps[k]
        if not x.along and not (k == i and ns.notApplicable(x) or k ~= i and ns.doneAhead(k)) then
            if x.t == s.t and x.q then
                for _, a in ipairs(s.q) do
                    for _, b in ipairs(x.q) do if a == b then return true end end
                end
            end
            seen = seen + 1
            if seen > 3 then return false end -- the current step and the three shown after it
        end
    end
    return false
end

-- Along-the-way entries you hid (the × on the row in ALONG THE WAY), per character: by quest (a quest's
-- objectives, a Camping 101 quest the route doesn't have) or by the items collected, so every tier of the same
-- items goes with it. Hidden means not shown and not acted on along the way (target button, item buttons); the
-- route's own steps for that quest stay. Settings > Panel shows them again.
local alongKeyCache = setmetatable({}, { __mode = "k" })
local NO_KEYS = {}
local function alongKeyList(s)
    local k = alongKeyCache[s]
    if k then return k end
    if s.t == "complete" and s.q and #s.q > 0 then
        k = {}
        for _, q in ipairs(s.q) do k[#k + 1] = "q" .. q end
    elseif s.col and #s.col > 0 then
        local ids = {}
        for _, c in ipairs(s.col) do ids[#ids + 1] = c[1] end
        table.sort(ids)
        k = { "i" .. table.concat(ids, ",") }
    else
        k = NO_KEYS
    end
    alongKeyCache[s] = k
    return k
end
local function alongHidden(s)
    local h = ItineraryCharDB and ItineraryCharDB.hiddenAlong
    if not h or next(h) == nil then return false end
    local keys = alongKeyList(s)
    if #keys == 0 then return false end
    for _, key in ipairs(keys) do if not h[key] then return false end end
    return true
end
ns.alongHidden = alongHidden
function ns.alongHideable(s) return s and #alongKeyList(s) > 0 or false end
function ns.alongKeyHidden(key)
    local h = ItineraryCharDB and ItineraryCharDB.hiddenAlong
    return h and h[key] and true or false
end
-- what hiding this along-the-way step stores: { {key, name}, ... }, or nil when it can't be hidden
function ns.alongKeys(s)
    local keys = s and alongKeyList(s) or NO_KEYS
    if #keys == 0 then return nil end
    local out = {}
    if s.t == "complete" and s.q then
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID
        -- (the name: the quest log's, else the route's accept or turn-in step's)
        local function routeName(q)
            for _, x in ipairs(ns.steps()) do
                if x.n and x.q then for k, y in ipairs(x.q) do if y == q and x.n[k] then return x.n[k] end end end
            end
        end
        for k, q in ipairs(s.q) do out[#out + 1] = { keys[k], (s.n and s.n[k]) or (title and title(q)) or routeName(q) or ("Quest " .. q) } end
    else
        local nameOf = (C_Item and C_Item.GetItemNameByID) or function(id) return GetItemInfo and (GetItemInfo(id)) end
        local names = {}
        for _, c in ipairs(s.col) do names[#names + 1] = nameOf(c[1]) or ("item " .. c[1]) end
        out[1] = { keys[1], table.concat(names, ", ") }
    end
    return out
end
function ns.hideAlong(entries)
    if not (entries and entries[1]) then return end
    local c = ItineraryCharDB
    c.hiddenAlong = type(c.hiddenAlong) == "table" and c.hiddenAlong or {}
    local names = {}
    for _, e in ipairs(entries) do
        c.hiddenAlong[e[1]] = e[2] or e[1]
        names[#names + 1] = e[2] or e[1]
    end
    ns.print("hidden from Along the way: " .. table.concat(names, ", ") .. " (Settings > Panel shows it again)")
    if ns.update then ns.update() end
    if ns.refresh then ns.refresh() end
    if ns.refreshSettings then ns.refreshSettings() end
end
-- show one again (key), or all of them (no key)
function ns.unhideAlong(key)
    local c = ItineraryCharDB
    if type(c.hiddenAlong) ~= "table" then return end
    if key then c.hiddenAlong[key] = nil else c.hiddenAlong = {} end
    if ns.update then ns.update() end
    if ns.refresh then ns.refresh() end
end
-- the hidden entries, by name: { {key=, name=}, ... }
function ns.hiddenAlongList()
    local out, h = {}, ItineraryCharDB and ItineraryCharDB.hiddenAlong
    if type(h) ~= "table" then return out end
    for k, v in pairs(h) do out[#out + 1] = { key = k, name = type(v) == "string" and v or k } end
    table.sort(out, function(a, b) return a.name < b.name or (a.name == b.name and a.key < b.key) end)
    return out
end

function ns.alongActive(i)
    local out, steps = {}, ns.steps()
    local _, _, first = ns.chapterOf(i)
    local cur = steps[i]
    for j = (first or 1), math.min(i, #steps) do
        local s = steps[j]
        -- (an item collect taken over by the current step still counts as its tier below)
        local tier = s.t == "do" and s.col
        if s.along and (not s.till or s.till >= i) and not ns.stepDone(j) and (tier or not (j ~= i and takenOver(s, cur)))
           and not (j ~= i and comingUp(s, steps, i)) and not ((s.need or s.buffItem) and ns.itemStepIdle(s))
           and not alongHidden(s) then
            out[#out + 1] = j
        end
    end
    -- the guide's tiers of one item ("4 Chunks of Boar Meat", then 10, then 50 for Cooking): only the next one,
    -- and none while that one is your current step's own objective
    -- (the same set of items in tiers counts too: cloth for 60, then for 240)
    local function tierKey(s)
        local ids = {}
        for _, c in ipairs(s.col) do ids[#ids + 1] = c[1] end
        table.sort(ids)
        return table.concat(ids, ",")
    end
    local low = {}
    for _, j in ipairs(out) do
        local s = steps[j]
        if s.t == "do" and s.col then
            local key, n = tierKey(s), s.col[1][2]
            if not low[key] or n < steps[low[key]].col[1][2] then low[key] = j end
        end
    end
    -- the same objectives twice (the guide's version without a side quest and the one with it, "if you have
    -- Lost Book"): only the bigger one
    local function within(a, b)
        if #a.q >= #b.q then return false end
        for _, q in ipairs(a.q) do
            local f = false
            for _, x in ipairs(b.q) do if x == q then f = true break end end
            if not f then return false end
        end
        return true
    end
    -- (the very same objectives in two guide steps - the zone's step repeated, or one "if you're on the
    -- cooking quest" with a longer note: the conditional one, else the later one)
    local function same(a, b)
        if #a.q ~= #b.q then return false end
        local key = function(x)
            local t = {}
            for n, q in ipairs(x.q) do t[#t + 1] = q .. ":" .. tostring(x.qo and x.qo[n] or 0) end
            table.sort(t)
            return table.concat(t, ",")
        end
        return key(a) == key(b)
    end
    local sub = {}
    for _, j in ipairs(out) do
        local a = steps[j]
        if a.t == "complete" and a.q then
            for _, k in ipairs(out) do
                local b = steps[k]
                if k ~= j and b.t == "complete" and b.q and not sub[k] then
                    if within(a, b) then sub[j] = true break end
                    if same(a, b) and ((b.cond and not a.cond) or (not a.cond == not b.cond and k > j)) then
                        sub[j] = true break
                    end
                end
            end
        end
    end
    local kept, death = {}, false
    for _, j in ipairs(out) do
        local s = steps[j]
        local tier = s.t == "do" and s.col
        local drop = sub[j] or (tier and (low[tierKey(s)] ~= j or (j ~= i and takenOver(s, cur))))
        -- one death skip at a time: the next one shows once you're alive again (Felwood: die in the furbolg
        -- cave, then once more at the slime pond)
        if s.death and not drop then
            if death then drop = true end
            death = true
        end
        if not drop then kept[#kept + 1] = j end
    end
    return kept
end

-- A flight step's flight master: the nearest one of your side, not only the one the route names. The guide may
-- mean either of two ("Dungar Longdrink or Thor", by where you are), or you went somewhere on your own and come
-- back to the route from there. Only flight masters on the continent of the route's own one count (a flight from
-- there gets you where the step goes); without the data or your position it's the route's. Returns
-- { m, x, y, npc, own = true for the route's } or nil (no place known).
local fmWorld = {} -- (each flight master's world position, worked out once)
ns.fmWorld = fmWorld -- (tests)
local function fmPos(k, f)
    local w = fmWorld[k]
    if w then return w[1], w[2], w[3] end
    local c, wx, wy = ns.worldPos(f[2], f[3] / 100, f[4] / 100)
    if c and wx then fmWorld[k] = { c, wx, wy } end -- (not kept when the map can't say yet)
    return c, wx, wy
end
function ns.flightMasterFor(s)
    if not (s and s.t == "fly") then return nil end
    local own = s.m and s.m > 0 and s.x and { m = s.m, x = s.x, y = s.y, npc = s.npc, own = true } or nil
    local list, worldPos, playerWorld = ns.DATA_FLIGHT_MASTERS, ns.worldPos, ns.playerWorld
    if not (list and worldPos and playerWorld) then return own end
    local pc, px, py = playerWorld()
    if not (pc and px) then return own end
    local oc, ox, oy
    if own then oc, ox, oy = worldPos(own.m, own.x / 100, own.y / 100) end
    if own and oc ~= pc then return own end -- (you're on another continent: the route's way stands)
    local side = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup and UnitFactionGroup("player") or ""]
    local best, bd = nil, nil
    local function consider(f, c, wx, wy)
        if not (c and c == pc and wx) then return end
        local d = (wx - px) ^ 2 + (wy - py) ^ 2
        if not bd or d < bd then best, bd = f, d end
    end
    for k, f in ipairs(list) do
        if f[5] == side or f[5] == "AH" then
            local c, wx, wy = fmPos(k, f)
            -- the route's own flight master (its exact place; the name the data gives there - a guide that
            -- names two may have the other one's name on it)
            if own and c == oc and wx and (wx - ox) ^ 2 + (wy - oy) ^ 2 < 50 * 50 then
                own.npc = f[1]
            else
                consider({ m = f[2], x = f[3], y = f[4], npc = f[1] }, c, wx, wy)
            end
        end
    end
    if own then consider(own, oc, ox, oy) end
    return best or own
end

-- Where the arrow should lead for step i: first the unfinished "along the way" travel steps (enter the cave,
-- follow the path inside...), then the step's own way in and its target. Each point: {map, x, y, radius, step, last}
function ns.arrowRoute(i)
    local steps, seq = ns.steps(), {}
    if type(i) == "string" and i:sub(1, 7) == "trainer" and ns.detourStep then
        local d = ns.detourStep
        return { { d.m, d.x, d.y, 0, final = true, last = true } }
    end
    local function add(j, s, final)
        local way = s.way or (s.x and { { s.m, s.x, s.y, s.r or 0 } }) or nil
        if not way then return end
        for k, p in ipairs(way) do
            seq[#seq + 1] = { p[1], p[2], p[3], p[4] or 0, step = j, last = (k == #way), final = final and k == #way }
        end
    end
    for _, j in ipairs(ns.alongActive(i)) do
        local s = steps[j]
        -- only real travel steers the arrow (enter the cave, the path inside); things to kill or collect
        -- while you pass ("loot boars for meat") have a farming path of their own that isn't your way
        local side = s.col or s.mobs or s.t == "accept" or s.t == "turnin"
        local there = s.death and ItineraryCharDB.arrived[j] == "at" -- (at the place to die: on to the step)
        if s.t == "fly" then
            -- a flight to take first ("Fly to Redridge" while the step is the travel there): its flight master
            -- is where the arrow leads until you're in the air or there already - reaching them doesn't move it
            -- on, and the step's own place comes after the flight
            local f = not s.rec and not ns.stepDone(j) and ns.flightMasterFor(s)
            if f then add(j, f.own and s or f, true) return seq end
        elseif s.t ~= "complete" and s.m and not side and not s.vendor and not s.rec and not s.errand and not there and not ns.stepDone(j) then
            -- (a vendor errand only when you click it: then it's the arrow's manual target)
            add(j, s, false)
        end
    end
    local s = steps[i]
    if s and s.t == "fly" then
        local f = ns.flightMasterFor(s)
        if f then add(i, f.own and s or f, true) end
        return seq
    end
    if s and s.m and s.m > 0 and not s.area then add(i, s, true) end
    return seq
end
-- Class trainers you could visit: the route's class trainer steps plus the ones you have opened before
function ns.classTrainers()
    local out, seen = {}, {}
    local _, myClass = UnitClass("player")
    local mine = ItineraryDB.trainers and ItineraryDB.trainers[myClass] or {}
    local dataMine = ns.DATA_CLASS_TRAINERS and ns.DATA_CLASS_TRAINERS[myClass] or {}
    -- (a route's trainer stop at someone the data knows as another kind of trainer - a profession, pet, demon
    -- or portal trainer, a weapon master - isn't where your class skills are, unless you opened them as yours)
    local function other(npc)
        if mine[npc] or dataMine[npc] then return false end
        return (ns.profOfNpc and ns.profOfNpc(npc)) or (ns.DATA_OTHER_TRAINERS and ns.DATA_OTHER_TRAINERS[npc]) or false
    end
    for _, s in ipairs(ns.steps()) do
        if s.t == "train" and s.cls and s.npc and s.m and s.x and not seen[s.npc] and not other(s.npc) then
            seen[s.npc] = true
            out[#out + 1] = { name = s.npc, m = s.m, x = s.x, y = s.y }
        end
    end
    local _, class = UnitClass("player")
    for name, p in pairs(ItineraryDB.trainers and ItineraryDB.trainers[class] or {}) do
        if not seen[name] then seen[name] = true; out[#out + 1] = { name = name, m = p[1], x = p[2], y = p[3] } end
    end
    return out
end

-- Trainer detour: while new class spells are waiting and a class trainer is within
-- NEAR yards), the panel and arrow send you there first as a normal TRAIN step. Skipping it dismisses it
-- until your next level; opening the trainer ends it.
local NEAR = 400
local CITY = { [1453] = true, [1455] = true, [1457] = true, [1454] = true, [1456] = true, [1458] = true }
local function classDetour()
    local c = ItineraryCharDB
    if not (c and ns.worldPos and ns.spellsWaiting()) then return nil end
    local lvl = UnitLevel("player") or 1
    if c.detourSkip == lvl then return nil end
    local steps, i = ns.steps(), c.step
    local cur = steps[i]
    if cur and cur.t == "train" and cur.cls then return nil end
    local pc, px, py = ns.playerWorld()
    if not pc then return nil end
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local best, bd
    for _, t in ipairs(ns.classTrainers()) do
        local cc, wx, wy = ns.worldPos(t.m, t.x / 100, t.y / 100)
        if cc == pc then
            local d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
            local ok = d <= NEAR -- (a strict 400 yards, also in cities)
            if ok and (not bd or d < bd) then best, bd = t, d end
        end
    end
    if not best then return nil end
    -- the route goes to this very trainer in a moment anyway (as a step of its own; a route trainer visit
    -- shown as an instruction only appears once you get to it, so it doesn't count: this one shows now,
    -- and the route's own is hidden while this is up)
    for j = i, math.min(#steps, i + 8) do
        local s = steps[j]
        if s.t == "train" and s.cls and s.npc == best.name and not s.trainRec then return nil end
    end
    return { t = "train", cls = true, detour = true, npc = best.name, m = best.m, x = best.x, y = best.y,
             note = "New spells to learn", dist = bd }
end

---------------------------------------------------------------- weapon masters
-- Weapon skills you're missing, like the class trainer: while a weapon master within 400 yards teaches one
-- you can pay for, it's an instruction ("Train Staves and Polearms at Woo Ping") or, with Trainer visits:
-- Step, a detour step. Settings > Trainer > Weapon skills: every one your class can use, only the ones the
-- route trains (its weapon master stops), or none.
local WPN_NAME = { [201] = "1h Swords", [202] = "2h Swords", [198] = "1h Maces", [199] = "2h Maces",
    [196] = "1h Axes", [197] = "2h Axes", [227] = "Staves", [1180] = "Daggers", [264] = "Bows", [266] = "Guns",
    [5011] = "Crossbows", [2567] = "Thrown", [200] = "Polearms", [15590] = "Fist Weapons" }
ns.WPN_NAME = WPN_NAME
-- what each class can learn (Classic; wands come with the class)
local CLASS_WPN = {
    WARRIOR = { 196, 197, 198, 199, 201, 202, 1180, 15590, 200, 227, 264, 5011, 266, 2567 },
    PALADIN = { 196, 197, 198, 199, 201, 202, 200 },
    HUNTER  = { 196, 197, 201, 202, 1180, 15590, 200, 227, 264, 5011, 266, 2567 },
    ROGUE   = { 1180, 15590, 198, 201, 264, 5011, 266, 2567 },
    PRIEST  = { 198, 1180, 227 },
    SHAMAN  = { 196, 197, 198, 199, 1180, 15590, 227 },
    MAGE    = { 1180, 201, 227 },
    WARLOCK = { 1180, 201, 227 },
    DRUID   = { 1180, 15590, 198, 199, 227 },
}
-- the weapon masters in the capitals and what they teach come with the separate Itinerary_Data add-on
-- (ns.DATA_WEAPON_MASTERS: npc = { map, x, y, { skill ids }, faction }); one you open replaces that
-- with what he really teaches, and the route's stops give the exact spot.
local WPN_COST = 1000 -- 10 silver a weapon skill
local function wpnMode() return ItineraryDB and ItineraryDB.auto and ItineraryDB.auto.weapons or "route" end
local wpnCache
function ns.weaponPlan()
    local steps = ns.steps()
    local mode = wpnMode()
    if wpnCache and wpnCache.steps == steps and wpnCache.mode == mode then return wpnCache end
    local want, seenW, masters = {}, {}, {}
    local routeW = {}
    local function add(id, fromRoute)
        if fromRoute then routeW[id] = true end
        if not seenW[id] then seenW[id] = true; want[#want + 1] = id end
    end
    local function master(npc)
        local e = masters[npc]
        if not e then e = { name = npc, teach = {} }; masters[npc] = e end
        return e
    end
    -- the route's weapon skills first (the route picked them), then the rest your class can use
    for _, s in ipairs(steps) do
        if s.t == "train" and s.wpn then
            -- a choice ("2h Maces with a group, otherwise Thrown; if unsure, Thrown"): the safe pick, named last
            if s.wany then add(s.wpn[#s.wpn], true) else for _, id in ipairs(s.wpn) do add(id, true) end end
            if s.npc then
                local e = master(s.npc)
                if not e.s or (s.x and not e.s.x) then e.s = s end -- its place (zone coordinates come once the map is up)
                for _, id in ipairs(s.wpn) do e.teach[id] = true end
            end
        end
    end
    local _, class = UnitClass("player")
    if mode == "all" then
        -- what your class can learn: what a weapon master showed (recorded, or shipped), else the Classic list
        local seen = ItineraryDB.weaponClass and ItineraryDB.weaponClass[class]
        local shipped = ns.CLASS_DATA and ns.CLASS_DATA.weaponClass and ns.CLASS_DATA.weaponClass[class]
        local listed = {}
        for _, id in ipairs(CLASS_WPN[class] or {}) do listed[id] = true end
        for _, t in ipairs({ shipped or {}, seen or {} }) do for id, ok in pairs(t) do listed[id] = ok or nil end end
        local ids = {}
        for id in pairs(listed) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b)
            local ia, ib = 99, 99
            for k, id in ipairs(CLASS_WPN[class] or {}) do if id == a then ia = k end if id == b then ib = k end end
            if ia ~= ib then return ia < ib end
            return a < b
        end)
        for _, id in ipairs(ids) do add(id) end
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local HBDw = LibStub and LibStub("HereBeDragons-2.0", true)
    local FACTION_OF = { A = "Alliance", H = "Horde" }
    for npc, r in pairs(ns.DATA_WEAPON_MASTERS or {}) do
        -- { map, x, y (% of the zone map), { skill ids }, faction ("A"/"H") }
        local fa = r[5] and (FACTION_OF[r[5]] or r[5])
        if not (fa and faction and fa ~= faction) and HBDw then
            local wx, wy = HBDw:GetWorldCoordinatesFromZone(r[2] / 100, r[3] / 100, r[1])
            if wx then
                local e = master(npc)
                e.wm, e.wx, e.wy = r[1], wx, wy
                for _, id in ipairs(r[4]) do e.teach[id] = true end
            end
        end
    end
    -- recorded in game (shipped with the addon, then your own visits): exact place, list and prices
    local shippedM = ns.CLASS_DATA and ns.CLASS_DATA.weaponMasters or {}
    for _, src in ipairs({ shippedM, ItineraryDB.weaponMasters or {} }) do
        for npc, r in pairs(src) do
            if not (r[6] and faction and r[6] ~= faction) then
                local e = master(npc)
                e.m, e.x, e.y, e.s = r[1], r[2], r[3], nil
                -- (what a visit listed adds to what he's known to teach: a character who knew a skill already
                -- may not have seen it in his list)
                e.cost = e.cost or {}
                for id, c in pairs(r[5] or {}) do e.cost[id] = c end
                for _, id in ipairs(r[4] or {}) do e.teach[id] = true end
            end
        end
    end
    if mode == "off" then want = {} end
    wpnCache = { steps = steps, mode = mode, want = want, masters = masters, route = routeW }
    return wpnCache
end
-- the weapon skills you're missing: { id = true }, any
function ns.weaponsMissing()
    local out, any = {}, false
    local known = IsPlayerSpell or IsSpellKnown
    if not known then return out, false end
    for _, id in ipairs(ns.weaponPlan().want) do
        if not known(id) then out[id] = true; any = true end
    end
    return out, any
end
function ns.weaponPlanReset() wpnCache = nil end
-- where a weapon master stands, in zone coordinates
local function masterPos(t)
    if t.x and not t.s then return t.m, t.x, t.y end
    if t.s and t.s.x then return t.s.m, t.s.x, t.s.y end
    if t.wm and not t.zx then
        local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
        local x, y
        if HBD then x, y = HBD:GetZoneCoordinatesFromWorld(t.wx, t.wy, t.wm, true) end -- ("HBD and f()" keeps one value)
        if x and y then t.zx, t.zy = x * 100, y * 100 end
    end
    if t.zx then return t.wm, t.zx, t.zy end
end
-- the nearest weapon master with something for you: master, distance, { ids you're missing that he teaches }
function ns.nearestWeaponMaster(maxDist)
    local missing, any = ns.weaponsMissing()
    if not any then return nil end
    local pc, px, py = ns.playerWorld()
    if not pc then return nil end
    local best, bd, ids
    for _, t in pairs(ns.weaponPlan().masters) do
        local here = {}
        for _, id in ipairs(ns.weaponPlan().want) do if missing[id] and t.teach[id] then here[#here + 1] = id end end
        local m, x, y = masterPos(t)
        if #here > 0 and m and x then
            local cc, wx, wy = ns.worldPos(m, x / 100, y / 100)
            if cc == pc then
                local d = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
                if (not maxDist or d <= maxDist) and (not bd or d < bd) then best, bd, ids = t, d, here end
            end
        end
    end
    if best then best.m, best.x, best.y = masterPos(best) end
    return best, bd, ids
end
local function weaponDetour()
    local c = ItineraryCharDB
    if not (c and ns.worldPos) then return nil end
    local lvl = UnitLevel("player") or 1
    if c.wpnSkip == lvl then return nil end
    local keep = ns.trainReserve and ns.trainReserve() or 0
    local money = (GetMoney and GetMoney() or 0) - keep
    if money < WPN_COST then return nil end
    local best, bd, ids = ns.nearestWeaponMaster(NEAR)
    if not best then return nil end
    local can, total = {}, 0
    for _, id in ipairs(ids) do
        local cost = best.cost and best.cost[id] or WPN_COST
        if money >= total + cost then can[#can + 1] = id; total = total + cost end
    end
    if #can == 0 then return nil end
    local names = {}
    for _, id in ipairs(can) do names[#names + 1] = WPN_NAME[id] end
    local list = #names > 1 and (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]) or names[1]
    return { t = "train", detour = true, weapon = true, wpn = can, npc = best.name, m = best.m, x = best.x, y = best.y,
             name = "Train " .. list, dist = bd,
             note = string.format("Weapon skill%s, %s", #can > 1 and "s" or "", ns.money and ns.money(total) or "") }
end
ns.weaponDetour = weaponDetour
-- for the instruction's tooltip: the skills this weapon master has that you're missing
-- { { id, name, cost, route = the route trains it, icon }, ... } in the order they'd be bought
function ns.weaponMasterList(npc)
    local plan = ns.weaponPlan()
    local t = plan.masters[npc]
    if not t then return {} end
    local missing = ns.weaponsMissing()
    local out = {}
    for _, id in ipairs(plan.want) do
        if missing[id] and t.teach[id] then
            local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or (GetSpellTexture and GetSpellTexture(id)) or 134400
            out[#out + 1] = { id = id, name = WPN_NAME[id], cost = t.cost and t.cost[id] or WPN_COST, route = plan.route[id] or false,
                              icon = icon }
        end
    end
    return out
end

-- profession steps (learn, use the book, buy the tool) come before a class trainer visit
-- How far the route's current step is from you (nil if it has no place or it's on another continent)
local function stepDistance(s)
    if not (s and s.m and s.x and ns.worldPos and ns.playerWorld) then return nil end
    local pc, px, py = ns.playerWorld()
    local c, wx, wy = ns.worldPos(s.m, s.x / 100, s.y / 100)
    if not (pc and c and pc == c) then return nil end
    return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
end
ns.stepDistance = stepDistance

-- A detour only when it's closer than where the route sends you next: hand in the quest in front of you
-- first, the trainer comes when you pass it on the way
function ns.findDetour()
    if not ItineraryCharDB then return nil end
    local d = (ns.profDetour and ns.profDetour()) or classDetour() or weaponDetour()
    if d and d.dist then
        local here = stepDistance(ns.steps()[ItineraryCharDB.step])
        if here and d.dist > here then return nil end
    end
    return d
end
-- as instructions (Trainer visits: Instruction) they don't replace your step, so every one close by shows
function ns.findDetours()
    if not ItineraryCharDB then return {} end
    local out = {}
    for _, f in ipairs({ ns.profDetour or function() end, classDetour, weaponDetour }) do
        local d = f()
        if d then out[#out + 1] = d end
    end
    return out
end

-- the step the panel and arrow show: a trainer detour if there is one, else the route's current step
function ns.current()
    return ns.detourStep or ns.steps()[ItineraryCharDB.step]
end

-- an item that starts a quest counts as looted once that quest is taken: the route's accept step that
-- uses it (after step i) is done
function ns.itemQuestStarted(item, i)
    local steps = ns.steps()
    for j = i + 1, math.min(#steps, i + 12) do
        local s = steps[j]
        if s.t == "accept" and s.item then
            local list = type(s.item) == "table" and s.item or { s.item }
            for _, it in ipairs(list) do
                if it == item then
                    for _, q in ipairs(s.q) do if onQuest(q) or flaggedDone(q) then return true end end
                end
            end
        end
    end
    return false
end

function ns.arrived(j)
    local c = ItineraryCharDB
    if c.arrived[j] then return end
    -- (a death skip's place: "at" - the arrow moves on, the step is done when you're alive again)
    local s = ns.steps()[j]
    c.arrived[j] = (s and s.death) and "at" or true
    ns.update()
end

-- Back from the dead (spirit healer or your corpse): the "die and respawn" steps that were up are done -
-- the current step and the along-the-way ones (death skips)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_UNGHOST")
    f:SetScript("OnEvent", function()
        local c = ItineraryCharDB
        if not (c and c.arrived and ns.steps) then return end
        local steps, i = ns.steps(), c.step
        local any = false
        local cur = steps[i]
        if cur and cur.death then c.arrived[i] = true; any = true end
        for _, j in ipairs(ns.alongActive(i)) do
            if steps[j].death then c.arrived[j] = true; any = true end
        end
        if any and ns.update then ns.update() end
    end)
end

function ns.setStep(i)
    local n = #ns.steps()
    ItineraryCharDB.step = math.max(1, math.min(n + 1, i))
    if ns.refresh then ns.refresh() end
end
function ns.skip()
    local c = ItineraryCharDB
    -- gather mode: › skips this spot
    if ns.detourStep and ns.detourStep.gather then
        if ns.gatherSkip then ns.gatherSkip() end
        return
    end
    if ns.detourStep then
        if ns.detourStep.prof and c.prof then c.prof.skip = UnitLevel("player")
        elseif ns.detourStep.weapon then c.wpnSkip = UnitLevel("player")
        else c.detourSkip = UnitLevel("player") end
        ns.detourStep = nil
        if ns.refresh then ns.refresh() end
        return
    end
    -- skipping where you'd take a quest: it's dropped, and its chain with it
    local cur = ns.steps()[c.step]
    if cur and cur.t == "accept" and cur.q then
        local open = {}
        for _, q in ipairs(cur.q) do if not (onQuest(q) or flaggedDone(q)) then open[#open + 1] = q end end
        ns.dropQuests(open)
        local n = 0
        for _, q in ipairs(open) do n = n + ns.followUpsOf(q) end
        if n > 0 then
            ns.print(string.format("skipped: %d follow-up quest%s left out too. Take it after all (or ‹ back) to bring %s back.",
                n, n == 1 and "" or "s", n == 1 and "it" or "them"))
        end
    end
    c.manual[c.step] = true
    c.step = c.step + 1
    ns.advance()
    if ns.refresh then ns.refresh() end
end
function ns.back()
    local c = ItineraryCharDB
    if c.step <= 1 then return end
    c.step = c.step - 1
    c.manual[c.step] = nil
    local st = ns.steps()[c.step]
    if st and st.t == "accept" and st.q then ns.undropQuests(st.q) end
    if c.unavail[c.step] then
        c.unavail[c.step] = nil
        for _, q in ipairs(ns.steps()[c.step].q or {}) do c.unavailQ[q] = nil end
    end
    if ns.refresh then ns.refresh() end
end

-- mark the current step done when an event matches it (flew, hearthed, trained...)
-- The flight paths this character has, from the flight map whenever it opens ("Menethil Harbor, Wetlands" ->
-- c.fps["Menethil Harbor, Wetlands"]), and how many flight masters each zone has (c.fpZone): a "get the flight
-- path" step for one you have already is done (Menethil Harbor from the Darkshore boat, then again on the way to
-- the Ruins of Lordaeron)
function ns.noteFlightPaths()
    local c = ItineraryCharDB
    if not (c and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
    c.fps, c.fpZone = c.fps or {}, c.fpZone or {}
    local seen = {}
    for i = 1, (NumTaxiNodes() or 0) do
        local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
        if name and kind and kind ~= "NONE" then
            -- (REACHABLE / CURRENT: yours; DISTANT: yours, not reachable from here)
            c.fps[name] = true
        end
        local zone = name and name:match(",%s*(.+)$")
        if zone then seen[zone] = (seen[zone] or 0) + 1 end
    end
    for z, n in pairs(seen) do c.fpZone[z] = n end
end
local function fpKnown(s)
    local c = ItineraryCharDB
    local want = s.name and s.name:match("^([^,]+)")
    if not (c and c.fps and want) then return false end
    want = want:lower()
    for name in pairs(c.fps) do
        local city, zone = name:match("^([^,]+),%s*(.+)$")
        city, zone = (city or name):lower(), zone or ""
        -- the town ("Menethil Harbor"), or the zone when it has just the one flight master ("Westfall")
        if city == want or (zone:lower() == want and c.fpZone and c.fpZone[zone] == 1) then return true end
    end
    return false
end
ns.fpKnown = fpKnown

local function eventDone(kind)
    local c = ItineraryCharDB
    local steps = ns.steps()
    local s = steps[c.step]
    local hit = false
    -- a weapon master step is done by the skill itself, not by closing some trainer
    if s and s.t == kind and not s.wpn then c.manual[c.step] = true; hit = true end
    -- the same kind of step running along (a hearth under Instructions): done too
    for _, j in ipairs(ns.alongActive(c.step)) do
        if steps[j].t == kind and not steps[j].wpn then c.manual[j] = true; hit = true end
    end
    if hit then ns.update() end
end

-- A quest marked "not offered to you" that is in your log after all: its steps count again, and the route
-- goes back to the first of them that isn't done yet
-- back to the first step of quest q behind you that isn't done yet (its objectives, its hand-in)
local function backToQuest(q)
    local c = ItineraryCharDB
    for j, st in ipairs(ns.steps()) do
        if j >= c.step then break end
        local has = false
        if st.q and st.t ~= "accept" then for _, x in ipairs(st.q) do if x == q then has = true end end end
        if has and not st.along and not ns.stepDone(j) then c.step = j return true end
    end
    return false
end
function ns.restoreQuest(q)
    local c = ItineraryCharDB
    if not (c and c.unavailQ and c.unavailQ[q]) then return false end
    c.unavailQ[q] = nil
    local steps = ns.steps()
    for j, st in ipairs(steps) do
        if c.unavail[j] and st.q then for _, x in ipairs(st.q) do if x == q then c.unavail[j] = nil end end end
    end
    backToQuest(q)
    return true
end
-- A quest left out (skipped where you'd take it, or abandoned) that you take after all: its steps count again,
-- and when the route went past them meanwhile it goes back to the first one that isn't done
function ns.retakeQuest(q, again)
    local c = ItineraryCharDB
    local was = again or (c and c.droppedQ and c.droppedQ[q])
    ns.undropQuests({ q })
    if not was then return false end
    -- (not in the log yet this very moment: look again once it is)
    if not again and not onQuest(q) then C_Timer.After(0.5, function() ns.retakeQuest(q, true); ns.update() end) return true end
    local from = c.step
    if backToQuest(q) then
        c.lastJump = { from = from, to = c.step, at = date and date("%H:%M:%S") or "", why = { "took " .. tostring(q) .. " after all" } }
        ns.print("you took a quest you had left out: back to its steps")
    end
    return true
end
-- after login (the quest log is there): repair marks for quests you have
function ns.restoreQuests()
    local c = ItineraryCharDB
    local any = false
    for q in pairs(c and c.unavailQ or {}) do
        if onQuest(q) and ns.restoreQuest(q) then any = true end
    end
    if any then ns.update() end
end

-- Talking to the quest giver of the current accept step: if none of the step's quests are on offer
-- (a pre-quest you didn't do, or still too low), move on instead of waiting for them.
local function checkOffered(event)
    local c = ItineraryCharDB
    local i = c.step
    local s = ns.steps()[i]
    if not (s and s.t == "accept" and s.npc) then return end
    if UnitName("npc") ~= s.npc then return end
    local missing = {}
    for k, q in ipairs(s.q) do
        if not (onQuest(q) or flaggedDone(q)) then missing[#missing + 1] = { q = q, n = s.n and s.n[k] } end
    end
    if #missing == 0 then return end
    local offered, known = {}, false
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if info.questID then offered[info.questID] = true end
        end
        known = true
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableQuestInfo then
        known = true
        for k = 1, GetNumAvailableQuests() do
            local id = select(5, GetAvailableQuestInfo(k))
            if not id then known = false break end
            offered[id] = true
        end
    end
    if not known then return end
    for _, m in ipairs(missing) do if offered[m.q] then return end end
    -- quests you are too low for aren't shown either: wait instead of skipping
    local lvl = UnitLevel("player") or 1
    if (s.minlv and lvl < s.minlv) or (not s.minlv and lvl < (s.lv or 1) + 1) then
        if s.minlv then ns.print((s.n and s.n[1] or "This quest") .. " needs level " .. s.minlv .. " - keep grinding.") end
        return
    end
    -- not in the list right now - but the list can already be empty because the quest was just taken
    -- (auto accept, or you clicked it): only when it still isn't in your log a moment later is it really
    -- not offered
    C_Timer.After(2.5, function()
        local still = {}
        for _, m in ipairs(missing) do if not (onQuest(m.q) or flaggedDone(m.q)) then still[#still + 1] = m end end
        if #still == 0 or c ~= ItineraryCharDB or c.step ~= i then return end
        c.unavail[i] = true
        local names = {}
        for _, m in ipairs(still) do names[#names + 1] = m.n or ("quest " .. m.q); c.unavailQ[m.q] = true end
        ns.print(table.concat(names, ", ") .. " not offered to you (a pre-quest you skipped, or too low level), moving on. /iti back to return to it.")
        ns.update()
    end)
end

---------------------------------------------------------------- /played: pace against the route's reference run
local played = { total = nil, at = nil }    -- last known /played and the GetTime() it was read at
function ns.playedNow()
    if not played.total then return nil end
    return played.total + (GetTime() - played.at)
end
function ns.levelStartPlayed(level) return ItineraryCharDB.levelAt[level] end

---------------------------------------------------------------- step completion sound (Settings > Display)
-- Steps that take a while, worth a sound when they're done: kill / loot several of something
-- ("Kill Small Crag Boar (x12)", "Collect Tough Wolf Meat (x8)"), collecting several items, grinding.
-- A single kill, an emote or one item isn't (too spammy).
function ns.longStep(s)
    if s.t == "xp" then return true end
    local function many(text) local n = text and tonumber(text:match("%(x(%d+)%)") or text:match("%d+%s*/%s*(%d+)")) return n and n >= 2 end
    if s.t == "complete" then
        for _, o in ipairs(s.obj or {}) do if many(o) then return true end end
        for _, l in ipairs(ns.objectiveLines and ns.objectiveLines(s) or {}) do if many(l[1]) then return true end end
        return false
    end
    for _, c in ipairs(s.col or {}) do if (c[2] or 1) >= 2 then return true end end
    return false
end

-- Step sounds ship with Itinerary (sounds\), so everyone hears the same thing; only "Quest" is the game's own
local SND = "Interface\\AddOns\\Itinerary\\sounds\\"
ns.SOUNDS = {
    { "Off", nil },
    { "Quest", kit = "IG_QUEST_LIST_COMPLETE", id = 878, file = SND .. "Drop.ogg" },
    { "Drop", file = SND .. "Drop.ogg" },
    { "Ping", file = SND .. "Sonar.ogg" },
    { "Blip", file = SND .. "Blip.ogg" },
    { "Coins", file = SND .. "Coins.ogg" },
    { "Bell", file = SND .. "Bell.ogg" },
    { "Xylophone", file = SND .. "Xylophone.ogg" },
    { "Fanfare", file = SND .. "Fanfare.ogg" },
    { "Meow", file = SND .. "Meow.ogg" },
}
local OLD = { Chime = "Quest" } -- names from earlier versions
function ns.stepSound(name)
    name = name or ItineraryDB.stepSound
    name = OLD[name] or name
    for _, snd in ipairs(ns.SOUNDS) do
        if snd[1] == name then
            if snd.kit or snd.id then
                local id = (SOUNDKIT and SOUNDKIT[snd.kit]) or snd.id
                local ok, willPlay = pcall(PlaySound, id, "Master")
                if ok and willPlay ~= false then return end
            end
            if snd.file then pcall(PlaySoundFile, snd.file, "Master") end
            return
        end
    end
end

---------------------------------------------------------------- updates (throttled)
local pending = false
-- What a step is, independent of its number (to find it again when the route is rebuilt)
local function stepKey(s)
    if not s then return nil end
    return s.t .. ":" .. (s.q and table.concat(s.q, ",") or (s.name or "")) .. ":" .. (s.npc or "")
end

-- After an update of the routes the step numbers move: find the step you were on (by what it is), or else
-- the step after the last quest step you've done
function ns.resyncRoute()
    local c, r = ItineraryCharDB, ns.route()
    if not (c and r and r.seq and r.steps) then return end
    local sig = tostring(#r.seq)
    if c.routeSig == sig then return end
    local old, known = c.routeSig, (c.step or 1) > 1
    c.routeSig = sig
    if not old and not known then return end
    local steps, at = r.steps, nil
    if c.stepKey then
        local best
        for j = 1, #steps do
            if stepKey(steps[j]) == c.stepKey and (not best or math.abs(j - c.step) < math.abs(best - c.step)) then best = j end
        end
        at = best
    end
    if not at then
        local last = 0
        for j = 1, #steps do
            local s = steps[j]
            if (s.t == "accept" or s.t == "turnin" or s.t == "complete") and not s.along and not s.opt and ns.stepDone(j) then last = j end
        end
        at = last + 1
    end
    if at ~= c.step then
        c.step, c.manual = at, {}
        ns.print("the routes were updated - picked up again at step " .. at)
    end
    ns.advance()
    if ns.refresh then ns.refresh() end
end

function ns.update()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        dropCache = nil -- quest log changes: work the dropped chains out again
        local c, before = ItineraryCharDB, ItineraryCharDB.step
        ns.advance()
        c.stepKey = stepKey(ns.steps()[c.step])
        if ns.refreshEditor then ns.refreshEditor() end
        -- a sound when the step you were on got done (not when skipping, not on the first look after login),
        -- only for the ones that take a while: kill / loot objectives, collecting items, grinding a level
        local sb = ns.steps()[before]
        local long = sb and ns.longStep(sb)
        if long and ns.sawStep and c.step > before and not c.manual[before] and ns.stepDone(before) then ns.stepSound() end
        ns.sawStep = true
        if ns.refresh then ns.refresh() end
        if ns.updateItems then ns.updateItems() end
    end)
end

local f = CreateFrame("Frame")
local events = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "TIME_PLAYED_MSG", "PLAYER_CONTROL_LOST",
    "UNIT_SPELLCAST_SUCCEEDED", "HEARTHSTONE_BOUND", "TRAINER_CLOSED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "TAXIMAP_OPENED", "UI_INFO_MESSAGE", "BAG_UPDATE_DELAYED", "PLAYER_XP_UPDATE", "GOSSIP_SHOW", "QUEST_GREETING", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
}
for _, e in ipairs(events) do pcall(f.RegisterEvent, f, e) end

local askedPlayed = false
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 == ADDON then defaults() else tagPack(a1) end
        return
    end
    if not ItineraryCharDB then return end
    if event == "PLAYER_LOGIN" then
        -- a new character with the name of a deleted one inherits its saved data: start it fresh
        local c, guid = ItineraryCharDB, UnitGUID and UnitGUID("player")
        -- after a factory reset every character starts fresh too (each one the first time it logs in)
        if ItineraryDB.epoch and c.epoch ~= ItineraryDB.epoch then
            ItineraryCharDB = { epoch = ItineraryDB.epoch }
            defaults()
            c = ItineraryCharDB
        end
        if guid and c.guid and c.guid ~= guid then
            ns.wipeCharacter("new character with this name - started fresh")
        elseif guid and not c.guid and c.trainedLevel and c.trainedLevel > (UnitLevel("player") or 1) then
            ns.wipeCharacter("saved data was from a higher-level character with this name - started fresh")
        end
        ItineraryCharDB.guid = guid
        ns.pickRoute()
        ns.prepareRoute(ns.route())
        if ns.buildUI then ns.buildUI() end
        if ns.refreshRecStatus then ns.refreshRecStatus() end
        -- the quest log is complete a moment after login
        C_Timer.After(3, function() ns.resyncRoute(); ns.restoreQuests() end)
        -- another addon (our logger) usually asks for /played at login; ask ourselves if nobody did
        C_Timer.After(15, function()
            if not played.total and not askedPlayed and RequestTimePlayed then askedPlayed = true; RequestTimePlayed() end
        end)
        ns.update()
    elseif event == "TIME_PLAYED_MSG" then
        played.total, played.at = a1, GetTime()
        local lvl = UnitLevel("player")
        if a2 and lvl and not ItineraryCharDB.levelAt[lvl] then ItineraryCharDB.levelAt[lvl] = a1 - a2 end
        if ns.refresh then ns.refresh() end
    elseif event == "PLAYER_LEVEL_UP" then
        local now = ns.playedNow()
        if now and a1 then ItineraryCharDB.levelAt[a1] = now end
        ns.update()
    elseif event == "QUEST_ACCEPTED" then
        -- a quest we took for "not offered to you" (too low then, or a pre-quest) that you got after all:
        -- its steps count again (kill, loot, turn in)
        local q = (type(a2) == "number" and a2 > 0) and a2 or a1
        if q then
            ns.restoreQuest(q)
            ns.retakeQuest(q)
        end
        ns.update()
    elseif event == "QUEST_REMOVED" then
        -- abandoned (not handed in): a route quest you gave up is dropped, with its follow-ups
        local q = a1
        if type(q) == "number" and q > 0 then
            C_Timer.After(1.5, function()
                if onQuest(q) or flaggedDone(q) then return end
                local inRoute = false
                for _, st in ipairs(ns.steps()) do
                    if st.q and (st.t == "complete" or st.t == "turnin") then
                        for _, x in ipairs(st.q) do if x == q then inRoute = true break end end
                    end
                    if inRoute then break end
                end
                if not inRoute then return end
                ns.dropQuests({ q })
                local n = ns.followUpsOf(q)
                ns.print("quest abandoned: its steps" .. (n > 0 and (" and " .. n .. " follow-up quest" .. (n == 1 and "" or "s")) or "")
                    .. " are left out. Take it again to bring them back.")
                ns.update()
            end)
        end
        ns.update()
    elseif event == "QUEST_TURNED_IN" then
        if a1 then turnedIn[a1] = true end
        ns.update()
    elseif event == "PLAYER_CONTROL_LOST" then
        C_Timer.After(1, function() if UnitOnTaxi and UnitOnTaxi("player") then eventDone("fly") end end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" and a3 == 8690 then eventDone("hearth") end
    elseif event == "HEARTHSTONE_BOUND" then
        eventDone("sethearth")
    elseif event == "TRAINER_CLOSED" then
        eventDone("train")
    elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        ns.update()
    elseif event == "TAXIMAP_OPENED" then
        ns.noteFlightPaths()
        eventDone("fp")
    elseif event == "UI_INFO_MESSAGE" then
        -- "New flight path discovered!" (talking to the flight master learns it; the map may not open)
        local msg = type(a2) == "string" and a2 or (type(a1) == "string" and a1) or nil
        if msg and ((ERR_NEWTAXIPATH and msg == ERR_NEWTAXIPATH) or msg:lower():find("flight path")) then eventDone("fp") end
    elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        -- talking to the flight master of a "get the flight path" step: you have it now
        local cur = ns.steps()[ItineraryCharDB.step]
        if cur and cur.t == "fp" and cur.npc and UnitName("npc") == cur.npc then eventDone("fp") end
        checkOffered(event) -- right away, before the automation picks a quest and the list changes
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        local inInstance = IsInInstance and IsInInstance()
        if inInstance then eventDone("dungeon") end
        ns.update()
    else
        ns.update()
    end
end)

---------------------------------------------------------------- slash commands
SLASH_ITINERARY1 = "/itinerary"
SLASH_ITINERARY2 = "/iti"
SlashCmdList.ITINERARY = function(input)
    local cmd, arg = (input or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "" then if ns.togglePanel then ns.togglePanel() end
    elseif cmd == "next" or cmd == "skip" then ns.skip()
    elseif cmd == "back" or cmd == "prev" then ns.back()
    elseif cmd == "goto" and tonumber(arg) then ns.setStep(tonumber(arg))
    elseif cmd == "arrow" then if ns.toggleArrow then ns.toggleArrow() end
    elseif cmd == "lock" or cmd == "unlock" then if ns.setLocked then ns.setLocked(cmd == "lock"); ns.setArrowLocked(cmd == "lock") end
    elseif cmd == "find" then
        -- jump to the first unfinished step from the start (after skipping around)
        ItineraryCharDB.step = 1; ns.advance(); if ns.refresh then ns.refresh() end
        ns.print("now at step " .. ItineraryCharDB.step)
    elseif cmd == "reset" then
        ItineraryCharDB.step, ItineraryCharDB.manual, ItineraryCharDB.unavail, ItineraryCharDB.unavailQ, ItineraryCharDB.arrived = 1, {}, {}, {}, {}
        ItineraryCharDB.gates = nil
        ns.advance(); if ns.refresh then ns.refresh() end
        ns.print("route progress reset; moved to the first unfinished step (" .. ItineraryCharDB.step .. ")")
    elseif cmd == "factoryreset" then
        if arg == "yes" then ns.factoryReset()
        else ns.print("/iti factoryreset yes = Itinerary as if just installed: all settings, your route edits and own routes, and every character's progress are deleted, then the UI reloads.") end
    elseif cmd == "wipe" then
        if arg == "yes" then ns.wipeCharacter()
        else ns.print("/iti wipe yes = forget everything Itinerary saved for this character (route progress, trainer, professions). Settings stay.") end
    elseif cmd == "routes" then
        -- your class first, then the rest (/iti routes all lists every one)
        local _, class = UnitClass("player")
        local ids = {}
        for id, r in pairs(ns.routes) do
            if arg == "all" or not (r.match and r.match.class) or r.match.class == class then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do ns.print(id .. " = " .. (ns.routes[id].name or id) .. (id == ItineraryCharDB.route and " (active)" or "")) end
        if arg ~= "all" then ns.print("/iti routes all = every race and class; /iti route <id> = switch") end
    elseif cmd == "route" and ns.routes[arg] then
        ns.switchRoute(arg, true)
    elseif cmd == "debug" then
        -- what the game says about the current step's quests
        local i = ItineraryCharDB.step
        local st = ns.steps()[i]
        ns.print("step " .. i .. ": " .. (st and st.t or "none"))
        local cur, ci = ns.current()
        ns.print(string.format("  showing: %s %s  map %s  %.1f, %.1f%s", tostring(cur and cur.t), tostring(cur and (cur.name or cur.npc) or ""),
            tostring(cur and cur.m), cur and cur.x or 0, cur and cur.y or 0, cur and cur.detour and "  (detour)" or ""))
        local c = ItineraryCharDB
        local costs = {}
        for l, v in pairs(c.trainCosts or {}) do costs[#costs + 1] = l .. "=" .. v .. "/" .. ((c.trainTotals or {})[l] or "?") end
        ns.print(string.format("  trainer: visited at %s, owed %s (all %s), next %s, costs %s, pending %s/%s, money %d, waiting %s",
            tostring(c.trainedLevel), tostring(c.trainOwed), tostring(c.trainOwedAll), tostring(c.trainNext), table.concat(costs, " "),
            tostring(ns.pendingSpellCost()), tostring(ns.pendingSpellCost(true)), GetMoney() or 0, tostring(ns.spellsWaiting())))
        if c.trainSeenNow then ns.print("  last class trainer list: " .. c.trainSeenNow) end
        local okW, errW = pcall(function()
            local miss, names = ns.weaponsMissing(), {}
            for _, id in ipairs(ns.weaponPlan().want) do if miss[id] then names[#names + 1] = ns.WPN_NAME[id] end end
            local wm, wd = ns.nearestWeaponMaster()
            ns.print(string.format("  weapons (%s): missing %s; nearest master %s%s", tostring(ItineraryDB.auto.weapons or "route"),
                #names > 0 and table.concat(names, ", ") or "none", wm and wm.name or "none",
                wd and string.format(" at %d yd", math.floor(wd)) or ""))
        end)
        if not okW then ns.print("  weapons: error " .. tostring(errW)) end
        local okT, errT = pcall(ns.findDetours)
        if not okT then ns.print("  trainer checks: error " .. tostring(errT))
        else
            local names = {}
            for _, d in ipairs(errT) do names[#names + 1] = (d.name or "Train new skills") .. " at " .. tostring(d.npc) .. (d.dist and string.format(" (%d yd)", math.floor(d.dist)) or "") end
            ns.print("  trainers close by: " .. (#names > 0 and table.concat(names, "; ") or "none"))
        end
        local pm = C_Map.GetBestMapForUnit("player")
        local A = _G.ItineraryArrow
        ns.print("  you: map " .. tostring(pm) .. "  arrow " .. (A and (A:IsShown() and "shown" or "hidden") or "missing")
            .. "  setting " .. tostring(ItineraryDB.arrow.shown))
        for _, q in ipairs(st and st.q or {}) do
            local a = C_QuestLog and C_QuestLog.IsOnQuest and tostring(C_QuestLog.IsOnQuest(q)) or "n/a"
            local b = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and tostring(C_QuestLog.GetLogIndexForQuestID(q)) or "n/a"
            ns.print(string.format("  quest %d: IsOnQuest %s, log index %s, turned in %s, ready %s",
                q, a, b, tostring(flaggedDone(q)), tostring(readyToTurnIn(q))))
        end
    elseif cmd == "chapters" then if ns.toggleChapters then ns.toggleChapters() end
    elseif cmd == "chapter" and tonumber(arg) then ns.gotoChapter(tonumber(arg))
    elseif cmd == "pins" then
        ItineraryDB.pins = (ItineraryDB.pins == false)
        if ns.refreshPins then ns.refreshPins() end
        ns.print("map pins " .. (ItineraryDB.pins and "shown" or "hidden"))
    elseif cmd == "minimap" then if ns.toggleMinimap then ns.toggleMinimap() end
    elseif cmd == "target" then
        if ns.targetDebug then ns.targetDebug() end
    elseif cmd == "tags" then
        if ns.objTagDebug then ns.objTagDebug() end
    elseif cmd == "track" then
        if ns.trackState then ns.print("tracking: " .. ns.trackState()) end
        for _, l in ipairs(ItineraryDB.trackLog or {}) do print("  " .. l) end
    elseif cmd == "gather" then if ns.gatherToggle then ns.gatherToggle() end
    elseif cmd == "settings" or cmd == "options" or cmd == "config" then if ns.openSettings then ns.openSettings(true) end
    elseif cmd == "edit" or cmd == "editor" then if ns.openEditor then ns.openEditor(true) end
    elseif cmd == "record" then if ns.setRecording then ns.setRecording() end
    elseif cmd == "recorder" or cmd == "rec" then if ns.openRecorder then ns.openRecorder(true) end
    elseif cmd == "export" then if ns.openShare then ns.openShare("export", ItineraryCharDB.route) end
    elseif cmd == "dump" then if ns.dumpRoute then ns.dumpRoute(arg) end
    elseif cmd == "import" then if ns.openShare then ns.openShare("import") end
    elseif cmd == "professions" or cmd == "prof" then if ns.showProfPicker then ns.showProfPicker() end
    else
        ns.print("/iti = show/hide the route, /iti next, /iti back, /iti goto <step>, /iti find, /iti routes, /iti arrow, /iti lock, /iti unlock, /iti chapters, /iti chapter <n>, /iti pins, /iti minimap, /iti settings, /iti professions, /iti gather, /iti edit, /iti recorder, /iti record, /iti export, /iti import, /iti reset, /iti wipe, /iti debug")
    end
end
