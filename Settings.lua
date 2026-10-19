-- Itinerary settings window (/iti settings, Shift + click on the minimap button).
-- A free-floating, movable window in the Provisions / EllesmereUI look: the game stays playable while it's open.
-- Options > AddOns > Itinerary only holds a button that opens it.
local ADDON, ns = ...

local W, PAD, ROW_H = 540, 18, 56
local SEG_W, SEG_H = 74, 22
local TAB_NAMES = { "General", "Quests", "Travel", "Trainer", "Professions", "Panel", "Arrow", "Keys" }

local win, refresh
local activeTab = 1

local function accent() return ns.accent() end
local function fontPath()
    if EllesmereUI and EllesmereUI.GetFontPath then
        local ok, path = pcall(EllesmereUI.GetFontPath)
        if ok and path then return path end
    end
    return STANDARD_TEXT_FONT
end
local function addEdges(frame, r, g, b, a, layer)
    local edges = {}
    local px = 1 / (frame:GetEffectiveScale() or 1)
    local function edge() local t = frame:CreateTexture(nil, layer or "BORDER"); t:SetColorTexture(r, g, b, a); edges[#edges + 1] = t; return t end
    local t = edge(); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(px)
    local bt = edge(); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT"); bt:SetHeight(px)
    local l = edge(); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(px)
    local rt = edge(); rt:SetPoint("TOPRIGHT"); rt:SetPoint("BOTTOMRIGHT"); rt:SetWidth(px)
    function edges:SetColor(r2, g2, b2, a2) for _, e in ipairs(self) do e:SetColorTexture(r2, g2, b2, a2) end end
    return edges
end
local function text(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontPath(), size, "")
    fs:SetTextColor(r, g, b, a or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- one segment of a switch / one toggle chip
local function segment(parent, label)
    local ar, ag, ab = accent()
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SEG_W, SEG_H)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.edges = addEdges(b, 1, 1, 1, 0.18)
    b.text = text(b, 12, 1, 1, 1, 0.5)
    b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("CENTER"); b.text:SetWordWrap(false)
    b.text:SetText(label)
    function b:SetActive(on, dim)
        if on then
            -- lit but dimmed (worth a visit, yet not auto-bought): a paler chip
            self.bg:SetColorTexture(ar, ag, ab, dim and 0.4 or 0.9); self.edges:SetColor(ar, ag, ab, dim and 0.5 or 1)
            local oc = ns.theme().onAccent; self.text:SetTextColor(oc[1], oc[2], oc[3], dim and 0.75 or 1)
        else
            self.bg:SetColorTexture(ns.themeBtn(1)); self.edges:SetColor(1, 1, 1, 0.18)
            self.text:SetTextColor(1, 1, 1, dim and 0.22 or 0.5)
        end
        self.active, self.dim = on, dim
    end
    b:SetScript("OnEnter", function(self)
        if not self.active and not self.dim then self.text:SetTextColor(1, 1, 1, 0.85) end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(self.tip, 1, 1, 1, true); GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.active then self.text:SetTextColor(1, 1, 1, self.dim and 0.22 or 0.5) end
        GameTooltip:Hide()
    end)
    return b
end

-- shared with the route editor (same look)
ns.ui = { accent = accent, fontPath = fontPath, addEdges = addEdges, text = text, segment = segment }

---------------------------------------------------------------- what's in each tab
local function A() return ItineraryDB.auto end
local function className() local loc, c = UnitClass("player"); return c or "?", loc or c or "?" end
local ON_OFF, SHOW_HIDE = { { "On", true }, { "Off", false } }, { { "Show", true }, { "Hide", false } }

-- class skills seen at a trainer, sorted
local function skillNames()
    local class = className()
    local names = {}
    for n in pairs(A().trainSeen[class] or {}) do names[#names + 1] = n end
    table.sort(names)
    return names
end
local function profKeys(secondary)
    return (secondary and ns.PROF_SECONDARY or ns.PROF_PRIMARY) or {}
end

local OPTIONS = {
    -- General
    { tab = 1, label = "Route panel", desc = "Also: click the minimap button, or type /iti.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.panel.shown and true or false end,
      set = function(v) if (ItineraryDB.panel.shown and true or false) ~= v then ns.setPanelShown(v) end end },
    { tab = 1, label = "In dungeons", desc = "Hide: the route panel, the arrow and the item buttons step aside while you're inside a dungeon or raid, and come back when you leave. The route goes on in the background. The minimap button (or /iti) still shows them there.",
      choices = SHOW_HIDE, get = function() return not ItineraryDB.panel.hideInDungeon end,
      set = function(v)
          ItineraryDB.panel.hideInDungeon = (not v) or nil
          ns.dungeonPeek = nil
          if ns.refresh then ns.refresh() end
          if ns.refreshArrow then ns.refreshArrow() end
          if ns.updateItems then ns.updateItems() end
      end },
    { tab = 1, label = "Minimap button", desc = "Hidden: open this window with /iti settings.",
      choices = SHOW_HIDE, get = function() return not (ItineraryDB.minimap and ItineraryDB.minimap.hide) end,
      set = function(v) if (not ItineraryDB.minimap.hide) ~= v and ns.toggleMinimap then ns.toggleMinimap() end end },
    { tab = 1, label = "Blizzard quest tracker", desc = "The game's own quest list on the right of the screen. The route panel already tracks your objectives.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.hideTracker == false end,
      set = function(v) ItineraryDB.hideTracker = not v; if ns.applyTracker then ns.applyTracker() end end },
    { tab = 1, kind = "sound", label = "Sound when a step is done", desc = "Plays when a step that takes a while is done: kill or loot objectives, collecting items, grinding a level. Not for talking to NPCs or travelling, and not when you skip. Click one to hear it." },
    { tab = 1, kind = "packs", label = "Route packs", desc = "When two packs have a route for a new character, the higher one in this list wins. A newly installed pack goes to the bottom. In the route list (the button in the panel footer) you can also make any route your default for a race and class." },
    { tab = 1, kind = "wipe", factory = true, label = "Factory reset", desc = "Itinerary as if just installed: all settings, your route edits and own routes, and every character's progress (each one the next time it logs in). Reloads the UI." },
    { tab = 1, kind = "wipe", label = "This character", desc = "Forgets everything Itinerary saved for this character: route progress, trainer prices, professions. For a new character that reuses a deleted one's name (that's also detected on its own). Settings stay." },
    -- Quests
    { tab = 2, label = "Accept and hand in", desc = "Picks up quests and hands in finished ones when you talk to the NPC. With a choice of rewards you pick yourself (except the gathering book for your profession).",
      choices = ON_OFF, get = function() return A().quests end, set = function(v) A().quests = v end },
    { tab = 2, label = "Which quests", desc = "Route: only quests this route uses. All: every quest you're offered.",
      choices = { { "Route", "route" }, { "All", "all" } }, get = function() return A().scope end, set = function(v) A().scope = v end,
      enabled = function() return A().quests end },
    { tab = 2, label = "Share quests in a group", desc = "In a group, every quest you accept is shared with the others right away (when it can be shared), so whoever is behind - skilling a profession, say - doesn't have to run to the quest giver. Not the quests someone shared with you.",
      choices = ON_OFF, get = function() return A().share == true end, set = function(v) A().share = v end },
    { tab = 2, label = "Quest dialogue", desc = "Chooses dialogue options the game marks as part of a quest, and the ones the route asks for.",
      choices = ON_OFF, get = function() return A().gossip end, set = function(v) A().gossip = v end },
    { tab = 2, label = "Object name tags", desc = "Names an object you can click close by (the game picks one, within about 15 yards, in any direction) with a nameplate of its own. Quest: only objects for your quests, with the objective under the name. All: herbs, ore veins, chests and the rest too. Uses the game's interact settings like Node icons; Off puts your own values back. While Glimmer (NaowhForever QoL) is on, it does this and Itinerary leaves it to Glimmer.",
      choices = { { "Quest", "quest" }, { "All", "all" }, { "Off", "off" } },
      get = function() local m = A().objTags; return (m == "all" or m == "off") and m or "quest" end,
      set = function(v) A().objTags = v; if ns.applyObjTags then ns.applyObjTags(true) end end },
    { tab = 2, label = "Quest sparkles", desc = "Quest objects you can loot on the ground and NPCs with a quest for you sparkle, without the outlines around everything else (graphicsOutlineMode 0 + outlineModeShowLootEffectWhenDisabled 1). Off puts your own values back.",
      choices = ON_OFF, get = function() return ItineraryDB.lootSparkle ~= false end,
      set = function(v) ItineraryDB.lootSparkle = v; if ns.applyLootSparkle then ns.applyLootSparkle() end end },
    { tab = 2, label = "Pick gear rewards", desc = "When every reward choice is white or green armor: the best armor type you can wear, then the one that sells for most. Weapons you can use, shields, off-hands and blue items stay your choice.",
      choices = ON_OFF, get = function() return A().rewards == true end, set = function(v) A().rewards = v end },
    { tab = 2, label = "Best-selling reward", desc = "Puts a gold coin on the quest reward that sells for the most, when you get to choose.",
      choices = SHOW_HIDE, get = function() return A().rewardCoin ~= false end, set = function(v) A().rewardCoin = v end },
    { tab = 2, label = "Sell junk", desc = "Sells your grey items when you open any vendor, so there's money for spells and tools.",
      choices = ON_OFF, get = function() return A().junk ~= false end, set = function(v) A().junk = v end },
    { tab = 2, label = "Auction house steps", desc = "Skip: for playing without the auction house (self-found). Steps that send you to buy something there are left out of the route.",
      choices = { { "Show", false }, { "Skip", true } }, get = function() return ItineraryDB.skipAH and true or false end,
      set = function(v) ItineraryDB.skipAH = v or nil; if ns.update then ns.update() end; if ns.refresh then ns.refresh() end end },
    -- Travel
    { tab = 3, label = "Take flights", desc = "On a \"Fly to ...\" step, talking to the flight master opens the map and takes the flight to the route's destination.",
      choices = ON_OFF, get = function() return A().fly ~= false end, set = function(v) A().fly = v end },
    { tab = 3, label = "Set hearthstone", desc = "Talking to the innkeeper on a \"make this inn your home\" step sets your hearthstone there.",
      choices = ON_OFF, get = function() return A().bind ~= false end, set = function(v) A().bind = v end },
    { tab = 3, label = "Spirit healer", desc = "Talking to a spirit healer as a ghost resurrects you right away (route death skips).",
      choices = ON_OFF, get = function() return A().spirit ~= false end, set = function(v) A().spirit = v end },
    { tab = 3, label = "Map pins", desc = "Your next stops as numbered pins on the world map and minimap (steps at the same place share one: \"2-3\"), and your step's kill-area spots. Also /iti pins.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.pins ~= false end,
      set = function(v) ItineraryDB.pins = v; if ns.refreshPins then ns.refreshPins() end end },
    { tab = 3, label = "...on the world map", desc = "How many of your next stops get a pin on the world map.",
      choices = { { "Off", 0 }, { "Current", 1 }, { "Next 3", 3 }, { "Next 5", 5 } },
      get = function() return ItineraryDB.pinsWorld or 5 end,
      set = function(v) ItineraryDB.pinsWorld = v; if ns.refreshPins then ns.refreshPins() end end,
      enabled = function() return ItineraryDB.pins ~= false end },
    { tab = 3, label = "...on the minimap", desc = "How many of your next stops get a pin on the minimap. Only the first one stays at the minimap's edge when it's far away; the others show once they're in range.",
      choices = { { "Off", 0 }, { "Current", 1 }, { "Next 3", 3 }, { "Next 5", 5 } },
      get = function() return ItineraryDB.pinsMini or 5 end,
      set = function(v) ItineraryDB.pinsMini = v; if ns.refreshPins then ns.refreshPins() end end,
      enabled = function() return ItineraryDB.pins ~= false end },
    { tab = 3, label = "Line between the pins", desc = "A dotted line on the world map from one stop to the next, in route order. The stretch to your next stop is the brighter one.",
      choices = ON_OFF, get = function() return ItineraryDB.pinsLine ~= false end,
      set = function(v) ItineraryDB.pinsLine = v; if ns.refreshPins then ns.refreshPins() end end,
      enabled = function() return ItineraryDB.pins ~= false and (ItineraryDB.pinsWorld or 5) > 1 end },
    -- Trainer
    { tab = 4, label = "Buy class skills", desc = "Buys the skills you can afford when you open your class trainer, the worthwhile ones first (which ones: the setting below). From level 6 on it keeps some money: 40c at 6, doubling every other level, at most 5g (from level 28).",
      choices = ON_OFF, get = function() return A().train end, set = function(v) A().train = v end },
    { tab = 4, label = "...only worthwhile ones", desc = "Part of Buy class skills: only the skills marked worthwhile (green, see the list below). Off: the others too, once the worthwhile ones and your gathering tools are paid for (from level 10).",
      choices = ON_OFF, get = function() return A().buyWorthOnly ~= false end, set = function(v) A().buyWorthOnly = v end,
      enabled = function() return A().train end },
    { tab = 4, label = "Open the training window", desc = "At a trainer you came to train at (the route's trainer stop or a trainer instruction), or one where Itinerary buys or learns something for you, the training window opens when you talk to them - also when the trainer has other dialogue first. Hold Shift to see the dialogue.",
      choices = ON_OFF, get = function() return A().trainGossip ~= false end, set = function(v) A().trainGossip = v end },
    { tab = 4, label = "Trainer visits", desc = "Instruction: a trainer visit (with new skills you can afford) shows in the instructions next to your step, and the arrow stays on the route. Step: it becomes the step you're on and the arrow leads there.",
      choices = { { "Instruction", "rec" }, { "Step", "step" } }, get = function() return A().trainerSteps or "rec" end,
      set = function(v) A().trainerSteps = v; if ns.rebuildRoute then ns.rebuildRoute() end; if ns.refresh then ns.refresh() end end },
    { tab = 4, label = "Weapon skills", desc = "Weapon skills you don't have yet: an instruction (or a step, see Trainer visits) when a weapon master who teaches them is within 400 yards and you have the 10 silver each. Route (default): only the ones the route trains. All: every weapon your class can use.",
      choices = { { "Route", "route" }, { "All", "all" }, { "Off", "off" } }, get = function() return A().weapons or "route" end,
      set = function(v) A().weapons = v; if ns.refresh then ns.refresh() end end },
    { tab = 4, label = "Buy weapon skills", desc = "Buys the weapon skills from Weapon skills when you open a weapon master, keeping the money for your next class skills. Off: you pick them yourself.",
      choices = ON_OFF, get = function() return A().buyWeapons == true end, set = function(v) A().buyWeapons = v end },
    { tab = 4, kind = "skills" },
    -- Professions
    { tab = 5, label = "Learn at the trainer", desc = "Learns the professions you picked (and their next rank) when you open their trainer, if the money for your next class skills stays. Hold Shift to do it by hand.",
      choices = ON_OFF, get = function() return A().profLearn ~= false end, set = function(v) A().profLearn = v end },
    { tab = 5, kind = "prof", label = "Main professions", desc = "Up to two. The route sends you to their trainers when you pass close by; a gathering one is learned from the first quest's reward book." },
    { tab = 5, kind = "first", label = "First profession" },
    { tab = 5, kind = "prof", secondary = true, label = "Secondary", desc = "Low priority: learned (and the Fishing Pole bought) only when everything else is paid for and 10 silver are left over. A hint under INSTRUCTIONS when a trainer is close (learned without the 10 silver rule when your next class skills stay paid for); reminders near their trainers every 10 levels." },
    { tab = 5, label = "Gather mode (experimental)", desc = "A farming route instead of the leveling route (also /iti gather): the arrow leads from one spot where a herb or ore vein of your skill can spawn to the next, and the zone's spots show on the minimap and world map. Needs the Itinerary_Data folder. Your route waits where you left it.",
      choices = ON_OFF, get = function() return ns.gatherOn and ns.gatherOn() or false end,
      set = function(v) if ns.gatherToggle then ns.gatherToggle(v) end end },
    { tab = 5, label = "Gather data", desc = "Which spots gather mode uses. Shipped: where nodes can spawn from the Itinerary_Data add-on (map dots: herbs green, ore orange). Own: ours, from beta finds plus every node gathered or passed close by on this account (herbs blue, ore pink). Both: all of them; a shipped spot we found too shows in our colours.",
      choices = { { "Both", "both" }, { "Shipped", "ship" }, { "Own", "own" } }, get = function() return ns.gatherSource and ns.gatherSource() or "both" end,
      set = function(v) if ns.setGatherSource then ns.setGatherSource(v) end end },
    { tab = 5, label = "Gathering tracking", desc = "When no minimap tracking is on (after logging in or dying), Find Herbs or Find Minerals for your gathering profession is switched on. Tracking you picked yourself is left alone.",
      choices = ON_OFF, get = function() return A().gatherTrack ~= false end,
      set = function(v) A().gatherTrack = v; if v and ns.applyGatherTracking then pcall(ns.applyGatherTracking) end end },
    { tab = 5, label = "Node icons", desc = "The game's interact icons: an icon floats over the nearest herb, ore vein or chest within about 20 yards, in any direction (SoftTargetInteract). Off puts your own values back.",
      choices = ON_OFF, get = function() return A().nodeIcons ~= false end,
      set = function(v) A().nodeIcons = v; if ns.applyNodeIcons then ns.applyNodeIcons(true) end end },
    { tab = 5, label = "Gathering tools", desc = "Buys the tools for your professions at vendors. Below level 4 only the first profession's tool; the second profession waits. From level 4: all new damage spells first, then learning the second profession and its tool.",
      choices = ON_OFF, get = function() return A().tools ~= false end, set = function(v) A().tools = v end },
    -- Panel
    { tab = 6, label = "Color scheme", desc = "The colours of the panel, arrow, instructions card and windows. Itinerary: green and gold (follows EllesmereUI). Amethyst: purple on dark grey. Frost: blue. Ember: orange. Slate: grey and white. Changing it reloads the UI.",
      choices = (function() local c = {} for _, t in ipairs(ns.THEMES) do c[#c + 1] = { t.name, t.key } end return c end)(),
      get = function() return ItineraryDB.panel.scheme or "itinerary" end,
      set = function(v) ItineraryDB.panel.scheme = v; ReloadUI() end },
    { tab = 6, label = "Instructions", desc = "What to do next to your step (sell junk, buy a quest item, learn a profession, die to skip a run back...) in their own card on the route panel, or inside the panel.",
      choices = { { "Own card", true }, { "In the panel", false } }, get = function() return ItineraryDB.panel.recCard ~= false end,
      set = function(v) ItineraryDB.panel.recCard = v; if ns.refresh then ns.refresh() end end },
    { tab = 6, kind = "hiddenAlong", label = "Hidden along the way" },
    { tab = 6, label = "Item and spell links", desc = "Items and spells in the step text get their icon and quality colour. Hover one for its tooltip, Shift-click to link it in chat.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.panel.links ~= false end,
      set = function(v) ItineraryDB.panel.links = v; if ns.refresh then ns.refresh() end end },
    { tab = 6, label = "Panel style", desc = "Card: the dark box. Minimal: no box or border, a faint shade with shadowed text that stays readable on snow.",
      choices = { { "Card", "card" }, { "Minimal", "minimal" } }, get = function() return ItineraryDB.panel.style or "card" end,
      set = function(v) ItineraryDB.panel.style = v; if ns.applyPanelStyle then ns.applyPanelStyle() end end },
    { tab = 6, kind = "slider", label = "Background opacity", desc = "How dark the panel's background is.", min = 0, max = 100, step = 5,
      get = function() return math.floor((ItineraryDB.panel.alpha or 0.92) * 100 + 0.5) end,
      set = function(v) ItineraryDB.panel.alpha = v / 100; if ns.applyPanelStyle then ns.applyPanelStyle() end end },
    { tab = 6, kind = "slider", label = "Panel size", desc = "Makes the panel (text, icons and the instructions card) bigger or smaller.", min = 80, max = 150, step = 5,
      get = function() return math.floor((ItineraryDB.panel.scale or 1) * 100 + 0.5) end,
      set = function(v) ItineraryDB.panel.scale = v / 100; if ns.applyPanelStyle then ns.applyPanelStyle() end end },
    { tab = 6, label = "Text on a see-through panel", desc = "Below about half opacity (and in Minimal): a sharp drop shadow, or a dark outline around every letter (stronger on bright ground, a bit softer).",
      choices = { { "Shadow", "shadow" }, { "Outline", "outline" } }, get = function() return ItineraryDB.panel.textEdge or "shadow" end,
      set = function(v) ItineraryDB.panel.textEdge = v; if ns.applyPanelStyle then ns.applyPanelStyle() end end },
    { tab = 6, label = "Panel grows", desc = "Up: the bottom edge stays where you put it and the panel grows upward. Down: the top edge stays and it grows downward.",
      choices = { { "Up", "up" }, { "Down", "down" } }, get = function() return ItineraryDB.panel.grow == "down" and "down" or "up" end,
      set = function(v) ItineraryDB.panel.grow = v; if ns.anchorPanel then ns.anchorPanel(true) end; if ns.refresh then ns.refresh() end end },
    { tab = 6, kind = "anchor", label = "Item & target buttons", desc = "Which corner of the route panel the quest item and target buttons sit at. They stack away from that corner." },
    { tab = 6, label = "Panel position", desc = "Unlock to drag the route panel, then lock it again. Alt + right-click on the panel does the same.",
      choices = { { "Locked", true }, { "Unlocked", false } }, get = function() return ItineraryDB.panel.locked and true or false end,
      set = function(v) ns.setLocked(v) end },
    -- Arrow
    { tab = 7, label = "Waypoint arrow", desc = "Also: right-click the minimap button.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.arrow.shown and true or false end,
      set = function(v) if (ItineraryDB.arrow.shown and true or false) ~= v then ns.toggleArrow() end end },
    { tab = 7, kind = "arrowskin", label = "Arrow look", desc = "Guide colours the arrow green when you're heading the right way and red when the target is behind you." },
    { tab = 7, label = "Instructions at the arrow", desc = "The instruction lines (buy this, sell junk, train...) also above the waypoint arrow, without a header.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.arrow.instr ~= false end,
      set = function(v) ItineraryDB.arrow.instr = v; if ns.refresh then ns.refresh() end end },
    { tab = 7, label = "Death skips at the arrow", desc = "\"Die and respawn at the spirit healer\" always shows above the waypoint arrow, also when Instructions at the arrow is hidden.",
      choices = ON_OFF, get = function() return ItineraryDB.arrow.deathInstr ~= false end,
      set = function(v) ItineraryDB.arrow.deathInstr = v; if ns.refresh then ns.refresh() end end },
    { tab = 7, kind = "slider", label = "Arrow instruction size", desc = "Font size of the instruction lines above the waypoint arrow.", min = 9, max = 24, step = 1, unit = " pt",
      get = function() return ItineraryDB.arrow.instrSize or 12 end,
      set = function(v) if ns.setArrowInstrSize then ns.setArrowInstrSize(v) end end },
    { tab = 7, label = "Arrow tooltip", desc = "The step's name and details when your mouse is over the arrow. Alt + right-click still locks and unlocks it.",
      choices = SHOW_HIDE, get = function() return ItineraryDB.arrow.tooltip ~= false end,
      set = function(v) ItineraryDB.arrow.tooltip = v end },
    { tab = 7, label = "Arrow position", desc = "Unlock to drag the waypoint arrow, then lock it again. Alt + right-click on the arrow does the same.",
      choices = { { "Locked", true }, { "Unlocked", false } }, get = function() return ItineraryDB.arrow.locked and true or false end,
      set = function(v) ns.setArrowLocked(v) end },
    -- Keys
    { tab = 8, kind = "key", bind = "ItineraryTarget", label = "Target button", desc = "Targets the quest mobs of your step (or the NPC to talk to)." },
    { tab = 8, label = "Show target button", desc = "Off hides the button next to the panel; its key binding above still works.",
      choices = ON_OFF, get = function() return A().targetBtn ~= false end, set = function(v) A().targetBtn = v; if ns.updateItems then ns.updateItems() end end },
    { tab = 8, label = "Talk on second press", desc = "When the target button found a friendly NPC, pressing its key again talks to them (Interact with Target) - spam it on a contested escort to take the quest first. Outside combat; back to normal after 8 seconds or once you talk.",
      choices = ON_OFF, get = function() return A().interact ~= false end, set = function(v) A().interact = v end },
    { tab = 8, label = "Tag with a spell", desc = "The target button also casts an instant spell on the enemy it finds (Judgement, Earth Shock, Shadow Word: Pain, Curse of Agony, Fire Blast, Arcane Shot, Moonfire, Throw, Charge), auto attack until you know one. Spam it on a contested respawn to tag it first.",
      choices = ON_OFF, get = function() return A().tagSpell ~= false end, set = function(v) A().tagSpell = v; if ns.updateItems then ns.updateItems() end end },
    { tab = 8, label = "Mark the target", desc = "The target button puts a skull on the enemy it finds, and an orange circle on a friendly NPC or player.",
      choices = ON_OFF, get = function() return A().skull ~= false end, set = function(v) A().skull = v; if ns.updateItems then ns.updateItems() end end },
    { tab = 8, kind = "key", bind = "ItineraryItem1", label = "Quest item 1", desc = "The top item button (nearest the panel's corner)." },
    { tab = 8, kind = "key", bind = "ItineraryItem2", label = "Quest item 2" },
    { tab = 8, kind = "key", bind = "ItineraryItem3", label = "Quest item 3" },
    { tab = 8, kind = "key", bind = "ItineraryItem4", label = "Quest item 4" },
}

---------------------------------------------------------------- rows
local function switchRow(row, opt)
    local segs = {}
    for c = #opt.choices, 1, -1 do
        local b = segment(row, opt.choices[c][1])
        -- (a longer label gets a wider segment instead of being cut off: "In the panel")
        local tw = b.text.GetStringWidth and b.text:GetStringWidth()
        if type(tw) == "number" and tw + 14 > SEG_W then b:SetWidth(math.ceil(tw + 14)) end
        if c == #opt.choices then b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
        else b:SetPoint("RIGHT", segs[c + 1], "LEFT", 1, 0) end
        b:SetScript("OnClick", function()
            if opt.enabled and not opt.enabled() then return end
            if opt.get() ~= opt.choices[c][2] then opt.set(opt.choices[c][2]); refresh() end
        end)
        segs[c] = b
    end
    function row:Refresh()
        local on = not opt.enabled or opt.enabled()
        local cur = opt.get()
        for c, b in ipairs(segs) do b:SetActive(on and cur == opt.choices[c][2], not on) end
        self.lbl:SetAlpha(on and 1 or 0.4)
        self.sub:SetText(opt.desc)
        self:SetHeight(math.max(ROW_H, 8 + SEG_H + 6 + self.sub:GetStringHeight() + 10))
    end
end

-- a grid of toggle chips under the label; build(cols) returns the list of {label, on, dim, click, tip}
local function chipRow(row, cols, items, extra)
    local chipW = math.floor((W - PAD * 2) / cols)
    row.chips = {}
    function row:Refresh()
        local list = items()
        for k, it in ipairs(list) do
            local b = self.chips[k]
            if not b then
                b = segment(self, "")
                b:SetSize(chipW + 1, SEG_H)
                b:SetScript("OnClick", function(s) if s.click then s.click(); refresh() end end)
                self.chips[k] = b
            end
            local col, line = (k - 1) % cols, math.floor((k - 1) / cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", col * chipW, -(8 + SEG_H + 6 + line * (SEG_H - 1)))
            b.text:SetText(it[1]); b.click, b.tip = it[4], it[5]
            b:SetActive(it[2], it[3])
            b:Show()
        end
        for k = #list + 1, #self.chips do self.chips[k]:Hide() end
        local lines = math.ceil(#list / cols)
        local gridH = lines > 0 and (lines * (SEG_H - 1) + 1 + 6) or 0
        if extra then extra(self, list) end
        self.sub:ClearAllPoints()
        self.sub:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(8 + SEG_H + 6 + gridH))
        self:SetHeight(8 + SEG_H + 6 + gridH + self.sub:GetStringHeight() + 10)
    end
end

local function buildRow(opt, i)
    local row = CreateFrame("Frame", nil, win)
    row:SetHeight(ROW_H)
    row.tab = opt.tab
    row.lbl = text(row, 15, 1, 1, 1, 0.9)
    row.lbl:SetPoint("TOPLEFT", 0, -11)
    row.lbl:SetWidth(W - PAD * 2 - SEG_W * 2 - 12)
    row.lbl:SetWordWrap(false)
    row.sub = text(row, 11, 1, 1, 1, 0.38)
    row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(8 + SEG_H + 6))
    row.sub:SetWidth(W - PAD * 2)
    row.sub:SetWordWrap(true)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetColorTexture(1, 1, 1, 0.05); row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT"); row.line:SetPoint("BOTTOMRIGHT")

    if opt.choices then
        row.lbl:SetText(opt.label)
        switchRow(row, opt)
    elseif opt.kind == "skills" then
        -- one grid of the class's skills, two views: which are worth a trip to the trainer, which get bought.
        -- [All][None] [Worth a visit][Auto-buy] on the right of the label
        local function view() return A().skillView == "buy" and "buy" or "worth" end
        local vBuy, vWorth = segment(row, "Auto-buy"), segment(row, "Worth a visit")
        vBuy:SetSize(96, SEG_H); vWorth:SetSize(96, SEG_H)
        vBuy:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8); vWorth:SetPoint("RIGHT", vBuy, "LEFT", 1, 0)
        vBuy:SetScript("OnClick", function() A().skillView = "buy"; refresh() end)
        vWorth:SetScript("OnClick", function() A().skillView = "worth"; refresh() end)
        local all, none = segment(row, "All"), segment(row, "None")
        none:SetSize(46, SEG_H); all:SetSize(46, SEG_H)
        none:SetPoint("RIGHT", vWorth, "LEFT", -10, 0); all:SetPoint("RIGHT", none, "LEFT", 1, 0)
        row.lbl:SetWidth(W - PAD * 2 - 96 * 2 - 46 * 2 - 14)
        local function setWorthAll(on)
            local class = className()
            A().trainWorth = A().trainWorth or {}
            local w = {}
            for _, n in ipairs(skillNames()) do w[n] = on end
            A().trainWorth[class] = w
        end
        all:SetScript("OnClick", function()
            if view() == "buy" then A().trainSkip[className()] = {} else setWorthAll(true) end
            refresh()
        end)
        none:SetScript("OnClick", function()
            if view() == "buy" then
                local skip = {}
                for _, n in ipairs(skillNames()) do skip[n] = true end
                A().trainSkip[className()] = skip
            else setWorthAll(false) end
            refresh()
        end)
        chipRow(row, 3, function()
            local class = className()
            local skip, on = A().trainSkip[class] or {}, A().train
            local out = {}
            for _, n in ipairs(skillNames()) do
                if view() == "buy" then
                    out[#out + 1] = { n, on and not skip[n], not on, function()
                        if not A().train then return end
                        A().trainSkip[class] = A().trainSkip[class] or {}
                        A().trainSkip[class][n] = (not A().trainSkip[class][n]) or nil
                    end, n }
                else
                    -- dimmed: you won't buy it (Auto-buy view), so a visit for it is only a reminder
                    out[#out + 1] = { n, ns.trainWorth and ns.trainWorth(n, class) or false, on and skip[n] or false, function()
                        local w = A().trainWorth or {}
                        A().trainWorth = w
                        w[class] = w[class] or {}
                        w[class][n] = not (ns.trainWorth and ns.trainWorth(n, class))
                    end, n }
                end
            end
            return out
        end, function(self, list)
            local _, loc = className()
            self.lbl:SetText(loc .. " skills")
            local buy, on = view() == "buy", A().train
            vBuy:SetActive(buy); vWorth:SetActive(not buy)
            all:SetActive(false, buy and not on); none:SetActive(false, buy and not on)
            all:SetShown(#list > 0); none:SetShown(#list > 0)
            if #list == 0 then
                self.sub:SetText("Your skills show up here after the first visit to a class trainer. Until then every skill is bought and damage spells are worth a trip.")
            elseif buy then
                self.sub:SetText(on and "Lit = bought automatically at the trainer. Click a skill to switch it."
                    or "Lit = bought automatically once \"Buy class skills\" is on.")
            else
                self.sub:SetText("Lit = the route sends you to the trainer for it (damage spells by default); the rest is bought when you're there anyway. Dimmed = not auto-bought.")
            end
        end)
    elseif opt.kind == "first" then
        -- which of the two main professions comes first
        row.lbl:SetText(opt.label)
        local segs = {}
        for c = 2, 1, -1 do
            local b = segment(row, "")
            b:SetSize(104, SEG_H)
            if c == 2 then b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
            else b:SetPoint("RIGHT", segs[2], "LEFT", 1, 0) end
            b:SetScript("OnClick", function(self) if self.key then ns.profSetFirst(self.key); refresh() end end)
            segs[c] = b
        end
        row.lbl:SetWidth(W - PAD * 2 - 208 - 12)
        function row:Refresh()
            local main = ns.profMain and ns.profMain() or {}
            local two = #main == 2
            for c, b in ipairs(segs) do
                local k = main[c]
                b.key = two and k or nil
                b.text:SetText(k and ns.PROF[k].name or "-")
                b:SetActive(two and c == 1, not two)
            end
            self.lbl:SetAlpha(two and 1 or 0.4)
            local first = main[1] and ns.PROF[main[1]]
            local book = ns.bookProf and ns.bookProf()
            local d
            if not two then d = "Pick two main professions to choose which one comes first."
            else
                d = first.name .. " is learned first and gets its tool first."
                if book then d = d .. " The first quest's reward book teaches " .. ns.PROF[book].name .. "." end
            end
            self.sub:SetText(d)
            self:SetHeight(math.max(ROW_H, 8 + SEG_H + 6 + self.sub:GetStringHeight() + 10))
        end
    elseif opt.kind == "packs" then
        -- the installed route packs in your order, each with Up / Down
        row.lbl:SetText(opt.label)
        row.lines = {}
        function row:Refresh()
            local list = ns.packList and ns.packList() or {}
            for k, p in ipairs(list) do
                local ln = self.lines[k]
                if not ln then
                    ln = CreateFrame("Frame", nil, self)
                    ln:SetSize(W - PAD * 2, SEG_H)
                    ln.t = text(ln, 12, 1, 1, 1, 0.85); ln.t:SetPoint("LEFT", 0, 0)
                    ln.t:SetWidth(W - PAD * 2 - SEG_W * 2 - 10); ln.t:SetWordWrap(false)
                    ln.down = segment(ln, "Down"); ln.down:SetPoint("RIGHT", ln, "RIGHT", 0, 0)
                    ln.up = segment(ln, "Up"); ln.up:SetPoint("RIGHT", ln.down, "LEFT", 1, 0)
                    ln.up:SetScript("OnClick", function(b) ns.movePack(b.pack, -1); refresh() end)
                    ln.down:SetScript("OnClick", function(b) ns.movePack(b.pack, 1); refresh() end)
                    self.lines[k] = ln
                end
                ln:ClearAllPoints()
                ln:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(8 + SEG_H + 6 + (k - 1) * (SEG_H + 3)))
                ln.t:SetText(k .. ".  " .. p.title .. "  |cff8a8a8a" .. p.routes .. " routes|r")
                ln.up.pack, ln.down.pack = p.name, p.name
                ln.up:SetActive(false, k == 1); ln.down:SetActive(false, k == #list)
                ln:Show()
            end
            for k = #list + 1, #self.lines do self.lines[k]:Hide() end
            local listH = #list > 0 and (#list * (SEG_H + 3) + 4) or 0
            self.sub:ClearAllPoints()
            self.sub:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(8 + SEG_H + 6 + listH))
            self.sub:SetText(#list == 0 and "No route pack installed: record your own route or import one." or opt.desc)
            self:SetHeight(8 + SEG_H + 6 + listH + self.sub:GetStringHeight() + 10)
        end
    elseif opt.kind == "wipe" then
        row.lbl:SetText(opt.label)
        local b = segment(row, "Reset")
        b:SetSize(130, SEG_H)
        b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
        b:SetScript("OnClick", function(self)
            if self.armed and GetTime() - self.armed < 5 then
                self.armed = nil
                if opt.factory then ns.factoryReset() else ns.wipeCharacter() end
            else
                self.armed = GetTime()
                self.text:SetText("Click again to wipe"); self:SetActive(true)
                C_Timer.After(5, function() self.armed = nil; refresh() end)
            end
        end)
        function row:Refresh()
            if not b.armed then b.text:SetText("Reset"); b:SetActive(false) end
            self.sub:SetText(opt.desc)
            self:SetHeight(math.max(ROW_H, 8 + SEG_H + 6 + self.sub:GetStringHeight() + 10))
        end
    elseif opt.kind == "arrowskin" then
        row.lbl:SetText(opt.label)
        row.sub:SetText(opt.desc)
        chipRow(row, 6, function()
            local cur = ItineraryDB.arrow.skin or "Itinerary"
            local out = {}
            for _, sk in ipairs(ns.ARROW_SKINS or {}) do
                out[#out + 1] = { sk[1], cur == sk[1], false, function()
                    ItineraryDB.arrow.skin = sk[1]
                    if ns.applyArrowSkin then ns.applyArrowSkin() end
                end }
            end
            return out
        end)
    elseif opt.kind == "sound" then
        row.lbl:SetText(opt.label)
        row.sub:SetText(opt.desc)
        chipRow(row, 5, function()
            local cur = ItineraryDB.stepSound or "Off"
            if cur == "Chime" then cur = "Quest" end
            local out = {}
            for _, snd in ipairs(ns.SOUNDS) do
                out[#out + 1] = { snd[1], cur == snd[1], false, function()
                    ItineraryDB.stepSound = snd[1]
                    ns.stepSound(snd[1])
                end }
            end
            return out
        end)
    elseif opt.kind == "packopt" then
        -- a route pack's own on/off choices (registered by the pack; Itinerary only shows and keeps them)
        local g = opt.group
        row.lbl:SetText(g.title .. "  |cff8a8a8a" .. (opt.packTitle or g.pack) .. "|r")
        -- (a choice your route doesn't depend on - an older version of the route, another pack's route, or
        -- one the other choices make moot - is dimmed; changing it needs no reload)
        local function usedSet() return ns.packKeysOfRoute and ns.packKeysOfRoute(g.pack) end
        chipRow(row, 4, function()
            local used = usedSet()
            local out = {}
            for _, it in ipairs(g.items) do
                local on = ns.packOption(g.pack, it.key)
                local idle = used and not used[tostring(it.key)]
                local tip = idle and ((it.tip and (it.tip .. "\n") or "") .. "|cff9a9a9aNot used by your route|r") or it.tip
                out[#out + 1] = { it.label, on, idle and true or false, function() ns.setPackOption(g.pack, it.key, not on) end, tip }
            end
            return out
        end, function(self)
            local used, any = usedSet(), false
            for _, it in ipairs(g.items) do if not used or used[tostring(it.key)] then any = true end end
            self.sub:SetText((g.text and (g.text .. " ") or "") .. (any
                and "Lit = on. For this character; a change rebuilds your route with a quick reload."
                or "Lit = on. Your route doesn't use these switches; they're kept for a route that does."))
        end)
    elseif opt.kind == "anchor" then
        row.lbl:SetText(opt.label)
        row.sub:SetText(opt.desc)
        local CHOICES = { { "Top left", "TOPLEFT" }, { "Top right", "TOPRIGHT" }, { "Bottom left", "BOTTOMLEFT" }, { "Bottom right", "BOTTOMRIGHT" } }
        chipRow(row, 4, function()
            local cur = ItineraryDB.itemAnchor or "BOTTOMLEFT"
            local out = {}
            for _, c in ipairs(CHOICES) do
                out[#out + 1] = { c[1], cur == c[2], false, function()
                    if InCombatLockdown() then ns.print("the buttons can only move outside combat") return end
                    ItineraryDB.itemAnchor = c[2]
                    if ns.updateItems then ns.updateItems() end
                end }
            end
            return out
        end)
    elseif opt.kind == "slider" then
        row.lbl:SetText(opt.label)
        local ar, ag, ab = accent()
        local val = text(row, 13, ar, ag, ab, 1)
        val:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -12)
        local slider = CreateFrame("Slider", nil, row)
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(16)
        slider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(8 + SEG_H + 8))
        slider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        slider:SetMinMaxValues(opt.min, opt.max)
        slider:SetValueStep(opt.step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(ns.themeBtn(1)); track:SetHeight(6)
        track:SetPoint("LEFT"); track:SetPoint("RIGHT")
        local fill = slider:CreateTexture(nil, "BORDER")
        fill:SetColorTexture(ar, ag, ab, 0.6); fill:SetHeight(6); fill:SetPoint("LEFT", track, "LEFT")
        local thumb = slider:CreateTexture(nil, "ARTWORK")
        thumb:SetColorTexture(ar, ag, ab, 1); thumb:SetSize(10, 16)
        slider:SetThumbTexture(thumb)
        local updating = false
        local function show(v)
            val:SetText(math.floor(v + 0.5) .. (opt.unit or "%"))
            local w = slider:GetWidth() or 0
            fill:SetWidth(math.max(1, w * (v - opt.min) / (opt.max - opt.min)))
        end
        slider:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v / opt.step + 0.5) * opt.step
            show(v)
            if not updating then opt.set(v) end
        end)
        row.sub:ClearAllPoints()
        row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(8 + SEG_H + 8 + 16 + 6))
        function row:Refresh()
            local v = opt.get()
            updating = true; slider:SetValue(v); updating = false
            show(v)
            self.sub:SetText(opt.desc)
            self:SetHeight(8 + SEG_H + 8 + 16 + 6 + self.sub:GetStringHeight() + 10)
        end
    elseif opt.kind == "key" then
        -- click, then press a key (or a mouse button 3-5) to bind it; right-click clears it
        row.lbl:SetText(opt.label)
        local cmd = "CLICK " .. opt.bind .. ":LeftButton"
        local b = segment(row, "")
        b:SetSize(150, SEG_H)
        b:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.tip = "Click, then press a key, a mouse button (3-5) or turn the mouse wheel - with Shift, Ctrl or Alt if you like. Right-click clears it. Escape cancels."
        local function keysOf() return GetBindingKey and { GetBindingKey(cmd) } or {} end
        local function stop()
            if win.capture == b then win.capture = nil end
            win:EnableKeyboard(false)
            win:SetScript("OnKeyDown", nil)
            win:EnableMouseWheel(false)
            win:SetScript("OnMouseWheel", nil)
            refresh()
        end
        local function bind(key)
            if InCombatLockdown() then ns.print("key bindings can only change outside combat") stop() return end
            for _, k in ipairs(keysOf()) do SetBinding(k) end
            if key then SetBinding(key, cmd) end
            SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1)
            if ns.updateItems then ns.updateItems() end
            stop()
        end
        local MODS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }
        local function combo(key)
            local p = ""
            if IsAltKeyDown() then p = p .. "ALT-" end
            if IsControlKeyDown() then p = p .. "CTRL-" end
            if IsShiftKeyDown() then p = p .. "SHIFT-" end
            return p .. key
        end
        b:SetScript("OnClick", function(_, button)
            if button == "RightButton" then bind(nil) return end
            if win.capture == b then stop() return end
            win.capture = b
            b.text:SetText("Press a key…"); b:SetActive(true)
            win:EnableKeyboard(true)
            if win.SetPropagateKeyboardInput then win:SetPropagateKeyboardInput(false) end
            win:SetScript("OnKeyDown", function(_, key)
                if key == "ESCAPE" then stop() return end
                if MODS[key] then return end
                bind(combo(key))
            end)
            -- the mouse wheel (with Shift / Ctrl / Alt too) anywhere over this window
            win:EnableMouseWheel(true)
            win:SetScript("OnMouseWheel", function(_, delta)
                bind(combo(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
            end)
        end)
        b:SetScript("OnMouseDown", function(_, button)
            if win.capture ~= b then return end
            local m = ({ MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" })[button]
            if m then bind(combo(m)) end
        end)
        function row:Refresh()
            if win.capture ~= b then
                local k = keysOf()[1]
                b.text:SetText(k and (GetBindingText and GetBindingText(k) or k) or "Not bound")
                b:SetActive(false, not k)
            end
            self.sub:SetText(opt.desc or "")
            self:SetHeight(opt.desc and math.max(ROW_H, 8 + SEG_H + 6 + self.sub:GetStringHeight() + 10) or (8 + SEG_H + 12))
        end
    elseif opt.kind == "hiddenAlong" then
        -- the along-the-way entries you hid (the × on their row in the panel), this character's; click one to
        -- show it again
        row.lbl:SetText(opt.label)
        local all = segment(row, "Show all")
        all:SetSize(96, SEG_H)
        all:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -8)
        all:SetScript("OnClick", function() if ns.unhideAlong then ns.unhideAlong() end; refresh() end)
        chipRow(row, 2, function()
            local out = {}
            for _, e in ipairs(ns.hiddenAlongList and ns.hiddenAlongList() or {}) do
                out[#out + 1] = { e.name, true, false, function() ns.unhideAlong(e.key) end, e.name .. "\nClick to show it again." }
            end
            return out
        end, function(self, list)
            all:SetShown(#list > 0); all:SetActive(false)
            self.sub:SetText(#list == 0
                and "None. The × on an entry under ALONG THE WAY hides it on this character: a Camping 101 quest you're not doing, items you don't want to collect. The route's own steps for a quest stay."
                or "Hidden on this character: not shown under ALONG THE WAY, and the target and item buttons leave them out. Click one to show it again.")
        end)
    elseif opt.kind == "prof" then
        row.lbl:SetText(opt.label)
        row.sub:SetText(opt.desc)
        chipRow(row, 3, function()
            local out, main = {}, 0
            for _, k in ipairs(ns.profChosen and ns.profChosen() or {}) do
                if ns.PROF[k] and not ns.PROF[k].secondary then main = main + 1 end
            end
            for _, k in ipairs(profKeys(opt.secondary)) do
                local p = ns.PROF[k]
                local on = ns.profIsChosen(k)
                local full = not opt.secondary and not on and main >= 2
                out[#out + 1] = { p.name, on, full, function() ns.profToggle(k) end,
                    p.gather and (p.name .. " - gathering") or nil }
            end
            return out
        end)
    end
    win.rows[i] = row
    return row
end

---------------------------------------------------------------- window
local function savePos()
    local p, _, rp, x, y = win:GetPoint()
    ItineraryDB.settingsPos = { p, rp, x, y }
end

local function build()
    local ar, ag, ab = accent()
    win = CreateFrame("Frame", "ItinerarySettingsWindow", UIParent)
    win:SetSize(W, 400)
    local pos = ItineraryDB.settingsPos
    if pos then win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else win:SetPoint("CENTER") end
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function() win:StopMovingOrSizing(); savePos() end)
    tinsert(UISpecialFrames, "ItinerarySettingsWindow") -- Escape closes it

    local bg = win:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.97))
    addEdges(win, 1, 1, 1, 0.15)
    local top = win:CreateTexture(nil, "ARTWORK"); top:SetColorTexture(ar, ag, ab, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)

    local eyebrow = text(win, 12, ar, ag, ab, 0.9); eyebrow:SetPoint("TOPLEFT", PAD, -16); eyebrow:SetText("ITINERARY")
    local title = text(win, 19, 1, 1, 1, 1); title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -4); title:SetText("Settings")
    local desc = text(win, 12, 1, 1, 1, 0.45)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); desc:SetWidth(W - PAD * 2); desc:SetWordWrap(true)
    desc:SetText("Hold Shift while talking to an NPC, opening a trainer or a vendor to do it by hand.")

    local close = CreateFrame("Button", nil, win)
    close:SetSize(24, 24); close:SetPoint("TOPRIGHT", -8, -8)
    local x = text(close, 18, 1, 1, 1, 0.5); x:SetPoint("CENTER"); x:SetJustifyH("CENTER"); x:SetText("×")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 0.9) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.5) end)
    close:SetScript("OnClick", function() win:Hide() end)

    activeTab = math.min(ItineraryDB.settingsTab or 1, #TAB_NAMES)
    -- two rows of four tabs
    local PER = 4
    local tabW = math.floor((W - PAD * 2) / PER)
    win.tabs = {}
    for t, name in ipairs(TAB_NAMES) do
        local b = segment(win, name)
        b:SetSize(tabW + 1, SEG_H + 4)
        local col, line = (t - 1) % PER, math.floor((t - 1) / PER)
        b:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", col * tabW, -12 - line * (SEG_H + 3))
        b:SetScript("OnClick", function() activeTab = t; ItineraryDB.settingsTab = t; refresh() end)
        win.tabs[t] = b
    end
    local div = win:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(1, 1, 1, 0.08); div:SetHeight(1)
    div:SetPoint("TOPLEFT", win.tabs[#TAB_NAMES - ((#TAB_NAMES - 1) % PER)], "BOTTOMLEFT", 0, -10)
    div:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)

    win.rows = {}
    -- the route packs' own choices go right under Route packs (one row per list a pack registered)
    local list = {}
    for _, opt in ipairs(OPTIONS) do
        list[#list + 1] = opt
        if opt.kind == "packs" and ns.packOptionGroups then
            for _, e in ipairs(ns.packOptionGroups()) do
                list[#list + 1] = { tab = opt.tab, kind = "packopt", group = e.group, packTitle = e.packTitle }
            end
        end
    end
    for i, opt in ipairs(list) do buildRow(opt, i) end

    local hint = text(win, 11, 1, 1, 1, 0.3)
    hint:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", PAD, 14); hint:SetWidth(W - PAD * 2); hint:SetWordWrap(true)
    hint:SetText("Changes apply right away. Drag the window anywhere; Escape closes it.")
    local fl = win:CreateTexture(nil, "ARTWORK")
    fl:SetColorTexture(1, 1, 1, 0.08); fl:SetHeight(1)
    fl:SetPoint("BOTTOMLEFT", hint, "TOPLEFT", 0, 10); fl:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)

    -- one height for all tabs (the tallest), so switching tabs never resizes the window
    local function layout()
        local heights = {}
        for _, r in ipairs(win.rows) do heights[r.tab] = (heights[r.tab] or 0) + (r:GetHeight() or ROW_H) end
        local tallest = 0
        for _, h in pairs(heights) do tallest = math.max(tallest, h) end
        local last
        for k, r in ipairs(win.rows) do
            local show = r.tab == activeTab
            r:SetShown(show)
            if show then
                r:ClearAllPoints()
                if last then r:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0)
                else r:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -4) end
                r:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
                local nxt = win.rows[k + 1]
                r.line:SetShown(nxt and nxt.tab == r.tab or false)
                last = r
            end
        end
        for t, b in ipairs(win.tabs) do b:SetActive(t == activeTab) end
        local header = 16 + eyebrow:GetStringHeight() + 4 + title:GetStringHeight() + 6 + desc:GetStringHeight() + 12 + SEG_H + 4 + 10
        local wt, db = win:GetTop(), div:GetBottom()
        if wt and db and wt > db then header = wt - db end
        local footer = 12 + 1 + 10 + hint:GetStringHeight() + 14
        win:SetHeight(math.floor(header + 4 + tallest + footer + 0.5))
    end

    refresh = function()
        if not win:IsShown() then return end
        for _, r in ipairs(win.rows) do r:Refresh() end
        layout()
    end
    win:SetScript("OnShow", function()
        for _, r in ipairs(win.rows) do r:Refresh() end
        layout()
        C_Timer.After(0, function() if win:IsShown() then layout() end end) -- positions settle next frame
    end)
    win:HookScript("OnHide", function()
        win.capture = nil; win:EnableKeyboard(false); win:SetScript("OnKeyDown", nil)
        win:EnableMouseWheel(false); win:SetScript("OnMouseWheel", nil)
    end)
    win:Hide()
end

function ns.refreshSettings()
    if win and refresh then refresh() end
end

function ns.openSettings(toggle)
    if not win then
        if not (ItineraryDB and ItineraryDB.auto) then return end
        build()
    end
    if toggle and win:IsShown() then win:Hide() return end
    win:Show()
    win:Raise()
end

---------------------------------------------------------------- stub in Options > AddOns
local function blizzardStub()
    local p = CreateFrame("Frame", "ItinerarySettingsStub")
    p.name = "Itinerary"
    local t = text(p, 18, 1, 1, 1, 1); t:SetPoint("TOPLEFT", 16, -16); t:SetText("Itinerary")
    local s = text(p, 12, 1, 1, 1, 0.6); s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6); s:SetWidth(520)
    s:SetText("Itinerary's settings live in their own window, so you can keep playing while it's open. Open it with /iti settings or Shift + click on the minimap button.")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(180, 26); b:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -14); b:SetText("Open settings")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        ns.openSettings()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(p, "Itinerary")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if ns.autoDefaults then ns.autoDefaults() end
    pcall(blizzardStub)
end)
