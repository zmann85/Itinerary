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
    if a.share == nil then a.share = false end      -- share the quests you accept with your group
    if a.bank == nil then a.bank = true end         -- bank steps: put their items in / take them out at the bank
    if a.groupQuests == nil then a.groupQuests = true end -- the guide's group quests in the route (off: its solo versions)
    a.trainSkip = a.trainSkip or {}
    a.trainSeen = a.trainSeen or {} -- [CLASS][spell] = true: spells this class has seen at a trainer (for the filter list)
    if ns.seedClassData then ns.seedClassData() end
end

-- The class skills and trainer places that come with the addon (ClassData.lua, recorded from the game):
-- every class has its full trainer list before its first visit. What a trainer shows you replaces them
-- (ItineraryDB.classSpells[CLASS]["name:rank"] = { name, level, cost, rank, true = seen at a trainer}).
-- The shipped entries are ClassData's own tables (a trainer's replace them, nothing changes them in place),
-- and they leave the saved variables again before the game writes them (ns.unseedClassData): seeded at
-- every login, saved only as what trainers showed.
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
            if not (cur and cur[5]) then cs[key] = e end -- live data wins
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
-- before the game saves (logout, reload): the shipped class skills go out of the saved variables again - they
-- come back from ClassData.lua at the next login; only what a trainer showed ([5] = true) is kept
function ns.unseedClassData()
    local g = ItineraryDB
    for _, cs in pairs(g and g.classSpells or {}) do
        for key, e in pairs(cs) do if not e[5] then cs[key] = nil end end
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
-- A quest the route takes somewhere. A pick-up that's only for when you have its items (RestedXP's "take it and
-- hand it in at once, if you bought the parts": Harvesting the Harvesters, Pearl Diving) counts only while you
-- have them - talking to the quest giver without them doesn't take a quest nothing in the route works on.
local function inRoute(q)
    local r = ns.route and ns.route()
    if not r then return false end
    if routeQuestsFor ~= r.steps then -- a new step list (another route, or edited) builds it again
        routeQuests, routeQuestsFor = {}, r.steps
        for _, s in ipairs(r.steps) do
            if s.t == "accept" then
                for _, id in ipairs(s.q) do
                    local cur = routeQuests[id]
                    if not (s.need or s.needs) then
                        routeQuests[id] = true
                    elseif cur ~= true then
                        cur = cur or {}
                        cur[#cur + 1] = s
                        routeQuests[id] = cur
                    end
                end
            end
        end
    end
    local e = routeQuests[q]
    if e == true or not e then return e or false end
    for _, s in ipairs(e) do
        if ns.itemNeedsMet and ns.itemNeedsMet(s) then return true end
    end
    return false
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
        -- (not one you hid with the × on its row)
        if not header and title and title:match("^Camping 101: ") and q and not inRoute(q)
           and not (ns.alongKeyHidden and ns.alongKeyHidden("q" .. q)) then
            local parts, done = {}, true
            for _, o in ipairs(C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q) or {}) do
                if not o.finished then done = false; parts[#parts + 1] = o.text end
            end
            out[#out + 1] = { title, done and "Done - hand it in" or table.concat(parts, ", "), q = q }
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
    local t = title or titleOf(q)
    if campingWanted(t) then return true end
    -- a profession quest for a profession you didn't pick isn't taken, even where the route has it
    if t and t:match("^Camping 101: ") and #(ns.profChosen and ns.profChosen() or {}) > 0 then return false end
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
    local npc = ns.unitName("npc")
    for _, k in ipairs(list) do
        local s = steps[k]
        if s and s.t == "sethearth" and not ns.stepDone(k) and (not s.npc or s.npc == npc) then return true end
    end
    return false
end
local function optionText(o) return (o.name or ""):lower() end
-- the route wants a flight now: when the step you're on is the flight, or a flight runs along the way right
-- now ("Fly to Redridge" under Instructions while the step is the travel there). Never a later step, so you
-- can't be flown away from a step you still have to do
local function flyWanted()
    if not (ns.steps and ItineraryCharDB) or ns.detourStep then return nil end
    local i = ItineraryCharDB.step
    local steps = ns.steps()
    local s = steps[i]
    if s and s.t == "fly" and s.name and not ns.stepDone(i) then return s end
    if ns.alongActive then
        for _, j in ipairs(ns.alongActive(i)) do
            local f = steps[j]
            if f and f.t == "fly" and f.name and not ns.stepDone(j) then return f end
        end
    end
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

-- you're at this trainer to train: the step you're on, an along-the-way trainer stop, or a trainer
-- instruction (class skills, weapon skills, a profession) names them
local function trainWanted(npc)
    if not npc or (IsShiftKeyDown and IsShiftKeyDown()) or not (ns.steps and ItineraryCharDB) then return false end
    local i = ItineraryCharDB.step
    local steps = ns.steps()
    local s = steps[i]
    if s and s.t == "train" and s.npc == npc then return true end
    for _, j in ipairs(ns.alongActive and ns.alongActive(i) or {}) do
        local st = steps[j]
        if st.t == "train" and st.npc == npc then return true end
    end
    local ok, list = pcall(function() return ns.findDetours and ns.findDetours() or {} end)
    for _, d in ipairs(ok and list or {}) do if d.npc == npc then return true end end
    ok, list = pcall(function() return ns.profRecommend and ns.profRecommend() or {} end)
    for _, r in ipairs(ok and list or {}) do if r.go and r.go.npc == npc then return true end end
    return false
end

-- Itinerary would buy or learn something at this trainer: your class trainer with skills to buy (Buy class
-- skills), a weapon master with a weapon skill to buy (Buy weapon skills), a trainer of a profession you picked
-- with it or its next rank to learn (Learn at the trainer). A trainer with nothing else to say opens its
-- training window by itself; one with another dialogue option (a quest, unlearning talents) waits in the
-- dialogue - this opens the training window there too, so the buying happens the same way.
local function buysHere(npc)
    local a = A()
    if not (a and npc) or (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    if a.train and ns.classTrainers then
        for _, t in ipairs(ns.classTrainers()) do
            if t.name == npc then
                if ns.spellsWaiting and ns.spellsWaiting() then return true end
                -- (with "only worthwhile ones" off, the rest is bought too from level 10)
                local lvl = UnitLevel("player") or 1
                if a.buyWorthOnly == false and lvl >= 10 and ns.learnableSpells then
                    local money = (GetMoney() or 0) - (ns.trainReserve and ns.trainReserve() or 0)
                    for _, e in ipairs(ns.learnableSpells()) do
                        if not e.skip and (e.level or 99) <= lvl and (e.cost or 0) <= money then return true end
                    end
                end
                break
            end
        end
    end
    if a.buyWeapons and ns.weaponMasterList then
        local ok, list = pcall(ns.weaponMasterList, npc)
        if ok and list and #list > 0 then return true end
    end
    local k = a.profLearn ~= false and ns.profOfNpc and ns.profOfNpc(npc)
    if k and ns.profIsChosen and ns.profIsChosen(k) and ns.profLearnable then
        local known = ns.profKnown and ns.profKnown(k)
        for _, e in ipairs((ns.profLearnable(k, npc))) do
            if e.tier then
                if not known and ns.canAfford and ns.canAfford("learn", k) then return true end
                if known and (e.cost or 0) <= (GetMoney() or 0) then return true end
            end
        end
    end
    return false
end
ns.trainerBuysHere = buysHere -- (tests, /iti debug)

-- the dialogue option that opens the training window: the trainer icon first, else its words (never the one
-- for unlearning talents)
local function trainerOption(options)
    local function notTalents(t) return not t:find("unlearn") and not t:find("talent") end
    for _, o in ipairs(options) do
        if o.icon == 132058 and notTalents(optionText(o)) then return o end
    end
    for _, o in ipairs(options) do
        local t = optionText(o)
        if (t:find("train") or t:find("teach") or t:find("skills")) and notTalents(t) then return o end
    end
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
    -- a trainer you came to train at (the route's trainer stop, or a trainer instruction for this NPC), or
    -- one where Itinerary buys or learns something: open the training window, buying runs from there (hold
    -- Shift to talk instead)
    if a.trainGossip ~= false then
        local npc = ns.unitName("npc")
        local o = trainerOption(options)
        if o and (trainWanted(npc) or buysHere(npc)) then
            C_GossipInfo.SelectOption(o.gossipOptionID or o.optionID)
            return
        end
    end
    if not a.gossip then return end
    -- a dialogue choice the route asks for at this NPC, or one the game marks as part of a quest
    local want = {}
    for _, s in ipairs(stepsForNpc(ns.unitName("npc"))) do
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
    -- the route says "just talk to them" (gossip = true) and there is only one thing to say
    if #options == 1 then
        for _, s in ipairs(stepsForNpc(ns.unitName("npc"))) do
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
-- Escorts and fights that start the moment you accept them, from the NPC who also takes the quest before them
-- (quest = { that quest before it, ... }). In a group, a member who hasn't handed that one in yet can't join
-- and is left out - so these wait until nobody near you still has it in their log. Not here: escorts with
-- nothing to hand in at that NPC first (contested respawns: Protect Kaya, Tooga's Quest) - those are taken as
-- fast as ever. From the game's quest data (QuestieDB's WoW Forever quests: a scripted quest whose giver takes
-- one of its previous quests, the event starting on accept); the escorts RestedXP holds back are in it.
ns.GROUP_WAIT = {
    [434] = { 2746 },   -- The Attack! (Tyrion)
    [648] = { 351 },    -- Rescue OOX-17/TN!
    [660] = { 657 },    -- Hints of a New Plague? (Kinelory)
    [731] = { 729 },    -- The Absent Minded Prospector (Prospector Remtravel)
    [836] = { 485 },    -- Rescue OOX-09/HL!
    [863] = { 858 },    -- The Escape (Wizzlecrank's Shredder)
    [994] = { 993 },    -- Escape Through Force (Volcor)
    [995] = { 993 },    -- Escape Through Stealth (Volcor)
    [1249] = { 1248 },  -- The Missing Diplomat (Mikhail: Tapoke Jahn)
    [1324] = { 1266 },  -- The Missing Diplomat (Private Hendel)
    [1440] = { 1439 },  -- Return to Vahlarriel (Dalinda Malem)
    [1447] = { 1246 },  -- The Missing Diplomat (Dashel Stonefist)
    [1640] = { 1639 },  -- Beat Bartleby
    [1651] = { 1650 },  -- The Tome of Valor (Daphne Stilwell)
    [2767] = { 2766 },  -- Rescue OOX-22/FE!
    [2845] = { 2844 },  -- Wandering Shay
    [3525] = { 3523 },  -- Extinguishing the Idol (Belnistrasz)
    [3982] = { 3981 },  -- What Is Going On? (Commander Gor'shak)
    [4245] = { 4244 },  -- Chasing A-Me 01
    [4322] = { 4282 },  -- Jail Break! (Marshal Windsor)
    [4491] = { 4492 },  -- A Little Help From My Friends (Ringo)
    [4901] = { 979 },   -- Guardians of the Altar (Ranshalla)
    [4966] = { 4881 },  -- Protect Kanati Greycloud
    [5203] = { 5202 },  -- Rescue From Jaedenar (Captured Arko'narin)
    [6403] = { 6402 },  -- The Great Masquerade (Reginald Windsor)
    [7046] = { 7044 },  -- The Scepter of Celebras
}
-- the group members near you (in sight) who still have one of those quests in their log: their names
local function groupUnits()
    local out = {}
    if IsInRaid and IsInRaid() then
        for k = 1, 40 do local u = "raid" .. k; if UnitExists(u) and not UnitIsUnit(u, "player") then out[#out + 1] = u end end
    elseif IsInGroup and IsInGroup() then
        for k = 1, 4 do local u = "party" .. k; if UnitExists(u) then out[#out + 1] = u end end
    end
    return out
end
function ns.groupStillOn(prev)
    local names = {}
    local on = C_QuestLog and C_QuestLog.IsUnitOnQuest
    for _, u in ipairs(groupUnits()) do
        if (not UnitIsConnected or UnitIsConnected(u)) and (not UnitIsVisible or UnitIsVisible(u)) then
            for _, p in ipairs(prev) do
                local ok, yes = pcall(on, u, p)
                if ok and ns.plain(yes) then names[#names + 1] = ns.unitName(u) or "a group member" break end
            end
        end
    end
    return names, on ~= nil
end
local waitFor -- the quest the open quest window waits with: { q = id, said = text }
local startTicking -- (below)
local function groupWaits(id)
    local a = A()
    local prev = id and ns.GROUP_WAIT[id]
    if not prev or (a and a.groupWait == false) or not (IsInGroup and IsInGroup()) then return false end
    local names, can = ns.groupStillOn(prev)
    if not can then
        -- (no way to see the others' quests: you accept it yourself)
        if not (waitFor and waitFor.q == id) then ns.print("in a group: accept this escort yourself when everyone is ready") end
        waitFor = { q = id, manual = true }
        return true
    end
    if #names == 0 then return false end
    local title = (ns.routeQuestName and ns.routeQuestName(prev[1]))
        or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(prev[1]))
    local text = table.concat(names, ", ") .. " still " .. (#names == 1 and "has " or "have ") .. (title or "the quest before it")
        .. " to hand in - accepting once " .. (#names == 1 and "it's" or "they're") .. " in (or click Accept)"
    if not (waitFor and waitFor.q == id and waitFor.said == text) then ns.print("waiting for your group: " .. text) end
    local ticking = waitFor and waitFor.q == id and waitFor.ticking
    waitFor = { q = id, said = text, ticking = ticking }
    return true
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
        -- an escort your group has to be ready for: the window stays open until they are
        if groupWaits(id) then startTicking() return end
        waitFor = nil
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        else
            AcceptQuest()
        end
    end
end
-- while a quest window waits for the group: look again when a member's quest log changes, and every second
local function recheckWait()
    if not waitFor or waitFor.manual then return end
    local id = GetQuestID and GetQuestID()
    if not (QuestFrame and QuestFrame:IsShown()) or id ~= waitFor.q then waitFor = nil return end
    if not groupWaits(id) then
        waitFor = nil
        ns.print("your group is ready: accepting")
        if QuestGetAutoAccept and QuestGetAutoAccept() then
            if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        else
            AcceptQuest()
        end
    end
end
ns.recheckGroupWait = recheckWait
local function tick()
    if not (waitFor and not waitFor.manual) then return end
    recheckWait()
    if waitFor and not waitFor.manual then C_Timer.After(1, tick) else if waitFor then waitFor.ticking = nil end end
end
function startTicking()
    if waitFor and not waitFor.manual and not waitFor.ticking then waitFor.ticking = true; C_Timer.After(1, tick) end
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
-- A gold coin on the reward that sells for the most: the one to take when nothing is an upgrade
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
        -- a gold coin on the corner of the item's name box: tells "sells for the most" apart from the game's own
        -- highlight on the reward you click
        -- (inside the top right of the reward's box: the button's own edge - the name frame's texture is
        -- wider than what it shows)
        local box = CreateFrame("Frame", nil, b)
        box:SetSize(16, 16)
        box:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -3)
        box:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
        local shadow = box:CreateTexture(nil, "BACKGROUND")
        shadow:SetPoint("CENTER"); shadow:SetSize(18, 18)
        shadow:SetTexture("Interface\\Common\\Indicator-Gray"); shadow:SetVertexColor(0, 0, 0, 0.8)
        local coin = box:CreateTexture(nil, "OVERLAY")
        coin:SetAllPoints()
        coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
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
    -- a skill the trainer lists under a new name (Blessing of Salvation -> Salvation): the old name's entry goes
    local listed, twin = {}, {}
    for i = 1, GetNumTrainerServices() or 0 do
        local name, _, rank = serviceInfo(i)
        if name then listed[name .. ":" .. (rank or "")] = true end
    end
    for key, e in pairs(cs) do
        if listed[key] and e[6] then twin[table.concat({ tostring(e[2]), tostring(e[3]), tostring(e[4] or ""), tostring(e[6]) }, ":")] = e[1] end
    end
    for key, e in pairs(cs) do
        local g = e[6] and table.concat({ tostring(e[2]), tostring(e[3]), tostring(e[4] or ""), tostring(e[6]) }, ":")
        if not listed[key] and g and twin[g] and twin[g] ~= e[1] then cs[key] = nil end
    end
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
        local npc = ns.unitName("npc")
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
        local npc = ns.unitName("npc")
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
    local npc = ns.unitName("npc")
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
local learnableSpells
function ns.learnableSpells() return ns.memo("learnableSpells", learnableSpells) end
learnableSpells = function()
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
    -- a skill the game renamed (Blessing of Salvation is Salvation now): the old name's entry has the same
    -- level, price, rank and icon as the new one, and knowing the new one is knowing it
    -- (one string per entry, no list to join: this runs for every class skill at each refresh)
    local function sig(e) return e[6] and (tostring(e[2]) .. ":" .. tostring(e[3]) .. ":" .. tostring(e[4] or "") .. ":" .. tostring(e[6])) end
    local top, low, knownSig = {}, {}, {}
    for _, e in pairs(cs) do
        local name, rank = e[1], e[4]
        local n = rank and tonumber(rank:match("(%d+)")) or 0
        if name and known(name, rank) then
            if (top[name] or -1) < n then top[name] = n end
            local g = sig(e)
            if g then knownSig[g] = true end
        end
        if name and (not low[name] or n < low[name]) then low[name] = n end
    end
    local out = {}
    for _, e in pairs(cs) do
        local name, req, cost, rank = e[1], e[2], e[3], e[4]
        local n = rank and tonumber(rank:match("(%d+)")) or 0
        -- a spell whose first rank no trainer teaches comes from a talent (Seal of Command, Holy Shock, Mortal
        -- Strike) or a quest: its higher ranks only once you have it
        local gated = name and low[name] and low[name] > 1 and not top[name] and not known(name)
        local g = sig(e)
        local renamed = g and knownSig[g]
        if name and req and req <= lvl and not gated and not renamed and not (top[name] and top[name] >= n) then
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
    -- only the worthwhile skills (Settings > Trainer, on by default); with that off, still only them before
    -- level 10: the rest waits (money for professions, gear, bags)
    local early = a.buyWorthOnly ~= false or (UnitLevel("player") or 1) < 10
    for _, o in ipairs(order) do
        local i = o[1]
        local name, category, rank = serviceInfo(i)
        if name and category == "available" and not skip[name] and not boughtNow[name .. (rank or "")]
            and not (worthWaiting and o[2] == 1) and not (early and o[2] == 1) then
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
        local lvl = UnitLevel("player") or 1
        for _, o in ipairs(order) do
            local name, category, rank = serviceInfo(o[1])
            local cost = GetTrainerServiceCost(o[1]) or 0
            if name and category == "available" and not skip[name] and cost <= money and cost > spendable
               and not (early and o[2] == 1) then
                reserveSaid = true
                ns.print("left " .. name .. " (" .. coins(cost) .. ") at the trainer: buying class skills keeps " .. coins(reserve)
                    .. " (Settings > Trainer)")
                break
            end
            -- (or because the money for your professions comes first below level 4: that was silent - the
            -- user's Skyborne rogue left Stealth with nothing said)
            local keep = ((o[2] == 1 or lvl < 4) and ns.profReserve) and ns.profReserve() or 0
            if name and category == "available" and not skip[name] and not boughtNow[name .. (rank or "")]
               and cost <= spendable and cost + keep > spendable and not (early and o[2] == 1)
               and not (worthWaiting and o[2] == 1) then
                reserveSaid = true
                ns.print("left " .. name .. " (" .. coins(cost) .. ") at the trainer: "
                    .. (lvl < 4 and "up to level 4 the money for your professions comes first" or "the money for your professions comes first")
                    .. " (" .. coins(keep) .. ": their tools and learning them; Settings > Professions)")
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
    local npc = ns.unitName("npc")
    for _, j in ipairs(list) do
        local s = ns.steps()[j]
        if s and s.vendor then c.manual[j] = true end
        -- the guide's vendor visits (".vendor", "Vendor trash at Rallic Finn"): done when you open that vendor
        -- (a "Vendor trash" step with no NPC: any vendor). Steps that buy something finish on their items instead.
        if s and s.t == "do" and not s.col and not s.need and not s.needs then
            local junk = s.name and (s.name:find("^Vendor trash") or s.name:find("^Sell ") or s.name:find("[Vv]endor"))
            -- (selling junk as an instruction next to your step: any vendor you open does it)
            local sell = s.errand and s.name and (s.name:find("^Vendor trash") or s.name:find("^Sell "))
            if (s.npc and npc and s.npc == npc) or (junk and not s.npc) or sell then c.manual[j] = true end
        end
    end
    if ns.update then ns.update() end
end
-- an optional buy (a weapon, quest items for later, the auction house's "buy these"): done when you close that
-- vendor - you had your chance to buy - or any auction house for the auction house's
local lastShop = false
local function buyErrandsDone(npc, auction)
    local c = ItineraryCharDB
    if not (c and ns.steps) then return end
    local list = { c.step }
    if ns.alongActive then for _, j in ipairs(ns.alongActive(c.step)) do list[#list + 1] = j end end
    local hit = false
    for _, j in ipairs(list) do
        local s = ns.steps()[j]
        if s and s.errandBuy then
            local isAuction = s.ah or (s.npc and s.npc:find("^Auctioneer")) or false
            if (auction and isAuction) or (not auction and npc and s.npc == npc) then c.manual[j] = true; hit = true end
        end
    end
    if hit and ns.update then ns.update() end
end
ns.buyErrandsDone = buyErrandsDone

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

---------------------------------------------------------------- bank steps
-- A bank step (bankIn / bankOut: RestedXP's ".bankdeposit" / ".bankwithdraw"): opening the bank while it's your step
-- puts its items in and takes its items out (Settings > Route > Bank steps), one at a time; the bank steps right
-- after it (take these out, put those in) go in the same visit. A withdrawal is done once the open bank has none of
-- its items left - also one you never had; a deposit once none of its items are in your bags (Core.lua).
local bankOpen, bankBusy, bankQueued, bankTries = false, false, false, 0
local bankStart
local bankTaken, bankMoved = {}, nil
local function numSlots(bag)
    local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    return f and f(bag) or 0
end
local function pickup(bag, slot)
    local f = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
    if f then f(bag, slot) end
end
-- the character bank: its tabs (WoW Forever), or the old bank and its bags
local function bankBags()
    local out = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
        local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(ids) == "table" then for _, b in ipairs(ids) do out[#out + 1] = b end end
        if #out > 0 then return out end
    end
    if Enum and Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1 then
        for k = 1, 9 do local b = Enum.BagIndex["CharacterBankTab_" .. k]; if b then out[#out + 1] = b end end
        return out
    end
    if BANK_CONTAINER then out[#out + 1] = BANK_CONTAINER end
    local n = NUM_BAG_SLOTS or 4
    for b = n + 1, n + (NUM_BANKBAGSLOTS or 6) do out[#out + 1] = b end
    return out
end
local function playerBags()
    local out = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
    return out
end
-- an empty slot to put something (not one a move of this visit is filling; in your bags not a quiver, soul or
-- herb bag)
local function emptySlot(bags, mine)
    local free = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    for _, bag in ipairs(bags) do
        local family = 0
        if mine and free then family = select(2, free(bag)) or 0 end
        if family == 0 then
            for slot = 1, numSlots(bag) do
                if not containerInfo(bag, slot) and not bankTaken[bag * 1000 + slot] then return bag, slot end
            end
        end
    end
end
local function inBags(bags, id)
    for _, bag in ipairs(bags) do
        for slot = 1, numSlots(bag) do
            local info = containerInfo(bag, slot)
            if info and info.itemID == id then return true end
        end
    end
    return false
end
-- one item of a set from these bags to those: "moved", "wait" (one is still on its way), "full" or nil (none left)
local function moveOne(set, from, to, mine)
    local wait = false
    for _, bag in ipairs(from) do
        for slot = 1, numSlots(bag) do
            local info = containerInfo(bag, slot)
            if info and info.itemID and set[info.itemID] then
                if info.isLocked then
                    wait = true
                else
                    local tb, ts = emptySlot(to, mine)
                    if not tb then return "full" end
                    pickup(bag, slot)
                    pickup(tb, ts)
                    if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() return "full" end
                    bankTaken[tb * 1000 + ts] = true
                    local m = bankMoved[mine and "out" or "in"]
                    m[info.itemID] = (m[info.itemID] or 0) + (info.stackCount or 1)
                    return "moved"
                end
            end
        end
    end
    return wait and "wait" or nil
end
-- your step and the bank steps right after it that aren't done
local function bankSteps()
    local c = ItineraryCharDB
    local out = {}
    if not (c and ns.steps) then return out end
    local steps, j = ns.steps(), c.step
    while steps[j] and steps[j].t == "do" and (steps[j].bankIn or steps[j].bankOut) do
        if not ns.stepDone(j) then out[#out + 1] = j end
        j = j + 1
    end
    return out
end
local function itemText(id, n)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local link = info and select(2, info(id))
    return (link or ("item " .. id)) .. ((n or 1) > 1 and (" x" .. n) or "")
end
local function bankSay(full)
    if not bankMoved then return end
    for _, k in ipairs({ "in", "out" }) do
        local t = {}
        for id, n in pairs(bankMoved[k]) do t[#t + 1] = itemText(id, n) end
        if #t > 0 then ns.print((k == "in" and "put in the bank: " or "taken out of the bank: ") .. table.concat(t, ", ")) end
    end
    if full == "full" then ns.print("no room left for the rest - make some space and open the bank again") end
    bankMoved = { ["in"] = {}, out = {} }
end
local function bankWork()
    bankQueued = false
    if not bankOpen then bankBusy = false return end
    local c, steps = ItineraryCharDB, ns.steps()
    local list = bankSteps()
    if #list == 0 then bankBusy = false; bankSay() return end
    -- (the bank's slots not there yet: nothing can be told about what's in it - look again in a moment)
    local loaded = false
    for _, b in ipairs(bankBags()) do if numSlots(b) > 0 then loaded = true break end end
    if not loaded then
        bankBusy = false
        bankTries = (bankTries or 0) + 1
        if bankTries <= 10 then bankStart(0.5) end
        return
    end
    local put, take = {}, {}
    for _, j in ipairs(list) do
        for _, id in ipairs(steps[j].bankIn or {}) do put[id] = true end
        for _, id in ipairs(steps[j].bankOut or {}) do take[id] = true end
    end
    -- (in one step and out in another: leave it where it is)
    for id in pairs(put) do if take[id] then put[id], take[id] = nil, nil end end
    local a = A()
    local state
    if a and a.bank ~= false and not paused() and not (CursorHasItem and CursorHasItem()) then
        bankBusy = true
        bankMoved = bankMoved or { ["in"] = {}, out = {} }
        state = moveOne(put, playerBags(), bankBags(), false)
        if state ~= "moved" and state ~= "full" then
            local s2 = moveOne(take, bankBags(), playerBags(), true)
            if s2 then state = s2 end
        end
        if state == "moved" or state == "wait" then
            C_Timer.After(state == "moved" and 0.15 or 0.3, bankWork)
            return
        end
    end
    bankBusy = false
    bankSay(state)
    -- nothing (more) to move: a withdrawal is done when the bank has none of its items left (and what the step
    -- puts in is in)
    local hit = false
    local bank, bags = bankBags(), playerBags()
    for _, j in ipairs(list) do
        local s = steps[j]
        if s.bankOut and not c.manual[j] then
            local left = false
            for _, id in ipairs(s.bankOut) do if inBags(bank, id) then left = true break end end
            for _, id in ipairs(s.bankIn or {}) do if not left and inBags(bags, id) then left = true end end
            if not left then c.manual[j] = true; hit = true end
        end
    end
    if hit and ns.update then ns.update() end
end
function bankStart(delay)
    if bankQueued or bankBusy then return end
    bankQueued = true
    C_Timer.After(delay or 0.2, bankWork)
end
ns.bankStart = bankStart

---------------------------------------------------------------- sharing quests in a group
-- Settings > Quests > Share quests in a group (off): every quest you accept is shared with your group right away,
-- when it can be shared, so whoever is behind (skilling a profession, say) doesn't have to run to the quest giver.
-- Not the ones a group member shared with you: they have it already.
local fromPlayer = {} -- quest id -> true: offered by a player (shared with you), not by an NPC
local function noteSharer()
    local id = GetQuestID and GetQuestID()
    if not (id and id > 0 and UnitIsPlayer) then return end
    for _, u in ipairs({ "npc", "questnpc" }) do
        if UnitExists and UnitExists(u) and UnitIsPlayer(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            fromPlayer[id] = true
            return
        end
    end
end
local function questLogIndex(q)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local i = C_QuestLog.GetLogIndexForQuestID(q)
        if i and i > 0 then return i end
    end
    for i = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
        if GetQuestLogTitle and select(8, GetQuestLogTitle(i)) == q then return i end
    end
end
-- Shares go out one at a time, a few seconds apart: a group member whose quest window is still open for the one before
-- (their auto-accept takes a moment) is "busy" and gets nothing. How a share went the game only says in chat ("Bob is
-- busy.", "Bob has accepted your quest."): a busy member gets it again a moment later, one too far away once near
-- you. And every 10 seconds the quests shared this way are held against the group (C_QuestLog.IsUnitOnQuest): someone
-- near you who still hasn't got one gets it again - not one who declined it, can't take it, has done it or has a
-- full quest log. At most 5 shares of a quest, for 30 minutes after you took it; the repeats' chat lines (but
-- "accepted") are left out.
local SHARE_GAP, SHARE_TRIES, SHARE_FOR, SHARE_EVERY, SHARE_BUSY = 2.5, 5, 1800, 10, 3
local shared = {}     -- quest id -> { at = when you took it, tries = shares, last = last share, final = {[name] = result}, far = {} }
local shareOrder = {} -- quest ids waiting to be shared, in order
local lastPush, lastPushQ, lastPushRepeat = -100, nil, false
local pumping = false
local FINAL = { accepted = true, has = true, done = true, cant = true, full = true, declined = true, gone = true }
local RESULT_STRINGS = {
    { "ERR_QUEST_PUSH_ACCEPTED_S", "accepted", "%s has accepted your quest." },
    { "ERR_QUEST_PUSH_BUSY_S", "busy", "%s is busy." },
    { "ERR_QUEST_PUSH_TOO_FAR_S", "far", "%s is too far away to receive your quest." },
    { "ERR_QUEST_PUSH_DECLINED_S", "declined", "%s has declined your quest." },
    { "ERR_QUEST_PUSH_ONQUEST_S", "has", "%s is already on that quest." },
    { "ERR_QUEST_PUSH_ALREADY_DONE_S", "done", "%s has completed that quest." },
    { "ERR_QUEST_PUSH_INVALID_S", "cant", "%s is not eligible for that quest." },
    { "ERR_QUEST_PUSH_LOG_FULL_S", "full", "%s's quest log is full." },
    { "ERR_QUEST_PUSH_NOT_IN_PARTY_S", "gone", "%s is not in your party." },
    { "ERR_QUEST_PUSH_TIMER_EXPIRED_S", "cant" },
    { "ERR_QUEST_PUSH_NOT_DAILY_S", "cant" },
    { "ERR_QUEST_PUSH_DIFFERENT_SERVER_DAILY_S", "cant" },
    { "ERR_QUEST_PUSH_INVALID_TO_RECIPIENT_S", "cant" },
    { "ERR_QUEST_PUSH_NEW_PLAYER_EXPERIENCE_S", "cant" },
    { "ERR_QUEST_PUSH_NOT_ALLOWED_S", "cant" },
    { "ERR_QUEST_PUSH_SUCCESS_S", "sent", "Sharing quest with %s..." },
}
local resultPatterns
local function shareResult(msg)
    if type(msg) ~= "string" then return end
    if not resultPatterns then
        resultPatterns = {}
        for _, e in ipairs(RESULT_STRINGS) do
            local fmt = _G[e[1]]
            if type(fmt) ~= "string" then fmt = e[3] end
            if fmt then
                -- the game's text with the player's name for its %s ("%1$s" in some languages)
                local pat = fmt:gsub("%%%d?%$?s", "\1")
                pat = pat:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                pat = pat:gsub("\1", "(.-)")
                resultPatterns[#resultPatterns + 1] = { "^" .. pat .. "$", e[2] }
            end
        end
    end
    for _, p in ipairs(resultPatterns) do
        local name = msg:match(p[1])
        if name then return p[2], (name:gsub("%-.*$", "")) end
    end
end
ns.shareResult = shareResult
local function memberName(u)
    local n = ns.unitName and ns.unitName(u) or (UnitName and UnitName(u))
    return type(n) == "string" and (n:gsub("%-.*$", "")) or nil
end
local queueShare
local function pushShare(q)
    local a = A()
    local e = shared[q]
    if not (a and a.share and e) or not (IsInGroup and IsInGroup()) or not QuestLogPushQuest then return end
    local idx = questLogIndex(q)
    if not idx then
        -- (the quest log may not list it yet)
        e.waits = (e.waits or 0) + 1
        if e.waits <= 5 and e.tries == 0 then C_Timer.After(0.5, function() queueShare(q) end) end
        return
    end
    -- the quest log's selection is what gets shared: select it, share, put your selection back
    local before = GetQuestLogSelection and GetQuestLogSelection()
    if SelectQuestLogEntry then SelectQuestLogEntry(idx)
    elseif C_QuestLog and C_QuestLog.SetSelectedQuest then C_QuestLog.SetSelectedQuest(q) end
    if not GetQuestLogPushable or GetQuestLogPushable() then
        QuestLogPushQuest()
        lastPush, lastPushQ, lastPushRepeat = GetTime(), q, e.tries > 0
        e.tries, e.last = e.tries + 1, GetTime()
    else
        shared[q] = nil -- (not one that can be shared)
    end
    if before and before > 0 and before ~= idx and SelectQuestLogEntry then SelectQuestLogEntry(before) end
end
local function pumpShares()
    if #shareOrder == 0 then return end
    local wait = lastPush + SHARE_GAP - GetTime()
    if wait > 0 then
        if not pumping then
            pumping = true
            C_Timer.After(wait, function() pumping = false; pumpShares() end)
        end
        return
    end
    pushShare(table.remove(shareOrder, 1))
    if #shareOrder > 0 then pumpShares() end
end
function queueShare(q)
    for _, x in ipairs(shareOrder) do if x == q then return end end
    shareOrder[#shareOrder + 1] = q
    pumpShares()
end
-- a quest you took: shared with the group (not one a group member shared with you)
local function shareQuest(q)
    local a = A()
    if not (a and a.share and q and q > 0) or not (IsInGroup and IsInGroup()) or not QuestLogPushQuest then return end
    if fromPlayer[q] then fromPlayer[q] = nil return end
    shared[q] = { at = GetTime(), tries = 0, final = {}, far = {} }
    queueShare(q)
end
ns.shareQuest = shareQuest
-- the game's answer to a share, per group member
local function onShareResult(msg)
    if not lastPushQ or GetTime() - lastPush > 8 then return end
    local r, name = shareResult(msg)
    local e = shared[lastPushQ]
    if not (r and name and e) then return end
    local q = lastPushQ
    if FINAL[r] then
        e.final[name] = r; e.far[name] = nil
    elseif r == "busy" and e.tries < SHARE_TRIES then
        C_Timer.After(SHARE_BUSY, function() if shared[q] then queueShare(q) end end)
    elseif r == "far" then
        e.far[name] = true
    end
end
ns.onShareResult = onShareResult
-- the repeats' chat lines ("Bob is already on that quest.") are left out; "accepted" stays
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if lastPushRepeat and GetTime() - lastPush <= 8 then
            local r = shareResult(msg)
            if r and r ~= "accepted" then return true end
        end
        return false
    end)
end
-- someone near you in your group who doesn't have quest q and hasn't answered it for good
local function shareNeeded(q, e)
    local f = C_QuestLog and C_QuestLog.IsUnitOnQuest
    if not f then return false end
    for k = 1, 4 do
        local u = "party" .. k
        if UnitExists and UnitExists(u) then
            local name = memberName(u)
            local near = not UnitIsVisible or UnitIsVisible(u)
            local fight = UnitAffectingCombat and UnitAffectingCombat(u)
            if name and not e.final[name] and near and not fight and (not UnitIsConnected or UnitIsConnected(u)) then
                local okc, on = pcall(f, u, q)
                if okc and on == false then return true end
            end
        end
    end
    return false
end
-- every 10 seconds: the quests shared this way that someone near you still hasn't got
function ns.shareCheck()
    local a = A()
    if not (a and a.share) or not (IsInGroup and IsInGroup()) then return end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then return end
    local now = GetTime()
    for q, e in pairs(shared) do
        if now - e.at > SHARE_FOR or e.tries >= SHARE_TRIES or (e.tries > 0 and not questLogIndex(q)) then
            shared[q] = nil
        elseif e.tries > 0 and now - (e.last or 0) >= SHARE_EVERY and shareNeeded(q, e) then
            queueShare(q)
        end
    end
end
function ns.shareState(q) return shared[q] end
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(SHARE_EVERY, function() pcall(ns.shareCheck) end) end

---------------------------------------------------------------- events
local f = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_QUEST_LOG_CHANGED", "GROUP_ROSTER_UPDATE",
                     "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED",
                     "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "QUEST_ACCEPTED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
                     "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "CONFIRM_BINDER", "CONFIRM_XP_LOSS", "TAXIMAP_OPENED",
                     "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED",
                     "CHAT_MSG_SYSTEM" }) do
    pcall(f.RegisterEvent, f, e)
end
local trainQueued = false
f:SetScript("OnEvent", function(_, event, a1, a2)
    if not ItineraryDB or not ItineraryDB.auto then return end
    if event == "CHAT_MSG_SYSTEM" then
        onShareResult(a1)
        return
    elseif event == "CONFIRM_BINDER" then
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
    elseif event == "QUEST_DETAIL" then noteSharer(); onDetail(false)
    elseif event == "QUEST_PROGRESS" then onProgress()
    elseif event == "QUEST_COMPLETE" then onComplete()
    elseif event == "QUEST_FINISHED" then hideCoins(); waitFor = nil
    elseif event == "UNIT_QUEST_LOG_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        if waitFor then C_Timer.After(0.2, recheckWait) end
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
        lastShop = ns.unitName("npc") or false
        C_Timer.After(0.1, sellJunk)
        vendorStepDone()
    elseif event == "MERCHANT_CLOSED" then
        if lastShop then buyErrandsDone(lastShop, false) end
        lastShop = false
    elseif event == "BANKFRAME_OPENED" then
        bankOpen, bankTaken, bankMoved, bankTries = true, {}, nil, 0
        -- (the bank's contents come a moment after it opens)
        bankStart(0.4)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        bankSay()
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        -- items moved by hand while the bank is open: a withdrawal may be done now
        if bankOpen then bankStart(0.3) end
    elseif event == "AUCTION_HOUSE_SHOW" then
        lastShop = false
    elseif event == "AUCTION_HOUSE_CLOSED" then
        buyErrandsDone(nil, true)
    elseif event == "QUEST_ACCEPTED" then
        routeQuestsFor = nil -- cheap: rebuild on next use (the route may have changed)
        -- (QUEST_ACCEPTED: log index, quest id; some clients give just the id)
        local q = (type(a2) == "number" and a2 > 0) and a2 or a1
        if type(q) == "number" and q > 0 then C_Timer.After(0.3, function() shareQuest(q) end) end
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
