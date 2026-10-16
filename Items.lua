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
        for _, id in ipairs(s and s.item and (type(s.item) == "table" and s.item or { s.item }) or {}) do
            if not seen[id] and (getCount(id) or 0) > 0 and getSpell and getSpell(id) then
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
-- ("8/8 Elder Crag Boar slain" -> no more boars, the bears and leopards stay). A mob counts for an open
-- objective that names it or shares a word with it ("Crag Boar Rib" needs the Elder Crag Boars).
-- Without live objectives (not on the quest yet) every mob stays.
local stillNeeded
local GENERIC = { slain = true, killed = true, collected = true, the = true, of = true }
local function words(t)
    local w = {}
    for x in t:lower():gmatch("[%a']+") do if #x >= 4 and not GENERIC[x] then w[x] = true end end
    return w
end
stillNeeded = function(st)
    if st.t ~= "complete" or not ns.objectiveLines then return nil end
    local lines = ns.objectiveLines(st)
    if #lines == 0 then return nil end
    local open = {}
    for _, l in ipairs(lines) do if not l[2] then open[#open + 1] = words(l[1]) end end
    if #open == 0 then return nil end
    return function(name)
        local mw = words(name)
        for _, ow in ipairs(open) do
            for x in pairs(mw) do
                if ow[x] or ow[x .. "s"] or (x:sub(-1) == "s" and ow[x:sub(1, -2)]) then return true end
            end
        end
        return false
    end
end

local function targetNames()
    local mobs, friends, seen = {}, {}, {}
    if not (ns.steps and ItineraryCharDB) then return mobs, false end
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
        for _, n in ipairs(m or {}) do if not need or need(n) then add(mobs, n); kept = kept + 1 end end
        -- nothing matched an open objective by name (an item called unlike its mob): keep them all
        if need and kept == 0 then for _, n in ipairs(m or {}) do add(mobs, n) end end
    end
    if #mobs > 0 then return mobs, false end
    if cur then
        -- (generated routes leave out "targets" when it's just the step's NPC)
        for _, n in ipairs(cur.targets or (cur.npc and { cur.npc }) or {}) do add(friends, n) end
        if cur.npc and (cur.t == "accept" or cur.t == "turnin" or cur.t == "train" or cur.detour) then add(friends, cur.npc) end
    end
    return friends, true
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

local function targetMacro(names, friendly)
    local lines = {}
    for k = #names, 1, -1 do lines[#lines + 1] = "/targetexact " .. names[k] end
    local tail = "\n/targetlasttarget [dead]"
    -- a mark on what you found, picked by what was actually targeted: an orange circle on friendly NPCs and
    -- players, a skull on enemies. Only a macro may do this (Lua gets blocked); "!" keeps an existing mark
    -- instead of toggling it off (how the Forever client's /tm works)
    if not (ItineraryDB.auto and ItineraryDB.auto.skull == false) then tail = tail .. "\n/tm [harm] !8; [exists] !2" end
    -- on quest mobs (not when it looks for an NPC to talk to): tag it
    if not friendly then tail = tail .. tagLine() end
    local text = table.concat(lines, "\n")
    while #text + #tail > 255 and #lines > 1 do table.remove(lines, 1); text = table.concat(lines, "\n") end
    return text .. tail
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
    local names, friendly = targetNames()
    local y = 0
    if #names > 0 then
        target.names, target.friendly = names, friendly
        target:SetAttribute("type", "macro")
        target:SetAttribute("macrotext", targetMacro(names, friendly))
        target.icon:SetTexture(friendly and "Interface\\Icons\\Ability_EyeOfTheOwl" or "Interface\\Icons\\Ability_Hunter_SniperShot")
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
        target.names = nil
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
    row:SetShown((#items > 0 or #names > 0) and ItineraryDB.panel.shown)
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
    target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.friendly and "Target the NPC" or "Target quest mobs", 1, 1, 1)
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
