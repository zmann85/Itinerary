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
