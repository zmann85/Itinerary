-- Itinerary UI: the step panel, the waypoint arrow and the minimap button (EllesmereUI look).
local ADDON, ns = ...
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function accent() return ns.accent() end
local function fontPath()
    if EllesmereUI and EllesmereUI.GetFontPath then
        local ok, path = pcall(EllesmereUI.GetFontPath)
        if ok and path then return path end
    end
    return STANDARD_TEXT_FONT
end
local function addEdges(frame, r, g, b, a)
    local px = 1 / (frame:GetEffectiveScale() or 1)
    local edges = {}
    local function edge() local t = frame:CreateTexture(nil, "BORDER"); t:SetColorTexture(r, g, b, a); edges[#edges + 1] = t; return t end
    local t = edge(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(px)
    local bt = edge(); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT"); bt:SetHeight(px)
    local l = edge(); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(px)
    local rt = edge(); rt:SetPoint("TOPRIGHT"); rt:SetPoint("BOTTOMRIGHT"); rt:SetWidth(px)
    return edges
end
local PANEL_FONTS = {} -- the panel's text, for the Minimal style's shadow
local function text(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), size, "")
    fs:SetTextColor(r, g, b, a or 1)
    fs:SetJustifyH("LEFT")
    fs.base = { r, g, b, a or 1 } -- its own colour, to brighten faded text over a see-through background
    fs.size = size
    PANEL_FONTS[#PANEL_FONTS + 1] = fs
    return fs
end
local function clock(sec)
    if not sec then return "-" end
    sec = math.floor(math.abs(sec) + 0.5)
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

---------------------------------------------------------------- how a step reads
local VERB = { accept = "ACCEPT", complete = "COMPLETE", turnin = "TURN IN", fly = "FLY", hearth = "HEARTH",
               sethearth = "SET HEARTH", train = "TRAIN", dungeon = "DUNGEON", fp = "FLIGHT PATH", go = "TRAVEL",
               ["do"] = "DO", xp = "GRIND", gather = "GATHER" }
local ICON = {
    gather = "Interface\\Icons\\INV_Misc_Flower_02",
    accept = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    complete = "Interface\\Icons\\INV_Sword_04",
    fly = "Interface\\GossipFrame\\TaxiGossipIcon",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    sethearth = "Interface\\GossipFrame\\BinderGossipIcon",
    train = "Interface\\GossipFrame\\TrainerGossipIcon",
    dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    fp = "Interface\\GossipFrame\\TaxiGossipIcon",
    go = "Interface\\Icons\\INV_Misc_Map_01",
    ["do"] = "Interface\\GossipFrame\\VendorGossipIcon",
    xp = "Interface\\Icons\\Spell_Holy_SealOfMight",
}
-- [Item names] in the route text: icon, quality colour and a real item / spell link, so hovering shows
-- the game's own tooltip and shift-click puts it in chat. Ids come from Links.lua (baked from the guide
-- sources and QuestieDB); names it doesn't know are looked up in what the client knows (your spells).
local SPELL_COL, PLAIN_COL = "ff71d5ff", "ffe6cc80"
local QUALITY_COL = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80" }
local linkCache, linkWaiting = {}, false
local function linkPiece(name)
    local hit = linkCache[name]
    if hit then return hit end
    local L = ns.LINKS and ns.LINKS[name]
    local kind, id, icon = nil, nil, L and L.icon
    if L and L.i then kind, id = "item", L.i elseif L and L.s then kind, id = "spell", L.s end
    if not kind then
        local sp = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
        if type(sp) == "table" and sp.spellID then kind, id, icon = "spell", sp.spellID, icon or sp.iconID end
    end
    if not kind then
        local inst = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local iid, _, _, _, ic = nil, nil, nil, nil, nil
        if inst then iid, _, _, _, ic = inst(name) end
        if iid then kind, id, icon = "item", iid, icon or ic end
    end
    local col, final = PLAIN_COL, true
    if kind == "item" then
        if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
        local q = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
        if q then col = QUALITY_COL[q] or QUALITY_COL[1] else
            col, final = QUALITY_COL[1], false -- not in the client's cache yet: white until it arrives
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            linkWaiting = true
        end
    elseif kind == "spell" then
        col = SPELL_COL
    end
    local piece = (icon and ("|T" .. icon .. ":0|t ") or "") .. "|c" .. col
        .. (kind and ("|H" .. kind .. ":" .. id .. "|h[" .. name .. "]|h") or ("[" .. name .. "]")) .. "|r"
    if final then linkCache[name] = piece end
    return piece
end
-- resume: the colour code the surrounding text was in (a link's |r ends it)
local function linkify(t, resume)
    if not t or t == "" or not t:find("[", 1, true) then return t end
    if ItineraryDB and ItineraryDB.panel and ItineraryDB.panel.links == false then return (t:gsub("[%[%]]", "")) end
    return (t:gsub("%[([^%[%]\n|]+)%]", function(n)
        if n:match("^[%d%s%%%+%-]+$") then return n end
        return linkPiece(n) .. (resume or "")
    end))
end
ns.linkify = linkify
-- an item by id (live counts "Chunk of Boar Meat 3/10"), same look
local function itemLink(id, name)
    local saved = ns.LINKS and ns.LINKS[name]
    if not (saved and saved.i == id) then
        ns.LINKS = ns.LINKS or {}
        ns.LINKS[name] = { i = id, icon = saved and saved.icon }
    end
    return linkPiece(name)
end
-- item data arriving later: redraw once with the right colours
local linkEv = CreateFrame("Frame")
linkEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
linkEv:SetScript("OnEvent", function()
    if not linkWaiting then return end
    linkWaiting = false
    C_Timer.After(0.3, function() if ns.refresh then ns.refresh() end end)
end)
-- hover / shift-click on links in a frame's text
-- The tooltip of every trainer instruction: what that trainer has for you now, with prices.
-- spec: true / a class token = your class trainer, { weapon = npc } = a weapon master,
-- { prof = key, npc = name } = a profession trainer.
local function tipLine(e, r, g, b, extra)
    local name = "|T" .. (e.icon or 134400) .. ":16:16:0:0:64:64:5:59:5:59|t  " .. e.name
        .. ((e.rank and e.rank ~= "") and ("  |cff999999" .. e.rank .. "|r") or "") .. (extra or "")
    GameTooltip:AddDoubleLine(name, e.cost and ns.money(e.cost) or "?", r, g, b, 1, 1, 1)
end
local function tipFooter(total, n)
    if n > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("All of them", ns.money(total), ns.WARM[1], ns.WARM[2], ns.WARM[3], 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Your money", ns.money(GetMoney and GetMoney() or 0), 0.7, 0.7, 0.7, 1, 1, 1)
end
function ns.trainerTip(owner, spec)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("READY TO LEARN", ns.WARM[1], ns.WARM[2], ns.WARM[3]) -- the instructions card's header colour
    local total, n = 0, 0
    if type(spec) == "table" and spec.weapon then
        -- a weapon master: the weapon skills he has that you're missing
        local buy = ItineraryDB.auto and ItineraryDB.auto.buyWeapons
        for _, e in ipairs(ns.weaponMasterList and ns.weaponMasterList(spec.weapon) or {}) do
            if e.route then tipLine(e, 0.55, 0.92, 0.5) else tipLine(e, 0.85, 0.85, 0.85) end -- green: the route trains it
            total, n = total + (e.cost or 0), n + 1
        end
        if n == 0 then GameTooltip:AddLine("Nothing known yet - open a weapon master once to fill this in.", 0.7, 0.7, 0.7, true) end
        tipFooter(total, n)
        GameTooltip:AddLine("Green: the route trains it", 0.5, 0.5, 0.5)
        if not buy then GameTooltip:AddLine("Not bought for you (Settings > Trainer > Buy weapon skills)", 0.5, 0.5, 0.5) end
    elseif type(spec) == "table" and spec.prof then
        -- a profession trainer: the profession or its next rank, then the recipes your skill allows
        local list, recorded = {}, false
        if ns.profLearnable then list, recorded = ns.profLearnable(spec.prof, spec.npc) end
        local MAX = 12
        for k, e in ipairs(list) do
            if k <= MAX then
                if e.tier then tipLine(e, 0.55, 0.92, 0.5)
                else tipLine(e, 0.85, 0.85, 0.85, (e.skill and e.skill > 0) and ("  |cff777777(" .. e.skill .. ")|r") or nil) end
            end
            total, n = total + (e.cost or 0), n + 1
        end
        if #list > MAX then GameTooltip:AddLine(string.format("... and %d more", #list - MAX), 0.6, 0.6, 0.6) end
        if n == 0 then GameTooltip:AddLine("Nothing new for your skill right now.", 0.7, 0.7, 0.7, true) end
        tipFooter(total, n)
        local learn = ItineraryDB.auto and ItineraryDB.auto.profLearn ~= false
        GameTooltip:AddLine(learn and "Green: learned for you when you open the trainer (professions you picked)"
            or "Green: the profession and its ranks", 0.5, 0.5, 0.5, true)
        if not recorded then
            GameTooltip:AddLine(spec.npc and ("Recipes show up once you've opened " .. spec.npc .. " (trainers teach different ones).")
                or ("Recipes show up once you've opened a " .. (ns.profName(spec.prof) or "") .. " trainer."), 0.5, 0.5, 0.5, true)
        end
    else
        -- your class trainer
        local list = ns.learnableSpells and ns.learnableSpells() or {}
        if #list == 0 then
            GameTooltip:AddLine("Nothing new known yet - visit the trainer once to fill this in.", 0.7, 0.7, 0.7, true)
        end
        for _, e in ipairs(list) do
            local r, g, b, extra = 0.85, 0.85, 0.85, nil
            if e.worth then r, g, b = 0.55, 0.92, 0.5 end -- worth a trainer visit: bought first
            if e.skip then r, g, b = 0.5, 0.5, 0.5; extra = "  |cff777777(not auto-bought)|r" end
            tipLine(e, r, g, b, extra)
            total, n = total + e.cost, n + 1
        end
        tipFooter(total, n)
        GameTooltip:AddLine("Green: worth a trainer visit, bought first", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end
-- the quest chain of a quest step (hover its title): the quests before it, this one, the ones that follow -
-- for each where the route takes it - and what the route's follow-ups need from this step
local CHAIN_MAX = 10 -- quests named on each side; the rest are counted
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
function ns.chainTip(owner, s, at)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local Q = ns.quest
    local ar, ag, ab = accent()
    local steps = ns.steps()
    local curCh = at and ns.chapterOf(at)
    local function where(x)
        if Q.flaggedDone(x) then return "done", 0.5, 0.5, 0.5 end
        if Q.onQuest(x) then return "in your log", 0.55, 0.92, 0.5 end
        local j = ns.routeQuestStep(x)
        if not j then return "not on this route", 0.5, 0.5, 0.5 end
        if ns.questDropped(x) then return "left out", 0.5, 0.5, 0.5 end
        local n, ch = ns.chapterOf(j)
        if j < (at or 0) then return "passed", 0.7, 0.7, 0.7 end
        if n and n == curCh then return "this chapter", 0.85, 0.85, 0.85 end
        return ch and ch.name or ("step " .. j), 0.85, 0.85, 0.85
    end
    local function nameOf(x) return ns.routeQuestName(x) or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(x)) end
    -- (a chain whose quests share a name - The Defias Brotherhood, seven times - numbers them: "(part 2)")
    local label = {}
    local function names(ch, q)
        local all, count, nth = {}, {}, {}
        for _, x in ipairs(ch.before) do all[#all + 1] = x end
        all[#all + 1] = q
        for _, x in ipairs(ch.after) do all[#all + 1] = x end
        for _, x in ipairs(all) do local n = nameOf(x); if n then count[n] = (count[n] or 0) + 1 end end
        for _, x in ipairs(all) do
            local n = nameOf(x)
            if n and count[n] > 1 then nth[n] = (nth[n] or 0) + 1; label[x] = n .. " (part " .. nth[n] .. ")" else label[x] = n end
        end
    end
    local function line(x, this)
        local name = label[x]
        if not name then return false end
        local r, g, b = 1, 1, 1
        local right, rr, rg, rb = where(x)
        if this then r, g, b = ar, ag, ab; right, rr, rg, rb = "this step", ar, ag, ab
        elseif right == "done" or right == "not on this route" or right == "left out" then r, g, b = 0.6, 0.6, 0.6 end
        GameTooltip:AddDoubleLine((Q.flaggedDone(x) and not this and CHECK or "   ") .. name, right, r, g, b, rr, rg, rb)
        return true
    end
    local function list(qs)
        local shown, more = 0, 0
        for _, x in ipairs(qs) do
            if shown < CHAIN_MAX and line(x) then shown = shown + 1 else more = more + 1 end
        end
        if more > 0 then GameTooltip:AddLine("   +" .. more .. " more", 0.6, 0.6, 0.6) end
    end
    local seen, any = {}, false
    for _, q in ipairs(s.q or {}) do
        local ch = not seen[q] and ns.questChain(q)
        seen[q] = true
        if ch then
            if any then GameTooltip:AddLine(" ") end
            any = true
            label = {}
            names(ch, q)
            GameTooltip:AddLine("QUEST CHAIN", ns.WARM[1], ns.WARM[2], ns.WARM[3])
            list(ch.before)
            if not line(q, true) then GameTooltip:AddDoubleLine("   " .. ("Quest " .. q), "this step", ar, ag, ab, ar, ag, ab) end
            list(ch.after)
            local f = ns.routeFollowUps(q, at)
            local n = #f
            if n > 0 then
                local what = n == 1 and "its follow-up" or ("its " .. n .. " follow-ups")
                local text = s.t == "accept" and ("Skip it and the route leaves out " .. what .. " too.")
                    or s.t == "turnin" and ("The route takes " .. what .. " once you've handed it in.")
                    or ("The route takes " .. what .. " once it's done.")
                GameTooltip:AddLine(text, 0.7, 0.7, 0.7, true)
            elseif #ch.after == 0 then
                GameTooltip:AddLine("The end of the chain.", 0.7, 0.7, 0.7, true)
            else
                GameTooltip:AddLine("The route doesn't take its follow-ups.", 0.7, 0.7, 0.7, true)
            end
        end
    end
    if any then GameTooltip:Show() else GameTooltip:Hide() end
end

-- what kind of trainer a route step visits, as a tooltip spec (nil: not a trainer)
function ns.trainerSpec(s)
    if not s or s.t ~= "train" then return nil end
    if s.wpn then return { weapon = s.npc } end
    if s.cls then return s.cls end
    local k = s.prof or (ns.profOfNpc and ns.profOfNpc(s.npc))
    if k then return { prof = k, npc = s.npc } end
    return nil
end

local function linkHandlers(f)
    if f.SetHyperlinksEnabled then f:SetHyperlinksEnabled(true) end
    f:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    f:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnHyperlinkClick", function(_, link)
        if not (IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
        local kind, id = link:match("^(%a+):(%d+)")
        id = tonumber(id)
        local full
        if kind == "item" then
            local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            full = info and select(2, info(id))
        elseif kind == "spell" then
            full = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id))
        end
        if full and ChatEdit_InsertLink then ChatEdit_InsertLink(full) end
    end)
end
ns.linkHandlers = linkHandlers

local function questTitle(q)
    local f = C_QuestLog and C_QuestLog.GetTitleForQuestID
    return f and f(q)
end
-- "You can afford 1 of 3 (10s of 30s)": what the class trainer has for you against your money (cheapest
-- first; the reserve auto-buy keeps doesn't count as spendable)
function ns.affordText()
    local list = ns.learnableSpells and ns.learnableSpells() or {}
    if #list == 0 then return "New skills to learn" end
    local money = GetMoney and GetMoney() or 0
    local keep = (ItineraryDB.auto and ItineraryDB.auto.train and ns.trainReserve) and ns.trainReserve() or 0
    -- the way auto-buy spends it: worthwhile skills first (a worthwhile one you can't pay for yet keeps the
    -- money), then the rest, cheapest first
    local total = 0
    for _, e in ipairs(list) do total = total + e.cost end
    local n, spent, left = 0, 0, money - keep
    local rest, blocked = {}, false
    for _, e in ipairs(list) do
        if e.worth then
            if e.cost <= left then n = n + 1; spent = spent + e.cost; left = left - e.cost else blocked = true end
        else rest[#rest + 1] = e.cost end
    end
    if not blocked then
        table.sort(rest)
        for _, c in ipairs(rest) do if c <= left then n = n + 1; spent = spent + c; left = left - c end end
    end
    if n == #list then
        return #list == 1 and "You can afford it" or ("You can afford all " .. #list)
    end
    return string.format("You can afford %d of %d (%s of %s)", n, #list, ns.money(spent), ns.money(total))
end
-- money the way the game shows it: 1g 2s 3c with the coin icons, leaving out empty units
function ns.money(c)
    c = math.floor(c or 0)
    local g, sv, cp = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
    local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
    local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    local t = {}
    if g > 0 then t[#t + 1] = g .. G end
    if sv > 0 then t[#t + 1] = sv .. S end
    if cp > 0 or #t == 0 then t[#t + 1] = cp .. C end
    return table.concat(t, " ")
end
-- a step waiting on a cooldown ("grind until your Hearthstone is ready"): how long until it's done
function ns.cdWaitText(st)
    if not (st and st.cdDone and ns.cdState) then return nil end
    local met, w = ns.cdState(st.cdDone, true)
    if met or not w then return nil end
    local what = (st.cdDone[1] == "item" and st.cdDone[2] == 6948) and "Hearthstone" or "Cooldown"
    return "|cffffd100" .. what .. ": done in " .. ns.timeText(w) .. "|r"
end
-- seconds until your Hearthstone is ready (0 = ready)
function ns.hearthCooldown()
    local cd = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not cd then return 0 end
    local start, dur = cd(6948)
    if not start or start == 0 or not dur or dur <= 1.5 then return 0 end -- (the global cooldown isn't one)
    return math.max(0, start + dur - GetTime())
end
-- a quest's level: from your quest log (remembered account-wide for the next character), else baked
local function questLevel(q)
    local idx = (C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q))
        or (GetQuestLogIndexByID and GetQuestLogIndexByID(q))
    if idx and idx > 0 then
        local lv
        local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(idx)
        if type(info) == "table" then lv = info.level end
        if not lv and GetQuestLogTitle then lv = select(2, GetQuestLogTitle(idx)) end
        if lv and lv > 0 then
            ItineraryDB.questLevels = ItineraryDB.questLevels or {}
            ItineraryDB.questLevels[q] = lv
            return lv
        end
    end
    return (ItineraryDB.questLevels and ItineraryDB.questLevels[q]) or (ns.QUEST_LEVEL and ns.QUEST_LEVEL[q])
end
-- the quest log's difficulty colours: grey, green, yellow, orange, red against your level
local function questName(q, name)
    local lv = q and questLevel(q)
    if not lv then return name end
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lv)
    local r, g, b
    if type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b
    else
        local d = lv - (UnitLevel("player") or 1)
        if d >= 5 then r, g, b = 1, 0.1, 0.1 elseif d >= 3 then r, g, b = 1, 0.5, 0.25
        elseif d >= -2 then r, g, b = 1, 0.82, 0 elseif d >= -8 then r, g, b = 0.25, 0.75, 0.25
        else r, g, b = 0.5, 0.5, 0.5 end
    end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)
end
ns.questName = questName
local function title(s)
    if s.detour and s.name then return linkify(s.name) .. (s.npc and (" at " .. s.npc) or "") end
    if s.n then
        -- (a quest of the step you're leaving out - a profession you didn't pick - isn't named)
        local t = {}
        for k, n in ipairs(s.n) do
            local q = s.q and s.q[k]
            if not (q and ns.questDropped and ns.questDropped(q) and #s.n > 1) then t[#t + 1] = questName(q, n) end
        end
        if #t == 0 then for k, n in ipairs(s.n) do t[k] = questName(s.q and s.q[k], n) end end
        return table.concat(t, "\n")
    end
    if s.t == "complete" then
        -- the quest's own name; the objectives and their counts go underneath
        local names, seen = {}, {}
        for _, q in ipairs(s.q or {}) do
            local n = questTitle(q)
            if n and not seen[n] then seen[n] = true; names[#names + 1] = questName(q, n) end
        end
        if #names > 0 then return table.concat(names, "\n") end
        if s.obj and #s.obj > 0 then return table.concat(s.obj, "\n") end
    end
    if s.t == "fly" then return "Fly to " .. (s.name or "?") end
    if s.t == "hearth" then return "Hearth to " .. (s.name or "your inn") end
    if s.t == "sethearth" then return "Make " .. (s.name or "this inn") .. " your home" end
    if s.t == "train" and s.wpn and s.name then return s.name .. (s.npc and (" at " .. s.npc) or "") end
    if s.t == "train" then return "Visit " .. (s.npc or "your trainer") end
    if s.t == "dungeon" then return "Enter " .. (s.name or "the dungeon") end
    if s.t == "fp" then return "Get the flight path" .. (s.name and s.name ~= "" and (" at " .. s.name) or "") end
    if s.t == "xp" then
        if s.name then return linkify(s.name) end
        local level, xpIn, xpPct, xpLeft = ns.xpTarget(s)
        if xpIn then return string.format("Grind to %d XP into level %d", xpIn, level) end
        if xpPct then return string.format("Grind to %d%% of level %d", math.floor(xpPct + 0.5), level) end
        if xpLeft then return string.format("Grind to %d XP short of level %d", xpLeft, level) end
        return "Grind to level " .. level
    end
    if s.name then return linkify((s.name:gsub("%s*%-%-%s*c:.*$", ""))) end
    return s.t
end
local function progressText(s)
    local lines = ns.objectiveLines and ns.objectiveLines(s) or {}
    if #lines == 0 then return nil end
    local t = {}
    for _, l in ipairs(lines) do
        -- the count in the warm accent while open, green once done; the words stay white
        local c = l[2] and "|cff33dd88" or ns.hintHex()
        local txt, n = l[1]:gsub("(%d+%s*/%s*%d+)", c .. "%1|r|cffffffff", 1)
        if n == 0 and l[2] then txt = "|cff33dd88" .. l[1] .. "|r" end
        t[#t + 1] = "|cffffffff" .. txt .. "|r"
    end
    return table.concat(t, "\n")
end
ns.progressText = progressText

-- a note that only restates the objective ("Kill Frostmane Troll Whelps") adds nothing next to the counts
local function usefulNote(s)
    local n = s.note
    if not n then return nil end
    if s.t == "complete" and not n:find("\n") and n:match("^%s*[KkLlCc]%a+ [^%.%[]*$") then return nil end
    return n
end

-- the panel's second block: live objective counts, who to talk to, and any tip worth reading.
-- Zone and coordinates are left to the arrow and the map pins.
-- items to get on this step ("collect"): link and live count, yellow while short, green when you have them
local function collectLines(s)
    if not s.col then return nil end
    local count = ns.itemCount or (C_Item and C_Item.GetItemCount) or GetItemCount -- (bags on the bag bar count)
    local nameOf = (C_Item and C_Item.GetItemNameByID) or function(id) return GetItemInfo and (GetItemInfo(id)) end
    local out = {}
    for _, c in ipairs(s.col) do
        local id, need = c[1], c[2]
        local name = nameOf(id)
        if not name then
            for n, L in pairs(ns.LINKS or {}) do if L.i == id then name = n break end end
        end
        if name then
            local have = math.min(count(id) or 0, need)
            local col = have >= need and "|cff33dd88" or ns.hintHex()
            out[#out + 1] = linkify("[" .. name .. "]") .. "  " .. col .. have .. "/" .. need .. "|r"
        end
    end
    return #out > 0 and table.concat(out, "\n") or nil
end
local function detail(s)
    local lines = {}
    local prog = progressText(s)
    -- a step with items to get lists them with counts (and leaves the bare "[Item]" lines out of its note)
    local cl = (not prog or s.t == "complete") and collectLines(s)
    if cl then prog = prog and (prog .. "\n" .. cl) or cl end
    if prog then
        lines[#lines + 1] = prog
    elseif s.t == "complete" and s.obj and #s.obj > 0 then
        lines[#lines + 1] = table.concat(s.obj, ", ")
    end
    -- (a flight: the flight master it leads to, which may not be the one the route names)
    local who = s.t == "fly" and ns.flightMasterFor and (ns.flightMasterFor(s) or {}).npc or s.npc
    if who and s.t ~= "train" and s.t ~= "complete" then lines[#lines + 1] = who end
    local note = usefulNote(s)
    if note and cl then
        local keep = {}
        for line in (note .. "\n"):gmatch("(.-)\n") do
            if not line:match("^%s*%[[^%]]+%]%s*$") then keep[#keep + 1] = line end
        end
        note = #keep > 0 and table.concat(keep, "\n") or nil
    end
    -- a line of space between the objective counts and the tip under them
    if note then lines[#lines + 1] = ((prog or (s.t == "complete" and #lines > 0)) and "\n" or "") .. ns.hintHex() .. linkify(note, ns.hintHex()) .. "|r" end
    return table.concat(lines, "\n")
end
local function oneLine(s)
    local verb = VERB[s.t] or s.t
    local t = s.n and s.n[1] or title(s)
    return verb:sub(1, 1) .. verb:sub(2):lower() .. "  " .. t
end
-- an "along the way" line: what you're collecting with its live count, or a short instruction;
-- the step's full text goes in the tooltip
-- (same form as the hearthstone's: text height in the panel, big and centred above the arrow)
local DEATH = "|TInterface\\Icons\\Spell_Holy_Resurrection:0:0:0:1:64:64:5:59:5:59|t "
local function shortObj(o) return (o:gsub("^Kill ", ""):gsub("^Collect ", ""):gsub("%s*%(x%d+%)$", "")) end
local function alongInfo(st)
    -- "Buy bread from him" means the step's own NPC, which isn't the one in front of you while
    -- this runs alongside another step: name them
    local function clean(t)
        if not t then return nil end
        t = t:gsub("%s*%-%-%s*c:[^\n]*", "") -- a stray coordinate note from the guide ("--c:Ironforge,39.5,57.4")
        if st.npc then t = t:gsub(" from h[ie][mr]%f[%A]", " from " .. st.npc) end
        return linkify(t)
    end
    -- side objectives: something to collect or kill while you go, with live counts
    if st.t == "complete" then
        local lines = ns.objectiveLines(st)
        local open, shown = 0, {}
        -- one objective per line, its count in the hint colour (the words keep the section's green); finished
        -- ones stay listed, greyed, so you see the whole quest
        local DONE = "|cff8fa898"
        for _, l in ipairs(lines) do
            if l[2] then shown[#shown + 1] = DONE .. l[1] .. "|r"
            else open = open + 1; shown[#shown + 1] = (l[1]:gsub("(%d+%s*/%s*%d+)", ns.hintHex() .. "%1|r", 1)) end
        end
        if st.col then
            local count = ns.itemCount or (C_Item and C_Item.GetItemCount) or GetItemCount -- (bags on the bag bar count)
            local nameOf = (C_Item and C_Item.GetItemNameByID) or function(id) return GetItemInfo and (GetItemInfo(id)) end
            for _, c in ipairs(st.col) do
                local have, n = math.min(count(c[1]) or 0, c[2]), nameOf(c[1])
                if n and have < c[2] then open = open + 1; shown[#shown + 1] = ns.hintHex() .. have .. "/" .. c[2] .. "|r " .. itemLink(c[1], n)
                elseif n then shown[#shown + 1] = DONE .. have .. "/" .. c[2] .. " " .. n .. "|r" end
            end
        end
        local label
        if open > 0 then label = table.concat(shown, "\n")
        elseif st.obj and #st.obj > 0 then
            local o = {}
            for _, x in ipairs(st.obj) do o[#o + 1] = shortObj(x) end
            label = table.concat(o, "   ")
        end
        return label or clean(st.note) or "?", label and clean(st.note) or nil, "side"
    end
    -- (a buy errand with its items - the Skyborne Rogue's "Buy and equip a [Shortsword]" - is an instruction, below)
    if st.col and not st.errand then
        local parts = {}
        local count = ns.itemCount or (C_Item and C_Item.GetItemCount) or GetItemCount -- (bags on the bag bar count)
        local nameOf = (C_Item and C_Item.GetItemNameByID) or function(id) return GetItemInfo and (GetItemInfo(id)) end
        for _, c in ipairs(st.col) do
            local n = nameOf(c[1])
            if n then parts[#parts + 1] = string.format("%s %d/%d", itemLink(c[1], n), math.min(count(c[1]) or 0, c[2]), c[2]) end
        end
        if #parts > 0 then
            local desc = clean(st.name) .. (st.note and ("\n" .. clean(st.note)) or "")
            return table.concat(parts, "   "), desc, "side"
        end
    end
    -- recommended actions: death skips, entering caves, timers, warnings
    if st.death then return DEATH .. clean(st.name or "Die and respawn at the spirit healer"), clean(st.note), "rec" end
    if st.t == "accept" or st.t == "turnin" then return oneLine(st), clean(st.note), "rec" end
    -- travel along the way: its name alone ("Thelsamar") says nothing, so say what to do
    if st.t == "hearth" then
        -- on cooldown: hidden while it's more than 5 minutes away, else with the time left
        local left = ns.hearthCooldown and ns.hearthCooldown() or 0
        -- on cooldown while the step you'd hearth to is far away: say so instead (you'll have to travel)
        if left > 0 then
            local cur = ns.steps()[ItineraryCharDB.step]
            local d = ns.stepDistance and ns.stepDistance(cur)
            if d and d > 500 then
                ns.hearthCheckAt = math.min(ns.hearthCheckAt or math.huge, GetTime() + (left <= 300 and 1 or 5))
                local t = left >= 3600 and string.format("%d:%02d:%02d", math.floor(left / 3600), math.floor(left % 3600 / 60), math.floor(left % 60))
                    or string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
                return "|TInterface\\Icons\\INV_Misc_Rune_01:0:0:0:1:64:64:5:59:5:59|t Travel to " .. (st.name or "your inn")
                    .. " yourself: your Hearthstone isn't ready (" .. t .. ")",
                    "It should have been ready here.", "rec"
            end
        end
        if left > 300 then
            ns.hearthCheckAt = math.min(ns.hearthCheckAt or math.huge, GetTime() + left - 300)
            return nil
        end
        local wait = ""
        if left > 0 then
            ns.hearthCheckAt = GetTime() -- count down every second
            wait = string.format("  |cffffd100(ready in %d:%02d)|r", math.floor(left / 60), math.floor(left % 60))
        end
        -- text height, edges cropped (above the arrow it's drawn twice as big, see setArrowInstructions)
        local icon = "|TInterface\\Icons\\INV_Misc_Rune_01:0:0:0:1:64:64:5:59:5:59|t "
        return icon .. "Use your Hearthstone to " .. (st.name or "your inn") .. wait, clean(st.note), "rec"
    end
    if st.t == "fly" or st.t == "sethearth" or st.t == "fp" or st.t == "dungeon" then
        return title(st), clean(st.note), "rec"
    end
    if st.trainRec then
        return (st.cls and "Train new skills" or (st.name or "Visit the trainer")) .. (st.npc and (" at " .. st.npc) or ""), clean(st.note), "rec"
    end
    -- an errand at a vendor ("Vendor trash at Rallic Finn", "Buy Ice Cold Milk"): who it's at. A buy with its items
    -- ("Buy and equip a [Shortsword]") is one too, with the count on it (it showed under Along the way as
    -- "[Shortsword] 0/1", not as an instruction to click for the arrow)
    if st.errand then
        local label, desc = clean(st.name) or "Visit the vendor", clean(st.note)
        if st.npc and not label:find(st.npc, 1, true) then
            if label:find("^Vendor") or label:find("^Sell") or label:find("^Repair") then
                label = label .. " at " .. st.npc
            else
                desc = "At " .. st.npc .. (desc and desc ~= "" and ("\n" .. desc) or "")
            end
        end
        if st.col then
            local count = ns.itemCount or (C_Item and C_Item.GetItemCount) or GetItemCount
            local nameOf = (C_Item and C_Item.GetItemNameByID) or function(id) return GetItemInfo and (GetItemInfo(id)) end
            local h = ns.hintHex()
            if #st.col == 1 then
                local c = st.col[1]
                label = label .. "  " .. h .. math.min(count(c[1]) or 0, c[2]) .. "/" .. c[2] .. "|r"
            else
                -- (several: each with its count above the rest of the hint)
                local parts = {}
                for _, c in ipairs(st.col) do
                    local n = nameOf(c[1])
                    parts[#parts + 1] = (n and itemLink(c[1], n) or ("item " .. c[1])) .. " " .. h .. math.min(count(c[1]) or 0, c[2]) .. "/" .. c[2] .. "|r"
                end
                desc = table.concat(parts, "   ") .. (desc and desc ~= "" and ("\n" .. desc) or "")
            end
        end
        return label, desc, "rec"
    end
    local desc = st.name and clean(st.note) or nil
    if st.untilQ then
        local till = "Until you turn in " .. questName(st.untilQ, st.untilN or ("quest " .. st.untilQ))
        desc = desc and (desc .. "\n" .. till) or till
    end
    return clean(st.name or st.note or oneLine(st)), desc, "rec"
end

-- an upcoming step: action icon, the action in the accent colour, then what
local function nextLine(s)
    local verb = VERB[s.t] or s.t
    verb = verb:sub(1, 1) .. verb:sub(2):lower()
    -- a slight accent: the theme colour softened toward the grey of the upcoming lines
    local ar, ag, ab = accent()
    local function soft(v) return math.floor((v * 0.7 + 0.55 * 0.3) * 255 + 0.5) end
    local icon = ICON[s.t]
    local crop = icon and icon:find("Icons") and ":12:12:0:0:64:64:6:58:6:58" or ":12:12"
    local t = s.n and s.n[1] or title(s):match("[^\n]+")
    return (icon and ("|T" .. icon .. crop .. "|t ") or "")
        .. string.format("|cff%02x%02x%02x%s|r  %s", soft(ar), soft(ag), soft(ab), verb, t)
end

ns.stepText = { title = title, detail = detail, oneLine = oneLine, nextLine = nextLine }

---------------------------------------------------------------- the step panel
local panel, arrow
local W, PAD = 330, 14

local function savePos(frame, store)
    local p, _, rp, x, y = frame:GetPoint()
    store.point, store.relPoint, store.x, store.y = p, rp, x, y
end
local function restorePos(frame, store, dp, dx, dy)
    frame:ClearAllPoints()
    if store.point then frame:SetPoint(store.point, UIParent, store.relPoint, store.x, store.y)
    else frame:SetPoint(dp, UIParent, dp, dx, dy) end
end

-- Waypoint arrow looks (Settings > Display): texture, its own rotation, colour
ns.ARROW_SKINS = {
    { "Itinerary", tex = "arrow", size = 44, accent = true },
    { "Gold", tex = "arrow", size = 44, color = { 1, 0.78, 0.25 } },
    { "White", tex = "arrow", size = 44, color = { 1, 1, 1 } },
    { "Guide", tex = "arrow", size = 44, steer = true },
    { "Classic", tex = "Interface\\Minimap\\MinimapArrow", size = 40, color = { 1, 1, 1 } },
    { "Big", tex = "arrow", size = 60, accent = true },
}
local function arrowSkin()
    local name = ItineraryDB and ItineraryDB.arrow and ItineraryDB.arrow.skin
    for _, sk in ipairs(ns.ARROW_SKINS) do if sk[1] == name then return sk end end
    return ns.ARROW_SKINS[1]
end
function ns.applyArrowSkin()
    if not (arrow and arrow.tex) then return end
    local sk = arrowSkin()
    local path = sk.tex == "arrow" and ("Interface\\AddOns\\" .. ADDON .. "\\arrow") or sk.tex
    arrow.tex:SetTexture(path)
    arrow.tex:SetSize(sk.size or 44, sk.size or 44)
    if sk.accent then
        local ar, ag, ab = accent()
        arrow.tex:SetVertexColor(ar, ag, ab, 1)
    elseif sk.color then
        arrow.tex:SetVertexColor(sk.color[1], sk.color[2], sk.color[3], 1)
    else
        arrow.tex:SetVertexColor(1, 1, 1, 1)
    end
end

-- The panel grows up from its bottom edge (default) or down from its top edge (Settings > Layout):
-- pin that edge where it is now, so a height change only moves the other one.
function ns.anchorPanel(save)
    if not panel or panel.moving then return end
    local left, b, t = panel:GetLeft(), panel:GetBottom(), panel:GetTop()
    if not (left and b and t) then return end
    local g = ItineraryDB.panel
    local down = g.grow == "down"
    panel:ClearAllPoints()
    if down then panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, t)
    else panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, b) end
    if save then savePos(panel, g) end
end

local function makeButton(parent, label, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 20)
    local fs = text(b, 15, 1, 1, 1, 0.5)
    fs:SetPoint("CENTER"); fs:SetText(label)
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 1, 1, 0.95)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip, 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1, 0.5); GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

local function buildPanel()
    local ar, ag, ab = accent()
    panel = CreateFrame("Frame", "ItineraryPanel", UIParent)
    panel:SetSize(W, 120)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    -- the item / target buttons follow the panel every frame while it is dragged
    local function startDrag()
        if ItineraryDB.panel.locked or InCombatLockdown() then return end
        panel.moving = true
        panel:StartMoving()
        panel:SetScript("OnUpdate", function() if ns.placeItems then ns.placeItems() end end)
    end
    local function stopDrag()
        panel:StopMovingOrSizing()
        panel:SetScript("OnUpdate", nil)
        panel.moving = false
        ns.anchorPanel(true)
        if ns.updateItems then ns.updateItems() end
    end
    panel:SetScript("OnDragStart", startDrag)
    panel:SetScript("OnDragStop", stopDrag)
    -- Alt + right-click locks / unlocks the panel
    local function altRight(button)
        if button == "RightButton" and IsAltKeyDown() then ns.setLocked(not ItineraryDB.panel.locked) return true end
    end
    panel:SetScript("OnMouseUp", function(_, button) altRight(button) end)
    -- the saved position is in the panel's own (scaled) units, so the scale must be set before it is restored
    panel:SetScale(ItineraryDB.panel.scale or 1)
    restorePos(panel, ItineraryDB.panel, "RIGHT", -60, 0)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.92))
    panel.bg = bg
    panel.edges = addEdges(panel, 1, 1, 1, 0.15)
    -- the top edge doubles as chapter progress: a dim track with the done part in the accent colour
    local track = panel:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(ar, ag, ab, 0.25)
    track:SetPoint("TOPLEFT", 1, -1); track:SetPoint("TOPRIGHT", -1, -1); track:SetHeight(2)
    panel.track = track
    local top = panel:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(ar, ag, ab, 0.95)
    top:SetPoint("TOPLEFT", 1, -1); top:SetHeight(2); top:SetWidth(1)
    panel.progress = top

    panel.eyebrow = text(panel, 11, ar, ag, ab, 0.9)
    panel.eyebrow:SetPoint("TOPLEFT", PAD, -12)
    panel.where = text(panel, 11, 1, 1, 1, 0.45)
    panel.where:SetPoint("TOPRIGHT", -PAD, -12)
    panel.where:SetJustifyH("RIGHT")

    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(18, 18)
    panel.icon:SetPoint("TOPLEFT", PAD, -34)
    panel.title = text(panel, 14, 1, 1, 1, 1)
    panel.title:SetPoint("TOPLEFT", panel.icon, "TOPRIGHT", 8, 1)
    panel.title:SetWidth(W - PAD * 2 - 26)
    panel.title:SetWordWrap(true)
    -- a trainer step: hover its title for what the trainer has for you; a quest step of a quest chain: for the
    -- chain (mouse motion only, so dragging the panel still works; shown only on those steps, so links in other
    -- titles keep working)
    do
        local hov = CreateFrame("Frame", nil, panel)
        hov:SetPoint("TOPLEFT", panel.icon, "TOPLEFT", -2, 2)
        hov:SetPoint("BOTTOMRIGHT", panel.title, "BOTTOMRIGHT", 2, -2)
        local ok = pcall(function() hov:SetMouseClickEnabled(false); hov:SetMouseMotionEnabled(true) end)
        hov:SetScript("OnEnter", function(self)
            if self.spec then ns.trainerTip(self, self.spec)
            elseif self.chain then ns.chainTip(self, self.chain, self.chainAt) end
        end)
        hov:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hov:Hide()
        if ok then panel.titleHover = hov end
    end
    panel.detail = text(panel, 11.5, 1, 1, 1, 0.55)
    panel.detail:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.detail:SetWidth(W - PAD * 2 - 26)
    panel.detail:SetWordWrap(true)

    -- the two blocks under the main goal: recommended actions, then side objectives along the way
    local function section(label)
        local fs = text(panel, 9.5, ar, ag, ab, 0.75)
        fs:SetText(label)
        return fs
    end
    panel.secRec = section("INSTRUCTIONS")
    panel.secSide = section("ALONG THE WAY")
    -- rows take the mouse for their links, and pass a drag / Alt + right-click on to the panel
    local function linkRow(row)
        row:EnableMouse(true)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function() row.dragged = true; startDrag() end)
        row:SetScript("OnDragStop", stopDrag)
        row:SetScript("OnMouseDown", function() row.dragged = false end)
        row:SetScript("OnMouseUp", function(_, button)
            if altRight(button) then return end
            -- an instruction with a place: point the arrow there (again: back to the route)
            if button == "LeftButton" and not row.dragged and row.go and not IsModifiedClick("CHATLINK") then
                ns.setManualTarget(row.go)
            elseif button == "LeftButton" and not row.dragged and row.click and not IsModifiedClick("CHATLINK") then
                -- (an instruction that opens something: your talents)
                pcall(row.click)
            end
        end)
        linkHandlers(row)
        -- a trainer instruction: hover for what that trainer has for you and what it costs
        row:SetScript("OnEnter", function(self) if self.spells then ns.trainerTip(self, self.spells) end end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- the small x: dismiss this instruction (a route one is done; a trainer or profession one waits for
        -- your next level)
        local x = CreateFrame("Button", nil, row)
        x:SetSize(14, 14)
        x:SetPoint("TOPRIGHT", row, "TOPRIGHT", 4, 1)
        x.fs = text(x, 12, 1, 1, 1, 0.35)
        x.fs:SetPoint("CENTER"); x.fs:SetText("×")
        x:SetScript("OnEnter", function(self)
            self.fs:SetTextColor(1, 0.45, 0.4, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(type(row.dismissTitle) == "string" and row.dismissTitle or "Dismiss this instruction", 1, 1, 1)
            GameTooltip:AddLine(type(row.dismissText) == "string" and row.dismissText or "It won't show again.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", function(self) self.fs:SetTextColor(1, 1, 1, 0.35); GameTooltip:Hide() end)
        x:SetScript("OnClick", function()
            GameTooltip:Hide()
            if type(row.dismiss) == "function" then row.dismiss() end
            if ns.update then ns.update() end
            if ns.refresh then ns.refresh() end
        end)
        x:Hide()
        row.x = x
    end
    -- the row's dismiss (x), from its entry
    local function setDismiss(row, e)
        row.dismiss = (e and type(e.dismiss) == "function") and e.dismiss or false
        row.dismissText = e and e.dismissText or false
        row.dismissTitle = e and e.dismissTitle or false
        if row.x then if row.dismiss then row.x:Show() else row.x:Hide() end end
    end
    ns.setRowDismiss = setDismiss
    linkHandlers(panel)
    panel.rows = {}
    for i = 1, 6 do
        local row = CreateFrame("Frame", nil, panel)
        linkRow(row)
        row:SetWidth(W - PAD * 2)
        row.label = text(row, 11.5, 1, 1, 1, 0.9)
        row.label:SetPoint("TOPLEFT"); row.label:SetWidth(W - PAD * 2 - 12); row.label:SetWordWrap(true)
        row.desc = text(row, 10.5, 1, 1, 1, 0.5)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2); row.desc:SetWidth(W - PAD * 2); row.desc:SetWordWrap(true)
        row:Hide()
        panel.rows[i] = row
    end

    -- recommendations get their own small card on top of the panel, so they don't get lost in it
    local card = CreateFrame("Frame", nil, panel)
    card:SetWidth(W)
    card.bg = card:CreateTexture(nil, "BACKGROUND"); card.bg:SetAllPoints()
    card.edges = addEdges(card, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.35)
    card.bar = card:CreateTexture(nil, "ARTWORK"); card.bar:SetColorTexture(ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.95)
    card.bar:SetPoint("TOPLEFT", 1, -1); card.bar:SetPoint("BOTTOMLEFT", 1, 1); card.bar:SetWidth(3)
    card.head = text(card, 9.5, ns.WARM[1], ns.WARM[2], ns.WARM[3], 0.95); card.head:SetPoint("TOPLEFT", PAD, -8); card.head:SetText("INSTRUCTIONS")
    card.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Frame", nil, card)
        linkRow(row)
        row:SetWidth(W - PAD * 2)
        row.label = text(row, 12, 0.5, 0.8, 1, 1) -- the instruction itself in blue, so it stands out
        row.label:SetPoint("TOPLEFT"); row.label:SetWidth(W - PAD * 2 - 12); row.label:SetWordWrap(true)
        row.desc = text(row, 10.5, 1, 1, 1, 0.6)
        row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2); row.desc:SetWidth(W - PAD * 2); row.desc:SetWordWrap(true)
        row:Hide()
        card.rows[i] = row
    end
    local ag = card:CreateAnimationGroup()
    if type(ag) == "table" then
        local fa = ag:CreateAnimation("Alpha")
        if type(fa) == "table" then fa:SetFromAlpha(0); fa:SetToAlpha(1); fa:SetDuration(0.35); fa:SetSmoothing("OUT"); card.fade = ag end
    end
    card:Hide()
    panel.recCard = card

    panel.div = panel:CreateTexture(nil, "ARTWORK")
    panel.div:SetColorTexture(1, 1, 1, 0.08)
    panel.div:SetHeight(1)
    panel.next = {}
    for i = 1, 5 do
        local fs = text(panel, 11.5, 1, 1, 1, 0.4)
        fs:SetWidth(W - PAD * 2); fs:SetWordWrap(false)
        panel.next[i] = fs
    end
    panel.pace = text(panel, 11, 1, 1, 1, 0.55)
    panel.backBtn = makeButton(panel, "‹", ns.back, "Previous step")
    panel.skipBtn = makeButton(panel, "›", ns.skip, "Skip this step")
    panel.skipBtn:SetPoint("BOTTOMRIGHT", -6, 6)
    panel.backBtn:SetPoint("RIGHT", panel.skipBtn, "LEFT", -2, 0)
    panel.pace:SetPoint("BOTTOMLEFT", PAD, 11)
    -- tiny gear: opens the settings window
    panel.gearBtn = CreateFrame("Button", nil, panel)
    panel.gearBtn:SetSize(20, 20)
    panel.gearBtn:SetPoint("RIGHT", panel.backBtn, "LEFT", -4, 0)
    local gear = panel.gearBtn:CreateTexture(nil, "ARTWORK")
    gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetSize(13, 13); gear:SetPoint("CENTER"); gear:SetDesaturated(true); gear:SetAlpha(0.45)
    -- hover: the settings button's tooltip also shows memory (refreshed every second while you hover)
    panel.gearBtn:SetScript("OnEnter", function(self)
        gear:SetAlpha(0.95)
        ns.memoryTooltip(self)
        self.memT = 0
        self:SetScript("OnUpdate", function(b, el)
            b.memT = (b.memT or 0) + el
            if b.memT >= 1 then b.memT = 0; if GameTooltip:IsOwned(b) then ns.memoryTooltip(b) end end
        end)
    end)
    panel.gearBtn:SetScript("OnLeave", function(self) gear:SetAlpha(0.45); self:SetScript("OnUpdate", nil); GameTooltip:Hide() end)
    panel.gearBtn:SetScript("OnClick", function() if ns.openSettings then ns.openSettings(true) end end)
    -- route list: the versions and your own routes for this character; right-click: the route editor;
    -- Shift + right-click: the recorder
    panel.routeBtn = makeButton(panel, "", function(self, btn)
        if btn == "RightButton" and IsShiftKeyDown() then if ns.openRecorder then ns.openRecorder(true) end
        elseif btn == "RightButton" then if ns.openEditor then ns.openEditor(true) end
        else ns.toggleRoutePicker(self) end
    end, "Routes: versions and your own routes")
    panel.routeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.routeBtn:HookScript("OnEnter", function()
        GameTooltip:AddLine("Right-click: route editor", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Shift + right-click: recorder", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    local rt = panel.routeBtn:CreateTexture(nil, "ARTWORK")
    rt:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    rt:SetSize(14, 14); rt:SetPoint("CENTER"); rt:SetDesaturated(true); rt:SetAlpha(0.6)
    panel.routeBtn:SetPoint("RIGHT", panel.gearBtn, "LEFT", -2, 0)
    -- recording light: a pulsing red dot and REC while the recorder records (dim while paused); click: recorder
    local rb = CreateFrame("Button", nil, panel)
    rb:SetSize(42, 20)
    rb:SetPoint("RIGHT", panel.routeBtn, "LEFT", -2, 0)
    rb.dot = rb:CreateTexture(nil, "ARTWORK")
    rb.dot:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\dot")
    rb.dot:SetSize(9, 9); rb.dot:SetPoint("LEFT", 4, 0)
    rb.label = text(rb, 10, 1, 0.3, 0.25, 0.95)
    rb.label:SetPoint("LEFT", rb.dot, "RIGHT", 3, 0)
    local pg = rb.dot.CreateAnimationGroup and rb.dot:CreateAnimationGroup()
    if type(pg) == "table" then
        pg:SetLooping("BOUNCE")
        local fade = pg:CreateAnimation("Alpha")
        if type(fade) == "table" then fade:SetFromAlpha(1); fade:SetToAlpha(0.25); fade:SetDuration(0.8); fade:SetSmoothing("IN_OUT") end
        rb.pulse = pg
    else
        rb.pulse = false
    end
    rb:SetScript("OnClick", function() if ns.openRecorder then ns.openRecorder() end end)
    rb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local st = ns.recorderState and ns.recorderState()
        GameTooltip:AddLine(st == "paused" and "Recording paused" or "Recording", 1, 0.3, 0.25)
        GameTooltip:AddLine("Click: open the recorder", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    rb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rb:Hide()
    panel.recBtn = rb
    function ns.refreshRecStatus()
        if not (panel and panel.recBtn) then return end
        local st = ns.recorderState and ns.recorderState()
        local b = panel.recBtn
        panel.pace:ClearAllPoints()
        panel.pace:SetPoint("BOTTOMLEFT", PAD, 11)
        if not st then
            b:Hide(); if b.pulse then b.pulse:Stop() end
            panel.pace:SetPoint("RIGHT", panel.routeBtn, "LEFT", -6, 0)
            return
        end
        b:Show()
        panel.pace:SetPoint("RIGHT", b, "LEFT", -4, 0)
        if st == "on" then
            b.dot:SetVertexColor(1, 0.15, 0.12, 1); b.label:SetText("REC"); b.label:SetTextColor(1, 0.3, 0.25, 0.95)
            if b.pulse and not b.pulse:IsPlaying() then b.pulse:Play() end
        else
            b.dot:SetVertexColor(0.75, 0.35, 0.3, 0.6); b.label:SetText("PAUSE"); b.label:SetTextColor(1, 1, 1, 0.45)
            if b.pulse then b.pulse:Stop() end
            b.dot:SetAlpha(1)
        end
        local w = b.label:GetStringWidth(); b:SetWidth((type(w) == "number" and w or 24) + 20)
    end
    panel.pace:SetPoint("RIGHT", panel.routeBtn, "LEFT", -6, 0)
    panel.pace:SetWordWrap(false)
    -- hover the level timer: time per level so far and the character's total /played
    local paceHit = CreateFrame("Frame", nil, panel)
    paceHit:SetPoint("TOPLEFT", panel.pace, "TOPLEFT", -2, 3)
    paceHit:SetPoint("BOTTOMRIGHT", panel.pace, "BOTTOMRIGHT", 2, -3)
    -- only hover: a click or drag still goes to the panel (moving it)
    if paceHit.SetMouseMotionEnabled then paceHit:SetMouseMotionEnabled(true); paceHit:SetMouseClickEnabled(false)
    else paceHit:EnableMouse(true) end
    paceHit:SetScript("OnEnter", function(self) ns.paceTooltip(self) end)
    paceHit:EnableMouseWheel(true)
    paceHit:SetScript("OnMouseWheel", function(self, d) ns.paceTooltip(self, d) end)
    paceHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- quests skipped behind you: hover for the list
    panel.skipped = CreateFrame("Button", nil, panel)
    panel.skipped:SetSize(W - PAD * 2, 16)
    panel.skipped:SetPoint("BOTTOMLEFT", PAD, 30)
    panel.skipped.fs = text(panel.skipped, 11, 1, 0.75, 0.4, 0.9)
    panel.skipped.fs:SetPoint("LEFT"); panel.skipped.fs:SetJustifyH("LEFT")
    panel.skipped:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Skipped quests still open", 1, 1, 1)
        for _, e in ipairs(self.list or {}) do
            local n = ns.followUpsOf and ns.followUpsOf(e.q) or 0
            GameTooltip:AddDoubleLine(e.name .. (n > 0 and string.format("  |cff999999(+%d follow-up%s)|r", n, n == 1 and "" or "s") or "")
                .. (e.level and "  |cffd8b070(your level)|r" or ""),
                "step " .. e.step, 0.85, 0.85, 0.85, 0.5, 0.5, 0.5)
        end
        GameTooltip:AddLine("Click to go back to the first one", 0.5, 0.5, 0.5)
        local lv = false
        for _, e in ipairs(self.list or {}) do if e.level then lv = true end end
        if lv then
            GameTooltip:AddLine("Your level: left out because you're past the level the route does them at (Settings > Route > Skip overlevelled steps). Going back to one brings its quest back.", 0.5, 0.5, 0.5, true)
        end
        GameTooltip:AddLine("Right-click: not doing them (the line goes away)", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Quests of a zone you've left drop off by themselves", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    panel.skipped:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.skipped:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.skipped:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if ns.ignoreSkipped then ns.ignoreSkipped(self.list) end
            GameTooltip:Hide()
            ns.print("skipped quests left out of the list (their steps stay skipped)")
            if ns.refresh then ns.refresh() end
            return
        end
        local e = self.list and self.list[1]
        if e then
            ItineraryCharDB.manual[e.step] = nil
            if e.level then
                -- left out for your level: you want it anyway (its steps count again)
                ItineraryCharDB.levelKeepQ = ItineraryCharDB.levelKeepQ or {}
                ItineraryCharDB.levelKeepQ[e.q] = true
            end
            if ns.undropQuests then ns.undropQuests({ e.q }) end
            ns.setStep(e.step)
        end
    end)

    -- profession reminder: a quiet line just under the panel, only near a trainer every 10 levels
    panel.profHint = CreateFrame("Button", nil, panel)
    panel.profHint:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 2, -3)
    panel.profHint:SetSize(W - 4, 14)
    panel.profHint.fs = text(panel.profHint, 10.5, 1, 1, 1, 0.55)
    panel.profHint.fs:SetPoint("LEFT"); panel.profHint.fs:SetPoint("RIGHT")
    panel.profHint.fs:SetJustifyH("LEFT"); panel.profHint.fs:SetWordWrap(false) -- the full line is in the tooltip
    panel.profHint:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Profession trainer nearby", 1, 1, 1)
        local t = self.fs:GetText()
        if t then GameTooltip:AddLine((t:gsub("^|c%x+•|r%s*", "")), ns.WARM[1], ns.WARM[2], ns.WARM[3], true) end
        GameTooltip:AddLine("Every 10 levels: new ranks and recipes. Opening the trainer clears this; click to hide it until your next 10 levels.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    panel.profHint:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.profHint:SetScript("OnClick", function(self)
        local c = ItineraryCharDB
        if self.prof and c.prof then
            c.prof.seen = c.prof.seen or {}
            c.prof.seen[self.prof] = math.floor((UnitLevel("player") or 1) / 10) * 10
        end
        ns.refresh()
    end)
    panel.profHint:Hide()

    -- while the panel is unlocked: a quiet line under it saying how to lock it
    panel.lockHint = text(panel, 10.5, 1, 1, 1, 0.35)
    panel.lockHint:SetText("Unlocked · drag to move · Alt + right-click to lock")
    panel.lockHint:Hide()

    -- the header opens the chapter list (and still drags the panel)
    local head = CreateFrame("Button", nil, panel)
    head:SetPoint("TOPLEFT", 0, 0); head:SetPoint("TOPRIGHT", 0, 0); head:SetHeight(26)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", startDrag)
    head:SetScript("OnDragStop", stopDrag)
    head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    head:SetScript("OnClick", function(_, button)
        if altRight(button) then return end
        if button == "LeftButton" and ns.toggleChapters then ns.toggleChapters() end
    end)
    head:SetScript("OnEnter", function(self)
        panel.where:SetTextColor(1, 1, 1, 0.85)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local cp = panel.chapterPos
        if cp then GameTooltip:AddLine(string.format("Step %d of %d in this chapter", cp[1], cp[2]), 1, 1, 1) end
        GameTooltip:AddLine("Click for chapters", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() panel.where:SetTextColor(1, 1, 1, 0.45); GameTooltip:Hide() end)
end

---------------------------------------------------------------- chapter list
local chapterFrame
local CH_ROWS = 10 -- chapters shown at once; the mouse wheel scrolls the rest
local function buildChapters()
    local ar, ag, ab = accent()
    chapterFrame = CreateFrame("Frame", "ItineraryChapters", panel)
    chapterFrame:SetWidth(250)
    chapterFrame:SetPoint("TOPRIGHT", panel, "TOPLEFT", -6, 0)
    chapterFrame:SetFrameStrata("HIGH")
    chapterFrame:EnableMouse(true)
    chapterFrame:EnableMouseWheel(true)
    chapterFrame.offset = 0
    local bg = chapterFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.96))
    addEdges(chapterFrame, 1, 1, 1, 0.15)
    local head = text(chapterFrame, 11, ar, ag, ab, 0.9)
    head:SetPoint("TOPLEFT", PAD, -12); head:SetText("CHAPTERS")
    chapterFrame.count = text(chapterFrame, 10.5, 1, 1, 1, 0.35)
    chapterFrame.count:SetPoint("TOPRIGHT", -PAD, -13); chapterFrame.count:SetJustifyH("RIGHT")
    -- scroll position: a thin track on the right edge with the visible part lit
    chapterFrame.track = chapterFrame:CreateTexture(nil, "ARTWORK")
    chapterFrame.track:SetColorTexture(1, 1, 1, 0.06); chapterFrame.track:SetWidth(2)
    chapterFrame.thumb = chapterFrame:CreateTexture(nil, "OVERLAY")
    chapterFrame.thumb:SetColorTexture(ar, ag, ab, 0.7); chapterFrame.thumb:SetWidth(2)
    chapterFrame:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, #ns.chapters() - CH_ROWS)
        self.offset = math.min(max, math.max(0, self.offset - delta * 2))
        ns.refreshChapters()
    end)
    chapterFrame.rows = {}
    chapterFrame:Hide()
end
function ns.refreshChapters()
    if not chapterFrame or not chapterFrame:IsShown() then return end
    local ar, ag, ab = accent()
    local cur = ns.chapterOf(ItineraryCharDB.step)
    local all = ns.chapters()
    local total = #all
    local max = math.max(0, total - CH_ROWS)
    chapterFrame.offset = math.min(max, math.max(0, chapterFrame.offset or 0))
    local y = -32
    for k = 1, math.min(CH_ROWS, total) do
        local n = chapterFrame.offset + k
        local c = all[n]
        local row = chapterFrame.rows[k]
        if not row then
            row = CreateFrame("Button", nil, chapterFrame)
            row:SetSize(250 - PAD * 2, 20)
            row.prog = text(row, 11, 1, 1, 1, 0.45); row.prog:SetPoint("RIGHT", 0, 0); row.prog:SetJustifyH("RIGHT")
            row.prog:SetWidth(46)
            row.name = text(row, 12, 1, 1, 1, 0.8); row.name:SetPoint("LEFT", 0, 0)
            row.name:SetPoint("RIGHT", row.prog, "LEFT", -6, 0); row.name:SetWordWrap(false)
            row:SetScript("OnEnter", function(self) self.name:SetTextColor(1, 1, 1, 1) end)
            row:SetScript("OnLeave", function() ns.refreshChapters() end)
            row:EnableMouseWheel(false) -- the wheel goes to the list
            chapterFrame.rows[k] = row
        end
        row:SetScript("OnClick", function() ns.gotoChapter(n) end)
        local _, _, first, last = ns.chapterOf(c.first)
        local done = 0
        for j = first, last do if ns.stepDone(j) then done = done + 1 end end
        row.name:SetText(n .. ".  " .. c.name)
        row.prog:SetText(done == last - first + 1 and "done" or (done .. "/" .. (last - first + 1)))
        if n == cur then row.name:SetTextColor(ar, ag, ab, 1) else row.name:SetTextColor(1, 1, 1, done == last - first + 1 and 0.4 or 0.8) end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", PAD, y); row:Show()
        y = y - 20
    end
    for k = math.min(CH_ROWS, total) + 1, #chapterFrame.rows do chapterFrame.rows[k]:Hide() end
    chapterFrame:SetHeight(-y + 10)
    -- "11-20 of 44" and the scroll track, only when there is more than fits
    local more = total > CH_ROWS
    chapterFrame.count:SetText(more and string.format("%d-%d of %d", chapterFrame.offset + 1, chapterFrame.offset + CH_ROWS, total) or "")
    chapterFrame.track:SetShown(more); chapterFrame.thumb:SetShown(more)
    if more then
        local h = CH_ROWS * 20
        chapterFrame.track:ClearAllPoints()
        chapterFrame.track:SetPoint("TOPRIGHT", -5, -32); chapterFrame.track:SetHeight(h)
        chapterFrame.thumb:ClearAllPoints()
        chapterFrame.thumb:SetPoint("TOPRIGHT", -5, -32 - h * chapterFrame.offset / total)
        chapterFrame.thumb:SetHeight(math.max(8, h * CH_ROWS / total))
    end
end
function ns.toggleChapters()
    if not chapterFrame then return end
    if chapterFrame:IsShown() then chapterFrame:Hide() return end
    -- open with the current chapter in view (a little below the top)
    local cur = ns.chapterOf(ItineraryCharDB.step) or 1
    chapterFrame.offset = math.max(0, cur - 3)
    chapterFrame:Show(); ns.refreshChapters()
end

-- Memory, like the game's own performance tooltip: measured only while you hover the settings button
-- (measuring makes the game check every addon you have loaded, so never in the background)
local function addonMemory()
    local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    local num = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local info = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not (update and get and num and info) then return nil end
    pcall(update)
    local list, total, ours = {}, 0, 0
    for i = 1, num() do
        local name, title = info(i)
        if type(name) == "string" and (not loaded or loaded(name)) then
            local kb = tonumber(get(name)) or 0
            if kb > 0 then
                total = total + kb
                if name == ADDON or name:find("^" .. ADDON .. "_") then ours = ours + kb end
                list[#list + 1] = { name = (type(title) == "string" and title ~= "" and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or name, kb = kb }
            end
        end
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    return list, total, ours
end
local function memStr(kb)
    return kb >= 1024 and string.format("%.1f MB", kb / 1024) or string.format("%d KB", kb)
end
function ns.memoryTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("Settings", 1, 1, 1)
    local list, total, ours = addonMemory()
    if list then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Itinerary (with route packs)", memStr(ours), ns.WARM[1], ns.WARM[2], ns.WARM[3], 1, 1, 1)
        GameTooltip:AddDoubleLine("All addons", memStr(total), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Most memory", 0.6, 0.6, 0.6)
        for k = 1, math.min(5, #list) do
            GameTooltip:AddDoubleLine(list[k].name, memStr(list[k].kb), 0.85, 0.85, 0.85, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end
local function paceText()
    local r = ns.route()
    local lvl = UnitLevel("player") or 1
    local now = ns.playedNow()
    local start = ns.levelStartPlayed(lvl)
    local refStart = r and r.ref and ((lvl == 1) and 0 or r.ref[lvl])
    local refNext = r and r.ref and r.ref[lvl + 1]
    local here = (now and start) and (now - start) or nil
    local refHere = (refStart and refNext) and (refNext - refStart) or nil
    local s = "Level " .. lvl .. "   " .. clock(here) .. (refHere and (" / ref " .. clock(refHere)) or "")
    if start and refStart then
        local d = start - refStart
        local col = d <= 0 and "|cff33dd88" or "|cffff7766"
        s = s .. "   " .. col .. (d <= 0 and "-" or "+") .. clock(d) .. "|r"
    end
    return s
end

-- The level timer's tooltip: the level you're on and the 5 before it (the mouse wheel goes further back),
-- each against the reference run where there is one, and the total /played at the bottom
local LEVEL_LINES = 6
local paceOff = 0
function ns.paceTooltip(owner, wheel)
    local c, r = ItineraryCharDB, ns.route()
    local lvl = UnitLevel("player") or 1
    local now = ns.playedNow()
    if wheel then paceOff = paceOff - wheel else paceOff = 0 end
    paceOff = math.max(0, math.min(paceOff, lvl - LEVEL_LINES))
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Time per level", 1, 1, 1)
    GameTooltip:AddLine(" ")
    local function startOf(l) if l == 1 then return 0 end return c.levelAt[l] end
    local function refOf(l)
        if not (r and r.ref) then return nil end
        local a, b = (l == 1) and 0 or r.ref[l], r.ref[l + 1]
        return (a and b) and (b - a) or nil
    end
    local top = lvl - paceOff
    for l = top, math.max(1, top - LEVEL_LINES + 1), -1 do
        local a = startOf(l)
        local b = (l == lvl) and now or c.levelAt[l + 1]
        local t = (a and b) and (b - a) or nil
        local right = t and clock(t) or "?"
        local ref = refOf(l)
        if t and ref and l < lvl then
            local d = t - ref
            right = right .. "  " .. (d <= 0 and "|cff33dd88-" or "|cffff7766+") .. clock(d) .. "|r"
        end
        GameTooltip:AddDoubleLine("Level " .. l .. (l == lvl and "  (so far)" or ""), right, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if lvl > LEVEL_LINES then
        local lo = math.max(1, top - LEVEL_LINES + 1)
        GameTooltip:AddLine(string.format("levels %d-%d of %d  ·  mouse wheel for more", lo, top, lvl), 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Time played", now and clock(now) or "asking the game...", ns.WARM[1], ns.WARM[2], ns.WARM[3], 1, 1, 1)
    if r and r.ref and r.ref[lvl] and c.levelAt[lvl] then
        local d = c.levelAt[lvl] - r.ref[lvl]
        GameTooltip:AddDoubleLine("Against the reference run", (d <= 0 and "|cff33dd88-" or "|cffff7766+") .. clock(d) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if not now and RequestTimePlayed and not wheel then RequestTimePlayed() end
    GameTooltip:Show()
end

-- Route picker: every route that fits this character (all versions), your own routes, and the rest on request
local picker
local function pickerRoutes(all)
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local out = {}
    local defId = ns.defaultRouteId and ns.defaultRouteId()
    for id, r in pairs(ns.routes) do
        local fit = ns.routeFit(r, race, class)
        local mine = r.custom and (not r.match or r.match.class == class)
        local sameClass = r.match and r.match.class == class
        local def = id == defId
        if (all and sameClass) or fit >= 3 or mine or def or id == ItineraryCharDB.route then
            out[#out + 1] = { id = id, r = r, fit = fit, mine = r.custom, def = def }
        end
    end
    table.sort(out, function(a, b)
        -- your default for this race and class on top
        if (a.def and 1 or 0) ~= (b.def and 1 or 0) then return a.def and true or false end
        if (a.mine and 1 or 0) ~= (b.mine and 1 or 0) then return not a.mine end
        if a.fit ~= b.fit then return a.fit > b.fit end
        -- the route packs' order (priority), as for the route a new character gets
        return ns.routeOrder(a.r, b.r, a.id, b.id) > 0
    end)
    return out
end
function ns.toggleRoutePicker(anchor, below)
    if picker and picker:IsShown() then picker:Hide() return end
    if not picker then
        local ar, ag, ab = accent()
        picker = CreateFrame("Frame", "ItineraryRoutePicker", UIParent)
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true)
        picker:EnableMouse(true)
        picker.bg = picker:CreateTexture(nil, "BACKGROUND"); picker.bg:SetAllPoints(); picker.bg:SetColorTexture(ns.themeBg(0.97))
        addEdges(picker, 1, 1, 1, 0.15)
        picker.head = text(picker, 10, ar, ag, ab, 0.9); picker.head:SetPoint("TOPLEFT", 10, -8); picker.head:SetText("ROUTES FOR THIS CHARACTER")
        picker.rows = {}
        picker.allBtn = CreateFrame("Button", nil, picker)
        picker.allBtn:SetSize(140, 18)
        picker.allBtn.fs = text(picker.allBtn, 11, 1, 1, 1, 0.5); picker.allBtn.fs:SetPoint("LEFT")
        picker.allBtn:SetScript("OnClick", function() picker.all = not picker.all; ns.refreshRoutePicker() end)
        tinsert(UISpecialFrames, "ItineraryRoutePicker")
    end
    picker:ClearAllPoints()
    -- from the panel footer it opens upward; from the route editor (below) it opens downward, above the editor
    if below then
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    else
        picker:SetFrameStrata("DIALOG")
        picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 6, 6)
    end
    picker.all = false
    picker:Show()
    ns.refreshRoutePicker()
end
function ns.refreshRoutePicker()
    if not (picker and picker:IsShown()) then return end
    local ar, ag, ab = accent()
    local list = pickerRoutes(picker.all)
    local W2, y = 320, -24
    for k, e in ipairs(list) do
        local row = picker.rows[k]
        if not row then
            row = CreateFrame("Button", nil, picker)
            row:SetSize(W2 - 16, 32)
            row.hl = row:CreateTexture(nil, "BACKGROUND"); row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.06); row.hl:Hide()
            row.name = text(row, 12, 1, 1, 1, 0.9); row.name:SetPoint("TOPLEFT", 4, -3); row.name:SetPoint("RIGHT", -84, 0); row.name:SetWordWrap(false)
            row.sub = text(row, 10.5, 1, 1, 1, 0.5); row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.sub:SetPoint("RIGHT", -84, 0); row.sub:SetWordWrap(false)
            -- "make default": new characters of this race and class start on this route (account-wide)
            row.def = CreateFrame("Button", nil, row)
            row.def:SetSize(78, 28); row.def:SetPoint("RIGHT", -2, 0)
            row.def.fs = text(row.def, 10.5, 1, 1, 1, 0.35); row.def.fs:SetPoint("RIGHT", -2, 0); row.def.fs:SetJustifyH("RIGHT")
            row.def:SetScript("OnEnter", function(self)
                row.hl:Show()
                if not self.on then self.fs:SetTextColor(1, 1, 1, 0.85) end
                local race = UnitRace("player"); local cls = UnitClass("player")
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.on and "Your default" or "Make it your default", 1, 1, 1)
                GameTooltip:AddLine("New " .. (race or "") .. " " .. (cls or "") .. " characters on this account start on this route."
                    .. " The newest version of a route also counts for its later versions; an older one only for itself. "
                    .. (self.on and "Click: back to the automatic choice." or "Characters you already play stay where they are."), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row.def:SetScript("OnLeave", function(self)
                row.hl:Hide(); GameTooltip:Hide()
                if not self.on then self.fs:SetTextColor(1, 1, 1, 0.35) end
            end)
            row.def:SetScript("OnClick", function(self)
                ns.setRouteDefault(not self.on and row.id or nil)
                GameTooltip:Hide()
                ns.refreshRoutePicker()
            end)
            row:SetScript("OnEnter", function(self) self.hl:Show() end)
            row:SetScript("OnLeave", function(self) self.hl:Hide() end)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" then
                    -- your own routes: right-click twice deletes
                    if not (ns.routes[self.id] and ns.routes[self.id].custom) then return end
                    if self.armed then picker:Hide(); ns.deleteCustomRoute(self.id) return end
                    self.armed = true; self.sub:SetText("|cffff7766right-click again to delete|r")
                    C_Timer.After(3, function() self.armed = false; ns.refreshRoutePicker() end)
                    return
                end
                picker:Hide()
                if self.id ~= ItineraryCharDB.route then ns.switchRoute(self.id, true) end
            end)
            picker.rows[k] = row
        end
        local active = e.id == ItineraryCharDB.route
        row.id = e.id
        row.name:SetText(e.r.name or e.id)
        row.name:SetTextColor(active and ar or 1, active and ag or 1, active and ab or 1, 0.95)
        -- (which pack it comes from, when there's more than one)
        local packTitle
        if e.r.pack and not e.mine and #ns.packList() > 1 then
            for _, p in ipairs(ns.packList()) do if p.name == e.r.pack then packTitle = p.title end end
        end
        row.sub:SetText((e.r.version or "") .. (active and "  ·  in use" or "") .. (e.fit < 3 and not e.mine and "  ·  other race/class" or "")
            .. (packTitle and ("  ·  " .. packTitle) or "") .. (e.mine and "  ·  right-click: delete" or ""))
        row.def.on = e.def
        row.def.fs:SetText(e.def and "default" or "make default")
        if e.def then row.def.fs:SetTextColor(ar, ag, ab, 0.95) else row.def.fs:SetTextColor(1, 1, 1, 0.35) end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 8, y); row:Show()
        y = y - 34
    end
    for k = #list + 1, #picker.rows do picker.rows[k]:Hide() end
    picker.allBtn:ClearAllPoints(); picker.allBtn:SetPoint("TOPLEFT", 12, y - 2)
    picker.allBtn.fs:SetText(picker.all and "Only this race" or "Your class, other races")
    picker:SetSize(W2, -y + 28)
end

-- the recommendations card on top of the panel (below it when the panel grows down from its top edge)
-- above the panel; below it when the panel grows down, under the small lines that hang below the panel
-- (profession trainer hint, "Unlocked · drag to move")
function ns.anchorRecCard()
    local card = panel and panel.recCard
    if not card then return end
    card:ClearAllPoints()
    if ItineraryDB.panel.grow == "down" then
        local below = (panel.lockHint:IsShown() and panel.lockHint) or (panel.profHint:IsShown() and panel.profHint) or nil
        if below then card:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -2, -5)
        else card:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -6) end
    else
        card:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 6)
    end
end
-- an instruction you can click to send the arrow there: a hint under it, a mark while the arrow is on it
local function goText(e)
    local label, desc = e[1], e[2]
    if not e.go then return label, desc end
    local mt = ns.manualTarget
    local on = mt and mt.npc == e.go.npc and mt.x == e.go.x and mt.y == e.go.y
    local hint = on and "|cff33dd88Arrow points here|r · click for the route again" or "Click to point the arrow here"
    return (on and "|cff33dd88» |r" or "") .. label, (desc and desc ~= "" and (desc .. "\n") or "") .. hint
end
function ns.showRecCard(list)
    local card = panel and panel.recCard
    if not card then return end
    if #list == 0 then card:Hide(); card.sig = nil return end
    local g = ItineraryDB.panel
    local y, sig = -22, {}
    for k, row in ipairs(card.rows) do
        local e = list[k]
        if e then
            -- (numbers left out: a distance or a countdown ticking along isn't a new instruction to fade in)
            sig[#sig + 1] = (tostring(e[1]):gsub("%d", ""))
            local label, desc = goText(e)
            row.go, row.spells, row.click = e.go, e.spells, e.click
            if ns.setRowDismiss then ns.setRowDismiss(row, e) end
            row.label:SetText(label)
            row.desc:SetText(desc or ""); row.desc:SetShown(desc and desc ~= "" and true or false)
            local h = row.label:GetStringHeight() + (row.desc:IsShown() and (row.desc:GetStringHeight() + 2) or 0)
            row:SetHeight(h)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", PAD, y); row:Show()
            y = y - h - 6
        else
            row:Hide()
        end
    end
    card:SetHeight(math.ceil(-y + 4))
    local minimal = g.style == "minimal"
    local alpha = g.alpha or 0.92
    if minimal then card.bg:SetColorTexture(0, 0, 0, alpha * 0.55) else card.bg:SetColorTexture(ns.themeCard(alpha)) end
    for _, e in ipairs(card.edges) do e:SetShown(not minimal); e:SetAlpha(math.min(1, alpha / 0.92)) end
    ns.anchorRecCard()
    local key = table.concat(sig, "|")
    if card.sig ~= key then
        card.sig = key
        card:Show()
        if type(card.fade) == "table" then card.fade:Stop(); card.fade:Play() end
    end
    card:Show()
end

-- Settings > General > In dungeons: Hide puts the panel, the arrow and the item buttons away while you're inside
-- a dungeon or raid (the route keeps going); they're back when you leave
local function inDungeon()
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    return inside and (kind == "party" or kind == "raid") or false
end
function ns.dungeonHidden()
    if not (ItineraryDB and ItineraryDB.panel and ItineraryDB.panel.hideInDungeon) then return false end
    -- (shown anyway with the minimap button or /iti: for this visit)
    if not inDungeon() then ns.dungeonPeek = nil return false end
    return not ns.dungeonPeek
end
ns.inDungeon = inDungeon
-- the panel is up: shown, and not put away in a dungeon
function ns.panelUp()
    return ItineraryDB.panel.shown and not ns.dungeonHidden()
end

-- Talent points you haven't spent (Settings > Trainer > Talent points, on): an instruction until you spend them;
-- clicking it opens your talents. WoW Forever keeps them as a talent tree's currency (C_ClassTalents / C_Traits:
-- its quantity is what's unspent; GetUnspentTalentPoints and UnitCharacterPoints don't exist there, and
-- GetNumUnspentTalents answers 0). Asked again only after a change (talents, level).
local tpKnown -- (nil: ask the game)
local function traitPoints()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeCurrencyInfo) then return nil end
    local ok, n = pcall(function()
        local c = C_ClassTalents.GetActiveConfigID()
        local info = c and C_Traits.GetConfigInfo(c)
        local total, any = 0, false
        for _, t in ipairs(info and info.treeIDs or {}) do
            -- (true: without the clicks not applied yet - points count as spent once you press Apply)
            for _, x in ipairs(C_Traits.GetTreeCurrencyInfo(c, t, true) or {}) do
                if type(x) == "table" and type(x.quantity) == "number" then total, any = total + x.quantity, true end
            end
        end
        return any and total or nil
    end)
    return ok and n or nil
end
function ns.unspentTalents()
    if tpKnown then return tpKnown end
    local n = traitPoints()
    if not n and GetUnspentTalentPoints then
        local ok, v = pcall(GetUnspentTalentPoints)
        if ok and type(v) == "number" then n = v end
    end
    if not n and UnitCharacterPoints then
        local ok, v = pcall(UnitCharacterPoints, "player")
        if ok and type(v) == "number" then n = v end
    end
    tpKnown = n -- (nothing yet - right after login the talent data may not be there: asked again next time)
    return n or 0
end
function ns.openTalents()
    if ToggleTalentFrame then ToggleTalentFrame() return end
    if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame() return end
    -- (the talent window is an add-on of the game's that loads when first opened)
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not PlayerSpellsFrame and load then pcall(load, "Blizzard_PlayerSpells") end
    if PlayerSpellsFrame then
        if PlayerSpellsFrame:IsShown() then HideUIPanel(PlayerSpellsFrame) else ShowUIPanel(PlayerSpellsFrame) end
    end
end
do
    local tf = CreateFrame("Frame")
    for _, e in ipairs({ "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_CONFIG_UPDATED",
                         "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_LEVEL_UP" }) do
        pcall(tf.RegisterEvent, tf, e)
    end
    tf:SetScript("OnEvent", function() tpKnown = nil; if ns.update then ns.update() end end)
end

local function refreshNow()
    ns.arrowDirty = true
    if not panel then return end
    local g = ItineraryDB
    if not ns.panelUp() then panel:Hide(); if arrow then arrow:Hide() end return end
    panel:Show()
    local steps, i = ns.steps(), ItineraryCharDB.step
    -- a class trainer close by with new spells waiting comes first, as a normal step
    local detour, recDetours = nil, {}
    -- as a recommendation (the default): trainers close by show next to your step instead of replacing it
    -- (a fault in the trainer checks must never cost you the panel: it's reported once and left out)
    local okD, res = pcall(function()
        if ns.trainerAsRec() then return ns.findDetours and ns.findDetours() or {} end
        return ns.findDetour and ns.findDetour() or nil
    end)
    if not okD then
        if not ns.detourErrSaid then ns.detourErrSaid = true; ns.print("trainer check failed: " .. tostring(res)) end
        res = nil
    end
    if ns.trainerAsRec() then recDetours = res or {} else detour = res end
    local recDetour
    for _, d in ipairs(recDetours) do if not d.prof and not d.weapon then recDetour = d end end
    -- gather mode (/iti gather): the farming route takes the place of your step, trainers and all
    ns.timerTick, ns.timerOnStep = nil, nil
    local gs = ns.gatherStep and ns.gatherStep()
    if gs then detour, recDetours, recDetour = gs, {}, nil end
    ns.detourStep = detour
    local s = detour or steps[i]
    local r = ns.route()
    panel.eyebrow:SetText("ITINERARY")
    if not s then
        panel.icon:SetTexture(nil)
        panel.title:SetText(r and "Route finished" or "No route loaded")
        panel.detail:SetText(r and r.name or "")
        panel.where:SetText(r and (#steps .. " / " .. #steps) or "")
    else
        local verb = VERB[s.t] or s.t:upper()
        local done, total
        if not detour then done, total = ns.stepProgress(i) end
        local need = s.t == "accept" and s.minlv and (UnitLevel("player") or 1) < s.minlv
        panel.eyebrow:SetText(verb .. (done and ("  " .. done .. "/" .. total) or "") .. (s.opt and "  ·  OPTIONAL" or "")
            .. (need and ("  ·  |cffff7766NEEDS LEVEL " .. s.minlv .. "|r") or ""))
        local n, ch, first, last = ns.chapterOf(i)
        panel.chapterPos = nil
        if s.gather then
            panel.where:SetText(s.where or "gather mode")
        elseif detour then
            panel.where:SetText(s.dist and string.format("detour  ·  %d yd", math.floor(s.dist)) or "profession")
        elseif ch then
            panel.where:SetText(ch.name)
            panel.chapterPos = { i - first + 1, last - first + 1 }
        else
            panel.where:SetText((s.z and s.z ~= "" and (s.z .. "  ·  ") or "") .. "step " .. i .. "/" .. #steps)
        end
        local cp = (not detour) and panel.chapterPos
        local frac = cp and math.min(1, (cp[1] - 1) / math.max(1, cp[2])) or 0
        panel.progress:SetWidth(math.max(1, (W - 2) * frac))
        panel.progress:SetShown(cp and true or false)
        panel.icon:SetTexture(ICON[s.t])
        panel.title:SetText(title(s))
        local dt = detail(s)
        -- a quest timer goes on the instruction that runs until the turn-in when there is one (more
        -- prominent there), else on your step
        local onInstr = false
        if not detour then
            for _, j in ipairs(ns.alongActive(i)) do if ns.stepTimeLeft(steps[j]) then onInstr = true break end end
        end
        local left = not onInstr and ns.stepTimeLeft(s)
        if left then
            ns.timerTick, ns.timerOnStep = true, true
            dt = "|cffff9933Time left " .. ns.timeText(left) .. "|r" .. ((dt and dt ~= "") and ("\n" .. dt) or "")
        end
        local cw = not detour and ns.cdWaitText and ns.cdWaitText(s)
        if cw then
            ns.timerTick = true
            dt = cw .. ((dt and dt ~= "") and ("\n" .. dt) or "")
        end
        panel.detail:SetText(dt)
    end
    if panel.titleHover then
        local spec = s and ns.trainerSpec(s) or nil
        panel.titleHover.spec = spec
        -- a quest step of a quest chain: hover the title for the chain
        local chain = nil
        if not spec and s and not detour and ns.QUEST_STEP[s.t] and s.q and ns.questChain then
            for _, q in ipairs(s.q) do if ns.questChain(q) then chain = s break end end
        end
        panel.titleHover.chain, panel.titleHover.chainAt = chain, i
        panel.titleHover:SetShown(spec ~= nil or chain ~= nil)
    end
    local y = -(34 + math.max(18, panel.title:GetStringHeight()) + 4 + ((panel.detail:GetText() or "") ~= "" and panel.detail:GetStringHeight() or 0) + 10)
    -- recommended actions and side objectives (along-the-way steps), with their explanations
    local al = (s and not detour) and ns.alongActive(i) or {}
    local rec, side = {}, {}
    local C = ItineraryCharDB
    local lvl = UnitLevel("player") or 1
    local untilLevel = "Until your next level."
    for _, d in ipairs(recDetours) do
        local what = (d.prof or d.weapon) and (d.name or "Learn your profession") or "Train new skills"
        rec[#rec + 1] = { what .. (d.npc and (" at " .. d.npc) or ""),
                          (d.prof or d.weapon) and d.note or ns.affordText(),
                          go = d.m and d.x and { m = d.m, x = d.x, y = d.y, npc = d.npc } or nil,
                          spells = d.weapon and { weapon = d.npc } or (d.prof and (d.t == "train" and { prof = d.prof, npc = d.npc } or nil)) or true,
                          dismissText = untilLevel,
                          dismiss = function()
                              if d.prof and C.prof then C.prof.skip = lvl
                              elseif d.weapon then C.wpnSkip = lvl
                              else C.detourSkip = lvl end
                          end }
    end
    C.dismissed = type(C.dismissed) == "table" and C.dismissed or {}
    for _, r in ipairs((not gs) and ns.profRecommend and ns.profRecommend() or {}) do
        local key = "prof:" .. tostring(r.label):gsub("%d", "")
        if C.dismissed[key] ~= lvl then
            rec[#rec + 1] = { r.label, r.desc, go = r.go, spells = r.prof and { prof = r.prof, npc = r.go and r.go.npc } or nil,
                              dismissText = untilLevel, dismiss = function() C.dismissed[key] = lvl end }
        end
    end
    -- talent points to spend
    local tp = (not gs) and not (g.auto and g.auto.talentRec == false) and ns.unspentTalents() or 0
    if tp > 0 and C.dismissed.talents ~= lvl then
        rec[#rec + 1] = { tp == 1 and "Spend your talent point" or ("Spend your " .. tp .. " talent points"), "Click to open your talents",
                          click = ns.openTalents, dismissText = untilLevel, dismiss = function() C.dismissed.talents = lvl end }
    end
    -- (the × on an along-the-way entry hides it on this character; Settings > Panel shows it again)
    local HIDE_TITLE, HIDE_TEXT = "Hide this", "It won't show under Along the way again on this character. Settings > Panel > Hidden along the way brings it back."
    for _, e in ipairs((not gs) and ns.campingSide and ns.campingSide() or {}) do
        if #side < 2 then
            if e.q and ns.hideAlong then
                local key, name = "q" .. e.q, e[1]
                e.dismiss, e.dismissTitle, e.dismissText = function() ns.hideAlong({ { key, name } }) end, HIDE_TITLE, HIDE_TEXT
            end
            side[#side + 1] = e
        end
    end
    ns.hearthCheckAt = nil
    local seenLabel = {}
    for _, j in ipairs(al) do
        local st0 = steps[j]
        -- a trainer visit of the route shown as an instruction: only within 400 yards (it is the next
        -- stop's trainer, not the one across the zone), and not twice when a nearby class trainer is up
        local hide = false
        if st0.trainRec then
            local d = ns.stepDistance and ns.stepDistance(st0)
            if not d or d > 400 then hide = true end
            if st0.cls and recDetour and not recDetour.prof and not recDetour.weapon then hide = true end
            -- the route's weapon master stops: the weapon master instruction covers them (any master, any time)
            if st0.wpn then hide = true end
        end
        if not hide then
        local label, desc, kind = alongInfo(steps[j])
        local list = kind == "rec" and rec or side
        local st = steps[j]
        -- (a trainer or a vendor errand: click it and the arrow leads there)
        local go = (st.trainRec or st.errand) and st.m and st.x and { m = st.m, x = st.x, y = st.y, npc = st.npc } or nil
        -- (a flight: at the nearest flight master, which the arrow leads to already)
        if st.t == "fly" and ns.flightMasterFor then
            local f = ns.flightMasterFor(st)
            if f and f.npc then desc = "At " .. f.npc .. ((desc and desc ~= "") and ("\n" .. desc) or "") end
        end
        local spells = st.trainRec and ns.trainerSpec(st) or nil
        if st.trainRec and st.cls then desc = ns.affordText() end
        -- (not twice: when your step shows the timer, because no instruction has it, nothing else does)
        local left = not ns.timerOnStep and ns.stepTimeLeft(st)
        if left then
            ns.timerTick = true
            local t = "|cffff9933Time left " .. ns.timeText(left) .. "|r"
            desc = (desc and desc ~= "") and (t .. "\n" .. desc) or t
        end
        local cw = ns.cdWaitText and ns.cdWaitText(st)
        if cw then
            ns.timerTick = true
            desc = (desc and desc ~= "") and (cw .. "\n" .. desc) or cw
        end
        -- the same thing twice (two guide steps collecting the same items): once
        if label and seenLabel[label] then label = nil end
        if label then seenLabel[label] = true end
        -- (a death skip always gets in, in place of the last other instruction when there are three)
        if label and #list >= 3 and st.death then
            for x = #list, 1, -1 do if not list[x].death then table.remove(list, x) break end end
        end
        if label and #list < 3 then
            local e = { label, desc, go = go, spells = spells, timer = left or nil, death = st.death or nil }
            if kind == "rec" then e.dismiss = function() C.manual[j] = true end
            elseif ns.alongHideable and ns.alongHideable(st) then
                -- (a side objective: hidden, not done - its quest's own steps still come)
                e.dismiss = function() ns.hideAlong(ns.alongKeys(st)) end
                e.dismissTitle, e.dismissText = HIDE_TITLE, HIDE_TEXT
            end
            list[#list + 1] = e
        end
        end
    end
    local used = 0
    local function block(head, list, r, g, b)
        if #list == 0 then head:Hide() return end
        y = y - 2
        head:ClearAllPoints(); head:SetPoint("TOPLEFT", PAD, y); head:Show()
        y = y - 13
        for _, e in ipairs(list) do
            used = used + 1
            local row = panel.rows[used]
            local label, desc = goText(e)
            row.go, row.spells, row.click = e.go, e.spells, e.click
            if ns.setRowDismiss then ns.setRowDismiss(row, e) end
            row.label:SetText(label); row.label:SetTextColor(r, g, b, 0.95)
            row.desc:SetText(desc or ""); row.desc:SetShown(desc and desc ~= "" and true or false)
            local h = row.label:GetStringHeight() + (row.desc:IsShown() and (row.desc:GetStringHeight() + 2) or 0)
            row:SetHeight(h)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", PAD, y); row:Show()
            y = y - h - 6
        end
    end
    local useCard = g.panel.recCard ~= false
    block(panel.secRec, useCard and {} or rec, 0.5, 0.8, 1)
    block(panel.secSide, side, 0.55, 0.92, 0.5) -- side objectives in a bright green, apart from their text
    ns.showRecCard(useCard and rec or {})
    if ns.setArrowInstructions then ns.setArrowInstructions(rec) end
    -- the arrow goes to a clicked instruction's place only while that instruction is there: hidden with its x
    -- (or gone by itself), the arrow is back on the route
    local mt = ns.manualTarget
    if mt then
        local still = false
        for _, l in ipairs({ rec, side }) do
            for _, e in ipairs(l) do
                local go = e.go
                if go and go.npc == mt.npc and go.x == mt.x and go.y == mt.y then still = true break end
            end
        end
        if not still then ns.manualTarget = nil; ns.arrowDirty = true end
    end
    for k = used + 1, #panel.rows do panel.rows[k]:Hide() end
    if used > 0 then y = y - 2 end
    -- next few steps
    local upcoming, j = {}, detour and i or i + 1
    while #upcoming < 5 and steps[j] do
        -- (not the ones done already: "Abandon Red Leather Bandanas" after you handed it in)
        if not steps[j].along and not ns.doneAhead(j) then upcoming[#upcoming + 1] = steps[j] end
        j = j + 1
    end
    local shownN = gs and 0 or math.min(g.nextCount or 3, #upcoming, 5)
    local sk = gs and {} or ns.skippedBehind()
    -- the panel fits its content; ns.anchorPanel keeps the bottom edge (or the top, Settings > Layout) in place
    local bottom = 8 + shownN * 16 + 30 + (#sk > 0 and 18 or 0)
    local H = math.ceil(-y + bottom)
    panel.div:ClearAllPoints()
    panel.div:SetPoint("TOPLEFT", PAD, y); panel.div:SetPoint("TOPRIGHT", -PAD, y)
    y = y - 8
    for k = 1, 5 do
        local fs = panel.next[k]
        local ns_ = upcoming[k]
        if k <= shownN and ns_ then
            fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", PAD, y)
            fs:SetText(nextLine(ns_)); fs:Show()
            y = y - 16
        else
            fs:Hide()
        end
    end
    panel.pace:SetText(paceText())
    panel.skipped.list = sk
    if #sk > 0 then
        local nl = 0
        for _, e in ipairs(sk) do if e.level then nl = nl + 1 end end
        panel.skipped.fs:SetText(#sk .. (#sk == 1 and " skipped quest still open" or " skipped quests still open")
            .. (nl > 0 and (nl == #sk and " (your level)" or string.format(" (%d for your level)", nl)) or "") .. "  ·  hover for the list")
        panel.skipped:Show()
    else
        panel.skipped:Hide()
    end
    ns.anchorPanel()
    panel:SetHeight(H)
    local ht, hk = nil, nil
    if ns.profHint and not gs then ht, hk = ns.profHint() end
    panel.profHint.prof = hk
    if ht then
        local ar, ag, ab = accent()
        panel.profHint.fs:SetText(string.format("|cff%02x%02x%02x•|r  %s", math.floor(ar * 255), math.floor(ag * 255), math.floor(ab * 255), ht))
        panel.profHint:Show()
    else
        panel.profHint:Hide()
    end
    panel.lockHint:ClearAllPoints()
    if panel.profHint:IsShown() then panel.lockHint:SetPoint("TOPLEFT", panel.profHint, "BOTTOMLEFT", 0, -1)
    else panel.lockHint:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 2, -3) end
    panel.lockHint:SetShown(not ItineraryDB.panel.locked)
    ns.anchorRecCard()
    if ns.refreshChapters then ns.refreshChapters() end
    if ns.refreshPins then ns.refreshPins() end
    if ns.refreshArrow then ns.refreshArrow() end
    if ns.updateItems then ns.updateItems() end -- target button and quest items follow the step
end
-- (the trainer checks, the detour and the recommendations ask about the spending plan and the class skills
-- many times: answered once per refresh)
function ns.refresh() return ns.memoRun(refreshNow) end

---------------------------------------------------------------- waypoint arrow
-- Map position -> world position. Every conversion makes new vector tables in the game's API, and the
-- arrow asks 20 times a second: a step's points never move, so each is converted once and remembered.
local wpCache, wpCount = {}, 0
local function worldPosRaw(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and cont and v then return cont, v.x, v.y end
end
local function worldPos(mapID, x, y)
    local key = mapID .. ":" .. x .. ":" .. y
    local e = wpCache[key]
    if e == nil then
        if wpCount > 2000 then wipe(wpCache); wpCount = 0 end
        local c, wx, wy = worldPosRaw(mapID, x, y)
        e = c and { c, wx, wy } or false
        wpCache[key], wpCount = e, wpCount + 1
    end
    if e then return e[1], e[2], e[3] end
end
-- Where you are in the world. UnitPosition gives it without making any tables; which of its numbers is
-- which axis is checked once against the map functions (and the map functions are used if it can't say).
local upMiss = 0
local upOrder -- nil = not checked yet, 1 = same order, 2 = swapped, false = don't use UnitPosition
local function playerWorldMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    return worldPosRaw(map, x, y)
end
local function playerWorld()
    local a, b, inst
    if UnitPosition and upOrder ~= false then
        local p1, p2, _, i = UnitPosition("player")
        a, b, inst = p1, p2, i
    end
    if a and upOrder == 1 then return inst, a, b end
    if a and upOrder == 2 then return inst, b, a end
    local c, wx, wy = playerWorldMap()
    if a and c and upOrder == nil then
        if inst == c and math.abs(a - wx) < 2 and math.abs(b - wy) < 2 then upOrder = 1
        elseif inst == c and math.abs(b - wx) < 2 and math.abs(a - wy) < 2 then upOrder = 2
        else
            upMiss = upMiss + 1
            if upMiss >= 10 then upOrder = false end -- this client's numbers don't line up: keep the map way
        end
    end
    return c, wx, wy
end
ns.worldPos, ns.playerWorld = worldPos, playerWorld

local function buildArrow()
    local ar, ag, ab = accent()
    arrow = CreateFrame("Frame", "ItineraryArrow", UIParent)
    arrow:SetSize(64, 78)
    arrow:SetClampedToScreen(true)
    arrow:SetMovable(true)
    arrow:EnableMouse(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetScript("OnDragStart", function(self) if not ItineraryDB.arrow.locked then self:StartMoving() end end)
    arrow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self, ItineraryDB.arrow) end)
    arrow:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and IsAltKeyDown() then ns.setArrowLocked(not ItineraryDB.arrow.locked) end
    end)
    restorePos(arrow, ItineraryDB.arrow, "TOP", 0, -140)
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetPoint("TOP", 0, -2)
    ns.applyArrowSkin()
    arrow.dist = text(arrow, 12, 1, 1, 1, 0.85)
    arrow.dist:SetPoint("TOP", arrow.tex, "BOTTOM", 0, -4)
    arrow.dist:SetJustifyH("CENTER")
    -- the instructions (just the lines, no header) above the arrow, where your eyes are anyway
    -- one line per instruction, stacked upward from the arrow; an action icon (hearthstone) is its own
    -- texture in front of its line, so it can be big and still sit on the line's middle
    arrow.lines = {}
    for k = 1, 3 do
        local fs = text(arrow, ItineraryDB.arrow.instrSize or 12, 0.5, 0.8, 1, 0.95) -- Settings > Display
        fs:SetWidth(300); fs:SetJustifyH("CENTER"); fs:SetJustifyV("BOTTOM"); fs:SetWordWrap(true)
        fs:Hide()
        fs.icon = arrow:CreateTexture(nil, "ARTWORK")
        fs.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        fs.icon:Hide()
        arrow.lines[k] = fs
    end
    arrow.instr = arrow.lines[1]
    arrow:SetScript("OnEnter", function(self)
        if ItineraryDB.arrow.tooltip == false then return end -- Settings > Display
        local s = ns.current()
        if not s then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(title(s), 1, 1, 1)
        GameTooltip:AddLine(detail(s), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(ItineraryDB.arrow.locked and "Alt + right-click to unlock" or "Drag to move · Alt + right-click to lock", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local acc = 0
    -- where you are this update, and how far a point is from there (one function, not a new one each time)
    local pc, px, py
    local function dist(p)
        local c, wx, wy = worldPos(p[1], p[2] / 100, p[3] / 100)
        if not (c and pc and c == pc) then return nil end
        return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
    end
    local nav = {} -- where the arrow is in the current step's way / kill loop
    arrow.nav = nav
    arrow:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        local i = ItineraryCharDB.step
        local s = ns.current()
        -- a detour has its own key, so switching from one detour to another rebuilds the way
        if s and s.detour then i = "trainer:" .. (s.name or "") .. ":" .. (s.npc or "") .. ":" .. tostring(s.x) .. ":" .. tostring(s.y) end
        -- a place you picked by clicking an instruction (a trainer) leads until you get there
        local mt = ns.manualTarget
        if not (ns.arrowWanted and ns.arrowWanted(s)) then self:Hide() return end
        pc, px, py = playerWorld()
        local tm, tx0, ty0, label = s and s.m, s and s.x, s and s.y, nil
        if mt then tm, tx0, ty0 = mt.m, mt.x, mt.y end
        if not mt then
        -- 1) the way in: unfinished "along the way" travel (enter the cave, the path inside...) and the
        --    step's own approach points, followed in order; you move on as you reach each point
        if nav.seqStep ~= i or ns.arrowDirty then
            local old = nav.seqStep == i and nav.seq and nav.seqIdx and nav.seq[nav.seqIdx]
            nav.seqStep, ns.arrowDirty = i, false
            nav.seq = ns.arrowRoute(i)
            nav.seqIdx = nil
            -- keep heading for the same point after a refresh
            if old then
                for k, p in ipairs(nav.seq) do
                    if p.step == old.step and p[2] == old[2] and p[3] == old[3] then nav.seqIdx = k break end
                end
            end
        end
        local seq = nav.seq or {}
        if #seq > 0 and pc then
            if not nav.seqIdx then
                -- join the way at the closest point (when you are already halfway in, don't send you back), but
                -- not past someone to talk to on the way that you haven't reached yet (a stop)
                local best, bd = 1, nil
                for k, p in ipairs(seq) do
                    local d = dist(p)
                    if d and (not bd or d < bd) then best, bd = k, d end
                    if p.stop then break end
                end
                nav.seqIdx = best
            end
            local p = seq[nav.seqIdx]
            -- a point on the way that is farther from where that way ends than you are: you're past it (or
            -- came another way), so it's skipped instead of sending you back. Not indoors, where a straight
            -- line says little (a cave below you).
            local function between(a, b)
                local c1, x1, y1 = worldPos(a[1], a[2] / 100, a[3] / 100)
                local c2, x2, y2 = worldPos(b[1], b[2] / 100, b[3] / 100)
                if not (c1 and c2 and c1 == c2) then return nil end
                return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
            end
            local indoors = IsIndoors and IsIndoors()
            while p and not p.last and not indoors do
                local k = nav.seqIdx
                while seq[k + 1] and seq[k].step == p.step and not seq[k].last do k = k + 1 end
                local goal = seq[k]
                local mine, its = dist(goal), between(p, goal)
                if not (mine and its and mine + 10 < its) then break end
                nav.seqIdx = nav.seqIdx + 1
                p = seq[nav.seqIdx]
            end
            while p do
                local d = dist(p)
                local reach = (p[4] and p[4] > 0) and p[4] or 15
                if not (d and d < reach) then break end
                if p.last and p.step then ns.arrived(p.step) end -- that travel step is done
                if p.final then break end
                nav.seqIdx = nav.seqIdx + 1
                p = seq[nav.seqIdx]
            end
            if p then
                tm, tx0, ty0 = p[1], p[2], p[3]
                if p.step and p.step ~= i then label = "way in" end
            end
        end
        -- 2) kill/loot areas: once there, walk the loop, moving on to the next spot as you reach each one
        local area = s.area
        if area and pc and not (nav.seq and nav.seqIdx and nav.seq[nav.seqIdx]) then
            if nav.areaStep ~= i then
                nav.areaStep = i
                local best, bd = 1, nil
                for k, p in ipairs(area) do
                    local d = dist(p)
                    if d and (not bd or d < bd) then best, bd = k, d end
                end
                -- still on your way there: start where the loop starts (a cave's entrance), not at the
                -- spot that is closest as the crow flies (in a mine that can be under a hill you'd climb)
                if bd and bd > 60 then best = 1 end
                nav.areaIdx, nav.areaLeft = best, false
            end
            local p = area[nav.areaIdx]
            local d = dist(p)
            -- move on to the next spot once you reach this one: within 25 yd if you came from farther away,
            -- else (spots close together) only when you're really on it, so it can't flip back and forth
            if d and d > 30 then nav.areaLeft = true end
            if d and (d < 8 or (d < 25 and nav.areaLeft)) then
                nav.areaIdx = nav.areaIdx % #area + 1
                p = area[nav.areaIdx]
                local d2 = dist(p)
                nav.areaLeft = not d2 or d2 > 30
            end
            tm, tx0, ty0 = p[1], p[2], p[3]
            label = "spot " .. nav.areaIdx .. "/" .. #area
        end
        end -- not mt
        if not (tm and tm > 0 and tx0) then
            -- no place on the map (Monty inside the Deeprun Tram has none): a faded arrow with who to look for
            if s and s.npc then
                self.tex:SetRotation(0); self.tex:SetAlpha(0.25)
                self.dist:SetText("find " .. s.npc); self.lastYd = nil
                return
            end
            self:Hide() return
        end
        local tc, tx, ty = worldPos(tm, tx0 / 100, ty0 / 100)
        if not (tc and pc and tc == pc) then
            self.tex:SetRotation(0); self.tex:SetAlpha(0.25)
            self.dist:SetText(s.z or "other zone"); self.lastYd = nil
            return
        end
        self.tex:SetAlpha(1)
        local dn, dw = tx - px, ty - py
        local d = math.sqrt(dn * dn + dw * dw)
        -- right on the spot the direction is just noise: stop turning and show "here" until you walk off
        -- again (a few yards of slack so it doesn't flicker at the edge)
        if self.hereM ~= tm or self.hereX ~= tx0 or self.hereY ~= ty0 then -- a new target starts fresh
            self.hereM, self.hereX, self.hereY, self.here = tm, tx0, ty0, false
        end
        if d < 8 then self.here = true elseif d > 14 then self.here = false end
        local facing = GetPlayerFacing and GetPlayerFacing()
        if self.here then
            self.tex:SetRotation(0); self.tex:SetAlpha(0.45)
        elseif facing then
            local ang = atan2(dw, dn) - facing
            local sk = arrowSkin()
            self.tex:SetRotation(ang + (sk.rot or 0))
            -- "Guide": green when you're heading the right way, through yellow to red when it's behind you
            if sk.steer then
                local off = math.abs(((ang + math.pi) % (2 * math.pi)) - math.pi) / math.pi -- 0 ahead .. 1 behind
                self.tex:SetVertexColor(math.min(1, off * 2), math.min(1, 2 - off * 2), 0.15, 1)
            end
        end
        -- only new text when it changed (no new strings 20 times a second)
        local yd = self.here and -1 or math.floor(d + 0.5)
        if yd ~= self.lastYd or label ~= self.lastLabel then
            self.lastYd, self.lastLabel = yd, label
            local dt = self.here and "here" or (yd .. " yd")
            self.dist:SetText(dt) -- just the distance (no "spot 1/3" or "way in" line)
        end
    end)
    -- click-through last: the game turns a frame's mouse back on when it gets a mouse script (OnEnter above)
    ns.applyArrowMouse()
end

-- Settings > Display > "Arrow instruction size"
function ns.setArrowInstrSize(v)
    ItineraryDB.arrow.instrSize = v
    if arrow and arrow.lines then
        for _, fs in ipairs(arrow.lines) do fs.size = v; fs:SetFont(fontPath(), v, "") end
        if ns.applyPanelStyle then ns.applyPanelStyle() end
    end
end
-- Settings > Arrow > "Instructions at the arrow" (on by default); "Death skips at the arrow" (on by default):
-- a death skip shows there also when the other instructions don't
local ICON_ESC = "|T([^:|]+):0:0:0:1:64:64:5:59:5:59|t%s*"
function ns.setArrowInstructions(list)
    if not (arrow and arrow.lines) then return end
    local all = ItineraryDB.arrow.instr ~= false
    local deaths = ItineraryDB.arrow.deathInstr ~= false
    local show = (all or deaths) and list and #list > 0
    local entries = {}
    -- trainer visits (class, weapon, profession) aren't where the arrow leads unless you clicked one: over the
    -- arrow they're one general line instead ("Skills to learn nearby"), the instruction itself has the details
    local mt = ns.manualTarget
    local trainerLine = false
    if show then for k, e in ipairs(list) do if k <= 3 and e[1] and (all or (deaths and e.death)) then
        local on = mt and e.go and mt.npc == e.go.npc and mt.x == e.go.x and mt.y == e.go.y
        if e.spells and e.go and not on then
            if not trainerLine then
                trainerLine = true
                entries[#entries + 1] = "|cffd9b26fSkills to learn nearby|r - click the instruction panel to go there"
            end
        else
            -- a quest timer on the instruction goes after it here too
            entries[#entries + 1] = e[1] .. (e.timer and ("  |cffff9933" .. ns.timeText(e.timer) .. "|r") or "")
        end
    end end end
    local size = ItineraryDB.arrow.instrSize or 12
    local px = size * 2 -- action icons twice the text size
    local below, gapBelow = nil, 0
    -- the last instruction sits right above the arrow, earlier ones above it
    for k = 1, 3 do
        local fs = arrow.lines[k]
        fs:Hide(); fs.icon:Hide(); fs:ClearAllPoints()
    end
    local n = #entries
    for idx = n, 1, -1 do
        local fs = arrow.lines[n - idx + 1]
        local txt = entries[idx]
        local icon
        txt = txt:gsub(ICON_ESC, function(path) icon = icon or path; return "" end, 1)
        -- item icons inside the line (links) can't be lined up with this font: the first one becomes the
        -- line's icon in front (like the hearthstone's), the others are left out; the names keep their colour
        txt = txt:gsub("|T(%d+):0|t%s*", function(id) icon = icon or tonumber(id); return "" end)
        fs:SetText(txt)
        local w = math.min(300, (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0)
        local lineH = size * 1.15
        local pad = icon and math.max(0, (px - lineH) / 2) or 0
        local dx = icon and (px + 4) / 2 or 0 -- keep icon + text centred over the arrow
        if below then fs:SetPoint("BOTTOM", below, "TOP", dx - (below.dx or 0), 2 + gapBelow + pad)
        else fs:SetPoint("BOTTOM", arrow, "TOP", dx, 2 + pad) end
        fs.dx = dx
        fs:Show()
        if icon then
            fs.icon:SetTexture(icon); fs.icon:SetSize(px, px)
            fs.icon:ClearAllPoints()
            fs.icon:SetPoint("RIGHT", fs, "TOP", -w / 2 - 4, -lineH / 2)
            fs.icon:Show()
        end
        below, gapBelow = fs, pad
    end
end

-- the arrow has somewhere to point: a picked place, the step's own place, or a way in to it (a step
-- without a place of its own, like Monty inside the Deeprun Tram, still has "Enter the Deeprun Tram")
function ns.arrowWanted(s)
    if ns.manualTarget then return true end
    if not s then return false end
    if s.m and s.m > 0 and s.x then return true end
    if s.detour then return false end
    -- (the arrow's own way for this step, while it's up to date: this is asked 20 times a second)
    local nav, step = arrow and arrow.nav, ItineraryCharDB.step
    local seq = nav and nav.seq and nav.seqStep == step and not ns.arrowDirty and nav.seq or ns.arrowRoute(step)
    if #seq > 0 then return true end
    return s.npc ~= nil -- no place known, but someone to look for (shown faded with their name)
end
-- click an instruction with a place (a trainer): the arrow goes there instead until you talk to them;
-- clicking it again gives the arrow back to the route
function ns.setManualTarget(go)
    local mt = ns.manualTarget
    if not go or (mt and mt.npc == go.npc and mt.x == go.x and mt.y == go.y) then
        ns.manualTarget = nil
    else
        ns.manualTarget = { m = go.m, x = go.x, y = go.y, npc = go.npc }
        ns.print("arrow: " .. (go.npc or "there") .. " (click the instruction again for the route)")
    end
    ns.arrowDirty = true
    if ns.refresh then ns.refresh() end
end
local mtEv = CreateFrame("Frame")
for _, e in ipairs({ "TRAINER_SHOW", "GOSSIP_SHOW", "MERCHANT_SHOW", "QUEST_GREETING", "QUEST_DETAIL" }) do pcall(mtEv.RegisterEvent, mtEv, e) end
mtEv:SetScript("OnEvent", function(_, event)
    local mt = ns.manualTarget
    if not mt then return end
    -- talked to them (or any trainer, when that's what you went for): done
    if ns.unitName("npc") == mt.npc or event == "TRAINER_SHOW" then ns.setManualTarget(nil) end
end)
function ns.refreshArrow()
    if not arrow then return end
    local s = ns.current()
    if ItineraryDB.arrow.shown and ns.panelUp() and ns.arrowWanted(s) then arrow:Show() else arrow:Hide() end
end

---------------------------------------------------------------- toggles + minimap button
-- the trainer hint depends on where you are: look again every few seconds
-- (one memo run: the trainer checks and the profession hint ask the same questions, and a refresh it calls
-- shares the answers)
local function detourTick()
    if not panel or not panel:IsShown() or not ns.findDetour then return end
    local ok, key = pcall(function()
        local list = ns.trainerAsRec() and ns.findDetours() or { ns.findDetour() }
        local k = {}
        for _, d in ipairs(list) do k[#k + 1] = (d.name or "") .. (d.npc or "") end
        return table.concat(k, ";")
    end)
    if not ok then key = "" end
    local cur = panel.detourKey or ""
    panel.detourKey = key
    local hint = ns.profHint and ns.profHint() or nil
    if key ~= cur or hint ~= panel.lastHint then panel.lastHint = hint; ns.refresh() end
    -- the arrow hides itself on steps without a place; bring it back when the step has one again
    if arrow and not arrow:IsShown() then ns.refreshArrow() end
end
C_Timer.NewTicker(2, function() ns.memoRun(detourTick) end)

-- Settings > Arrow > Click through the arrow: while it's locked, the mouse goes through it to the world behind
-- (no tooltip, no Alt + right-click); unlocked, it takes the mouse again so you can drag it
function ns.applyArrowMouse()
    if not arrow then return end
    local through = ItineraryDB.arrow.clickThrough and ItineraryDB.arrow.locked and true or false
    arrow:EnableMouse(not through)
    -- (clicks and hovering each: the game keeps them apart, and a mouse script switches them back on)
    if arrow.SetMouseClickEnabled then arrow:SetMouseClickEnabled(not through) end
    if arrow.SetMouseMotionEnabled then arrow:SetMouseMotionEnabled(not through) end
    if through and GameTooltip:GetOwner() == arrow then GameTooltip:Hide() end
end
function ns.setArrowLocked(on)
    ItineraryDB.arrow.locked = on
    ns.applyArrowMouse()
    ns.print(on and (ItineraryDB.arrow.clickThrough and "arrow locked - clicks go through it; unlock it in Settings > Arrow" or "arrow locked (Alt + right-click it to unlock)")
        or "arrow unlocked - drag it where you like")
    if ns.refreshSettings then ns.refreshSettings() end
end

function ns.setPanelShown(v)
    ItineraryDB.panel.shown = v and true or false
    ns.refresh()
    if ns.refreshArrow then ns.refreshArrow() end
    if ns.updateItems then ns.updateItems() end
end
function ns.togglePanel()
    -- in a dungeon with "In dungeons: Hide": shows the panel for this visit (or puts it away again)
    if ItineraryDB.panel.shown and ItineraryDB.panel.hideInDungeon and inDungeon() then
        ns.dungeonPeek = not ns.dungeonPeek
    else
        ItineraryDB.panel.shown = not ItineraryDB.panel.shown
    end
    ns.refresh()
    if ns.refreshArrow then ns.refreshArrow() end
    if ns.updateItems then ns.updateItems() end
end
function ns.toggleArrow()
    ItineraryDB.arrow.shown = not ItineraryDB.arrow.shown
    ns.refreshArrow()
    ns.print("arrow " .. (ItineraryDB.arrow.shown and "shown" or "hidden"))
end
function ns.setLocked(on)
    ItineraryDB.panel.locked = on
    ns.print(on and "panel locked (Alt + right-click it to unlock)" or "panel unlocked - drag it where you like")
    if ns.refresh then ns.refresh() end
    if ns.refreshSettings then ns.refreshSettings() end
end

---------------------------------------------------------------- panel look: Card or Minimal, background opacity
-- Card: the dark box with a hairline border. Minimal: no box or border, just a faint shade behind the
-- text (the opacity slider sets how much) and a shadow under every line so it reads on any ground.
function ns.applyPanelStyle()
    if not panel then return end
    local g = ItineraryDB.panel
    local minimal = g.style == "minimal"
    local alpha = g.alpha or 0.92
    if minimal then
        panel.bg:SetColorTexture(0, 0, 0, alpha * 0.45)
    else
        panel.bg:SetColorTexture(ns.themeBg(alpha))
    end
    -- size: the whole panel scales (text stays sharp); keep its bottom-left (or top-left) corner in place
    local sc = g.scale or 1
    if math.abs((panel:GetScale() or 1) - sc) > 0.001 then
        local l, bt, tp = panel:GetLeft(), panel:GetBottom(), panel:GetTop()
        local old = panel:GetScale() or 1
        panel:SetScale(sc)
        if l and bt then
            panel:ClearAllPoints()
            if g.grow == "down" then panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * old / sc, tp * old / sc)
            else panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * old / sc, bt * old / sc) end
            ns.anchorPanel(true)
        end
        if ns.placeItems then ns.placeItems() end
    end
    -- the border fades with the background, so 0% really is no box at all
    for _, e in ipairs(panel.edges) do e:SetShown(not minimal); e:SetAlpha(math.min(1, alpha / 0.92)) end
    panel.track:SetAlpha(minimal and 0.6 or 1)
    panel.div:SetAlpha(minimal and 0.5 or 1)
    -- over little or no background: a shadow under every line, and the faded lines brighter
    -- over little or no background every line gets a dark outline (reads on snow and grass alike) and the
    -- faded lines become near white
    local low = minimal or alpha < 0.55
    local outline = low and g.textEdge == "outline"
    local font = fontPath()
    for _, fs in ipairs(PANEL_FONTS) do
        if fs.size then fs:SetFont(font, fs.size, outline and "OUTLINE" or "") end
        if low then fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(outline and 1 or 1.2, outline and -1 or -1.2)
        else fs:SetShadowColor(0, 0, 0, 0); fs:SetShadowOffset(0, 0) end
        local b = fs.base
        if b and b[4] < 0.8 then fs:SetTextColor(b[1], b[2], b[3], low and math.max(b[4], 0.92) or b[4]) end
    end
    if ns.refresh then ns.refresh() end
end

---------------------------------------------------------------- Blizzard's quest tracker
-- Hidden by moving it under a hidden frame (not :Hide(), which the game undoes); only outside combat.
local trackerHider = CreateFrame("Frame")
trackerHider:Hide()
local TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local trackerParent = {}
local function applyTracker()
    if InCombatLockdown() then trackerHider.wait = true return end
    trackerHider.wait = false
    local hide = ItineraryDB and ItineraryDB.hideTracker ~= false
    -- EllesmereUI's quest tracker skins Blizzard's tracker and draws its own background and lines around
    -- it; moving the tracker away leaves those behind (a stray line). Ask it to hide itself instead.
    local eqt = _G._EQT_SetSuppressed
    if eqt then pcall(eqt, "Itinerary", hide) end
    for _, n in ipairs(TRACKERS) do
        local f = _G[n]
        if eqt and n == "ObjectiveTrackerFrame" then
            if trackerParent[n] then f:SetParent(trackerParent[n]); trackerParent[n] = nil end
        elseif f and f.SetParent then
            if hide then
                if f:GetParent() ~= trackerHider then trackerParent[n] = f:GetParent(); f:SetParent(trackerHider) end
            elseif trackerParent[n] then
                f:SetParent(trackerParent[n]); trackerParent[n] = nil
            end
        end
    end
end
ns.applyTracker = applyTracker
trackerHider:RegisterEvent("PLAYER_ENTERING_WORLD")
trackerHider:RegisterEvent("PLAYER_REGEN_ENABLED")
trackerHider:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" and not self.wait then return end
    applyTracker()
end)

local function setupMinimap()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not DBIcon or DBIcon:IsRegistered("Itinerary") then return end
    local obj = LDB:NewDataObject("Itinerary", {
        type = "launcher", text = "Itinerary", icon = "Interface\\AddOns\\Itinerary\\icon",
        OnClick = function(_, button)
            if IsShiftKeyDown() then if ns.openSettings then ns.openSettings(true) end
            elseif button == "RightButton" then ns.toggleArrow() else ns.togglePanel() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Itinerary")
            tt:AddLine("|cffffffffClick|r show/hide the route", 0.7, 0.7, 0.7)
            tt:AddLine("|cffffffffRight-click|r show/hide the arrow", 0.7, 0.7, 0.7)
            tt:AddLine("|cffffffffShift + click|r settings", 0.7, 0.7, 0.7)
        end,
    })
    DBIcon:Register("Itinerary", obj, ItineraryDB.minimap)
end
function ns.toggleMinimap()
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not DBIcon then return end
    ItineraryDB.minimap.hide = not ItineraryDB.minimap.hide
    if ItineraryDB.minimap.hide then DBIcon:Hide("Itinerary") else DBIcon:Show("Itinerary") end
end

function ns.buildUI()
    if panel then return end
    buildPanel()
    buildChapters()
    buildArrow()
    ns.applyPanelStyle()
    if ns.buildItems then ns.buildItems(panel) end
    pcall(setupMinimap)
    -- the pace line ticks once a second
    C_Timer.NewTicker(1, function()
        if not panel:IsShown() then return end
        panel.pace:SetText(paceText())
        -- a hearthstone instruction waiting on its cooldown: redraw for the countdown / when it comes back
        if ns.hearthCheckAt and GetTime() >= ns.hearthCheckAt then ns.refresh()
        -- a quest timer on your step or an instruction: count it down
        elseif ns.timerTick then ns.refresh() end
    end)
    ns.refresh()
end

---------------------------------------------------------------- quest sparkles without outlines
-- Same as /console outlineModeShowLootEffectWhenDisabled 1 + /console graphicsOutlineMode 0: no outlines
-- around NPCs and objects, but lootable quest objects and NPCs with a quest for you sparkle. Your own values come back when switched off.
local function setCVar(k, v)
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, k, v) elseif SetCVar then pcall(SetCVar, k, v) end
end
local function getCVar(k)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(k) end
    return GetCVar and GetCVar(k)
end
function ns.applyLootSparkle()
    local g = ItineraryDB
    if not g then return end
    if g.lootSparkle ~= false then
        if not g.lootSparkleSaved then
            g.lootSparkleSaved = { getCVar("graphicsOutlineMode"), getCVar("outlineModeShowLootEffectWhenDisabled") }
        end
        setCVar("outlineModeShowLootEffectWhenDisabled", "1")
        setCVar("graphicsOutlineMode", "0")
    elseif g.lootSparkleSaved then
        local s = g.lootSparkleSaved
        if s[2] then setCVar("outlineModeShowLootEffectWhenDisabled", s[2]) end
        if s[1] then setCVar("graphicsOutlineMode", s[1]) end
        g.lootSparkleSaved = nil
    end
end
local lsf = CreateFrame("Frame")
lsf:RegisterEvent("PLAYER_LOGIN")
lsf:SetScript("OnEvent", function() ns.applyLootSparkle() end)
