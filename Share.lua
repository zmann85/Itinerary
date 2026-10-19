-- Itinerary: share your own routes as a text string (export) and add someone else's (import).
-- A route of yours is a list of changes (ItineraryDB.edits[id].ops) on top of a route that comes with the addon,
-- or on an empty route. The string holds those changes plus which route they go on:
--   "!ITI1!" .. printable(deflate(serialize(payload)))
-- Nothing in a string is ever run: it is data, checked field by field on import, and macros on item buttons
-- are only kept when they are plain emotes and targeting/use lines.
local ADDON, ns = ...

local PREFIX = "!ITI1!"
local LibSerialize = LibStub and LibStub("LibSerialize", true)
local LibDeflate = LibStub and LibStub("LibDeflate", true)

local function baseId(id) return id and (id:gsub("@.*$", "")) end

---------------------------------------------------------------- export
function ns.exportRoute(id)
    local def = ItineraryDB.customRoutes and ItineraryDB.customRoutes[id]
    if not def then return nil, "Only your own routes can be exported (make a copy of this one first)." end
    if not (LibSerialize and LibDeflate) then return nil, "The libraries for sharing are missing." end
    local E = ItineraryDB.edits and ItineraryDB.edits[id]
    local src = def.from and ns.routes[def.from]
    local payload = {
        fmt = 1,
        name = def.name, faction = def.faction, match = def.match, recorded = def.recorded,
        from = def.from, fromBase = baseId(def.from), fromVn = src and src.vn, fromName = src and src.name,
        ops = E and E.ops or {},
        author = UnitName and UnitName("player") or nil,
        at = time and time() or nil,
    }
    local ser = LibSerialize:Serialize(payload)
    local packed = LibDeflate:CompressDeflate(ser, { level = 9 })
    return PREFIX .. LibDeflate:EncodeForPrint(packed)
end

---------------------------------------------------------------- import: read and check
-- plain data only: strings, numbers, booleans and tables of them, not too deep or too big
local function clean(v, depth)
    local t = type(v)
    if t == "string" then return #v <= 4000 and v or v:sub(1, 4000) end
    if t == "number" then return (v == v and v ~= math.huge and v ~= -math.huge) and v or nil end
    if t == "boolean" then return v end
    if t ~= "table" or depth > 6 then return nil end
    local out, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 20000 then break end
        if type(k) == "string" or type(k) == "number" then
            local c = clean(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

-- macro lines an imported route may put on an item button: emotes, targeting, using an item, casting
local SAFE_SLASH = {
    ["/sit"] = true, ["/stand"] = true, ["/kneel"] = true, ["/sleep"] = true, ["/dance"] = true, ["/wave"] = true,
    ["/cheer"] = true, ["/bow"] = true, ["/salute"] = true, ["/emote"] = true, ["/e"] = true, ["/me"] = true,
    ["/target"] = true, ["/tar"] = true, ["/targetexact"] = true, ["/tm"] = true, ["/cleartarget"] = true,
    ["/use"] = true, ["/cast"] = true, ["/stopcasting"] = true, ["/equip"] = true, ["/startattack"] = true,
    ["/roar"] = true, ["/flex"] = true, ["/kiss"] = true, ["/hug"] = true, ["/applaud"] = true, ["/clap"] = true,
    ["/laugh"] = true, ["/thank"] = true, ["/greet"] = true, ["/pray"] = true, ["/beg"] = true, ["/chicken"] = true,
    ["/flirt"] = true, ["/cry"] = true, ["/cower"] = true, ["/plead"] = true, ["/bonk"] = true, ["/tickle"] = true,
    ["/shy"] = true,
}
local function safeMacro(text)
    if type(text) ~= "string" then return false end
    for line in text:gmatch("[^\n]+") do
        local cmd = line:match("^%s*(/%S+)")
        if not (cmd and SAFE_SLASH[cmd:lower()]) then return false end
    end
    return true
end

local VALID_T = { accept = 1, complete = 1, turnin = 1, go = 1, ["do"] = 1, train = 1, xp = 1, fly = 1, hearth = 1,
                  sethearth = 1, fp = 1, dungeon = 1, vendor = 1 }

-- returns the checked route (or nil and why), and how many macros were left out
function ns.decodeShared(str)
    if not (LibSerialize and LibDeflate) then return nil, "The libraries for sharing are missing." end
    str = tostring(str or ""):gsub("%s+", "")
    if str:sub(1, #PREFIX) ~= PREFIX then return nil, "This isn't an Itinerary route (it should start with " .. PREFIX .. ")." end
    local packed = LibDeflate:DecodeForPrint(str:sub(#PREFIX + 1))
    local ser = packed and LibDeflate:DecompressDeflate(packed)
    if not ser then return nil, "The text is damaged or incomplete (copy it again, all of it)." end
    local ok, payload = LibSerialize:Deserialize(ser)
    if not ok or type(payload) ~= "table" or payload.fmt ~= 1 then return nil, "The text couldn't be read." end
    payload = clean(payload, 0)
    if type(payload.ops) ~= "table" then return nil, "There is no route in this text." end
    local ops, dropped, maxId = {}, 0, 0
    for _, op in ipairs(payload.ops) do
        if type(op) == "table" then
            if op.k == "add" and type(op.s) == "table" and VALID_T[op.s.t] and tonumber(op.id) then
                local s = op.s
                if s.macro and not (type(s.macro) == "table" and safeMacro(s.macro[3])) then s.macro = nil; dropped = dropped + 1 end
                ops[#ops + 1] = { k = "add", id = tonumber(op.id), after = type(op.after) == "string" and op.after or "^", s = s }
                if tonumber(op.id) > maxId then maxId = tonumber(op.id) end
            elseif op.k == "hide" and type(op.at) == "string" then
                ops[#ops + 1] = { k = "hide", at = op.at }
            elseif op.k == "set" and type(op.at) == "string" and type(op.f) == "table" then
                if op.f.macro and not (type(op.f.macro) == "table" and safeMacro(op.f.macro[3])) then op.f.macro = nil; dropped = dropped + 1 end
                if op.f.t and not VALID_T[op.f.t] then op.f.t = nil end
                ops[#ops + 1] = { k = "set", at = op.at, f = op.f }
            end
        end
    end
    payload.ops, payload.maxId, payload.droppedMacros = ops, maxId, dropped
    return payload
end

-- which installed route an imported copy goes on: the same one, else the newest version of it
local function findBase(p)
    if not p.from then return nil, true end
    if ns.routes[p.from] then return p.from, true end
    local best
    for id, r in pairs(ns.routes) do
        if not r.custom and baseId(id) == p.fromBase and (not best or ns.versionCompare(r, ns.routes[best]) > 0) then best = id end
    end
    return best, false
end

function ns.importPreview(p)
    local adds, changes = 0, 0
    for _, op in ipairs(p.ops) do if op.k == "add" then adds = adds + 1 else changes = changes + 1 end end
    local lines = { "|cffffffff" .. (p.name or "Unnamed route") .. "|r" .. (p.author and ("  ·  by " .. p.author) or "") }
    local myFaction = UnitFactionGroup and UnitFactionGroup("player")
    if p.from then
        local base, exact = findBase(p)
        if not base then
            lines[#lines + 1] = "|cffff7766Built on " .. (p.fromName or p.from) .. ", which this character doesn't have"
                .. (p.faction and p.faction ~= myFaction and (" (a " .. p.faction .. " route)") or "") .. ". Import it on a fitting character.|r"
            return table.concat(lines, "\n"), false
        end
        local r = ns.routes[base]
        lines[#lines + 1] = "Your changes to " .. (r.name or base) .. " " .. (r.version or "")
            .. (exact and "" or ("  |cffd9b26f(made on " .. (p.fromVn and ("v" .. p.fromVn) or "another version") .. ": a few steps may not line up)|r"))
        lines[#lines + 1] = string.format("%d added steps, %d changed or hidden", adds, changes)
    else
        lines[#lines + 1] = string.format("A route of its own: %d steps", adds)
    end
    if p.faction and p.faction ~= myFaction then lines[#lines + 1] = "|cffd9b26fA " .. p.faction .. " route.|r" end
    if p.droppedMacros > 0 then lines[#lines + 1] = "|cffd9b26f" .. p.droppedMacros .. " item-button macro(s) left out (only emotes, targeting and use/cast lines are taken over).|r" end
    return table.concat(lines, "\n"), true
end

function ns.importRoute(p)
    local base = p.from and findBase(p) or nil
    if p.from and not base then return nil end
    ItineraryDB.customRoutes = ItineraryDB.customRoutes or {}
    local n = 1
    while ItineraryDB.customRoutes["my-route-" .. n] do n = n + 1 end
    local id = "my-route-" .. n
    local name = p.name or "Imported route"
    for _, d in pairs(ItineraryDB.customRoutes) do if d.name == name then name = name .. " (imported)" break end end
    ItineraryDB.customRoutes[id] = { name = name, faction = p.faction, match = type(p.match) == "table" and p.match or nil,
                                     from = base, recorded = p.recorded, imported = p.author or true }
    ItineraryDB.edits = ItineraryDB.edits or {}
    ItineraryDB.edits[id] = { ops = p.ops, n = p.maxId or 0 }
    if ns.registerCustomRoutes then ns.registerCustomRoutes() end
    ns.print("imported \"" .. name .. "\": pick it with the list button in the panel footer")
    return id
end

---------------------------------------------------------------- the window
local win
local function build()
    local ui = ns.ui
    local ar, ag, ab = ui.accent()
    local W, H, P = 520, 340, 14
    win = CreateFrame("Frame", "ItineraryShareWindow", UIParent)
    win:SetSize(W, H); win:SetPoint("CENTER", 0, 60)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetClampedToScreen(true); win:EnableMouse(true); win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ItineraryShareWindow")
    local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.077, 0.068, 0.058, 0.97)
    ui.addEdges(win, 1, 1, 1, 0.15)
    local top = win:CreateTexture(nil, "ARTWORK"); top:SetColorTexture(ar, ag, ab, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
    local eyebrow = ui.text(win, 12, ar, ag, ab, 0.9); eyebrow:SetPoint("TOPLEFT", P, -12); eyebrow:SetText("ITINERARY")
    win.title = ui.text(win, 18, 1, 1, 1, 1); win.title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -3)
    local close = CreateFrame("Button", nil, win)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -8, -8)
    local x = ui.text(close, 18, 1, 1, 1, 0.5); x:SetPoint("CENTER"); x:SetJustifyH("CENTER"); x:SetText("×")
    close:SetScript("OnClick", function() win:Hide() end)
    win.hint = ui.text(win, 11, 1, 1, 1, 0.55); win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -8)
    win.hint:SetWidth(W - P * 2); win.hint:SetJustifyH("LEFT")

    -- the text box (scrolls; a long route is a long string)
    local box = CreateFrame("Frame", nil, win)
    box:SetPoint("TOPLEFT", P, -84); box:SetPoint("TOPRIGHT", -P, -84); box:SetHeight(130)
    local bbg = box:CreateTexture(nil, "BACKGROUND"); bbg:SetAllPoints(); bbg:SetColorTexture(0.03, 0.03, 0.03, 0.8)
    ui.addEdges(box, 1, 1, 1, 0.15)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 6, -6); sf:SetPoint("BOTTOMRIGHT", -6, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false)
    eb:SetFont(ui.fontPath(), 11, ""); eb:SetTextColor(1, 1, 1, 0.85)
    eb:SetWidth(W - P * 2 - 12)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, eb:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - d * 30)))
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:EnableMouse(true); box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    win.eb = eb

    win.preview = ui.text(win, 12, 1, 1, 1, 0.85)
    win.preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10); win.preview:SetWidth(W - P * 2)
    win.preview:SetJustifyH("LEFT"); win.preview:SetWordWrap(true)

    win.action = ui.segment(win, "Import")
    win.action:SetSize(150, 24); win.action:SetPoint("BOTTOMRIGHT", -P, 12)
    win.action:SetScript("OnClick", function()
        if win.mode == "import" and win.parsed and win.ok then
            local id = ns.importRoute(win.parsed)
            if id then win:Hide() end
        elseif win.mode == "export" then
            eb:SetFocus(); eb:HighlightText()
        end
    end)

    eb:SetScript("OnTextChanged", function(self, user)
        if win.mode == "export" then
            -- the export text stays as it is
            if user then self:SetText(win.exportText or ""); self:HighlightText() end
            return
        end
        local t = self:GetText()
        if t == "" then win.preview:SetText(""); win.parsed, win.ok = nil, false; win.action:SetAlpha(0.35) return end
        local p, err = ns.decodeShared(t)
        if not p then
            win.parsed, win.ok = nil, false
            win.preview:SetText("|cffff7766" .. err .. "|r")
        else
            local text, ok = ns.importPreview(p)
            win.parsed, win.ok = p, ok
            win.preview:SetText(text)
        end
        win.action:SetAlpha(win.ok and 1 or 0.35)
    end)
    win:Hide()
end

function ns.openShare(mode, id)
    if not ns.ui then return end
    if not win then build() end
    win.mode, win.parsed, win.ok = mode, nil, false
    win.eb:SetText("")
    if mode == "export" then
        local str, err = ns.exportRoute(id)
        win.title:SetText("Export a route")
        if not str then
            win.hint:SetText(err)
            win.preview:SetText("")
            win.exportText = ""
            win.action:SetAlpha(0.35)
        else
            local def = ItineraryDB.customRoutes[id]
            win.hint:SetText("Copy the text (Ctrl+C) and give it to someone. They open the route editor, Import, and paste it.")
            win.exportText = str
            win.eb:SetText(str)
            win.preview:SetText(string.format("|cffffffff%s|r  ·  %d characters", def and def.name or id, #str))
            win.action.text:SetText("Select all"); win.action:SetAlpha(1)
        end
        win:Show()
        if win.exportText ~= "" then win.eb:SetFocus(); win.eb:HighlightText() end
    else
        win.title:SetText("Import a route")
        win.hint:SetText("Paste a route someone shared (Ctrl+V). You see what it is before anything is saved.")
        win.preview:SetText("")
        win.action.text:SetText("Save as my route"); win.action:SetAlpha(0.35)
        win:Show()
        win.eb:SetFocus()
    end
end

---------------------------------------------------------------- the whole route as a file (/iti dump)
-- Writes the route this character follows - every step as Itinerary built it for you (your route pack choices,
-- your edits, the steps for your race and class) - as JSON into the saved variables: ItineraryDB.routeExport. The
-- game writes it to WTF\Account\<account>\SavedVariables\Itinerary.lua at a /reload or logout; route_export.py
-- (or any Lua-string reader) takes the JSON out of it. /iti dump clear removes it again (it can be a megabyte).
-- The JSON explains itself in its first field, "about".
local ORDERED = {} -- (marks a list of { key, value } pairs written as an object in that order)
local function obj(...) local t = { ... }; t[ORDERED] = true; return t end
local function json(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
            elseif c == "\t" then return "\\t" elseif c == "\r" then return "\\r" end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "number" then
        out[#out + 1] = (v ~= v or v == math.huge or v == -math.huge) and "null" or (math.floor(v) == v and string.format("%d", v) or string.format("%.4g", v))
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" and v[ORDERED] then
        out[#out + 1] = "{"
        local first = true
        for _, kv in ipairs(v) do
            if kv[2] ~= nil then
                if not first then out[#out + 1] = "," end
                first = false
                json(kv[1], out); out[#out + 1] = ":"; json(kv[2], out)
            end
        end
        out[#out + 1] = "}"
    elseif t == "table" then
        local n = #v
        local isArray = n > 0 or next(v) == nil
        if isArray then for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then isArray = false break end end end
        if isArray then
            out[#out + 1] = "["
            for i = 1, n do if i > 1 then out[#out + 1] = "," end; json(v[i], out) end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                json(tostring(k), out); out[#out + 1] = ":"; json(v[k], out)
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "null"
    end
end
ns.toJSON = function(v) local out = {}; json(v, out); return table.concat(out) end

local ABOUT = {
    "Itinerary route export: one leveling route, step by step, as the Itinerary add-on (WoW Forever) built it for",
    "one character - its race and class, its route pack choices and its own edits are already applied.",
    "route: id, name, version, faction; pack = the route pack it comes from (with license), copyOf = your copy's original.",
    "forCharacter: race, class, level of the character it was written for. packChoices: that route pack's switches (dungeons ...).",
    "chapters: [ { chapter, name, firstStep } ] - the route's sections in order (a zone and its levels).",
    "steps: in order. Every step has step (its number), chapter, type and title; the rest only when it applies:",
    "  type: accept, complete (do a quest's objectives), turnin, travel, do, train, grind (to a level), fly, flightPath",
    "        (get it), hearth, setHearth, dungeon.",
    "  title: what to do (the step's text, or the quest names). hint: more about it.",
    "  quests: [ { id, name, objective } ] - objective n = only the quest's n-th objective. objectives: their texts.",
    "  npc: who to talk to. targets / mobs: who to target / kill.",
    "  location: { mapId (uiMapID), zone, x, y (% of that zone map), worldX, worldY, radius (yards, when it counts as",
    "            reached), subzoneId }. waypoints: the way there, [ { mapId, x, y } ]. killArea: spots for the mobs.",
    "  items: { collect: [ { id, count } ], buttons: [ item ids to use ], macro: { name, text } }.",
    "  trainer: 'class', or { weaponSkills: [ spell ids ] }, or 'other' (profession and the like).",
    "  level: { reach, xpIntoLevel / percentOfLevel / xpBelowNext } for grind steps.",
    "  optional: true = can be skipped. sideTask: true = done next to the steps up to step `until` (an instruction",
    "  or 'along the way'). deathSkip, vendorErrand, sellJunk, auctionHouse, selfFoundOnly: what kind of step.",
    "  abandonQuests: quest ids to abandon. dialogue: gossip option ids to pick.",
    "  conditions: Itinerary's own fields for when a step applies (quests in your log, level, zone, items, money,",
    "              professions ...); most were applied for the character already, some depend on how you play.",
}
local TYPE = { go = "travel", xp = "grind", fp = "flightPath", sethearth = "setHearth" }
local COND = { "cond", "lvskip", "zskip", "minlv", "need", "money", "skill", "skill2", "needProf", "buffItem", "dps",
               "gateL", "gateMax", "untilQ", "dng" }
local function pos(p) -- a waypoint or kill-area spot: { map, x, y, ... }
    if type(p) ~= "table" then return nil end
    return obj({ "mapId", p[1] }, { "x", p[2] }, { "y", p[3] })
end
function ns.dumpRoute(arg)
    if arg == "clear" then
        ItineraryDB.routeExport = nil
        ns.print("route file removed from your saved variables")
        return
    end
    local r = ns.route()
    if not r then ns.print("no route to write") return end
    local steps = ns.steps()
    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    -- quest names the route knows (accept / turn in steps name them)
    local qn = {}
    for _, s in ipairs(steps) do
        if s.q and s.n then for k, q in ipairs(s.q) do if s.n[k] and s.n[k] ~= "" then qn[q] = s.n[k] end end end
    end
    local function questName(q) return qn[q] or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)) or nil end
    local chapterOf, chapters = {}, {}
    for c, ch in ipairs(r.chapters or {}) do
        chapters[#chapters + 1] = obj({ "chapter", c }, { "name", ch.name }, { "firstStep", ch.first })
        local last = (r.chapters[c + 1] and r.chapters[c + 1].first or #steps + 1) - 1
        for j = ch.first or 1, last do chapterOf[j] = c end
    end
    local function list(t) return (type(t) == "table" and #t > 0) and t or nil end
    local out = {}
    for j, s in ipairs(steps) do
        -- the title: the step's text, else its quests' names
        local quests, names = nil, {}
        if s.q and #s.q > 0 then
            quests = {}
            for k, q in ipairs(s.q) do
                local nm = (s.n and s.n[k] ~= "" and s.n[k]) or questName(q)
                local oi = s.qo and s.qo[k]
                quests[k] = obj({ "id", q }, { "name", nm }, { "objective", (oi and oi > 0) and oi or nil })
                if nm then names[#names + 1] = nm end
            end
        end
        local titleText = s.name or (#names > 0 and table.concat(names, " / ")) or nil
        if s.t == "fly" and s.name then titleText = "Fly to " .. s.name
        elseif s.t == "fp" and s.name then titleText = "Get the flight path at " .. s.name
        elseif s.t == "hearth" and s.name then titleText = "Hearth to " .. s.name
        elseif s.t == "sethearth" and s.name then titleText = "Make the inn at " .. s.name .. " your home"
        elseif s.t == "train" and not s.name then titleText = (s.cls and "Train your class skills" or "Train") .. (s.npc and (" at " .. s.npc) or "")
        end
        titleText = titleText or s.npc or s.t
        local x, y = s.x, s.y
        if not x and s.wx and s.m and HBD then
            local ok, zx, zy = pcall(HBD.GetZoneCoordinatesFromWorld, HBD, s.wx, s.wy, s.m, true)
            if ok and zx and zy then x, y = math.floor(zx * 10000 + 0.5) / 100, math.floor(zy * 10000 + 0.5) / 100 end
        end
        local location = (s.m or s.wx or s.z) and obj({ "mapId", s.m }, { "zone", s.z or s.zone }, { "x", x }, { "y", y },
            { "worldX", s.wx }, { "worldY", s.wy }, { "radius", s.r }, { "subzoneId", s.sub }) or nil
        local wps, area
        if list(s.path) then wps = {}; for k, p in ipairs(s.path) do wps[k] = pos(p) end end
        if list(s.wp) then area = {}; for k, p in ipairs(s.wp) do area[k] = pos(p) end end
        local items
        if s.col or s.item or s.macro then
            local col
            if list(s.col) then col = {}; for k, c in ipairs(s.col) do col[k] = obj({ "id", c[1] }, { "count", c[2] }) end end
            items = obj({ "collect", col }, { "buttons", list(s.item) },
                { "macro", type(s.macro) == "table" and obj({ "name", s.macro[1] }, { "text", s.macro[3] }) or nil })
        end
        local trainer
        if s.t == "train" then
            trainer = s.cls and "class" or (s.wpn and obj({ "weaponSkills", s.wpn })) or "other"
        end
        local level = (s.t == "xp") and obj({ "reach", s.lvl }, { "xpIntoLevel", s.xpIn }, { "percentOfLevel", s.xpPct },
            { "xpBelowNext", s.xpLeft }) or nil
        local cond
        for _, k in ipairs(COND) do
            if s[k] ~= nil then cond = cond or {}; cond[k] = s[k] end
        end
        local mobs = list(s.mobs)
        local targets = list(s.targets)
        if targets and #targets == 1 and targets[1] == s.npc then targets = nil end
        out[#out + 1] = obj(
            { "step", j }, { "chapter", chapterOf[j] }, { "type", TYPE[s.t] or s.t }, { "title", titleText },
            { "hint", s.note }, { "quests", quests }, { "objectives", list(s.obj) },
            { "npc", s.npc }, { "targets", targets }, { "mobs", mobs },
            { "location", location }, { "waypoints", wps }, { "killArea", area },
            { "items", items }, { "trainer", trainer }, { "level", level },
            { "optional", s.opt or nil }, { "sideTask", s.along or nil }, { "until", s.along and s.till or nil },
            { "deathSkip", s.death or nil }, { "vendorErrand", s.errand or nil }, { "sellJunk", s.vendor or nil },
            { "auctionHouse", s.ah or nil }, { "selfFoundOnly", s.ssf or nil },
            { "abandonQuests", list(s.abandon) }, { "dialogue", type(s.gossip) == "table" and list(s.gossip) or nil },
            { "conditions", cond })
    end
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local license = r.pack and getMeta and getMeta(r.pack, "Notes") or nil
    local payload = obj(
        { "about", ABOUT },
        { "format", "Itinerary route export 1" },
        { "exported", date and date("%Y-%m-%d %H:%M") or nil },
        { "addonVersion", getMeta and getMeta(ADDON, "Version") or nil },
        { "route", obj({ "id", ItineraryCharDB.route }, { "name", r.name }, { "version", r.version }, { "faction", r.faction },
            { "pack", r.pack and obj({ "name", r.pack }, { "about", license },
                { "license", "see the pack's LICENSE.txt - the RestedXP-based routes: CC BY-NC-SA 4.0 (credit, non-commercial, share alike)" }) or nil },
            { "copyOf", r.from }) },
        { "forCharacter", obj({ "race", race }, { "class", class }, { "level", UnitLevel("player") }) },
        { "packChoices", r.pack and ItineraryCharDB.packOptions and next(ItineraryCharDB.packOptions[r.pack] or {}) and ItineraryCharDB.packOptions[r.pack] or nil },
        { "chapters", chapters },
        { "steps", out })
    local text = ns.toJSON(payload)
    ItineraryDB.routeExport = text
    ns.print(string.format("route written: %s, %d steps (%d KB). It lands in SavedVariables\\Itinerary.lua at your next /reload or logout; /iti dump clear removes it.",
        r.name or ItineraryCharDB.route, #out, math.floor(#text / 1024)))
    if r.pack then ns.print("(a route pack's routes keep that pack's license - see its LICENSE.txt)") end
end
