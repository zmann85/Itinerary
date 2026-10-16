-- Itinerary automation: accept and hand in quests, click through quest dialogue, buy class skills at the trainer.
-- Hold Shift while talking to an NPC to do it by hand. Settings: /iti settings.
local ADDON, ns = ...

---------------------------------------------------------------- settings
-- ItineraryDB.auto (account wide): quests, scope ("route" | "all"), gossip, rewards, train, trainSkip[CLASS][spell] = true
function ns.autoDefaults()
    local g = ItineraryDB
    g.auto = g.auto or {}
    local a = g.auto
    if a.quests == nil then a.quests = true end
    if a.scope == nil then a.scope = "route" end
    if a.turnin == nil then a.turnin = true end
    if a.gossip == nil then a.gossip = true end
    if a.train == nil then a.train = false end
    if a.profLearn == nil then a.profLearn = true end -- learn the professions you picked at their trainer -- opt in (Settings > Trainer)
    if a.tools == nil then a.tools = true end
    if a.junk == nil then a.junk = true end
    if a.skull == nil then a.skull = true end
    if a.rewards == nil then a.rewards = false end -- off unless you switch it on
    if a.fly == nil then a.fly = true end         -- take the route's flight at the flight master
    if a.spirit == nil then a.spirit = true end     -- resurrect at the spirit healer when you talk to it as a ghost
    if a.bind == nil then a.bind = true end         -- set your hearthstone where the route says
    a.trainSkip = a.trainSkip or {}
    a.trainSeen = a.trainSeen or {} -- [CLASS][spell] = true: spells this class has seen at a trainer (for the filter list)
    if ns.seedClassData then ns.seedClassData() end
end

-- The class skills and trainer places that come with the addon (ClassData.lua, recorded from the game):
-- every class has its full trainer list before its first visit. What a trainer shows you replaces them
-- (ItineraryDB.classSpells[CLASS]["name:rank"] = { name, level, cost, rank, true = seen at a trainer}).
function ns.seedClassData()
    local D, g = ns.CLASS_DATA, ItineraryDB
    if not (D and g and g.auto) then return end
    g.classSpells = g.classSpells or {}
    for class, list in pairs(D.spells or {}) do
        local cs = g.classSpells[class] or {}
        g.classSpells[class] = cs
        local seen = g.auto.trainSeen[class] or {}
        g.auto.trainSeen[class] = seen
        for _, e in ipairs(list) do
            local key = e[1] .. ":" .. (e[4] or "")
            local cur = cs[key]
            if not (cur and cur[5]) then cs[key] = { e[1], e[2], e[3], e[4] } end -- live data wins
            seen[e[1]] = true
        end
    end
    g.trainers = g.trainers or {}
    for class, t in pairs(D.trainers or {}) do
        g.trainers[class] = g.trainers[class] or {}
        for npc, p in pairs(t) do
            if not g.trainers[class][npc] then g.trainers[class][npc] = { p[1], p[2], p[3] } end
        end
    end
    -- profession trainers: what they teach (a trainer you open records its own list on top)
    -- class trainer places from the Itinerary_Data add-on (when installed): after the ones above
    for class, t in pairs(ns.DATA_CLASS_TRAINERS or {}) do
        g.trainers[class] = g.trainers[class] or {}
        for npc, p in pairs(t) do
            if not g.trainers[class][npc] then g.trainers[class][npc] = { p[1], p[2], p[3] } end
        end
    end
    g.profSpells = g.profSpells or {}
    for k, list in pairs(D.profSpells or {}) do
        local ps = g.profSpells[k] or {}
        g.profSpells[k] = ps
        for _, e in ipairs(list) do
            local key = e[1] .. ":" .. (e[4] or "")
            if not ps[key] then ps[key] = { e[1], e[2], e[3], e[4], e[5], e[6], e[7] } end
        end
    end
    g.profTeach = g.profTeach or {}
    for npc, keys in pairs(D.profTeach or {}) do
        if not g.profTeach[npc] then
            local cur = {}
            for _, key in ipairs(keys) do cur[key] = true end
            g.profTeach[npc] = cur
        end
    end
end

local function A() return ItineraryDB and ItineraryDB.auto end
-- Shift held = do it by hand; not when the Shift belongs to the target button's key (Shift-W talking)
local function paused()
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    return not (ns.shiftOK and GetTime() < ns.shiftOK)
end

---------------------------------------------------------------- which quests are ours
local routeQuests, routeQuestsFor
local function inRoute(q)
    local r = ns.route and ns.route()
    if not r then return false end
    if routeQuestsFor ~= r.steps then -- a new step list (another route, or edited) builds it again
        routeQuests, routeQuestsFor = {}, r.steps
        for _, s in ipairs(r.steps) do
            if s.t == "accept" then for _, id in ipairs(s.q) do routeQuests[id] = true end end
        end
    end
    return routeQuests[q] or false
end
-- Forever's "Camping 101: <Profession>" quests: one per profession, offered together; take the ones for the
-- professions you picked (Cooking and First Aid included when you picked them)
local function campingWanted(title)
    local prof = title and title:match("^Camping 101: (.+)$")
    if not prof then return false end
    for _, k in ipairs(ns.profChosen and ns.profChosen() or {}) do
        if ns.profName and ns.profName(k) == prof then return true end
    end
    return false
end
ns.campingWanted = campingWanted
-- your Camping 101 quests the route doesn't cover, with what's left to do, for the panel's "along the way"
function ns.campingSide()
    local out = {}
    local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local title, q, header
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then title, q, header = info.title, info.questID, info.isHeader end
        elseif GetQuestLogTitle then
            local t, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            title, q, header = t, id, isHeader
        end
        if not header and title and title:match("^Camping 101: ") and q and not inRoute(q) then
            local parts, done = {}, true
            for _, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}) do
                if not o.finished then done = false; parts[#parts + 1] = o.text end
            end
            out[#out + 1] = { title, done and "Done - hand it in" or table.concat(parts, ", ") }
        end
    end
    return out
end
local function titleOf(q)
    local f = C_QuestLog and C_QuestLog.GetTitleForQuestID
    return q and f and f(q) or nil
end
local function wanted(q, title)
    local a = A()
    if not (a and a.quests) or paused() then return false end
    if a.scope == "all" then return true end
    if campingWanted(title or titleOf(q)) then return true end
    return q and inRoute(q)
end
ns.autoWanted = wanted

-- the current step (and the along-the-way ones) for this NPC, to find route-specific gossip choices
local function stepsForNpc(name)
    local out = {}
    if not (ns.steps and ItineraryCharDB) then return out end
    local steps, i = ns.steps(), ItineraryCharDB.step
    local list = { i }
    if ns.alongActive then for _, j in ipairs(ns.alongActive(i)) do list[#list + 1] = j end end
    for _, k in ipairs(list) do
        local s = steps[k]
        if s and (not s.npc or s.npc == name) then out[#out + 1] = s end
    end
    return out
end

---------------------------------------------------------------- quest dialogue
local QUEST_FLAG = (Enum and Enum.GossipOptionRecFlags and Enum.GossipOptionRecFlags.QuestLabelPrepend) or 1

-- the route wants your hearthstone set here (current step or one along the way)
local function bindWanted()
    if not (ns.steps and ItineraryCharDB) then return false end
    local steps, i = ns.steps(), ItineraryCharDB.step
    local list = { i }
    if ns.alongActive then for _, j in ipairs(ns.alongActive(i)) do list[#list + 1] = j end end
    for k = i + 1, math.min(#steps, i + 3) do list[#list + 1] = k end -- a step or two early is fine
    local npc = UnitName("npc")
    for _, k in ipairs(list) do
        local s = steps[k]
        if s and s.t == "sethearth" and not ns.stepDone(k) and (not s.npc or s.npc == npc) then return true end
    end
    return false
end
local function optionText(o) return (o.name or ""):lower() end
-- the route wants a flight now: only when the step you're on is the flight (never a later one, so you
-- can't be flown away from a step you still have to do)
local function flyWanted()
    if not (ns.steps and ItineraryCharDB) then return nil end
    local i = ItineraryCharDB.step
    local s = ns.steps()[i]
    if s and s.t == "fly" and s.name and not ns.detourStep and not ns.stepDone(i) then return s end
end
-- on the flight map: the node for the route's destination ("Ironforge", or a zone like "Loch Modan" for
-- "Thelsamar, Loch Modan"), only if you can fly there from here
local function takeFlight()
    local a = A()
    if not a or a.fly == false or paused() then return end
    local s = flyWanted()
    if not (s and NumTaxiNodes and TaxiNodeName and TakeTaxiNode) then return end
    local dest = s.name:match("^([^,]+)"):lower()
    local best, how
    for i = 1, NumTaxiNodes() do
        local name = TaxiNodeName(i)
        local kind = TaxiNodeGetType and TaxiNodeGetType(i)
        if name and kind == "REACHABLE" then
            local city, zone = name:match("^([^,]+),%s*(.+)$")
            city, zone = (city or name):lower(), (zone or ""):lower()
            if city == dest then best, how = i, 1 break
            elseif zone == dest and not best then best, how = i, 2
            elseif not best and (city:find(dest, 1, true) or dest:find(city, 1, true)) then best, how = i, 3 end
        end
    end
    if best then
        local name = TaxiNodeName(best)
        TakeTaxiNode(best)
        ns.print("flying to " .. name .. " (hold Shift when you talk to the flight master to choose yourself)")
    else
        ns.print("no flight to " .. s.name .. " from here: pick one yourself")
    end
end
local confirmBind, confirmRez = false, false
local bindAskedAt = 0

-- Spirit healer: as a ghost, the "resurrect here?" question is answered yes. Some clients ask straight away
-- when you click the healer (no dialogue first), so this doesn't depend on us having picked the option.
local rezAt = 0
local function rezWanted()
    local a = A()
    return a and a.spirit ~= false and not paused() and UnitIsGhost and UnitIsGhost("player")
end
local REZ_POPUPS = { "XP_LOSS", "XP_LOSS_NO_DURABILITY", "XP_LOSS_NO_SICKNESS" }
local function acceptRez()
    if not rezWanted() or (GetTime() - rezAt) < 2 then return end
    -- the game's own Accept button does it the way the client expects
    for _, which in ipairs(REZ_POPUPS) do
        local f = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
        if f and f.button1 and f.button1:IsShown() then
            rezAt = GetTime()
            f.button1:Click()
            ns.print("resurrected at the spirit healer (Settings > Quests: Spirit healer)")
            return
        end
    end
    rezAt = GetTime()
    local PIM = C_PlayerInteractionManager
    if PIM and PIM.ConfirmationInteraction and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.SpiritHealer then
        PIM.ConfirmationInteraction(Enum.PlayerInteractionType.SpiritHealer)
        if PIM.ClearInteraction then PIM.ClearInteraction(Enum.PlayerInteractionType.SpiritHealer) end
    elseif AcceptXPLoss then
        AcceptXPLoss()
    end
    if StaticPopup_Hide then for _, which in ipairs(REZ_POPUPS) do StaticPopup_Hide(which) end end
    ns.print("resurrected at the spirit healer (Settings > Quests: Spirit healer)")
end

local function onGossip()
    local a = A()
    if not a or paused() or not C_GossipInfo then return end
    local options = C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
    -- a ghost at the spirit healer: resurrect
    if a.spirit ~= false and UnitIsGhost and UnitIsGhost("player") then
        for _, o in ipairs(options) do
            local t = optionText(o)
            if t:find("resurrect") or t:find("return me to life") or t:find("bring me back") then
                confirmRez = true
                C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID)
                return
            end
        end
    end
    -- the innkeeper on a "set your hearthstone here" step
    if a.bind ~= false and bindWanted() then
        for _, o in ipairs(options) do
            local t = optionText(o)
            if t:find("inn your home") or t:find("make this inn") or o.icon == 132052 then
                confirmBind, bindAskedAt = true, GetTime()
                C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID)
                return
            end
        end
    end
    -- hand in finished quests first, then pick up new ones
    if a.quests and a.turnin then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if info.isComplete and info.questID and (a.scope == "all" or inRoute(info.questID) or ns.quest.onQuest(info.questID)) then
                C_GossipInfo.SelectActiveQuest(info.questID)
                return
            end
        end
    end
    if a.quests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if info.questID and wanted(info.questID, info.title) then
                C_GossipInfo.SelectAvailableQuest(info.questID)
                return
            end
        end
    end
    -- a flight master on a "fly to ..." step: open the flight map (the flight itself is taken there)
    if a.fly ~= false and flyWanted() then
        for _, o in ipairs(options) do
            local t = optionText(o)
            if o.icon == 132057 or t:find("fly") or t:find("flight") then
                C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID)
                return
            end
        end
    end
    if not a.gossip then return end
    -- a dialogue choice the route asks for at this NPC, or one the game marks as part of a quest
    local want = {}
    for _, s in ipairs(stepsForNpc(UnitName("npc"))) do
        if type(s.gossip) == "table" then for _, id in ipairs(s.gossip) do want[id] = true end end
    end
    for _, o in ipairs(options) do
        local id = o.gossipOptionID or o.optionID
        local questFlag = o.flags and bit and bit.band and bit.band(o.flags, QUEST_FLAG) ~= 0
        if id and (want[id] or questFlag or (o.name and o.name:find("^|cFF0000FF%(Quest%)|r"))) then
            C_GossipInfo.SelectOption(id)
            return
        end
    end
    -- the route says "just talk to them" (RestedXP .skipgossip) and there is only one thing to say
    if #options == 1 then
        for _, s in ipairs(stepsForNpc(UnitName("npc"))) do
            if s.gossip == true then
                local id = options[1].gossipOptionID or options[1].optionID
                if id then C_GossipInfo.SelectOption(id) end
                return
            end
        end
    end
end

local function onGreeting()
    local a = A()
    if not a or not a.quests or paused() then return end
    if a.turnin then
        for k = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            local _, complete = GetActiveTitle(k)
            local id = GetActiveQuestID and GetActiveQuestID(k)
            if complete and (a.scope == "all" or not id or inRoute(id) or ns.quest.onQuest(id)) then
                SelectActiveQuest(k)
                return
            end
        end
    end
    for k = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(k))
        if wanted(id, GetAvailableTitle and GetAvailableTitle(k)) then
            SelectAvailableQuest(k)
            return
        end
    end
end

-- a route quest by its name (a quest started from an item can show its window before the game has its ID)
local function routeQuestByTitle(title)
    if not (title and title ~= "" and ns.steps) then return nil end
    for _, s in ipairs(ns.steps()) do
        if s.t == "accept" and s.n then
            for k, n in ipairs(s.n) do if n == title then return s.q[k] end end
        end
    end
end
local function onDetail(retry)
    local id = GetQuestID and GetQuestID()
    local title = GetTitleText and GetTitleText()
    if not id or id == 0 then
        id = routeQuestByTitle(title)
        -- nothing to go by yet: look again in a moment (only while the quest window is still up)
        if not id and not retry and (not title or title == "") then
            C_Timer.After(0.3, function() if QuestFrame and QuestFrame:IsShown() then onDetail(true) end end)
            return
        end
    end
    if wanted(id, title) then
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        else
            AcceptQuest()
        end
    end
end

local function onProgress()
    local a = A()
    if not (a and a.quests and a.turnin) or paused() then return end
    if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
end

---------------------------------------------------------------- reward choice
-- Gear rewards (all white or green): the best armor type you can wear, the one that sells for most;
-- none of that type: the one that sells for most. Hands off when a choice is better than green, isn't
-- armor, or is a weapon / shield / off-hand you could use.
local WEAPONS = { -- weapon subclasses each class can use (trainable included)
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST  = { 4, 10, 15, 19 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
    DRUID   = { 4, 5, 6, 10, 13, 15 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
}
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local HOLDABLE = { PRIEST = true, MAGE = true, WARLOCK = true, DRUID = true, SHAMAN = true }
local function bestArmor(class, lvl) -- 1 cloth, 2 leather, 3 mail, 4 plate
    if class == "WARRIOR" or class == "PALADIN" then return lvl >= 40 and 4 or 3 end
    if class == "HUNTER" or class == "SHAMAN" then return lvl >= 40 and 3 or 2 end
    if class == "ROGUE" or class == "DRUID" then return 2 end
    return 1
end
function ns.gearRewardIndex()
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return nil end
    local _, class = UnitClass("player")
    local best = bestArmor(class, UnitLevel("player") or 1)
    local canWeapon = {}
    for _, sc in ipairs(WEAPONS[class] or {}) do canWeapon[sc] = true end
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local list = {}
    for i = 1, n do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        if not link then return nil, "loading" end
        local _, _, quality, _, _, _, _, _, equipLoc, _, price, classID, subclassID = info(link)
        if not classID then return nil, "loading" end -- not loaded yet: ask again in a moment
        if (quality or 0) > 2 then return nil, link .. " is better than green" end -- your call
        if classID == 2 then
            if canWeapon[subclassID] then return nil, link .. " is a weapon you can use" end -- your call
        elseif classID == 4 then
            if subclassID == 6 and SHIELD[class] then return nil, link .. " is a shield you can use" end
            if equipLoc == "INVTYPE_HOLDABLE" and HOLDABLE[class] then return nil, link .. " is an off-hand you can use" end
        else
            return nil, link .. " isn't gear" -- a bag, potions...: your call
        end
        list[#list + 1] = { i = i, armor = (classID == 4) and subclassID or -1, price = price or 0 }
    end
    local pick
    for _, e in ipairs(list) do
        if e.armor == best and (not pick or e.price > pick.price) then pick = e end
    end
    if not pick then
        for _, e in ipairs(list) do if not pick or e.price > pick.price then pick = e end end
    end
    return pick and pick.i
end

local onCompleteRetried = false
-- A golden frame around the reward that sells for the most: the one to take when nothing is an upgrade
local coinMarks = {}
local function rewardButton(i)
    if QuestInfo_GetRewardButton and QuestInfoFrame and QuestInfoFrame.rewardsFrame then
        local ok, b = pcall(QuestInfo_GetRewardButton, QuestInfoFrame.rewardsFrame, i)
        if ok and b then return b end
    end
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestRewardItem" .. i]
end
local function hideCoins() for _, t in pairs(coinMarks) do t:Hide() end end
local function markValuableReward(tries)
    hideCoins()
    local a = A()
    if not a or a.rewardCoin == false then return end
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return end
    local best, bestValue, missing = nil, 0, false
    for i = 1, n do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        local _, _, count = GetQuestItemInfo("choice", i)
        local info = link and { ((C_Item and C_Item.GetItemInfo) or GetItemInfo)(link) }
        local price = info and info[11]
        if not price then missing = true
        elseif price * math.max(1, count or 1) > bestValue then best, bestValue = i, price * math.max(1, count or 1) end
    end
    -- item data still on its way: look again in a moment
    if missing and (tries or 0) < 5 then C_Timer.After(0.3, function() markValuableReward((tries or 0) + 1) end) end
    if not best then return end
    local b = rewardButton(best)
    if not b then return end
    local t = coinMarks[b]
    if not t then
        -- a thin golden frame around the reward (Itinerary's own look)
        local box = CreateFrame("Frame", nil, b)
        box:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        box:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
        local function edge(p1, p2, w, h)
            local e = box:CreateTexture(nil, "OVERLAY")
            e:SetColorTexture(1, 0.78, 0.25, 0.95)
            e:SetPoint(p1); e:SetPoint(p2)
            if w then e:SetWidth(w) else e:SetHeight(h) end
        end
        edge("TOPLEFT", "TOPRIGHT", nil, 2); edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
        edge("TOPLEFT", "BOTTOMLEFT", 2, nil); edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
        local glow = box:CreateTexture(nil, "BACKGROUND")
        glow:SetAllPoints(); glow:SetColorTexture(1, 0.78, 0.25, 0.12)
        coinMarks[b] = box
        t = box
    end
    t:Show()
end
ns.markValuableReward = markValuableReward

local function onComplete()
    local a = A()
    markValuableReward()
    if ns.bookRewardIndex then ns.bookRewardIndex() end -- notes a book-reward quest even when we don't pick
    if not (a and a.quests and a.turnin) or paused() then return end
    -- with a choice of rewards you pick yourself
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices <= 1 then GetQuestReward(choices) return end
    -- the gathering book for the profession you picked
    local book = ns.bookRewardIndex and ns.bookRewardIndex()
    if book then GetQuestReward(book) return end
    local pick, why = ns.gearRewardIndex()
    if not a.rewards then
        -- off (the default): say once that it could have picked this one
        if pick and not ItineraryDB.rewardHintShown then
            ItineraryDB.rewardHintShown = true
            ns.print("tip: Itinerary can pick white/green armor rewards for you - /iti settings, Quests, Pick gear rewards")
        end
        return
    end
    if pick then
        local link = GetQuestItemLink("choice", pick)
        ns.print("took " .. (link or "the reward"))
        GetQuestReward(pick)
    elseif why and why ~= "loading" then
        ns.print("reward left to you: " .. why)
    elseif why == "loading" and not onCompleteRetried then
        onCompleteRetried = true -- item data still loading: one more look
        C_Timer.After(0.5, function() onCompleteRetried = false; if QuestFrameRewardPanel == nil or QuestFrameRewardPanel:IsShown() then onComplete() end end)
    end
end

---------------------------------------------------------------- trainer
local buying = false
local function className() local _, c = UnitClass("player"); return c or "?" end

-- GetTrainerServiceInfo returns (name, rank, category) on old clients and (name, category, icon, ?, rank) on newer
-- ones like Forever; tell them apart by where "available"/"unavailable"/"used" turns up
local CATS = { available = true, unavailable = true, used = true }
local function serviceInfo(i)
    local a, b, c, _, e = GetTrainerServiceInfo(i)
    if CATS[b] then return a, b, e end
    return a, c, b
end
local PROFESSIONS = { Alchemy = 1, Blacksmithing = 1, Enchanting = 1, Engineering = 1, Herbalism = 1, Leatherworking = 1,
                      Mining = 1, Skinning = 1, Tailoring = 1, Cooking = 1, ["First Aid"] = 1, Fishing = 1, Riding = 1 }
local function coins(c)
    if ns.money then return ns.money(c) end
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return f and f(c) or tostring(c)
end
local function isClassTrainer()
    if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
    if ns.profOfTrainer and ns.profOfTrainer() then return false end -- e.g. Forever's "Junior Mining Trainer"
    local n = GetNumTrainerServices() or 0
    for i = 1, n do
        local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(i)
        if line and PROFESSIONS[line] then return false end
        -- a profession's own rank ("Apprentice Cook", "Journeyman Leatherworker") is never on a class trainer
        local name = GetTrainerServiceInfo(i)
        if name and (name:find("^Apprentice ") or name:find("^Journeyman ") or name:find("^Expert ") or name:find("^Artisan ")) then
            return false
        end
    end
    -- and it must teach something of your class: a profession trainer the game doesn't flag as one (its
    -- recipes) or a pet trainer is not your class trainer, so nothing there is bought as a class skill
    local _, class = UnitClass("player")
    local cs = ItineraryDB and ItineraryDB.classSpells and ItineraryDB.classSpells[class]
    local known = {}
    local count = 0
    for _, e in pairs(cs or {}) do if not known[e[1]] then known[e[1]] = true; count = count + 1 end end
    if count >= 10 then
        for i = 1, n do
            local name = GetTrainerServiceInfo(i)
            if name and (known[name] or ns.trainWorth(name, class)) then return true end
        end
        return n == 0
    end
    return true
end
ns.isClassTrainer = isClassTrainer

-- Spells worth a trip to the trainer on their own: damage and the few things that speed up killing.
-- Everything else (a new aura rank, utility) is still bought when you're there anyway.
-- Override per spell in Settings > Trainer (ItineraryDB.auto.trainWorth[CLASS][spell] = true/false).
local WORTH = {
    PALADIN = { "Blessing of Might", "Seal of Righteousness", "Judgement", "Seal of the Crusader", "Seal of Command",
                "Holy Strike", "Crusader Strike", "Exorcism", "Hammer of Justice", "Consecration", "Holy Shock",
                "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation", "Blessing of Light",
                "Blessing of Sanctuary", "Blessing of Protection", "Blessing of Freedom", "Blessing of Sacrifice",
                "Greater Blessing of Might", "Greater Blessing of Wisdom", "Greater Blessing of Kings",
                "Greater Blessing of Salvation", "Greater Blessing of Light", "Greater Blessing of Sanctuary",
                "Seal of Fury", "Righteous Fury", "Holy Light", "Cleanse", "Lay on Hands" },
    WARRIOR = { "Heroic Strike", "Rend", "Battle Shout", "Thunder Clap", "Overpower", "Cleave", "Execute", "Slam",
                "Revenge", "Mortal Strike", "Bloodthirst", "Whirlwind", "Victory Rush", "Raging Blow" },
    MAGE    = { "Fireball", "Frostbolt", "Arcane Missiles", "Fire Blast", "Arcane Explosion", "Scorch", "Flamestrike",
                "Cone of Cold", "Pyroblast", "Arcane Blast", "Ice Lance" },
    PRIEST  = { "Smite", "Shadow Word: Pain", "Mind Blast", "Holy Fire", "Power Word: Shield", "Mind Flay", "Penance" },
    WARLOCK = { "Shadow Bolt", "Immolate", "Corruption", "Curse of Agony", "Drain Life", "Searing Pain", "Incinerate",
                "Haunt", "Life Tap" },
    HUNTER  = { "Raptor Strike", "Serpent Sting", "Arcane Shot", "Multi-Shot", "Aimed Shot", "Mongoose Bite",
                "Aspect of the Hawk", "Hunter's Mark", "Steady Shot", "Kill Command" },
    ROGUE   = { "Sinister Strike", "Eviscerate", "Backstab", "Slice and Dice", "Ambush", "Garrote", "Rupture",
                "Mutilate", "Hemorrhage" },
    DRUID   = { "Wrath", "Moonfire", "Starfire", "Insect Swarm", "Claw", "Rake", "Maul", "Ferocious Bite", "Rip",
                "Shred", "Swipe", "Mangle" },
    SHAMAN  = { "Lightning Bolt", "Earth Shock", "Flame Shock", "Rockbiter Weapon", "Flametongue Weapon",
                "Searing Totem", "Stormstrike", "Chain Lightning", "Strength of Earth Totem", "Lava Lash" },
}
local worthSet = {}
for class, list in pairs(WORTH) do
    worthSet[class] = {}
    for _, n in ipairs(list) do worthSet[class][n] = true end
end
function ns.trainWorth(name, class)
    class = class or select(2, UnitClass("player"))
    local o = ItineraryDB and ItineraryDB.auto and ItineraryDB.auto.trainWorth
    o = o and o[class]
    if o and o[name] ~= nil then return o[name] end
    return (worthSet[class] and worthSet[class][name]) and true or false
end

-- spells bought during this trainer visit (the trainer list can show them as available for a moment)
local boughtNow = {}
-- what this visit tells us: you trained at this level, and the next level with something new
-- The spell ID of a skill you know, by name and rank (the trainer doesn't say): "Name(Rank N)" names one
-- rank in the game's spell lookup; else search the spellbook
local function knownSpellID(name, rank)
    local hasRank = rank and rank ~= ""
    local q = hasRank and (name .. "(" .. rank .. ")") or name
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, q)
        if ok and type(info) == "table" and info.spellID then return info.spellID end
    elseif GetSpellInfo then
        local r = { pcall(GetSpellInfo, q) }
        if r[1] and r[8] then return r[8] end
    end
    local SB = C_SpellBook
    if SB and SB.GetSpellBookItemInfo then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for i = 1, 400 do
            local ok, info = pcall(SB.GetSpellBookItemInfo, i, bank)
            if not ok or type(info) ~= "table" then break end
            if info.name == name and (not hasRank or info.subName == rank) then return info.spellID or info.actionID end
        end
    elseif GetSpellBookItemName then
        for i = 1, 400 do
            local n, sub = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
            if not n then break end
            if n == name and (not hasRank or sub == rank) and GetSpellBookItemInfo then
                local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
                if id then return id end
            end
        end
    end
end
local function levelLearned(spellID)
    if not spellID then return nil end
    local f = (C_Spell and C_Spell.GetSpellLevelLearned) or GetSpellLevelLearned
    local ok, lv = pcall(f or function() end, spellID)
    return ok and lv or nil
end

-- Every class skill the trainer lists (also the ones for later levels), with its level and price, for every
-- character of this class; what the trainer shows replaces what came with the addon. Returns how many
-- were new or changed.
local function recordServices(class)
    ItineraryDB.classSpells = ItineraryDB.classSpells or {}
    local cs = ItineraryDB.classSpells[class] or {}
    ItineraryDB.classSpells[class] = cs
    local seenNames = ItineraryDB.auto and ItineraryDB.auto.trainSeen
    if seenNames then seenNames[class] = seenNames[class] or {} end
    local new = 0
    -- what an "already known" entry looks like through the game's functions (to check what they report)
    ItineraryDB.trainerDump = ItineraryDB.trainerDump or {}
    local dump = {}
    for i = 1, GetNumTrainerServices() or 0 do
        local name, cat, rank = serviceInfo(i)
        local req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
        local cost = GetTrainerServiceCost(i) or 0
        -- a skill you already know may come without its level: ask the spell itself
        local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
        local spellID = link and tonumber(link:match("spell:(%d+)"))
        if not spellID and (not req or req == 0) and name then spellID = knownSpellID(name, rank) end
        local learned = levelLearned(spellID)
        if (not req or req == 0) and learned and learned > 0 then req = learned end
        if name and cat ~= "available" and cat ~= "unavailable" and #dump < 40 then
            local r1, r2, r3, r4, r5 = GetTrainerServiceInfo(i)
            dump[#dump + 1] = table.concat({ "raw=" .. table.concat({ tostring(r1), tostring(r2), tostring(r3), tostring(r4), tostring(r5) }, ","),
                name, tostring(rank), tostring(cat),
                tostring(GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)), tostring(cost), tostring(link), tostring(spellID), tostring(learned),
                "fn=" .. tostring(C_Spell and C_Spell.GetSpellInfo ~= nil) .. "/" .. tostring(C_SpellBook and C_SpellBook.GetSpellBookItemInfo ~= nil) }, " | ")
        end
        if name and req and req > 0 then
            local key = name .. ":" .. (rank or "")
            local cur = cs[key]
            if not (cur and cur[5] and cur[2] == req and cur[3] == cost) then new = new + 1 end
            -- (6th: the skill's icon, for the "Ready to learn" tooltip)
            local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i)
            cs[key] = { name, req, cost, rank, true, icon or (cur and cur[6]) }
            if seenNames then seenNames[class][name] = true end
        end
    end
    if #dump > 0 then ItineraryDB.trainerDump[class] = dump end
    return new, cs
end
local function sayRecorded(new, cs)
    if new <= 0 then return end
    local n = 0
    for _, e in pairs(cs) do if e[5] then n = n + 1 end end
    ns.print(string.format("trainer list recorded: %d new or changed (%d %s skills known from trainers)", new, n, (UnitClass("player"))))
end
-- The trainer window hides the skills you already know (its "used" filter, and maybe the ones for later
-- levels): for a moment the list shows everything so the recorded list is complete, then the filter goes
-- back the way you had it. The list only changes after the filter is set, hence the short wait.
local fullRestore, fullDone
local function recordFullList(class)
    if fullDone or fullRestore or not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return end
    fullDone = true
    local was = {}
    for _, f in ipairs({ "available", "unavailable", "used" }) do
        if not GetTrainerServiceTypeFilter(f) then was[#was + 1] = f end
    end
    if #was == 0 then return end
    for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 1) end
    fullRestore = function()
        fullRestore = nil
        for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 0) end
    end
    C_Timer.After(0.5, function()
        if not fullRestore then return end
        if (GetNumTrainerServices and GetNumTrainerServices() or 0) > 0 then sayRecorded(recordServices(class)) end
        fullRestore()
    end)
end
-- A weapon master: record what he teaches, what it costs and where he stands (the whole list, every
-- filter on for a moment), and which of them your class can learn. Baked into ClassData.lua by
-- tools/bake_class_data.lua so every character knows the weapon masters before it meets one.
local wpnRestore
local function recordWeaponMaster()
    if wpnRestore or not (GetNumTrainerServices and GetTrainerServiceInfo) or not ns.WPN_NAME then return end
    local byName = {}
    for id in pairs(ns.WPN_NAME) do
        local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
        if n then byName[n] = id end
    end
    local function isWeaponMaster()
        for i = 1, GetNumTrainerServices() do if byName[GetTrainerServiceInfo(i) or ""] then return true end end
        return false
    end
    -- show everything for a moment (the window hides what you know or can't learn)
    local was = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs({ "available", "unavailable", "used" }) do
            if not GetTrainerServiceTypeFilter(f) then was[#was + 1] = f end
        end
        for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 1) end
    end
    wpnRestore = function()
        wpnRestore = nil
        for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 0) end
    end
    C_Timer.After(#was > 0 and 0.5 or 0, function()
        if not wpnRestore then return end
        if not isWeaponMaster() then wpnRestore(); return end
        local npc = UnitName("npc")
        local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = map and C_Map.GetPlayerMapPosition(map, "player")
        local _, class = UnitClass("player")
        local teach, costs, can, other = {}, {}, {}, {}
        for i = 1, GetNumTrainerServices() do
            local name, cat = serviceInfo(i)
            local id = name and byName[name]
            if id then
                teach[#teach + 1] = id
                costs[id] = GetTrainerServiceCost(i) or 0
                -- "unavailable" on a weapon master: your class can't use it, unless it only wants a higher level
                local req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
                can[id] = cat ~= "unavailable" or (req ~= nil and req > (UnitLevel("player") or 1))
            elseif name then
                other[#other + 1] = name
            end
        end
        wpnRestore()
        if not (npc and pos and #teach > 0) then return end
        local x, y = pos:GetXY()
        table.sort(teach)
        local g = ItineraryDB
        g.weaponMasters = g.weaponMasters or {}
        local old = g.weaponMasters[npc]
        g.weaponMasters[npc] = { map, math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100, teach, costs,
                                 UnitFactionGroup and UnitFactionGroup("player") or nil }
        g.weaponClass = g.weaponClass or {}
        g.weaponClass[class] = g.weaponClass[class] or {}
        for id, ok in pairs(can) do g.weaponClass[class][id] = ok end
        if ns.weaponPlanReset then ns.weaponPlanReset() end
        local names = {}
        for _, id in ipairs(teach) do names[#names + 1] = ns.WPN_NAME[id] .. " " .. coins(costs[id]) end
        ns.print((old and "weapon master updated: " or "weapon master recorded: ") .. npc .. " - " .. table.concat(names, ", ")
            .. (#other > 0 and ("  (also: " .. table.concat(other, ", ") .. ")") or ""))
        if ns.update then ns.update() end
    end)
end

local function noteTrainer()
    local c = ItineraryCharDB
    if not c or not GetNumTrainerServices or not isClassTrainer() then return end
    local lvl = UnitLevel("player") or 1
    -- what's still to buy here (you couldn't afford it yet) and what unlocks later, with prices,
    -- so the route only sends you back once you can pay for it
    local _, class = UnitClass("player")
    local skip = ItineraryDB.auto and ItineraryDB.auto.trainSkip[class] or {}
    local nextLv, owed, owedAll = nil, nil, 0
    -- what the trainer showed (for /iti debug), and whether it's your class trainer at all: a list with none
    -- of your class's worthwhile spells (in any state) is some other trainer and mustn't overwrite what we know
    local seen, any = {}, false
    local _, cls = UnitClass("player")
    for i = 1, GetNumTrainerServices() do
        local name, cat = serviceInfo(i)
        if name then
            seen[#seen + 1] = name .. ":" .. tostring(cat) .. ":" .. tostring(GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i))
            if ns.trainWorth(name, cls) then any = true end
        end
    end
    c.trainSeenNow = table.concat(seen, ", ")
    -- a known class trainer (route step or opened before) with nothing worthwhile left still counts:
    -- that's exactly the "all bought" case, and it must clear what we thought was owed
    if not any then
        local npc = UnitName("npc")
        for _, t in ipairs(ns.classTrainers and ns.classTrainers() or {}) do
            if npc and t.name == npc then any = true; break end
        end
    end
    if not any then return end
    c.trainCosts, c.trainTotals = {}, {}
    sayRecorded(recordServices(class))
    recordFullList(class)
    for i = 1, GetNumTrainerServices() do
        local name, cat = serviceInfo(i)
        local req = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
        local cost = GetTrainerServiceCost(i) or 0
        local rank = select(3, serviceInfo(i))
        if name and not skip[name] and ns.trainWorth(name, class) and not boughtNow[name .. (rank or "")] then
            -- only worthwhile skills send you to the trainer (Settings > Trainer marks them)
            local eff = cost
            if cat == "available" then
                if not owed or eff < owed then owed = eff end
                owedAll = owedAll + cost
            end
            if cat == "unavailable" and req and req > lvl then
                if not nextLv or req < nextLv then nextLv = req end
                local cur = c.trainCosts[req]
                if not cur or eff < cur then c.trainCosts[req] = eff end -- cheapest spell of that level
                c.trainTotals[req] = (c.trainTotals[req] or 0) + cost   -- all of that level's together
            end
        end
    end
    c.trainedLevel, c.trainWorthOnly = lvl, true
    c.trainNext = nextLv
    c.trainOwed = owed -- cheapest worthwhile spell you could learn now but didn't (money)
    c.trainOwedAll = owed and owedAll or nil -- all of them together
    -- remember where this trainer stands, for the "trainer nearby" hint
    local npc = UnitName("npc")
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if npc and pos then
        local x, y = pos:GetXY()
        local _, class = UnitClass("player")
        ItineraryDB.trainers = ItineraryDB.trainers or {}
        ItineraryDB.trainers[class] = ItineraryDB.trainers[class] or {}
        ItineraryDB.trainers[class][npc] = { map, x * 100, y * 100 }
    end
end

-- A character that hasn't been to its trainer with Itinerary (new install, reset): which worthwhile spells
-- up to its level it doesn't have, from what other characters of the class saw at the trainer. A spell
-- counts as known when the spellbook has it by name (a higher rank is only picked up at the next visit).
-- nil = nothing known about this class yet.
function ns.unknownSpellCost(lvl)
    local _, class = UnitClass("player")
    local cs = ItineraryDB.classSpells and ItineraryDB.classSpells[class]
    if not cs or not next(cs) then return nil end
    -- the worthwhile skills (any rank) you could learn now and haven't switched off
    local cheapest = false
    for _, e in ipairs(ns.learnableSpells()) do
        if e.worth and not e.skip and e.level <= lvl and (not cheapest or e.cost < cheapest) then cheapest = e.cost end
    end
    return cheapest or 0
end

-- The class skills you could learn now and don't know yet: { name, rank, cost, level, skip } cheapest first
-- (for the tooltip on the "Train new skills" instruction). Known spells are found by name and rank.
function ns.learnableSpells()
    local _, class = UnitClass("player")
    local cs = ItineraryDB.classSpells and ItineraryDB.classSpells[class]
    if not cs then return {} end
    local lvl = UnitLevel("player") or 1
    local skip = ItineraryDB.auto and ItineraryDB.auto.trainSkip and ItineraryDB.auto.trainSkip[class] or {}
    local function known(name, rank)
        local q = (rank and rank ~= "") and (name .. "(" .. rank .. ")") or name
        local info = (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(q)) or (GetSpellInfo and GetSpellInfo(q))
        return info ~= nil
    end
    -- the highest rank you know of each spell (a client may only keep the top rank in the spellbook, so
    -- knowing Rank 2 must also count for Rank 1)
    local top = {}
    for _, e in pairs(cs) do
        local name, rank = e[1], e[4]
        local n = rank and tonumber(rank:match("(%d+)")) or 0
        if name and (top[name] or -1) < n and known(name, rank) then top[name] = n end
    end
    local out = {}
    for _, e in pairs(cs) do
        local name, req, cost, rank = e[1], e[2], e[3], e[4]
        local n = rank and tonumber(rank:match("(%d+)")) or 0
        if name and req and req <= lvl and not (top[name] and top[name] >= n) then
            local icon = e[6]
            if not icon and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(name) end -- a rank you know
            if not icon and GetSpellTexture then icon = GetSpellTexture(name) end
            if not icon and ns.LINKS and ns.LINKS[name] then icon = ns.LINKS[name].icon end
            out[#out + 1] = { name = name, rank = rank, cost = cost or 0, level = req, skip = skip[name] and true or false,
                              icon = icon or 134400, worth = ns.trainWorth(name, class) and true or false }
        end
    end
    -- the order auto-buy goes in: worthwhile skills first, then by level
    table.sort(out, function(a, b)
        if a.worth ~= b.worth then return a.worth end
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    return out
end

-- Money buying class skills never touches, from level 6 on: 40c at 6, doubling every other level (new
-- skills come at even levels), at most 5g. 10 -> 1s 60c, 20 -> 51s 20c, 26 -> 4g 9s 60c, 28 and up -> 5g.
-- Below 6 everything may be spent: the first skills are cheap and matter most.
function ns.trainReserve(lvl)
    lvl = lvl or (UnitLevel and UnitLevel("player")) or 1
    if lvl < 6 then return 0 end
    return math.floor(math.min(50000, 10 * 2 ^ math.floor((lvl - 2) / 2)))
end

local reserveSaid -- the "kept your reserve" line, once per trainer visit
local trainMoney, lastBuy -- during one trainer visit: money left after what we bought, the last purchase
-- at a weapon master: the weapon skills your route trains that you're missing (Settings > Trainer > buy)
local function weaponBuy()
    local a = A()
    if not (a and a.buyWeapons) or paused() or not ns.weaponsMissing then -- off unless you turn it on
        buying = false
        return
    end
    local missing = ns.weaponsMissing()
    local byName = {}
    for id in pairs(missing) do
        local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
        if n then byName[n] = id end
    end
    -- class skills come first: what they'll cost stays put too
    local money = math.min(GetMoney(), trainMoney or math.huge) - ns.trainReserve() - (ns.pendingSpellCost and ns.pendingSpellCost(true) or 0)
    for i = 1, GetNumTrainerServices() do
        local name, cat, rank = serviceInfo(i)
        local cost = GetTrainerServiceCost(i) or 0
        if name and byName[name] and cat == "available" and not boughtNow[name] and cost <= money then
            boughtNow[name] = true
            buying = true
            trainMoney = math.min(GetMoney(), trainMoney or math.huge) - cost
            BuyTrainerService(i)
            ns.print("trained " .. name .. (cost > 0 and ("  " .. coins(cost)) or ""))
            return
        end
    end
    buying = false
end

local function trainerBuy()
    local a = A()
    if not (a and a.train) or paused() then return end
    if not GetNumTrainerServices or not isClassTrainer() then return end
    local class = className()
    a.trainSeen[class] = a.trainSeen[class] or {}
    local skip = a.trainSkip[class] or {}
    -- the money the server hasn't taken yet for what we just bought still counts as spent
    local money = math.min(GetMoney(), trainMoney or math.huge)
    local reserve = ns.trainReserve()
    local spendable = money - reserve
    -- say what was learned once the trainer shows it as learned (not when we merely asked)
    if lastBuy then
        local n, cat = serviceInfo(lastBuy.i)
        if n == lastBuy.name and cat ~= "available" then
            ns.print("trained " .. lastBuy.name .. (lastBuy.rank and lastBuy.rank ~= "" and (" (" .. lastBuy.rank .. ")") or "")
                .. (lastBuy.cost > 0 and ("  " .. coins(lastBuy.cost)) or ""))
        end
        lastBuy = nil
    end
    -- worthwhile spells (damage) first, then the rest with what's left
    local order = {}
    for i = 1, GetNumTrainerServices() do
        local name = serviceInfo(i)
        if name then a.trainSeen[class][name] = true end
        order[#order + 1] = { i, name and ns.trainWorth(name, class) and 0 or 1 }
    end
    table.sort(order, function(x, y) if x[2] ~= y[2] then return x[2] < y[2] end return x[1] < y[1] end)
    -- a damage spell you can't pay for yet keeps the money: nothing else is bought until you have it
    local worthWaiting = false
    for _, o in ipairs(order) do
        local name, category, rank = serviceInfo(o[1])
        if o[2] == 0 and name and category == "available" and not skip[name] and not boughtNow[name .. (rank or "")]
            and (GetTrainerServiceCost(o[1]) or 0) > spendable then
            worthWaiting = true
        end
    end
    for _, o in ipairs(order) do
        local i = o[1]
        local name, category, rank = serviceInfo(i)
        if name and category == "available" and not skip[name] and not boughtNow[name .. (rank or "")]
            and not (worthWaiting and o[2] == 1) then
            local cost = GetTrainerServiceCost(i) or 0
            -- below level 4 the professions come first (tools, learning the second one); spells that aren't
            -- worth a trip always wait for them
            local lvl = UnitLevel("player") or 1
            local keep = ((o[2] == 1 or lvl < 4) and ns.profReserve) and ns.profReserve() or 0
            if cost + keep <= spendable then
                buying = true
                trainMoney = money - cost
                lastBuy = { i = i, name = name, rank = rank, cost = cost }
                boughtNow[name .. (rank or "")] = true
                BuyTrainerService(i)
                -- the list changes after each purchase: carry on when the trainer updates
                return
            end
        end
    end
    buying = false
    -- skills you could pay for, left because of the reserve: say so once per visit
    if not reserveSaid then
        for _, o in ipairs(order) do
            local name, category, rank = serviceInfo(o[1])
            local cost = GetTrainerServiceCost(o[1]) or 0
            if name and category == "available" and not skip[name] and cost <= money and cost > spendable then
                reserveSaid = true
                ns.print("left " .. name .. " (" .. coins(cost) .. ") at the trainer: buying class skills keeps " .. coins(reserve)
                    .. " (Settings > Trainer)")
                break
            end
        end
    end
    noteTrainer()
    -- and once more a moment later, when the trainer list has caught up with the purchases
    C_Timer.After(1, function()
        if GetNumTrainerServices and (GetNumTrainerServices() or 0) > 0 then noteTrainer() end
        if ns.update then ns.update() end
    end)
    if ns.update then ns.update() end
    if ns.refreshSettings then ns.refreshSettings() end
end

---------------------------------------------------------------- vendor: sell grey items
local function containerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then return C_Container.GetContainerItemInfo(bag, slot) end
    if GetContainerItemInfo then
        local _, count, locked, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
        return { stackCount = count, isLocked = locked, quality = quality, hyperlink = link, hasNoValue = noValue, itemID = id }
    end
end
local function sellJunk()
    local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local a = A()
    if not (a and a.junk) or paused() then return end
    local total, n = 0, 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (numSlots and numSlots(bag) or 0) do
            local info = containerInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue and not info.isLocked and info.itemID then
                local price = select(11, (C_Item and C_Item.GetItemInfo or GetItemInfo)(info.itemID)) or 0
                if price > 0 and n < 12 then -- the server drops sales when there are too many at once
                    useItem(bag, slot)
                    total, n = total + price * (info.stackCount or 1), n + 1
                end
            end
        end
    end
    if n > 0 then ns.print("sold junk for " .. coins(total)) end
end

-- a "Sell junk" step is done once you've opened a vendor while on it
local function vendorStepDone()
    local c = ItineraryCharDB
    if not (c and ns.steps) then return end
    -- the current step, or a "Sell junk" recommendation running next to it
    local list = { c.step }
    if ns.alongActive then for _, j in ipairs(ns.alongActive(c.step)) do list[#list + 1] = j end end
    for _, j in ipairs(list) do
        local s = ns.steps()[j]
        if s and s.vendor then c.manual[j] = true end
    end
    if ns.update then ns.update() end
end

-- Innkeeper: the "make this inn your home?" question after we picked the option. Answered through the popup's
-- own button a moment after it shows (calling ConfirmBinder straight from the event does nothing on this client).
local function acceptBind(tries)
    if not confirmBind or (GetTime() - bindAskedAt) > 10 then confirmBind = false return end
    local f = StaticPopup_FindVisible and StaticPopup_FindVisible("CONFIRM_BINDER")
    if f and f.button1 and f.button1:IsShown() then
        confirmBind = false
        f.button1:Click()
        ns.print("hearthstone set here")
        if ns.update then ns.update() end
        return
    end
    if (tries or 0) < 10 then
        C_Timer.After(0.1, function() acceptBind((tries or 0) + 1) end)
        return
    end
    -- no popup came up: confirm the interaction directly
    confirmBind = false
    local PIM = C_PlayerInteractionManager
    if PIM and PIM.ConfirmationInteraction and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Binder then
        PIM.ConfirmationInteraction(Enum.PlayerInteractionType.Binder)
    elseif ConfirmBinder then
        ConfirmBinder()
    end
    if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_BINDER") end
    if ns.update then ns.update() end
end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
                     "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "QUEST_ACCEPTED", "MERCHANT_SHOW",
                     "CONFIRM_BINDER", "CONFIRM_XP_LOSS", "TAXIMAP_OPENED" }) do
    pcall(f.RegisterEvent, f, e)
end
local trainQueued = false
f:SetScript("OnEvent", function(_, event)
    if not ItineraryDB or not ItineraryDB.auto then return end
    if event == "CONFIRM_BINDER" then
        -- only the bind we asked for (not one you clicked yourself)
        if confirmBind then C_Timer.After(0.1, acceptBind) end
        return
    elseif event == "CONFIRM_XP_LOSS" then
        confirmRez = false
        -- the question pops up right after this event: answer it a moment later, through its button
        C_Timer.After(0.1, acceptRez)
        return
    elseif event == "TAXIMAP_OPENED" then
        C_Timer.After(0.1, takeFlight)
        return
    elseif event == "GOSSIP_SHOW" then onGossip()
    elseif event == "QUEST_GREETING" then onGreeting()
    elseif event == "QUEST_DETAIL" then onDetail(false)
    elseif event == "QUEST_PROGRESS" then onProgress()
    elseif event == "QUEST_COMPLETE" then onComplete()
    elseif event == "QUEST_FINISHED" then hideCoins()
    elseif event == "TRAINER_SHOW" or (event == "TRAINER_UPDATE" and buying) then
        if trainQueued then return end
        trainQueued = true
        C_Timer.After(0.2, function()
            trainQueued = false
            if event == "TRAINER_SHOW" then
                trainMoney, lastBuy, reserveSaid, fullDone = nil, nil, nil, nil; wipe(boughtNow); noteTrainer()
                recordWeaponMaster()
                if ns.update then ns.update() end
            end
            if isClassTrainer() then trainerBuy() else weaponBuy() end
        end)
    elseif event == "TRAINER_CLOSED" then
        buying = false
        if fullRestore then fullRestore() end
        if wpnRestore then wpnRestore() end
        trainMoney, lastBuy = nil, nil
    elseif event == "MERCHANT_SHOW" then
        C_Timer.After(0.1, sellJunk)
        vendorStepDone()
    elseif event == "QUEST_ACCEPTED" then
        routeQuestsFor = nil -- cheap: rebuild on next use (the route may have changed)
    end
end)

-- Some clients ask through a confirmation popup without the event above: answer the one we caused
if hooksecurefunc and StaticPopup_Show then
    hooksecurefunc("StaticPopup_Show", function(which)
        if not which then return end
        local f = _G["StaticPopup_FindVisible"] and StaticPopup_FindVisible(which)
        if (which == "CONFIRM_BINDER") and confirmBind then
            C_Timer.After(0, acceptBind)
        elseif which:find("^XP_LOSS") then
            confirmRez = false
            C_Timer.After(0, acceptRez)
        end
    end)
end
