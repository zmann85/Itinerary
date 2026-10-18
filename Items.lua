-- Itinerary quest item buttons: one click-to-use button per usable quest item in your bags.
-- Secure buttons, so they only change out of combat; during combat they keep what they had.
local ADDON, ns = ...

local MAX, SIZE = 4, 30
local row, buttons, target = nil, {}, nil
local pending = false

-- Key bindings (Options > Keybindings > AddOns > Itinerary; Bindings.xml)
BINDING_HEADER_ITINERARY = "Itinerary"
_G["BINDING_NAME_CLICK ItineraryTarget:LeftButton"] = "Target quest mobs / NPC"
for i = 1, MAX do _G["BINDING_NAME_CLICK ItineraryItem" .. i .. ":LeftButton"] = "Quest item " .. i end

local function accent() return ns.accent() end
local function edges(f, a)
    local px = 1 / (f:GetEffectiveScale() or 1)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, a)
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetHeight(px) else t:SetWidth(px) end
    end
end

local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local hearthTimer = false -- a check is queued for when the Hearthstone gets within 5 minutes of ready
local function bagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end
local function bagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.itemID
    end
end

local HEARTHSTONE = 6948

-- What an open objective of a step's quest asks you to do yourself, for any route (also when the route doesn't
-- say): an emote ("Sit near the campfire", "Salute Guard Thomas", "Use the /dance emote") gets a macro button, a
-- quest item with a Use effect in your bags that the objective or the quest's name mentions gets an item button.
local EMOTES = { sit = true, dance = true, kneel = true, salute = true, bow = true, cheer = true, wave = true,
    roar = true, flex = true, sleep = true, kiss = true, hug = true, applaud = true, clap = true, laugh = true,
    thank = true, greet = true, pray = true, beg = true, chicken = true, flirt = true, cry = true, cower = true,
    plead = true, bonk = true, tickle = true, shy = true }
local EMOTE_ICON = { sit = "Interface\\Icons\\Spell_Nature_Sleep", sleep = "Interface\\Icons\\Spell_Nature_Sleep",
    kneel = "Interface\\Icons\\Spell_Holy_PrayerOfHealing", pray = "Interface\\Icons\\Spell_Holy_PrayerOfHealing" }
local function emoteOf(text)
    local t = text:lower()
    local w = t:match("/(%a+)")
    if w and EMOTES[w] then return w end
    w = t:match("^%s*(%a+)")
    if w and EMOTES[w] then return w end
    w = t:match("(%a+)%s+emote")
    if w and EMOTES[w] then return w end
end
local STOP = { the = true, with = true, from = true, near = true, into = true, your = true, this = true, that = true,
    collect = true, collected = true, slain = true, killed = true, bring = true, gather = true, find = true, found = true }
local function stems(t, out)
    out = out or {}
    for x in (t or ""):lower():gmatch("%a+") do if #x >= 4 and not STOP[x] then out[x:sub(1, 5)] = true end end
    return out
end
local function isQuestItem(bag, slot)
    local qinfoFn = C_Container and C_Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    if not qinfoFn then return false end
    local a = qinfoFn(bag, slot)
    if type(a) == "table" then return a.isQuestItem end
    return a and true or false
end
local function nameOf(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    return GetItemInfo and (GetItemInfo(id)) or nil
end
-- -> macros { name, icon, text }, item ids
function ns.objectiveHelpers(s)
    local macros, items, have = {}, {}, {}
    if not (s and s.t == "complete" and s.q and C_QuestLog and C_QuestLog.GetQuestObjectives) then return macros, items end
    local want = {}
    for k, q in ipairs(s.q) do
        local oi = s.qo and s.qo[k] or 0
        local on = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q)
        if on then
            local any = false
            for i, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
                if (oi == 0 or oi == i) and not o.finished and o.text and o.text ~= "" then
                    any = true
                    local text = o.text:gsub("^%s*%d+/%d+%s*", ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "")
                    local e = o.type ~= "item" and o.type ~= "monster" and emoteOf(text)
                    if e and not s.macro then
                        -- at someone the step names: target them first
                        local who
                        local names = {}
                        if s.npc then for n in tostring(s.npc):gmatch("[^,]+") do names[#names + 1] = n:match("^%s*(.-)%s*$") end end
                        for _, n in ipairs(s.mobs or {}) do names[#names + 1] = n end
                        for _, n in ipairs(names) do if n ~= "" and text:lower():find(n:lower(), 1, true) then who = n break end end
                        local line = (who and ("/tar " .. who .. "\n") or "") .. "/" .. e
                        macros[#macros + 1] = { e:sub(1, 1):upper() .. e:sub(2), EMOTE_ICON[e] or "Interface\\Icons\\Ability_Warrior_BattleShout", line }
                    end
                    stems(text, want)
                end
            end
            if any and C_QuestLog.GetTitleForQuestID then stems(C_QuestLog.GetTitleForQuestID(q), want) end
        end
    end
    if next(want) then
        for bag = 0, 4 do
            for slot = 1, bagSlots(bag) or 0 do
                local id = bagItem(bag, slot)
                if id and not have[id] and getSpell and getSpell(id) and isQuestItem(bag, slot) then
                    for st in pairs(stems(nameOf(id))) do
                        if want[st] then items[#items + 1] = id; have[id] = true; break end
                    end
                end
            end
        end
    end
    return macros, items
end

-- the current step's quest items (from the route) that are in your bags and have a Use effect
local function questItems()
    local found = {}
    if not (ns.steps and ItineraryCharDB) then return found end
    local steps, i = ns.steps(), ItineraryCharDB.step
    local cur = ns.current and ns.current() or steps[i]
    local list = { cur }
    -- (gather mode and trainer detours: only that step, nothing from the route alongside)
    if ns.alongActive and not (cur and cur.detour) then for _, j in ipairs(ns.alongActive(i)) do list[#list + 1] = steps[j] end end
    local seen = {}
    -- looted items that start a quest you don't have yet (right-click opens the quest): first in line
    local qinfo = C_Container and C_Container.GetContainerItemQuestInfo or GetContainerItemQuestInfo
    if qinfo then
        for bag = 0, 4 do
            for slot = 1, bagSlots(bag) or 0 do
                local a, b, c = qinfo(bag, slot)
                local qid, active
                if type(a) == "table" then qid, active = a.questID, a.isActive else qid, active = b, c end -- old API: isQuestItem, questID, isActive
                local done = qid and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid)
                local id = qid and not active and not done and bagItem(bag, slot)
                if id and not seen[id] then seen[id] = true; found[#found + 1] = id end
            end
        end
    end
    -- recommendations that come with an item (a profession book)
    for _, r in ipairs(ns.profRecommend and ns.profRecommend() or {}) do
        if r.item and not seen[r.item] and (getCount(r.item) or 0) > 0 then seen[r.item] = true; found[#found + 1] = r.item end
    end
    for _, s in ipairs(list) do
        -- hearth steps put the Hearthstone on the button
        -- (not while it's more than 5 minutes from ready: then it comes back on its own)
        local left = ns.hearthCooldown and ns.hearthCooldown() or 0
        if s and s.t == "hearth" and left > 300 and not hearthTimer then
            hearthTimer = true
            C_Timer.After(left - 299, function() hearthTimer = false; if ns.updateItems then ns.updateItems() end end)
        end
        if s and s.t == "hearth" and left <= 300 and not seen[HEARTHSTONE] and (getCount(HEARTHSTONE) or 0) > 0 then
            seen[HEARTHSTONE] = true; table.insert(found, 1, HEARTHSTONE)
        end
        -- a step that wants an emote or a short macro ("/sit" at the campfire)
        if s and s.macro and not seen["m:" .. s.macro[3]] then
            seen["m:" .. s.macro[3]] = true
            table.insert(found, 1, { macro = s.macro })
        end
        -- what the quest's open objectives ask for, when the route doesn't say (an emote, a quest item to use)
        local macros, objItems = ns.objectiveHelpers(s)
        for _, m in ipairs(macros) do
            if not seen["m:" .. m[3]] then seen["m:" .. m[3]] = true; table.insert(found, 1, { macro = m }) end
        end
        for _, id in ipairs(objItems) do
            if not seen[id] then seen[id] = true; found[#found + 1] = id end
        end
        for _, id in ipairs(s and s.item and (type(s.item) == "table" and s.item or { s.item }) or {}) do
            -- (an item that starts the step's quest - "Use Croaky's Head to start the quest" - may have no spell:
            -- right-clicking it opens the quest, so it gets a button all the same)
            if not seen[id] and (getCount(id) or 0) > 0 and ((getSpell and getSpell(id)) or (s.t == "accept")) then
                seen[id] = true; found[#found + 1] = id
            end
        end
    end
    return found
end

-- who the target button looks for: the mobs of the current step (and the along-the-way ones), from the
-- route or else from the quest's kill objectives; on steps without mobs, the NPC you need to talk to
local function objectiveMobs(s)
    local out = {}
    if not (s and s.t == "complete" and s.q and C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    for k, q in ipairs(s.q) do
        local oi = s.qo and s.qo[k] or 0
        for i, o in ipairs(C_QuestLog.GetQuestObjectives(q) or {}) do
            if (oi == 0 or oi == i) and o.type == "monster" and not o.finished and o.text then
                local n = o.text:gsub("^%d+/%d+%s+", ""):gsub(":%s*%d+%s*/%s*%d+$", ""):gsub("%s+slain$", "")
                if n ~= "" then out[#out + 1] = n end
            end
        end
    end
    return out
end
-- Which of a step's mobs are still worth targeting: a mob drops out once the objectives it's for are done
-- ("8/8 Elder Crag Boar slain" -> no more boars, the bears and leopards stay). A kill objective ("Kobold
-- Workers slain") is for the mob of that name only - not the Kobold Vermin of the quest before; any other
-- objective (an item) for the mobs that share a word with it ("Crag Boar Rib" needs the Elder Crag Boars).
-- A kill objective none of the step's mobs is called like (credit for several kinds) goes by words too.
-- Without live objectives (not on the quest yet) every mob stays.
local stillNeeded
local GENERIC = { slain = true, killed = true, collected = true, the = true, of = true }
local function words(t)
    local w = {}
    for x in t:lower():gmatch("[%a']+") do if #x >= 4 and not GENERIC[x] then w[x] = true end end
    return w
end
local function killName(text)
    local t = text:lower():gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub(":%s*%d+%s*/%s*%d+%s*$", "")
    t = t:match("^%s*(.-)%s*$")
    return t:match("^(.-)%s+slain$") or t:match("^(.-)%s+killed$")
end
local function sameMob(name, kill)
    name = name:lower()
    return kill == name or kill == name .. "s" or kill == name .. "es"
        or (name:sub(-1) == "y" and kill == name:sub(1, -2) .. "ies") or (name:sub(-1) == "f" and kill == name:sub(1, -2) .. "ves")
end
ns.sameMob, ns.killName = sameMob, killName
stillNeeded = function(st)
    if st.t ~= "complete" or not ns.objectiveLines then return nil end
    local lines = ns.objectiveLines(st)
    if #lines == 0 then return nil end
    local kills, open, any = {}, {}, false
    for _, l in ipairs(lines) do
        if not l[2] then
            any = true
            local k = killName(l[1])
            local named = false
            if k then for _, m in ipairs(st.mobs or {}) do if sameMob(m, k) then named = true break end end end
            if named then kills[#kills + 1] = k else open[#open + 1] = words(l[1]) end
        end
    end
    if not any then return nil end
    return function(name)
        for _, k in ipairs(kills) do if sameMob(name, k) then return true end end
        local mw = words(name)
        for _, ow in ipairs(open) do
            for x in pairs(mw) do
                if ow[x] or ow[x .. "s"] or (x:sub(-1) == "s" and ow[x:sub(1, -2)]) then return true end
            end
        end
        return false
    end
end

-- a step after one particular mob: one kind of mob, and each open objective needs just one (Anaya Dawnrunner
-- for her pendant, Jai'vhanel's feather). That mob goes first, ahead of whatever else is closer.
local function singleTarget(st, m)
    if not (m and #m == 1 and st.t == "complete" and ns.objectiveLines) then return false end
    local open = 0
    for _, l in ipairs(ns.objectiveLines(st)) do
        if not l[2] then
            if tonumber(l[1]:match("%d+%s*/%s*(%d+)")) ~= 1 then return false end
            open = open + 1
        end
    end
    return open > 0
end

local function targetNames()
    local mobs, friends, seen, prio, main = {}, {}, {}, {}, {}
    if not (ns.steps and ItineraryCharDB) then return mobs, false, prio end
    local steps, i = ns.steps(), ItineraryCharDB.step
    local cur = ns.current and ns.current() or steps[i]
    local list = { cur }
    if ns.alongActive and not (cur and cur.detour) then
        for _, j in ipairs(ns.alongActive(i)) do
            if not (ns.stepDone and ns.stepDone(j)) then list[#list + 1] = steps[j] end
        end
    end
    local function add(t, n) if n and not seen[n] then seen[n] = true; t[#t + 1] = n end end
    for _, st in ipairs(list) do
        local m = st and st.mobs
        if st and not m and st.t == "complete" then m = objectiveMobs(st) end
        local need = st and stillNeeded(st)
        local kept = 0
        for _, n in ipairs(m or {}) do if not need or need(n) then add(mobs, n); kept = kept + 1; if st == cur then main[n] = true end end end
        -- nothing matched an open objective by name (an item called unlike its mob): keep them all
        if need and kept == 0 then for _, n in ipairs(m or {}) do add(mobs, n); if st == cur then main[n] = true end end end
        if st and singleTarget(st, m) then prio[m[1]] = true end
    end
    if #mobs > 0 then return mobs, false, prio, main end
    if cur then
        -- (generated routes leave out "targets" when it's just the step's NPC)
        for _, n in ipairs(cur.targets or (cur.npc and { cur.npc }) or {}) do add(friends, n) end
        if cur.npc and (cur.t == "accept" or cur.t == "turnin" or cur.t == "train" or cur.detour) then add(friends, cur.npc) end
    end
    return friends, true, {}
end
ns.targetNames = targetNames

-- /targetexact for each name (the last line run wins, so they go in reverse order of priority), then back
-- to your last target if what you got is dead
-- Tagging contested mobs: an instant ranged spell the class has early (first one you know wins), so spamming
-- the button on a respawn tags the mob right away; auto attack until you know one
local TAG = {
    PALADIN = { 20271 },             -- Judgement
    SHAMAN  = { 8042 },              -- Earth Shock
    PRIEST  = { 589 },               -- Shadow Word: Pain
    WARLOCK = { 980, 702 },          -- Curse of Agony, Curse of Weakness
    MAGE    = { 2136 },              -- Fire Blast
    HUNTER  = { 3044, 1978 },        -- Arcane Shot, Serpent Sting
    DRUID   = { 8921 },              -- Moonfire
    ROGUE   = { 2764 },              -- Throw
    WARRIOR = { 100 },               -- Charge
}
local function known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return IsSpellKnown and IsSpellKnown(id) or false
end
local function tagLine()
    if ItineraryDB.auto and ItineraryDB.auto.tagSpell == false then return "" end
    local _, class = UnitClass("player")
    for _, id in ipairs(TAG[class] or {}) do
        local name = known(id) and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)))
        if name then return "\n/cast [harm,nodead] " .. name end
    end
    return "\n/startattack [harm,nodead]"
end
ns.tagSpells = TAG

-- CheckInteractDistance on an enemy can raise an error in newer clients: then it simply doesn't count
local function near(u, k)
    if not CheckInteractDistance then return nil end
    local ok, r = pcall(CheckInteractDistance, u, k)
    if not ok then return nil end
    return r and true or false
end

-- the nameplate units around you: nameplate1..40 straight (never their frames - the game doesn't let addons
-- measure those)
local function plates()
    local out = {}
    for k = 1, 40 do
        local u = "nameplate" .. k
        if UnitExists(u) then out[#out + 1] = { u = u } end
    end
    return out
end

-- The closest one worth taking among the names, from the nameplates you can see (nameplates on): alive, not
-- tagged by someone else, not already fighting another player (its name then goes last in the macro). How
-- close comes in steps (10, 11, 28 yards,
-- further) - what the game lets an addon know. nil: no nameplate fits (then the names decide).
local function nearestPlate(names, friendly, prio, main)
    local want, first = {}, {}
    -- (a guide's plural - "Ice Claw Bears" - finds the mob too)
    for _, n in ipairs(names) do
        local one = n:gsub("s$", "")
        want[n] = true; want[one] = true
        if prio and prio[n] then first[n] = true; first[one] = true end
    end
    local best, bestScore
    for _, p in ipairs(plates()) do
        local u = p.u
        local name = UnitName(u) or ""
        if want[name] and not UnitIsDead(u) and not UnitIsPlayer(u) then
            local ok = friendly or (UnitCanAttack("player", u) and not (UnitIsTapDenied and UnitIsTapDenied(u)))
            if ok then
                local d = 4
                if near(u, 3) then d = 1 elseif near(u, 2) then d = 2 elseif near(u, 4) then d = 3 end
                -- busy with someone else (in combat, not with you): only when nothing else is there
                local busy = not friendly and UnitAffectingCombat(u) and not UnitIsUnit(u .. "target", "player")
                -- the one particular mob a step is after (Anaya Dawnrunner) before anything closer; your step's own
                -- mobs a bit before the along-the-way ones (one range band: an along-the-way mob right next to you
                -- still wins over one of yours far off)
                local mine = main and (main[name] or main[name .. "s"])
                local score = d + (busy and 5 or 0) - (first[name] and 20 or 0) - (mine and 1.5 or 0)
                if not bestScore or score < bestScore then best, bestScore = u, score end
            end
        end
    end
    return best
end

-- /iti target: what the target button looks for and what it sees
function ns.targetDebug()
    local ok, err = pcall(function()
    local names, friendly, prio, main = targetNames()
    local firstN = {}
    for n in pairs(prio or {}) do firstN[#firstN + 1] = n end
    ns.print("target button names: " .. table.concat(names, ", ") .. (friendly and " (NPCs)" or "")
        .. (#firstN > 0 and ("  - first: " .. table.concat(firstN, ", ")) or ""))
    local list = plates()
    if #list == 0 then ns.print("no nameplates around (enemy nameplates off? V shows them)") end
    for _, p in ipairs(list) do
        local u = p.u
        do
            print(string.format("  %s %s  10yd %s 11yd %s 28yd %s  tapped %s  combat %s", u, UnitName(u) or "?",
                tostring(near(u, 3)), tostring(near(u, 2)), tostring(near(u, 4)), tostring(UnitIsTapDenied and UnitIsTapDenied(u)),
                tostring(UnitAffectingCombat(u))))
        end
    end
    local ok, plate = pcall(nearestPlate, names, friendly, prio, main)
    ns.print("pick: " .. (ok and tostring(plate or "none in reach") or ("error: " .. tostring(plate))))
    if ns.portraitInfo then ns.print(ns.portraitInfo()) end
    ns.print("button: " .. tostring(target and target:IsShown()) .. ", combat " .. tostring(InCombatLockdown()) .. ", macro:")
    print((target and target:GetAttribute("macrotext") or "none"):gsub("\n", " | "))
    end)
    if not ok then ns.print("target debug error: " .. tostring(err)) end
end

local function targetMacro(names, friendly, plate, prio)
    local lines = {}
    -- the game won't target a nameplate by its unit in a macro, so the closest fitting mob's NAME goes last
    -- (the last line that finds something wins); the game then takes the nearest of that name. The one mob a
    -- step is after (prio: Anaya Dawnrunner) comes after that, so it wins whenever it's around.
    local first = plate and UnitName(plate)
    local function isPrio(n) return prio and prio[n] end
    for k = #names, 1, -1 do
        if names[k] ~= first and not isPrio(names[k]) then lines[#lines + 1] = "/targetexact " .. names[k] end
    end
    if first and not isPrio(first) then lines[#lines + 1] = "/targetexact " .. first end
    for k = #names, 1, -1 do
        if names[k] ~= first and isPrio(names[k]) then lines[#lines + 1] = "/targetexact " .. names[k] end
    end
    if first and isPrio(first) then lines[#lines + 1] = "/targetexact " .. first end
    local tail = "\n/targetlasttarget [dead]"
    -- a mark on what you found, picked by what was actually targeted: an orange circle on friendly NPCs and
    -- players, a skull on enemies. Only a macro may do this (Lua gets blocked); "!" keeps an existing mark
    -- instead of toggling it off (how the Forever client's /tm works)
    if not (ItineraryDB.auto and ItineraryDB.auto.skull == false) then tail = tail .. "\n/tm [harm] !8; [exists] !2" end
    -- on quest mobs (not when it looks for an NPC to talk to): tag it
    if not friendly then tail = tail .. tagLine() end
    local text = table.concat(lines, "\n")
    -- too long: the lowest-priority names go
    while #text + #tail > 255 and #lines > 1 do table.remove(lines, 1); text = table.concat(lines, "\n") end
    return text .. tail
end

-- The button's face, round like the game's unit frames:
--   1) the mob or NPC it would target now: the nameplate it picked, or your target when that's one of them
--   2) before you see them: the face remembered from an earlier meeting (the name's display ID), for the one
--      it goes for first
--   3) else its usual icon
-- Drawn again only for another mob or another face (a portrait is a small render of the model).
local function npcIdOf(guid)
    local kind, _, _, _, _, id = strsplit("-", guid or "")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
-- Display IDs are read with a model frame: the model loads a moment after SetUnit (or SetCreature with the NPC ID,
-- from the game's creature cache), so it waits for that (up to 2 s) and does one creature at a time.
local probe -- (false: this client can't)
local PQ = { list = {}, job = false, retry = false, tried = 0, got = 0, last = "none yet", asked = {} }
local function savedDisp(job, d)
    ItineraryDB.portraits = ItineraryDB.portraits or {}
    local e = ItineraryDB.portraits[job.name]
    if e and e.npc ~= job.npc then return end
    ItineraryDB.portraits[job.name] = { npc = job.npc, disp = d }
end
local probeStart, askDisplay
local function probeDone(d, how)
    local job = PQ.job
    PQ.job = false
    if job then
        if d then PQ.got = PQ.got + 1; savedDisp(job, d) end
        PQ.last = job.name .. ": " .. (d and ("display " .. d .. " (" .. how .. ")") or ("nothing (" .. how .. ")"))
        -- a sighting that didn't load (gone from view, a mouseover moved on): try the creature cache next
        if not d and job.how == "seen" then PQ.retry = job end
    end
    if probe then
        if type(probe.ClearModel) == "function" then pcall(probe.ClearModel, probe) end
        probe:Hide()
    end
    local again = PQ.retry
    PQ.retry = false
    if again then askDisplay(again.name, again.npc) end
    if not PQ.job and #PQ.list > 0 then probeStart(table.remove(PQ.list, 1)) end
end
local function probeRead()
    local ok, d = pcall(probe.GetDisplayInfo, probe)
    d = ok and tonumber(d) or nil
    return (d and d > 0) and d or nil
end
local function probeFrame()
    if probe == nil then
        local ok, m = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        probe = (ok and type(m) == "table" and type(m.SetUnit) == "function" and type(m.GetDisplayInfo) == "function") and m or false
        if probe then
            -- on screen (a model off screen may never load), one pixel in the corner and only while reading
            probe:SetSize(1, 1); probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
            if type(probe.SetFrameStrata) == "function" then probe:SetFrameStrata("BACKGROUND") end
            probe:Hide()
            local function check(_, el)
                local job = PQ.job
                if not job then return end
                job.t = job.t + (tonumber(el) or 0)
                local d = probeRead()
                if d then probeDone(d, job.how) elseif job.t > 2 then probeDone(nil, job.how .. ", no model after 2 s") end
            end
            probe:SetScript("OnUpdate", check)
            pcall(probe.SetScript, probe, "OnModelLoaded", function() check(nil, 0) end)
        end
    end
    return probe
end
function probeStart(job)
    if not probeFrame() then return end
    -- (another try of the same creature may have read it meanwhile)
    while job do
        local e = ItineraryDB.portraits and ItineraryDB.portraits[job.name]
        if not (e and e.npc == job.npc and e.disp) then break end
        job = table.remove(PQ.list, 1)
    end
    if not job then return end
    PQ.job, job.t = job, 0
    PQ.tried = PQ.tried + 1
    probe:Show()
    local ok
    if job.unit and UnitExists(job.unit) and UnitGUID(job.unit) == job.guid then
        job.how = "seen"
        ok = pcall(probe.SetUnit, probe, job.unit)
    elseif type(probe.SetCreature) == "function" then
        job.how = "creature cache"
        ok = pcall(probe.SetCreature, probe, job.npc)
    end
    if not ok then probeDone(nil, "can't load it") return end
    local d = probeRead()
    if d then probeDone(d, job.how .. ", at once") end
end
-- read the display ID of a unit in sight (up to 3 tries a session per NPC) or of an NPC ID (once)
function askDisplay(name, npc, unit)
    if probe == false then return end
    local k = unit and npc or ("c" .. npc)
    local n = PQ.asked[k] or 0
    if n >= (unit and 3 or 1) then return end
    PQ.asked[k] = n + 1
    local job = { name = name, npc = npc, unit = unit, guid = unit and UnitGUID(unit) }
    if PQ.job then
        if #PQ.list < 30 then table.insert(PQ.list, job) end
    else
        probeStart(job)
    end
end
-- Who a creature is, for every NPC and mob you target or hover and your step's ones on nameplates (account-wide):
-- ItineraryDB.portraits[name] = { npc = NPC ID, disp = display ID }
local function learn(unit)
    if not (ItineraryDB and unit and UnitExists(unit)) or UnitIsPlayer(unit) then return end
    local npc, name = npcIdOf(UnitGUID(unit)), UnitName(unit)
    if not (npc and name and name ~= "" and name ~= (UNKNOWNOBJECT or "Unknown")) then return end
    ItineraryDB.portraits = ItineraryDB.portraits or {}
    local e = ItineraryDB.portraits[name]
    if e and e.npc == npc and e.disp then return end
    if not (e and e.npc == npc) then ItineraryDB.portraits[name] = { npc = npc } end
    askDisplay(name, npc, unit)
end
ns.learnPortrait = learn
local function wanted(names)
    local want = {}
    for _, n in ipairs(names or {}) do want[n] = true; want[(n:gsub("s$", ""))] = true end
    return want
end
-- your target, when it's one of the step's mobs (alive, attackable) or its NPC
local function targetFits()
    if not (target and type(target.names) == "table" and UnitExists("target")) or UnitIsPlayer("target") or UnitIsDead("target") then return false end
    if not wanted(target.names)[UnitName("target") or ""] then return false end
    if target.friendly then return not UnitCanAttack("player", "target") end
    return UnitCanAttack("player", "target") and true or false
end
-- the one the button goes for when it can't see any of them: the one particular mob, else the first name
local function firstName()
    local names, prio = target.names, target.prio
    if type(names) ~= "table" then return nil end
    for _, n in ipairs(names) do if type(prio) == "table" and prio[n] then return n end end
    return names[1]
end
local function known(name)
    local P = ItineraryDB and ItineraryDB.portraits
    if not (P and name) then return nil end
    return P[name] or P[(name:gsub("s$", ""))]
end
-- Faces are kept for the session like the target frame's: one texture per name, drawn when that one is in sight
-- and shown again while the step still goes for that name (the latest 24 names).
local F = { byName = {}, order = {}, spare = {}, key = {}, shown = false, name = false, mask = false }
ns.targetFaces = F
local function faceTex(name)
    local t = F.byName[name]
    if t then return t end
    if #F.order >= 24 then
        local old = table.remove(F.order, (F.order[1] == F.name) and 2 or 1)
        local ot = F.byName[old]
        F.byName[old] = nil
        if ot then ot:Hide(); F.key[ot] = nil; table.insert(F.spare, ot) end
    end
    t = table.remove(F.spare)
    if not t then
        t = target:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetPoint("TOPLEFT", 1, -1); t:SetPoint("BOTTOMRIGHT", -1, 1)
        if F.mask and type(t.AddMaskTexture) == "function" then t:AddMaskTexture(F.mask) end
        t:Hide()
    end
    F.byName[name] = t
    table.insert(F.order, name)
    return t
end
local function showFace(t, name)
    if F.shown and F.shown ~= t then F.shown:Hide() end
    F.shown, F.name = t, name
    t:Show(); target.icon:Hide()
end
local function showIcon()
    if F.shown then F.shown:Hide() end
    F.shown, F.name = false, false
    target.icon:Show()
end
-- a face for one of the step's names without seeing them: drawn this session, else remembered (display ID)
local function faceFor(name)
    if type(name) ~= "string" then return nil end
    local one = name:gsub("s$", "")
    if F.byName[name] and F.key[F.byName[name]] then return F.byName[name], name end
    if F.byName[one] and F.key[F.byName[one]] then return F.byName[one], one end
    local e = known(name)
    if e and e.npc and not e.disp then askDisplay(name, e.npc) end
    if e and e.disp and SetPortraitTextureFromCreatureDisplayID then
        t = faceTex(name)
        local key = "disp:" .. e.disp
        if F.key[t] ~= key and pcall(SetPortraitTextureFromCreatureDisplayID, t, e.disp) then F.key[t] = key end
        if F.key[t] then return t, name end
    end
end
local function setPortrait(unit)
    if not (target and target.icon) then return end
    local guid = unit and SetPortraitTexture and UnitExists(unit) and UnitGUID(unit)
    if guid then
        local name = UnitName(unit)
        local t = faceTex(name)
        if F.key[t] ~= guid then SetPortraitTexture(t, unit); F.key[t] = guid end
        target.portraitUnit, target.pickName = unit, name
        learn(unit)
        showFace(t, name)
        return
    end
    target.portraitUnit, target.pickName = false, false
    -- not in sight: the face it showed last while the step still goes for that one, else the first of the
    -- step's names with a face (the one particular mob first)
    local names = type(target.names) == "table" and target.names or {}
    if F.shown and F.key[F.shown] and wanted(names)[F.name] then
        showFace(F.shown, F.name)
        return
    end
    local order, seen = {}, {}
    local fn = firstName()
    if fn then order[1] = fn; seen[fn] = true end
    for _, n in ipairs(names) do if not seen[n] then order[#order + 1] = n; seen[n] = true end end
    for _, n in ipairs(order) do
        local t, as = faceFor(n)
        if t then showFace(t, as) return end
    end
    showIcon()
end
ns.targetPortrait = setPortrait
-- (/iti target: what the face is and what the game lets it do)
function ns.portraitInfo()
    local P, n = ItineraryDB.portraits or {}, 0
    for _ in pairs(P) do n = n + 1 end
    local fn = target and firstName()
    local e = fn and known(fn)
    local shown = F.shown and F.key[F.shown]
    return string.format("portrait: %s; faces known: %d; %s: %s; drawing from display IDs: %s, reading them: %s (%d of %d read; last %s)",
        target and type(target.portraitUnit) == "string" and ("live " .. target.portraitUnit)
            or (shown and ((shown:find("^disp:") and "remembered " or "kept ") .. tostring(F.name)) or "icon"),
        n, tostring(fn), e and ("NPC " .. tostring(e.npc) .. ", display " .. tostring(e.disp)) or "not met yet",
        SetPortraitTextureFromCreatureDisplayID and "yes" or "no", probe and "yes" or (probe == false and "no" or "not tried yet"),
        PQ.got, PQ.tried, PQ.last)
end

-- out of combat the button follows the nearest fitting mob a few times a second (a secure button can't
-- change in combat: there the last pick, its face and the names stay)
do
    local acc = 0
    local tf = CreateFrame("Frame")
    tf:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc < 0.3 then return end
        acc = 0
        if not (target and target.names and target:IsShown()) or InCombatLockdown() then return end
        local ok, plate = pcall(nearestPlate, target.names, target.friendly, target.prio, target.main)
        local text = targetMacro(target.names, target.friendly, ok and plate or nil, target.prio)
        if text ~= target.lastMacro then
            target.lastMacro = text
            target:SetAttribute("macrotext", text)
        end
        setPortrait((ok and plate) or (targetFits() and "target") or nil)
    end)
    -- (a model that wasn't loaded yet when its portrait was drawn: draw it again once the game has it) and
    -- who the creatures you target, hover or see of your step are
    for _, e in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
        pcall(tf.RegisterEvent, tf, e)
    end
    tf:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then pcall(learn, "target") return end
        if event == "UPDATE_MOUSEOVER_UNIT" then pcall(learn, "mouseover") return end
        if event == "NAME_PLATE_UNIT_ADDED" then
            if unit and target and type(target.names) == "table" and wanted(target.names)[UnitName(unit) or ""] then pcall(learn, unit) end
            return
        end
        local t = target and unit == target.portraitUnit and F.shown
        if t and F.key[t] == UnitGUID(unit) and SetPortraitTexture then SetPortraitTexture(t, unit) end
    end)
end

-- the key bound to a button, short (S-1, C-F, M4 ...)
local function hotkey(b)
    local key = GetBindingKey and GetBindingKey("CLICK " .. b.bindName .. ":LeftButton")
    if not key then return "" end
    key = key:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-"):gsub("BUTTON", "M")
        :gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("NUMPAD", "N")
    return key
end

local function updateCooldowns()
    for _, b in ipairs(buttons) do
        if b:IsShown() and b.itemID and getCooldown then
            local start, dur, enable = getCooldown(b.itemID)
            if start and dur and dur > 1.5 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
        end
    end
end

-- secure frames must not move in combat, so the row is not anchored to the (moving, resizing) panel;
-- it is placed at the chosen corner here, out of combat (and every frame while you drag the panel)
local CORNERS = {
    TOPRIGHT    = { "TOPLEFT",     "right", "top",    6 },
    BOTTOMRIGHT = { "BOTTOMLEFT",  "right", "bottom", 6 },
    TOPLEFT     = { "TOPRIGHT",    "left",  "top",    -6 },
    BOTTOMLEFT  = { "BOTTOMRIGHT", "left",  "bottom", -6 },
}
local function corner() return CORNERS[ItineraryDB and ItineraryDB.itemAnchor or ""] and ItineraryDB.itemAnchor or "BOTTOMLEFT" end
function ns.placeItems()
    if not row or InCombatLockdown() then return end
    local p = row.panel
    if not (p and p:GetRight() and p:GetTop() and p:GetLeft() and p:GetBottom()) then return end
    local c = CORNERS[corner()]
    -- the panel may be scaled (Settings > Layout > Panel size): its edges in screen units
    local k = (p:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    local x = (c[2] == "right" and p:GetRight() or p:GetLeft()) * k + c[4]
    local y = (c[3] == "top" and p:GetTop() or p:GetBottom()) * k
    row:ClearAllPoints()
    row:SetPoint(c[1], UIParent, "BOTTOMLEFT", x, y)
end
-- buttons stack away from the corner: down from a top corner, up from a bottom one
local function stack(b, k)
    local top = corner():find("^TOP")
    b:ClearAllPoints()
    if top then b:SetPoint("TOP", row, "TOP", 0, -k * (SIZE + 4))
    else b:SetPoint("BOTTOM", row, "BOTTOM", 0, k * (SIZE + 4)) end
end

local function update()
    if not row then return end
    if InCombatLockdown() then pending = true; return end -- secure buttons only change outside combat
    pending = false
    ns.placeItems()
    local names, friendly, prio, main = targetNames()
    local y = 0
    if #names > 0 then
        target.names, target.friendly, target.prio, target.main = names, friendly, prio, main
        target:SetAttribute("type", "macro")
        target.lastMacro = targetMacro(names, friendly, nil, prio)
        target:SetAttribute("macrotext", target.lastMacro)
        target.icon:SetTexture(friendly and "Interface\\Icons\\Ability_EyeOfTheOwl" or "Interface\\Icons\\Ability_Hunter_SniperShot")
        local sig = table.concat(names, "|") .. (friendly and "+" or "-")
        if sig ~= target.sig then target.sig = sig; setPortrait(nil) end
        target.hotkey:SetText(hotkey(target))
        target:Show()
        -- hidden by setting: invisible and not clickable, but its key binding keeps working
        if ItineraryDB and ItineraryDB.auto and ItineraryDB.auto.targetBtn == false then
            target:SetAlpha(0); target:EnableMouse(false)
            target:ClearAllPoints(); target:SetPoint("CENTER", row, "CENTER")
        else
            target:SetAlpha(1); target:EnableMouse(true)
            stack(target, 0)
            y = 1
        end
    else
        target.names, target.sig = nil, nil
        setPortrait(nil)
        target:SetAttribute("macrotext", nil)
        target:Hide()
    end
    local items = questItems()
    for i = 1, MAX do
        local b, id = buttons[i], items[i]
        stack(b, y + i - 1)
        b.hotkey:SetText(hotkey(b))
        if type(id) == "table" then
            b.itemID, b.macro = nil, id.macro
            b:SetAttribute("type", "macro")
            b:SetAttribute("item", nil)
            b:SetAttribute("macrotext", id.macro[3])
            b.icon:SetTexture(id.macro[2] or 134400)
            b.count:SetText("")
            b:Show()
        elseif id then
            b.itemID, b.macro = id, nil
            b:SetAttribute("type", "item")
            b:SetAttribute("macrotext", nil)
            b:SetAttribute("item", "item:" .. id)
            b.icon:SetTexture(getInfo and select(5, getInfo(id)) or 134400)
            local n = getCount(id) or 0
            b.count:SetText(n > 1 and n or "")
            b:Show()
        else
            b.itemID, b.macro = nil, nil
            b:SetAttribute("item", nil)
            b:Hide()
        end
    end
    local up = ItineraryDB.panel.shown
    if ns.panelUp then up = ns.panelUp() end
    row:SetShown((#items > 0 or #names > 0) and up and true or false)
    updateCooldowns()
end
ns.updateItems = update

function ns.buildItems(panel)
    local ar, ag, ab = accent()
    row = CreateFrame("Frame", "ItineraryItems", UIParent)
    row:SetSize(SIZE, (SIZE + 4) * (MAX + 1))
    row.panel = panel
    row:SetPoint("CENTER")
    local function make(name)
        local b = CreateFrame("Button", name, row, "SecureActionButtonTemplate")
        b.bindName = name
        b:SetSize(SIZE, SIZE)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("useOnKeyDown", false)
        local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.92))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        edges(b, 0.15)
        b.hotkey = b:CreateFontString(nil, "OVERLAY")
        b.hotkey:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
        b.hotkey:SetTextColor(0.85, 0.85, 0.85, 1)
        b.hotkey:SetPoint("TOPRIGHT", -2, -2)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b.icon); hl:SetColorTexture(ar, ag, ab, 0.25)
        return b
    end
    target = make("ItineraryTarget")
    -- (the round mask every face shares)
    local mask = target.CreateMaskTexture and target:CreateMaskTexture()
    if mask and mask.SetTexture then
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("TOPLEFT", 1, -1); mask:SetPoint("BOTTOMRIGHT", -1, 1)
        F.mask = mask
    end
    target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.friendly and "Target the NPC" or "Target quest mobs", 1, 1, 1)
        if self.pickName then GameTooltip:AddLine("Now: " .. self.pickName, 1, 0.82, 0) end
        for _, n in ipairs(self.names or {}) do GameTooltip:AddLine(n, 0.75, 0.75, 0.75) end
        GameTooltip:AddLine("Bind a key: Options > Keybindings > AddOns > Itinerary", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    target:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Talking to a contested NPC (an escort that respawns): once the button has found a friendly NPC, its key
    -- becomes "Interact with Target" for a moment, so the next press opens the NPC (and the quest is taken).
    -- Spam the key: the first press that finds them targets, the next one talks. Outside combat only.
    local owner = CreateFrame("Frame")
    local overridden = false
    local function release(talking)
        if overridden and not InCombatLockdown() then ClearOverrideBindings(owner); overridden = false end
        -- the key has Shift in it (Shift-W): Shift held for that press isn't "do it by hand", so the quest
        -- automation keeps working through the conversation it opened
        if talking and ns.shiftOK then ns.shiftOK = GetTime() + 15 else ns.shiftOK = nil end
    end
    ns.releaseInteract = release
    target:HookScript("PostClick", function()
        if InCombatLockdown() or (ItineraryDB.auto and ItineraryDB.auto.interact == false) then return end
        if not (target.friendly and UnitExists("target") and not UnitCanAttack("player", "target") and not UnitIsDead("target")) then return end
        if UnitIsPlayer("target") then return end
        local k1, k2 = GetBindingKey("CLICK ItineraryTarget:LeftButton")
        if not k1 then return end
        SetOverrideBinding(owner, true, k1, "INTERACTTARGET")
        if k2 then SetOverrideBinding(owner, true, k2, "INTERACTTARGET") end
        overridden = true
        if k1:find("SHIFT") or (k2 and k2:find("SHIFT")) then ns.shiftOK = GetTime() + 8 end
        C_Timer.After(8, function() if overridden then release() end end)
    end)
    owner:RegisterEvent("PLAYER_TARGET_CHANGED")
    owner:RegisterEvent("GOSSIP_SHOW")
    owner:RegisterEvent("QUEST_DETAIL")
    owner:RegisterEvent("QUEST_GREETING")
    owner:RegisterEvent("PLAYER_REGEN_DISABLED")
    owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    owner:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" and UnitExists("target") and not UnitCanAttack("player", "target") then return end
        if not overridden then return end
        release(event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" or event == "QUEST_GREETING")
    end)

    target:Hide()
    for i = 1, MAX do
        local b = make("ItineraryItem" .. i)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b.icon)
        if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end -- the time left on it
        b.count = b:CreateFontString(nil, "OVERLAY")
        b.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b:SetScript("OnEnter", function(self)
            if self.macro then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.macro[1], 1, 1, 1)
                GameTooltip:AddLine(self.macro[3], 0.7, 0.7, 0.7)
                GameTooltip:Show()
                return
            end
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        buttons[i] = b
    end
    row:Hide()
    update()
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
                     "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "QUEST_LOG_UPDATE", "SPELLS_CHANGED",
                     "LEARNED_SPELL_IN_TAB" }) do
    pcall(f.RegisterEvent, f, e)
end
local queued = false
f:SetScript("OnEvent", function(_, event)
    if not row then return end
        if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then updateCooldowns() return end
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    if queued then return end
    queued = true
    C_Timer.After(0.3, function() queued = false; update() end)
end)
