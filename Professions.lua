-- Itinerary professions: pick your professions once per character, then the route points you to the
-- trainers (and the gathering tools) when you pass close by, uses the starting-zone book reward for a
-- gathering profession, and reminds you about new ranks near a trainer every 10 levels.
local ADDON, ns = ...

---------------------------------------------------------------- data
-- key -> name, apprentice spell, gathering?, tool item, book item (starting-zone quest reward)
local PROF = {
    mining         = { name = "Mining",         spell = 2575, gather = true, tool = 2901, book = 247840 },
    herbalism      = { name = "Herbalism",      spell = 2366, gather = true,              book = 247841 },
    skinning       = { name = "Skinning",       spell = 8613, gather = true, tool = 7005, book = 247846 },
    blacksmithing  = { name = "Blacksmithing",  spell = 2018, tool = 5956 },
    engineering    = { name = "Engineering",    spell = 4036 },
    alchemy        = { name = "Alchemy",        spell = 2259 },
    leatherworking = { name = "Leatherworking", spell = 2108 },
    tailoring      = { name = "Tailoring",      spell = 3908 },
    enchanting     = { name = "Enchanting",     spell = 7411 },
    cooking        = { name = "Cooking",        spell = 2550, secondary = true },
    firstaid       = { name = "First Aid",      spell = 3273, secondary = true },
    fishing        = { name = "Fishing",        spell = 7620, secondary = true, tool = 6256 },
}
local PRIMARY = { "mining", "herbalism", "skinning", "blacksmithing", "engineering", "alchemy",
                  "leatherworking", "tailoring", "enchanting" }
local SECONDARY = { "cooking", "firstaid", "fishing" }
local boughtHere = {} -- tools bought at the vendor you have open (the bags catch up a moment later)
local TOOLNAME = { [2901] = "Mining Pick", [7005] = "Skinning Knife", [5956] = "Blacksmith Hammer", [6256] = "Fishing Pole" }
-- quests early on whose reward choice includes the gathering books
local BOOK_QUESTS = { [234] = true, [91743] = true, [6395] = true, [4402] = true, [93552] = true }
-- vendors known to sell the tools: from the Itinerary_Data add-on (ns.addToolVendors) when it's installed; more are
-- recorded when you open a vendor that sells them
local TOOL_VENDORS = {}
function ns.addToolVendors(list)
    for item, vendors in pairs(list or {}) do
        TOOL_VENDORS[item] = TOOL_VENDORS[item] or {}
        for _, v in ipairs(vendors) do table.insert(TOOL_VENDORS[item], v) end
    end
end
-- profession trainers known before you meet them: prof, npc, map, x, y, side. They come with the separate
-- Itinerary_Data add-on; without it, trainers you target or open are recorded (ItineraryDB.profTrainers).
local TRAINERS = {} -- filled by Itinerary_Data (ns.addProfTrainers) when it is installed
-- the ranks a trainer teaches, when Itinerary_Data knows (npc -> { [75] = true, ... }; 75 Apprentice, 150
-- Journeyman, 225 Expert, 300 Artisan): a trainer out in the world like Kitta Firewind at the Tower of Azora
-- only teaches Expert, a "Journeyman" trainer in a village only Apprentice
local TRAINER_TIERS = {}
ns.PROF = PROF

---------------------------------------------------------------- state
local function C() return ItineraryCharDB end
local function side() return (UnitFactionGroup("player") == "Horde") and "H" or "A" end
function ns.profName(key) return PROF[key] and PROF[key].name end
function ns.profChosen()
    local p = C() and C().prof
    return p and p.list or {}
end
local function chosen(key)
    for _, k in ipairs(ns.profChosen()) do if k == key then return true end end
    return false
end
ns.profIsChosen = chosen
ns.PROF_PRIMARY, ns.PROF_SECONDARY = PRIMARY, SECONDARY
-- switch one profession on or off (settings window); max two main ones. The list order is the priority:
-- the first main profession is learned first (quest book if it's a gathering one) and gets its tool first.
function ns.profToggle(key)
    local c = C(); if not c or not PROF[key] then return false end
    c.prof = c.prof or {}
    local main, sec, on = {}, {}, false
    for _, k in ipairs(c.prof.list or {}) do
        if k == key then on = true
        elseif PROF[k].secondary then sec[#sec + 1] = k else main[#main + 1] = k end
    end
    if not on then
        if PROF[key].secondary then sec[#sec + 1] = key
        else
            if #main >= 2 then return false end
            -- a gathering profession goes first when the one you have is a crafting one (it gets the quest book)
            if #main == 1 and PROF[key].gather and not PROF[main[1]].gather then table.insert(main, 1, key)
            else main[#main + 1] = key end
        end
    end
    local list = {}
    for _, k in ipairs(main) do list[#list + 1] = k end
    for _, k in ipairs(sec) do list[#list + 1] = k end
    c.prof.list, c.prof.asked = list, true
    if ns.update then ns.update() end
    return true
end
-- the two main professions in priority order
function ns.profMain()
    local out = {}
    for _, k in ipairs(ns.profChosen()) do if PROF[k] and not PROF[k].secondary then out[#out + 1] = k end end
    return out
end
-- make this main profession the first one
function ns.profSetFirst(key)
    local c = C(); if not (c and c.prof and c.prof.list) then return end
    for i, k in ipairs(c.prof.list) do
        if k == key then table.remove(c.prof.list, i); table.insert(c.prof.list, 1, key); break end
    end
    if ns.update then ns.update() end
end

-- skill rank if you know the profession (nil if not)
local function skillLines()
    local out = {}
    if GetNumSkillLines and GetSkillLineInfo then
        -- a collapsed header ("Secondary Skills") hides its lines: open those for the read, close them again
        local opened = {}
        if ExpandSkillHeader then
            for i = GetNumSkillLines(), 1, -1 do
                local name, header, expanded = GetSkillLineInfo(i)
                if header and not expanded then opened[#opened + 1] = name; ExpandSkillHeader(i) end
            end
        end
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
            if name and not header then out[name] = { rank or 0, max or 0 } end
        end
        if #opened > 0 and CollapseSkillHeader then
            local close = {}
            for _, n in ipairs(opened) do close[n] = true end
            for i = GetNumSkillLines(), 1, -1 do
                local name, header = GetSkillLineInfo(i)
                if header and close[name] then CollapseSkillHeader(i) end
            end
        end
    end
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local name, _, rank, max = GetProfessionInfo(idx)
                if name then out[name] = { rank or 0, max or 0 } end
            end
        end
    end
    return out
end
-- skills a route can ask about that aren't professions: riding (one skill per mount kind in Classic -
-- Horse Riding, Ram Riding...) and lockpicking
local RIDING_SPELLS = { 824, 825, 826, 828, 10861, 10906, 10907, 18995 }
local function otherSkill(key)
    if key == "riding" then
        for name, line in pairs(skillLines()) do
            if name:find("Riding$") or name:find("Horsemanship$") or name:find("Piloting$") then return true, line[1], line[2] end
        end
        if IsPlayerSpell then
            for _, id in ipairs(RIDING_SPELLS) do if IsPlayerSpell(id) then return true, 75, 75 end end
        end
        return false
    elseif key == "lockpicking" then
        local line = skillLines()["Lockpicking"]
        if line then return true, line[1], line[2] end
        return false
    end
    return nil -- not a skill we know how to read
end

function ns.profKnown(key)
    local p = PROF[key]
    if not p then return otherSkill(key) end
    local line = skillLines()[p.name]
    if line then return true, line[1], line[2] end
    if IsPlayerSpell and p.spell and IsPlayerSpell(p.spell) then return true end
    return false
end

local function count(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return f and (f(id) or 0) or 0
end

---------------------------------------------------------------- where things are
local function distTo(m, x, y, world)
    if not (ns.worldPos and ns.playerWorld) then return nil end
    local pc, px, py = ns.playerWorld()
    if not pc then return nil end
    local c, wx, wy
    if world then
        -- world coordinates (HBD order): a = world y, b = world x
        local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
        if not HBD then return nil end
        local zx, zy = HBD:GetZoneCoordinatesFromWorld(x, y, m, true)
        if not zx then return nil end
        c, wx, wy = ns.worldPos(m, zx, zy)
    else
        c, wx, wy = ns.worldPos(m, x / 100, y / 100)
    end
    if c ~= pc then return nil end
    return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
end
local function zoneXY(m, x, y, world)
    if not world then return x, y end
    local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
    if not HBD then return nil end
    local zx, zy = HBD:GetZoneCoordinatesFromWorld(x, y, m, true)
    if zx and zy then return zx * 100, zy * 100 end
end

local CITY = { [1453] = true, [1455] = true, [1457] = true, [1454] = true, [1456] = true, [1458] = true }
local function closeEnough(m, d, near)
    if not d then return false end
    return d <= near -- (a strict distance, also in cities)
end

-- does this trainer teach that rank of the profession (tier 75 = the profession itself)? What you saw when you
-- opened them decides; else what Itinerary_Data knows; else yes
local function teachesTier(npc, key, tier)
    if not tier then return true end
    local teach = ItineraryDB.profTeach and ItineraryDB.profTeach[npc]
    local list = ItineraryDB.profSpells and ItineraryDB.profSpells[key]
    if teach and list then
        local any = false
        for k in pairs(teach) do
            local e = list[k]
            if e and e[7] then
                any = true
                if e[7] == tier then return true end
            end
        end
        if any then return false end
    end
    local t = TRAINER_TIERS[npc]
    if t then return t[tier] == true end
    return true
end
ns.profTeachesTier = teachesTier

-- nearest trainer for a profession (that teaches the rank you need, when given): recorded visits first, then
-- the table
local function nearestTrainer(key, near, tier)
    local best, bd
    local my = side()
    local rec = ItineraryDB.profTrainers and ItineraryDB.profTrainers[key] or {}
    for npc, p in pairs(rec) do
        local d = distTo(p[1], p[2], p[3])
        if closeEnough(p[1], d, near) and (not bd or d < bd) and teachesTier(npc, key, tier) then
            best, bd = { npc = npc, m = p[1], x = p[2], y = p[3] }, d
        end
    end
    for _, t in ipairs(TRAINERS) do
        if t[1] == key and t[6] == my and not rec[t[2]] and teachesTier(t[2], key, tier) then
            local d = distTo(t[3], t[4], t[5])
            if closeEnough(t[3], d, near) and (not bd or d < bd) then best, bd = { npc = t[2], m = t[3], x = t[4], y = t[5] }, d end
        end
    end
    return best, bd
end
local function nearestVendor(item, near)
    local best, bd
    local rec = ItineraryDB.vendors and ItineraryDB.vendors[item] or {}
    for npc, p in pairs(rec) do
        local d = distTo(p[1], p[2], p[3])
        if closeEnough(p[1], d, near) and (not bd or d < bd) then best, bd = { npc = npc, m = p[1], x = p[2], y = p[3] }, d end
    end
    for _, v in ipairs(TOOL_VENDORS[item] or {}) do
        if v[5] == side() and not rec[v[1]] then
            local d = distTo(v[2], v[3], v[4], v.world)
            if closeEnough(v[2], d, near) and (not bd or d < bd) then
                local x, y = zoneXY(v[2], v[3], v[4], v.world)
                if x then best, bd = { npc = v[1], m = v[2], x = x, y = y }, d end
            end
        end
    end
    return best, bd
end

-- is a starting-zone quest with the gathering book still ahead on the route?
-- Forever has one in every starting zone. The ones we know (or have seen offer a book) count by quest;
-- anywhere else, while you're still in the route's first chapter and no book reward has shown up yet,
-- it's assumed to be ahead.
local bookQuestAhead
function ns.bookQuestAhead() return bookQuestAhead() end
bookQuestAhead = function()
    local c = C()
    local steps, i = ns.steps(), c.step
    local seen = ItineraryDB.bookQuests or {}
    for j = i, #steps do
        local s = steps[j]
        if s.t == "turnin" and s.q then
            for _, q in ipairs(s.q) do
                if (BOOK_QUESTS[q] or seen[q]) and not ns.quest.flaggedDone(q) then return true end
            end
        end
    end
    if c.prof and c.prof.bookSeen then return false end
    local ch = ns.chapters and ns.chapters() or {}
    return ch[2] ~= nil and i < ch[2].first
end
-- the gathering profession the book reward is for: with two gathering professions the second one (the first
-- is learned at the trainer right away), else the one you picked
local function bookProf()
    local g = {}
    for _, k in ipairs(ns.profChosen()) do if PROF[k].gather and PROF[k].book and not PROF[k].secondary then g[#g + 1] = k end end
    return g[2] or g[1]
end
ns.bookProf = bookProf

-- what a tool costs (recorded at vendors; 1 silver until we've seen one)
function ns.toolPrice(id)
    return (ItineraryDB.toolPrice and ItineraryDB.toolPrice[id]) or 100
end
-- does this profession need its tool now (you know it, or are about to learn it from the book)?
local function needsTool(k)
    local p = PROF[k]
    return p.tool and count(p.tool) == 0 and (ns.profKnown(k) or (p.book and k == ns.bookProf()))
end
-- What your money goes to, in order. Below level 4: the first profession's tool, then learning the second
-- profession, then its tool (and the class spells after that). From level 4 on, the worthwhile class
-- spells of your level come first (all of them, e.g. 2s for Blessing of Might + Judgement), then the same
-- profession order. Each purchase waits until everything before it is paid for.
local function learnCost(k)
    return (ItineraryDB.profLearnCost and ItineraryDB.profLearnCost[k]) or 10
end
function ns.spendPlan()
    local c = C()
    local lvl = UnitLevel("player") or 1
    local plan = {}
    local spells = ns.pendingSpellCost and ns.pendingSpellCost(true)
    if spells and spells > 0 and lvl >= 4 then plan[#plan + 1] = { kind = "spells", cost = spells } end
    local mainN = 0
    for _, k in ipairs((c and c.prof and c.prof.list) or {}) do
        local p = PROF[k]
        if p and not p.secondary then mainN = mainN + 1 end
        -- the second main profession (learning it, its tool) waits for level 4: before that it brings
        -- nothing, and the money goes to the class spells
        -- (the book profession is free: it and its tool never wait)
        local isBook = p and p.book and k == ns.bookProf()
        local later = p and not p.secondary and mainN >= 2 and lvl < 4 and not isBook
        if later then plan.banned = plan.banned or {}; plan.banned[k] = true end
        if p and not p.secondary and not later then
            local viaBook = p.book and k == ns.bookProf() and (count(p.book) > 0 or ns.bookQuestAhead())
            if not ns.profKnown(k) and not viaBook then
                plan[#plan + 1] = { kind = "learn", prof = k, cost = learnCost(k) }
            end
            if p.tool and count(p.tool) == 0 and not boughtHere[p.tool] then
                -- the book profession's tool can come before the book (it's learned for free right after); a
                -- trainer profession's tool too, as its learning money comes first in the plan and stays put
                -- (with two gathering professions both tools are bought at the first vendor when the money
                -- covers them and the trainer)
                local learning = not ns.profKnown(k) and not viaBook
                plan[#plan + 1] = { kind = "tool", prof = k, cost = ns.toolPrice(p.tool),
                                    wait = learning and not (lvl < 4 and p.gather) }
            end
        end
    end
    if spells and spells > 0 and lvl < 4 then plan[#plan + 1] = { kind = "spells", cost = spells } end
    -- secondary professions (cooking, first aid, fishing) last, and only with money to spare (ns.LOW_BUFFER)
    for _, k in ipairs((c and c.prof and c.prof.list) or {}) do
        local p = PROF[k]
        if p and p.secondary then
            if not ns.profKnown(k) then plan[#plan + 1] = { kind = "learn", prof = k, cost = learnCost(k), low = true } end
            if p.tool and count(p.tool) == 0 and not boughtHere[p.tool] then
                plan[#plan + 1] = { kind = "tool", prof = k, cost = ns.toolPrice(p.tool), low = true, wait = not ns.profKnown(k) }
            end
        end
    end
    return plan
end
ns.LOW_BUFFER = 1000 -- 10 silver left over before a secondary profession is worth the money
-- can you pay for this now without touching the money for what comes before it? (and what comes before)
function ns.canAfford(kind, k, money)
    money = money or (GetMoney and GetMoney() or 0)
    local before = 0
    local plan = ns.spendPlan()
    if k and plan.banned and plan.banned[k] then return false, 0 end -- second profession before level 4
    for _, it in ipairs(plan) do
        if it.kind == kind and (k == nil or it.prof == k) then
            if it.wait then return false, before end
            return money >= before + it.cost + (it.low and ns.LOW_BUFFER or 0), before
        end
        before = before + it.cost
    end
    return true, before
end
-- money to keep for the professions' part of the plan (class trainer: spells that aren't worth a trip,
-- and below level 4 the class spells too, come after it)
function ns.profReserve()
    local sum = 0
    for _, it in ipairs(ns.spendPlan()) do if it.kind ~= "spells" and not it.low then sum = sum + it.cost end end
    return sum
end

-- money to keep for the tools you still need (class trainer: utility spells come after the tools)
function ns.toolReserve()
    local sum = 0
    for _, k in ipairs(ns.profChosen()) do
        if needsTool(k) then sum = sum + ns.toolPrice(PROF[k].tool) end
    end
    return sum
end

-- Recommendations next to the current step (they never block it): a profession book in your bags
local NEAR = 400 -- yards (or the same city) for a trainer / vendor stop to be worth it
function ns.profRecommend()
    local out = {}
    local c = C()
    if not (c and c.prof and c.prof.list) then return out end
    for _, k in ipairs(c.prof.list) do
        local p = PROF[k]
        if p.book and count(p.book) > 0 and not ns.profKnown(k) then
            out[#out + 1] = { label = "Learn " .. p.name, desc = "Use the book from the quest reward: click it next to the panel", item = p.book }
        end
        -- a secondary profession you picked, its trainer close by: a recommendation (it doesn't take you there)
        -- when it's paid for without touching the money for your next class skills
        if p.secondary and not ns.profKnown(k) then
            local cost = ItineraryDB.profLearnCost and ItineraryDB.profLearnCost[k] or 100
            local spare = (GetMoney and GetMoney() or 0) - (ns.pendingSpellCost and ns.pendingSpellCost() or 0)
            local t, d = nearestTrainer(k, NEAR, 75)
            -- only once it's paid for (what comes first keeps its money); no money, no instruction
            if t and (ns.canAfford("learn", k) or cost <= spare) then
                out[#out + 1] = { label = "Learn " .. p.name .. " at " .. t.npc, prof = k,
                    desc = "Opening the trainer learns it.",
                    go = { m = t.m, x = t.x, y = t.y, npc = t.npc } }
            end
        end
        -- the next rank (Journeyman, Expert, Artisan) is learnable now and its trainer is close
        local known, rank, max = ns.profKnown(k)
        local RANK = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }
        -- (secondary professions get Expert from a book, not a trainer)
        if known and RANK[max] and not (p.secondary and max == 150) and ns.profRankReady(rank, max) then
            local t = nearestTrainer(k, NEAR, max + 75)
            -- and you can pay for it (its price from that trainer, or any trainer of the profession)
            local price
            if t then
                for _, who in ipairs({ t.npc, false }) do
                    for _, e in ipairs((ns.profLearnable(k, who or nil))) do
                        if e.tier == max + 75 and not price then price = e.cost end
                    end
                end
            end
            if t and price and price > (GetMoney and GetMoney() or 0) then t = nil end
            if t then
                out[#out + 1] = { label = "Learn " .. RANK[max] .. " " .. p.name .. " at " .. t.npc, prof = k,
                    desc = string.format("Your %s is %d/%d: the next rank is ready. %s", p.name, rank, max,
                        (ItineraryDB.auto and ItineraryDB.auto.profLearn ~= false) and "Opening the trainer learns it." or "Learn it at the trainer."),
                    go = { m = t.m, x = t.x, y = t.y, npc = t.npc } }
            end
        end
    end
    return out
end

---------------------------------------------------------------- the detour step
function ns.profDetour()
    local c = C()
    if not (c and c.prof and c.prof.list) then return nil end
    local lvl = UnitLevel("player") or 1
    if c.prof.skip == lvl then return nil end
    -- 2) a profession you picked but haven't learned, trainer close by
    for _, k in ipairs(c.prof.list) do
        local p = PROF[k]
        local waitForBook = p.gather and k == bookProf() and bookQuestAhead()
        if not waitForBook and not ns.profKnown(k) and not p.secondary and ns.canAfford("learn", k) then
            local t, d = nearestTrainer(k, NEAR, 75)
            if t then
                return { t = "train", detour = true, prof = k, npc = t.npc, m = t.m, x = t.x, y = t.y, dist = d,
                         name = "Learn " .. p.name, note = p.name .. " trainer" }
            end
        end
    end
    -- 3) the tool for a profession you picked, when the plan says it's its turn and a vendor is close
    for _, k in ipairs(c.prof.list) do
        local p = PROF[k]
        if p.tool and count(p.tool) == 0 and not p.secondary and ns.canAfford("tool", k) then
            local v, d = nearestVendor(p.tool, NEAR)
            if v then
                return { t = "do", detour = true, prof = k, npc = v.npc, m = v.m, x = v.x, y = v.y, dist = d,
                         col = { { p.tool, 1 } }, name = "Buy a " .. (TOOLNAME[p.tool] or "tool"),
                         note = "Needed for " .. p.name }
            end
        end
    end
    return nil
end

-- A route visit to a profession trainer is done once you know the profession; it's passed while the
-- spend plan has no money for it yet (a detour picks it up later when you're close and can pay)
local TRAINER_PROF_OF, TRAINER_PROF_SET
function ns.profStepDone(s)
    if not (s.t == "train" and not s.cls and s.npc) then return nil end
    local k = TRAINER_PROF_OF(s.npc)
    if not k or not chosen(k) then return nil end
    return ns.profKnown(k) or not ns.canAfford("learn", k)
end

-- a route's profession steps (train at a profession trainer, buy a mining pick) only for professions you picked
local TRAINER_PROF = {}
TRAINER_PROF_OF = function(npc) return TRAINER_PROF[npc] end
TRAINER_PROF_SET = function(npc, k) TRAINER_PROF[npc] = k end
-- trainers you've found yourself count too (filled in at login)
function ns.profLoadRecorded()
    for k, list in pairs(ItineraryDB.profTrainers or {}) do
        for npc in pairs(list) do if not TRAINER_PROF[npc] then TRAINER_PROF[npc] = k end end
    end
end
function ns.addProfTrainers(list)
    for _, t in ipairs(list or {}) do
        TRAINERS[#TRAINERS + 1] = t
        if not TRAINER_PROF[t[2]] then TRAINER_PROF[t[2]] = t[1] end
        -- (Itinerary_Data 1.2: the ranks the trainer teaches, { 75 } or { 225 }; none = all of them)
        if type(t[7]) == "table" then
            local set = {}
            for _, tier in ipairs(t[7]) do set[tier] = true end
            TRAINER_TIERS[t[2]] = set
        end
    end
end
-- the profession a trainer teaches (known trainers, or ones you've found yourself)
function ns.profOfNpc(npc) return npc and TRAINER_PROF[npc] end

---------------------------------------------------------------- what a profession trainer teaches
-- Recorded whenever you open a profession trainer, for all your characters:
-- ItineraryDB.profSpells[prof]["name:rank"] = { name, level, cost, rank, skill, icon, tier }
-- (tier: the cap a profession rank gives - 75 Apprentice, 150 Journeyman, 225 Expert, 300 Artisan; nil for a
-- recipe). Trainers of one profession don't all teach the same (cooks have their own recipes, a junior
-- trainer stops at Journeyman), so each trainer's own list is kept too: ItineraryDB.profTeach[npc][key] = true. What each character already knows: the trainer's "used" entries and the recipes in its
-- profession window (c.prof.used / c.prof.recipes).
local TIER = { Apprentice = 75, Journeyman = 150, Expert = 225, Artisan = 300 }
local function tierOf(k, name, rank)
    local p = PROF[k]
    for word, cap in pairs(TIER) do
        if (name and name:find("^" .. word .. " ")) or rank == word then return cap end
    end
    if name == p.name then return 75 end
end
local function serviceInfo(i)
    local n1, n2, n3 = GetTrainerServiceInfo(i)
    if n2 == "available" or n2 == "unavailable" or n2 == "used" then return n1, nil, n2 end
    return n1, n2, n3
end
local function recordProfServices(k)
    if not (GetNumTrainerServices and k) then return end
    local g, c = ItineraryDB, C()
    g.profSpells = g.profSpells or {}
    local list = g.profSpells[k] or {}
    g.profSpells[k] = list
    c.prof = c.prof or {}
    c.prof.used = c.prof.used or {}
    local used = c.prof.used[k] or {}
    c.prof.used[k] = used
    local npc = UnitName("npc")
    local teach
    if npc then
        g.profTeach = g.profTeach or {}
        teach = {}
    end
    for i = 1, (GetNumTrainerServices() or 0) do
        local name, rank, cat = serviceInfo(i)
        if name and cat and cat ~= "header" then
            rank = rank or ""
            local key = name .. ":" .. rank
            local skill = 0
            if GetTrainerServiceSkillReq then
                local _, need = GetTrainerServiceSkillReq(i)
                skill = tonumber(need) or 0
            end
            local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 1
            local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil
            list[key] = { name, level or 1, GetTrainerServiceCost(i) or 0, rank, skill, icon, tierOf(k, name, rank ~= "" and rank or nil) }
            if cat == "used" then used[key] = true end
            if teach then teach[key] = true end
        end
    end
    -- (a scan with some filters still off sees part of the list: add to what this trainer teaches)
    if teach and next(teach) then
        local cur = g.profTeach[npc] or {}
        for key in pairs(teach) do cur[key] = true end
        g.profTeach[npc] = cur
    end
end
-- the whole list: every filter on for a moment (the window hides what you know or can't learn yet)
local profRestore
local function scanProfTrainer(k)
    if profRestore then return end
    local was = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs({ "available", "unavailable", "used" }) do
            if not GetTrainerServiceTypeFilter(f) then was[#was + 1] = f end
        end
    end
    if #was == 0 then pcall(recordProfServices, k) return end
    for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 1) end
    profRestore = function()
        profRestore = nil
        for _, f in ipairs(was) do pcall(SetTrainerServiceTypeFilter, f, 0) end
    end
    C_Timer.After(0.5, function()
        if not profRestore then return end
        if (GetNumTrainerServices and GetNumTrainerServices() or 0) > 0 then pcall(recordProfServices, k) end
        profRestore()
    end)
end
-- the recipes in an open profession window count as known
local function recordRecipes()
    local c = C()
    if not c then return end
    local function save(line, names)
        local k
        for key, p in pairs(PROF) do if p.name == line then k = key end end
        if not k then return end
        c.prof = c.prof or {}
        c.prof.recipes = c.prof.recipes or {}
        local r = c.prof.recipes[k] or {}
        c.prof.recipes[k] = r
        for _, n in ipairs(names) do r[n] = true end
    end
    if TradeSkillFrame and TradeSkillFrame:IsShown() and GetTradeSkillLine and GetNumTradeSkills then
        local names = {}
        for i = 1, (GetNumTradeSkills() or 0) do
            local n, kind = GetTradeSkillInfo(i)
            if n and kind ~= "header" then names[#names + 1] = n end
        end
        save((GetTradeSkillLine()), names)
    end
    if CraftFrame and CraftFrame:IsShown() and GetNumCrafts and GetCraftInfo then
        local names = {}
        for i = 1, (GetNumCrafts() or 0) do
            local n, _, kind = GetCraftInfo(i)
            if n and kind ~= "header" then names[#names + 1] = n end
        end
        local line = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or (GetCraftSkillLine and GetCraftSkillLine(1))
        save(line, names)
    end
end

-- What a profession trainer has for you now: { name, rank, cost, level, skill, icon, tier } - the profession
-- (or its next rank) first, then recipes by skill. With npc: only what that trainer teaches; a trainer you
-- haven't opened yet gets the profession and its ranks only (its recipes are unknown).
-- Also returns whether that trainer's list (or, without npc, anything of this profession) is known.
function ns.profLearnable(k, npc)
    local p = PROF[k]
    if not p then return {}, false end
    local c = C()
    local lvl = UnitLevel("player") or 1
    local known, rank, max = ns.profKnown(k)
    rank, max = rank or 0, max or 0
    local list = ItineraryDB.profSpells and ItineraryDB.profSpells[k] or {}
    local used = c and c.prof and c.prof.used and c.prof.used[k] or {}
    local recipes = c and c.prof and c.prof.recipes and c.prof.recipes[k] or {}
    local teach = npc and ItineraryDB.profTeach and ItineraryDB.profTeach[npc]
    local out, hasApprentice = {}, false
    for key, e in pairs(list) do
        -- that trainer's own list (unknown: the ranks it teaches)
        if not npc or (teach and teach[key]) or (not teach and e[7] and teachesTier(npc, k, e[7])) then
            local name, level, cost, rk, skill, icon, tier = e[1], e[2] or 1, e[3] or 0, e[4], e[5] or 0, e[6], e[7]
            local ok
            if tier then
                if tier == 75 then hasApprentice = true end
                -- the profession itself when you don't have it, else the rank after yours
                ok = (not known and tier == 75) or (known and max > 0 and tier == max + 75 and rank >= skill)
            else
                ok = known and rank >= skill and not used[key] and not recipes[name]
            end
            if ok and level <= lvl then
                out[#out + 1] = { name = name, rank = rk, cost = cost, level = level, skill = skill, icon = icon or 134400, tier = tier }
            end
        end
    end
    -- nothing recorded yet: the profession itself, with the price we know (or none)
    if not known and not hasApprentice and (not npc or teachesTier(npc, k, 75)) then
        local cost = ItineraryDB.profLearnCost and ItineraryDB.profLearnCost[k]
        out[#out + 1] = { name = p.name, rank = "Apprentice", cost = cost, level = 1, skill = 0, tier = 75,
                          icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(p.spell))
                              or (GetSpellTexture and GetSpellTexture(p.spell)) or 134400 }
    end
    table.sort(out, function(a, b)
        if (a.tier ~= nil) ~= (b.tier ~= nil) then return a.tier ~= nil end
        if a.skill ~= b.skill then return a.skill < b.skill end
        return a.name < b.name
    end)
    if npc then return out, teach ~= nil end
    return out, next(list) ~= nil
end
local TOOL_PROF = {}
for k, p in pairs(PROF) do if p.tool then TOOL_PROF[p.tool] = k end end
local scanMerchant = nil
function ns.profStepIrrelevant(s)
    local c = C()
    if not (c and c.prof and c.prof.list) then return false end
    if s.t == "train" and not s.cls and s.npc and TRAINER_PROF[s.npc] then
        return not chosen(TRAINER_PROF[s.npc])
    end
    if s.col then
        for _, cc in ipairs(s.col) do
            local k = TOOL_PROF[cc[1]]
            if k and not chosen(k) then return true end
        end
    end
    return false
end

---------------------------------------------------------------- reminder below the panel
-- every 10 levels, near a trainer of a profession you have: new ranks and recipes to look at
local HINT_NEAR = 150
-- the next rank (Journeyman 150, Expert 225, Artisan 300) is learnable 25 points before your cap and from a
-- character level: Journeyman at skill 50 and level 10, Expert at 125 and 20, Artisan at 200 and 35
local NEXT_RANK_LEVEL = { [75] = 10, [150] = 20, [225] = 35 }
function ns.profRankReady(rank, max, lvl)
    if not (rank and max and max > 0) then return false end -- skill not readable: no way to tell, stay quiet
    local need = NEXT_RANK_LEVEL[max]
    if not need then return false end -- already Artisan (or an odd cap)
    return rank >= max - 25 and (lvl or UnitLevel("player") or 1) >= need
end
function ns.profHint()
    local c = C()
    if not (c and c.prof and c.prof.list) then return nil end
    local lvl = UnitLevel("player") or 1
    local bucket = math.floor(lvl / 10) * 10
    if bucket < 10 then return nil end
    c.prof.seen = c.prof.seen or {}
    for _, k in ipairs(c.prof.list) do
        local known, rank, max = ns.profKnown(k)
        if known and (c.prof.seen[k] or 0) < bucket and ns.profRankReady(rank, max, lvl) then
            local t, d = nearestTrainer(k, HINT_NEAR, max + 75)
            if t then
                local skill = rank and max and max > 0 and string.format(" (%d/%d)", rank, max) or ""
                return string.format("%s%s · %s %d yd — new ranks and recipes", PROF[k].name, skill, t.npc, math.floor(d)), k
            end
        end
    end
end

---------------------------------------------------------------- events: trainers, vendors, quest rewards
local function playerPos()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    return map, x * 100, y * 100
end
local function profOfTrainer()
    local npc = UnitName("npc")
    if npc and TRAINER_PROF[npc] then return TRAINER_PROF[npc] end
    for i = 1, (GetNumTrainerServices and GetNumTrainerServices() or 0) do
        local line = GetTrainerServiceSkillLine and GetTrainerServiceSkillLine(i)
        local name = GetTrainerServiceInfo and GetTrainerServiceInfo(i)
        for k, p in pairs(PROF) do if line == p.name or name == p.name then return k end end
    end
    local rec = ItineraryDB.profTrainers
    for k, list in pairs(rec or {}) do if npc and list[npc] then return k end end
end
ns.profOfTrainer = function() return profOfTrainer() end

-- Trainers the data doesn't know yet (Forever adds new ones, like "<Junior Mining Trainer>" in Anvilmar):
-- remember where they stand as soon as you target or mouse over one. Opening the trainer records the
-- exact spot. Saved for all your characters.
local scanTip
local function unitTitle(unit)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit(unit)
        for n = 2, math.min(3, data and data.lines and #data.lines or 0) do
            local t = data.lines[n].leftText
            if t and t:find("Trainer") then return t end
        end
        return nil
    end
    scanTip = scanTip or CreateFrame("GameTooltip", "ItineraryScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetUnit(unit)
    for n = 2, math.min(3, scanTip:NumLines() or 0) do
        local fs = _G["ItineraryScanTipTextLeft" .. n]
        local t = fs and fs:GetText()
        if t and t:find("Trainer") then return t end
    end
end
local function noteTrainerUnit(unit)
    if not (UnitExists(unit) and not UnitIsPlayer(unit)) then return end
    local title = unitTitle(unit)
    if not title then return end
    local npc = UnitName(unit)
    for k, p in pairs(PROF) do
        if title:find(p.name, 1, true) then
            ItineraryDB.profTrainers = ItineraryDB.profTrainers or {}
            ItineraryDB.profTrainers[k] = ItineraryDB.profTrainers[k] or {}
            if npc and not ItineraryDB.profTrainers[k][npc] then
                local m, x, y = playerPos()
                if m then
                    ItineraryDB.profTrainers[k][npc] = { m, x, y, seen = true }
                    TRAINER_PROF_SET(npc, k)
                    if ns.update then ns.update() end
                end
            end
            return
        end
    end
end

-- the reward choice that is the book for your gathering profession
local BOOK_ITEM = {}
for _, p in pairs(PROF) do if p.book then BOOK_ITEM[p.book] = true end end
function ns.bookRewardIndex()
    -- remember quests that offer a gathering book (for the next character), and that this one got its chance
    for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id and BOOK_ITEM[id] then
            local q = GetQuestID and GetQuestID()
            if q and q > 0 then ItineraryDB.bookQuests = ItineraryDB.bookQuests or {}; ItineraryDB.bookQuests[q] = true end
            local c = C(); if c and c.prof then c.prof.bookSeen = true end
            break
        end
    end
    local k = bookProf()
    if not k or ns.profKnown(k) then return nil end
    local want = PROF[k].book
    for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do
        local link = GetQuestItemLink and GetQuestItemLink("choice", i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id == want then return i end
    end
end

local f = CreateFrame("Frame")
---------------------------------------------------------------- vendors: tool prices and buying
-- C_MerchantFrame.GetItemInfo returns a table on newer clients (Forever); GetMerchantItemInfo values on older ones
local function merchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if type(t) == "table" then return t.name, t.price end
    end
    if GetMerchantItemInfo then
        local name, _, price = GetMerchantItemInfo(i)
        return name, price
    end
end
local TOOL_BY_NAME = {}
for id, n in pairs(TOOLNAME) do TOOL_BY_NAME[n] = id end
scanMerchant = function()
    if not (MerchantFrame and MerchantFrame:IsShown()) and not ns.testMerchant then return end
    local m, x, y = playerPos()
    local npc = UnitName("npc")
    local here = {} -- tool id -> { slot, price }
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        if not id then
            local link = GetMerchantItemLink and GetMerchantItemLink(i)
            id = link and tonumber(link:match("item:(%d+)"))
        end
        local name, price = merchantInfo(i)
        -- Forever may use its own item ids: match the tool by name too
        if not (id and TOOL_PROF[id]) and name and TOOL_BY_NAME[name] then id = TOOL_BY_NAME[name] end
        if id and TOOL_PROF[id] then
            here[id] = { i, price }
            if m and npc then
                ItineraryDB.vendors = ItineraryDB.vendors or {}
                ItineraryDB.vendors[id] = ItineraryDB.vendors[id] or {}
                ItineraryDB.vendors[id][npc] = { m, x, y }
            end
            if price and price > 0 then
                ItineraryDB.toolPrice = ItineraryDB.toolPrice or {}
                ItineraryDB.toolPrice[id] = price
            end
        end
    end
    -- buy the tools for the professions you picked, in the order of the spend plan (ns.spendPlan)
    local a = ItineraryDB.auto
    if a and a.tools ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) then
        local money = GetMoney() or 0
        for _, it in ipairs(ns.spendPlan()) do
            if it.kind == "tool" then
                local id = PROF[it.prof].tool
                local h = here[id]
                if h then
                    local ok, before = ns.canAfford("tool", it.prof, money)
                    if ok then
                        BuyMerchantItem(h[1], 1)
                        boughtHere[id] = true
                        money = money - (h[2] or it.cost)
                        ns.print("bought a " .. (TOOLNAME[id] or "tool") .. " for " .. PROF[it.prof].name)
                    elseif it.wait then
                        -- not learned yet: comes after learning it
                    elseif not boughtHere.told then
                        boughtHere.told = true
                        local first = ns.spendPlan()[1]
                        local why = (first and first.kind == "spells") and "your new class spells come first"
                            or (first and first.kind == "learn") and ("learning " .. PROF[first.prof].name .. " comes first")
                            or (first and first.kind == "tool" and first.prof ~= it.prof) and ("the " .. (TOOLNAME[PROF[first.prof].tool] or "tool") .. " comes first")
                            or "not enough money"
                        ns.print("not buying a " .. (TOOLNAME[id] or "tool") .. " yet: " .. why)
                    end
                end
            end
        end
    end
    if ns.update then ns.update() end
end

for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_MONEY", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LOGIN" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if not (ItineraryDB and ItineraryCharDB) then return end
    local c = C()
    if event == "PLAYER_LOGIN" then
        ns.profLoadRecorded()
        c.prof = c.prof or {}
        if not c.prof.asked then C_Timer.After(3, function() if ns.showProfPicker then ns.showProfPicker() end end) end
        return
    end
    if event == "TRAINER_SHOW" then
        C_Timer.After(0.3, function()
            -- a profession trainer, known by name, by what it teaches, or by its title ("<Junior Mining Trainer>")
            local k = profOfTrainer()
            if not k then return end
            local m, x, y = playerPos()
            if m then
                ItineraryDB.profTrainers = ItineraryDB.profTrainers or {}
                ItineraryDB.profTrainers[k] = ItineraryDB.profTrainers[k] or {}
                ItineraryDB.profTrainers[k][UnitName("npc") or "?"] = { m, x, y }
            end
            c.prof = c.prof or {}
            c.prof.seen = c.prof.seen or {}
            c.prof.seen[k] = math.floor((UnitLevel("player") or 1) / 10) * 10
            -- learn the profession itself (or its next rank) if it's one you picked
            local a = ItineraryDB.auto
            -- (its own switch: learning a profession you picked doesn't wait for "Buy class skills")
            if chosen(k) and a and a.profLearn ~= false and not (IsShiftKeyDown and IsShiftKeyDown()) then
                local found = false
                for i = 1, (GetNumTrainerServices() or 0) do
                    local n1, n2, n3 = GetTrainerServiceInfo(i)
                    local cat = (n2 == "available" or n2 == "unavailable" or n2 == "used") and n2 or n3
                    local cost = GetTrainerServiceCost(i) or 0
                    -- the profession itself ("Mining", maybe with a rank word around it), not a recipe
                    -- or its rank at this trainer: Forever lists Cooking as "Apprentice Cook", "Journeyman Cook"...
                    local isProf = n1 and (n1 == PROF[k].name or n1:find(PROF[k].name, 1, true)
                        or n1:find("^Apprentice ") or n1:find("^Journeyman ") or n1:find("^Expert ") or n1:find("^Artisan "))
                    if isProf and cat == "available" then
                        found = true
                        if not ns.profKnown(k) then
                            ItineraryDB.profLearnCost = ItineraryDB.profLearnCost or {}
                            ItineraryDB.profLearnCost[k] = cost
                        end
                        local ok = ns.profKnown(k) and cost <= (GetMoney() or 0) or ns.canAfford("learn", k)
                        -- a secondary profession (Cooking, First Aid, Fishing) at a trainer you opened yourself:
                        -- learn it when it's paid for without touching the money for your next class spells
                        -- (the "10 silver to spare" rule is only for sending you there)
                        if not ok and PROF[k].secondary then
                            ok = cost <= (GetMoney() or 0) - (ns.pendingSpellCost and ns.pendingSpellCost() or 0)
                        end
                        if ok then
                            BuyTrainerService(i)
                            ns.print("learned " .. n1 .. (cost > 0 and ("  " .. (GetCoinTextureString and GetCoinTextureString(cost) or cost)) or ""))
                        else
                            local _, before = ns.canAfford("learn", k)
                            ns.print("not learning " .. n1 .. " yet: keeping " .. (GetCoinTextureString and GetCoinTextureString(before) or before) .. " for what comes first")
                        end
                        break
                    end
                end
                if not found and not ns.profKnown(k) then
                    local list = {}
                    for i = 1, (GetNumTrainerServices() or 0) do
                        local n1, n2, n3 = GetTrainerServiceInfo(i)
                        list[#list + 1] = tostring(n1) .. ":" .. tostring((n2 == "available" or n2 == "unavailable" or n2 == "used") and n2 or n3)
                    end
                    ns.print(PROF[k].name .. " trainer, but nothing to learn found: " .. table.concat(list, ", "))
                end
            end
            C_Timer.After(0.3, function() if ClassTrainerFrame and ClassTrainerFrame:IsShown() then scanProfTrainer(k) end end)
            if ns.update then ns.update() end
        end)
    elseif event == "TRAINER_UPDATE" then
        -- something learned while the trainer is open: its list changed
        local k = not profRestore and ClassTrainerFrame and ClassTrainerFrame:IsShown() and profOfTrainer()
        if k then pcall(recordProfServices, k) end
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        C_Timer.After(0.2, function() pcall(recordRecipes) end)
    elseif event == "MERCHANT_SHOW" then
        wipe(boughtHere)
        -- after junk has been sold (Automation.lua), so the money from it counts
        C_Timer.After(0.5, scanMerchant)
    elseif event == "PLAYER_TARGET_CHANGED" then
        noteTrainerUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        noteTrainerUnit("mouseover")
    elseif event == "MERCHANT_CLOSED" then
        -- the bags know about the purchases by now
        C_Timer.After(1, function() if not (MerchantFrame and MerchantFrame:IsShown()) then wipe(boughtHere) end end)
    elseif event == "PLAYER_MONEY" then
        -- more money while the vendor is open (junk sold): try the tools again
        if MerchantFrame and MerchantFrame:IsShown() then C_Timer.After(0.2, scanMerchant) end
    else
        if ns.update then ns.update() end
    end
end)

---------------------------------------------------------------- the picker
local picker
local function accent() return ns.accent() end
local function label(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(r, g, b, a or 1)
    fs:SetJustifyH("LEFT")
    return fs
end
local function buildPicker()
    local ar, ag, ab = accent()
    picker = CreateFrame("Frame", "ItineraryProfPicker", UIParent)
    picker:SetSize(380, 330)
    picker:SetPoint("CENTER", 0, 80)
    picker:SetFrameStrata("DIALOG")
    picker:EnableMouse(true); picker:SetMovable(true); picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    local bg = picker:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(ns.themeBg(0.96))
    local top = picker:CreateTexture(nil, "ARTWORK"); top:SetColorTexture(ar, ag, ab, 0.9)
    top:SetPoint("TOPLEFT", 1, -1); top:SetPoint("TOPRIGHT", -1, -1); top:SetHeight(2)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = picker:CreateTexture(nil, "OVERLAY"); t:SetColorTexture(1, 1, 1, 0.15)
        t:SetPoint(p[1]); t:SetPoint(p[2]); if p[3] then t:SetHeight(1) else t:SetWidth(1) end
    end
    local h = label(picker, 11, ar, ag, ab, 0.9); h:SetPoint("TOPLEFT", 16, -14); h:SetText("ITINERARY")
    local t = label(picker, 16, 1, 1, 1, 1); t:SetPoint("TOPLEFT", 16, -30); t:SetText("Your professions")
    local sub = label(picker, 11, 1, 1, 1, 0.55); sub:SetPoint("TOPLEFT", 16, -52); sub:SetWidth(348)
    sub:SetText("Pick up to two main professions; the one you tick first is your 1st (Swap changes it). The 1st gets the quest reward book if it gathers, and its tool first.")
    picker.checks = {}
    local function add(key, x, y)
        local cb = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
        cb:SetSize(22, 22); cb:SetPoint("TOPLEFT", x, y)
        cb.key = key
        cb.text = label(cb, 12, 1, 1, 1, 0.9); cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(PROF[key].name .. (PROF[key].gather and "  |cff888888gathering|r" or ""))
        -- "1st" / "2nd": which main profession comes first (book, trainer, tool); click order, or the Swap button
        cb.badge = label(cb, 10, ar, ag, ab, 0.95)
        cb.badge:SetPoint("LEFT", cb.text, "RIGHT", 6, 0)
        cb:SetScript("OnClick", function(self)
            if not PROF[key].secondary then
                for n = #picker.order, 1, -1 do if picker.order[n] == key then table.remove(picker.order, n) end end
                if self:GetChecked() then picker.order[#picker.order + 1] = key end
            end
            picker.refresh()
        end)
        picker.checks[#picker.checks + 1] = cb
    end
    local h1 = label(picker, 10, ar, ag, ab, 0.75); h1:SetPoint("TOPLEFT", 16, -92); h1:SetText("MAIN (UP TO TWO)")
    for n, k in ipairs(PRIMARY) do
        local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
        add(k, 14 + col * 175, -106 - row * 24)
    end
    local h2 = label(picker, 10, ar, ag, ab, 0.75); h2:SetPoint("TOPLEFT", 16, -232); h2:SetText("SECONDARY")
    for n, k in ipairs(SECONDARY) do add(k, 14 + (n - 1) * 118, -246) end
    picker.order = {}
    local swap = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    swap:SetSize(110, 22); swap:SetPoint("BOTTOMLEFT", 14, 14); swap:SetText("Swap 1st / 2nd")
    swap:SetScript("OnClick", function()
        local o = picker.order
        if #o == 2 then o[1], o[2] = o[2], o[1] end
        picker.refresh()
    end)
    picker.swap = swap
    picker.refresh = function()
        for _, cb in ipairs(picker.checks) do
            local pos
            for n, k in ipairs(picker.order) do if k == cb.key then pos = n end end
            cb.badge:SetText(pos == 1 and "1st" or pos == 2 and "2nd" or "")
        end
        swap:SetShown(#picker.order == 2)
        local main = 0
        for _, cb in ipairs(picker.checks) do if cb:GetChecked() and not PROF[cb.key].secondary then main = main + 1 end end
        for _, cb in ipairs(picker.checks) do
            if not PROF[cb.key].secondary then
                local on = cb:GetChecked() or main < 2
                cb:SetEnabled(on); cb.text:SetAlpha(on and 1 or 0.35)
            end
        end
    end
    local save = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    save:SetSize(110, 22); save:SetPoint("BOTTOMRIGHT", -14, 14); save:SetText("Save")
    save:SetScript("OnClick", function()
        local c = C()
        c.prof = c.prof or {}
        c.prof.list, c.prof.asked = {}, true
        -- main ones in the order you set (1st, 2nd), then the secondary ones
        for _, k in ipairs(picker.order) do table.insert(c.prof.list, k) end
        for _, cb in ipairs(picker.checks) do
            if cb:GetChecked() and PROF[cb.key].secondary then table.insert(c.prof.list, cb.key) end
        end
        picker:Hide()
        local names = {}
        for _, k in ipairs(c.prof.list) do names[#names + 1] = PROF[k].name end
        ns.print(#names > 0 and ("professions: " .. table.concat(names, ", ")) or "no professions picked")
        if ns.update then ns.update() end
        if ns.refreshSettings then ns.refreshSettings() end
    end)
    local later = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    later:SetSize(110, 22); later:SetPoint("RIGHT", save, "LEFT", -6, 0); later:SetText("Later")
    later:SetScript("OnClick", function() picker:Hide(); ns.print("pick your professions any time with /iti professions") end)
    picker:Hide()
end
function ns.showProfPicker()
    if not picker then buildPicker() end
    local list = ns.profChosen()
    picker.order = {}
    for _, k in ipairs(list) do if PROF[k] and not PROF[k].secondary then picker.order[#picker.order + 1] = k end end
    -- a character that hasn't picked yet: Cooking and First Aid start ticked
    local fresh = not (C().prof and C().prof.asked) and #list == 0
    for _, cb in ipairs(picker.checks) do
        local on = fresh and (cb.key == "cooking" or cb.key == "firstaid") or false
        for _, k in ipairs(list) do if k == cb.key then on = true end end
        cb:SetChecked(on)
    end
    picker.refresh()
    picker:Show()
end

---------------------------------------------------------------- gathering: node icons and tracking
-- Herbs and ore can't get the quest sparkle (only the game gives that, to quest objects). Two things that do
-- help, both in Settings > Professions:
-- * Node icons: the game's soft-target interact icons - an icon floats over the herb, vein or chest in
--   front of you when you're close (SoftTargetInteract and friends). Your own values come back when off.
-- * Gathering tracking: when no minimap tracking is on (after login or dying), Find Herbs / Find Minerals
--   for your gathering profession is switched on. Tracking you picked yourself is left alone.
local SOFT = { SoftTargetInteract = "3", SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1",
               SoftTargetInteractArc = "2", SoftTargetInteractRange = "45" }
-- (Arc 2: all around you, not only straight ahead of the camera. The game draws the icons up to about 20 yards
-- whatever the range says - the range is kept high in case a client allows more.)
local function getCV(k)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(k) end
    return GetCVar and GetCVar(k)
end
local function setCV(k, v)
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, k, v) elseif SetCVar then pcall(SetCVar, k, v) end
end
function ns.applyNodeIcons(say)
    local a = ItineraryDB and ItineraryDB.auto
    if not a then return end
    if getCV("SoftTargetInteract") == nil then
        if say then ns.print("node icons: this game client doesn't have the interact icons (SoftTargetInteract)") end
        return
    end
    if a.nodeIcons ~= false then -- on unless switched off
        if not a.nodeIconsSaved then
            a.nodeIconsSaved = {}
            -- (your own values: the name tags may have changed some of them first)
            for k in pairs(SOFT) do
                local tv = a.objTagsSaved and a.objTagsSaved[k]
                if tv ~= nil then a.nodeIconsSaved[k] = tv else a.nodeIconsSaved[k] = getCV(k) or false end
            end
        end
        for k, v in pairs(SOFT) do if getCV(k) ~= nil then setCV(k, v) end end
        -- the game may cap the range: say what it took
        if say then ns.print("node icons on: the nearest herb, vein or chest within about 20 yards, any direction") end
    elseif a.nodeIconsSaved then
        for k, v in pairs(a.nodeIconsSaved) do if v then setCV(k, v) end end
        a.nodeIconsSaved = nil
        if ns.applyObjTags then ns.applyObjTags() end -- (name tags need two of them)
    end
end

---------------------------------------------------------------- object name tags
-- The game can give the one object you'd interact with (the "softinteract" unit) a nameplate with its name
-- (SoftTargetNameplateInteract). Itinerary opens that nameplate only for the objects you want named - quest
-- objects, or every object - so NPCs, doors and mailboxes don't get one, and puts the quest objective under a
-- quest object's name. In combat it's closed: the game won't change these settings there, and an open one sits
-- on every lootable corpse. Settings > Quests > Object name tags (ItineraryDB.auto.objTags: quest/all/off).
local TAG_CV = "SoftTargetNameplateInteract"
-- (no nameplate without the icon; all around you, not only ahead; and objects beyond reach too - the game still
-- picks only within about 15-20 yards, whatever the range says)
local TAG_BASE = { SoftTargetInteract = "3", SoftTargetIconGameObject = "1", SoftTargetInteractArc = "2",
                   SoftTargetInteractRange = "45", SoftTargetInteractOnlyInRange = "0" }
local tag = { guid = false, open = false, combat = false, line = false, kind = "none" }
ns.objTagState = tag
local function tagMode()
    local a = ItineraryDB and ItineraryDB.auto
    local m = a and a.objTags
    if m == "all" or m == "off" then return m end
    return "quest"
end
-- NaowhForever QoL's Glimmer opens the same nameplate for what it lights up: while it's on, it's left to Glimmer
local function glimmerOn()
    local nf = rawget(_G, "NaowhForever")
    local gs = type(nf) == "table" and rawget(nf, "GlimmerSettings")
    return type(gs) == "table" and gs.enabled == true
end
ns.objTagsByGlimmer = glimmerOn
local function tagsActive() return tagMode() ~= "off" and not glimmerOn() and getCV(TAG_CV) ~= nil end
-- (the game answers UnitExists with no for an object as the soft target: its GUID is what says one is there)
local function softGUID(u)
    local ok, g = pcall(UnitGUID, u)
    return ok and type(g) == "string" and g ~= "" and g or false
end
local function isObject(u)
    if type(UnitIsGameObject) == "function" then
        local ok, r = pcall(UnitIsGameObject, u)
        if ok then return r and true or false end
    end
    local g = UnitGUID(u)
    return type(g) == "string" and g:find("^GameObject%-") ~= nil
end
-- the quest objective lines of the object's tooltip ("Gold Dust: 3/10")
local function objectiveLines(u)
    local out, TI = {}, C_TooltipInfo
    if not (type(TI) == "table" and type(TI.GetUnit) == "function") then return out end
    local ok, data = pcall(TI.GetUnit, u)
    if not (ok and type(data) == "table" and type(data.lines) == "table") then return out end
    local QO = type(Enum) == "table" and type(Enum.TooltipDataLineType) == "table" and Enum.TooltipDataLineType.QuestObjective
    for i, l in ipairs(data.lines) do
        local t = type(l) == "table" and l.leftText
        if i > 1 and type(t) == "string" and t ~= "" and ((QO and l.type == QO) or t:find("%d+/%d+")) then
            out[#out + 1] = (t:gsub("^%s*%-%s*", ""))
        end
    end
    return out
end
ns.objTagLines = objectiveLines
function ns.objTagName(u)
    local ok, n = pcall(UnitName, u)
    if ok and type(n) == "string" and n ~= "" then return n end
    local TI = C_TooltipInfo
    if type(TI) == "table" and type(TI.GetUnit) == "function" then
        local ok2, data = pcall(TI.GetUnit, u)
        local l = ok2 and type(data) == "table" and type(data.lines) == "table" and data.lines[1]
        if type(l) == "table" and type(l.leftText) == "string" and l.leftText ~= "" then return l.leftText end
    end
    return nil
end
-- one of your step's names (an object the route names, like a chest or a crate)
local function stepNames(name)
    if not (name and ns.targetNames) then return false end
    local ok, names = pcall(ns.targetNames)
    if not (ok and type(names) == "table") then return false end
    for _, n in ipairs(names) do if n == name or n:gsub("s$", "") == name then return true end end
    return false
end
-- the unfinished objectives of the quests in your log: { {text, thing}, ... } ("1/7 Half-Eaten Fish" ->
-- "half-eaten fish"; "Gold Dust: 3/10" -> "gold dust")
local function thingOf(t)
    return (t:lower():gsub("^%s*%-%s*", ""):gsub("^%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+.*$", ""))
end
local function openObjectives()
    local out = {}
    if not (GetNumQuestLogEntries and GetQuestLogTitle) then return out end
    local QL = C_QuestLog
    if not (type(QL) == "table" and type(QL.GetQuestObjectives) == "function") then return out end
    local n = tonumber((GetNumQuestLogEntries())) or 0
    for i = 1, n do
        local _, _, _, header, _, _, _, id = GetQuestLogTitle(i)
        if not header and tonumber(id) then
            local ok, objs = pcall(QL.GetQuestObjectives, id)
            for _, o in ipairs(ok and type(objs) == "table" and objs or {}) do
                if type(o) == "table" and not o.finished and type(o.text) == "string" and o.text ~= "" then
                    out[#out + 1] = { o.text, thingOf(o.text) }
                end
            end
        end
    end
    return out
end
-- an objective that names the object ("Followed Kobold Tracks 2/6" for Kobold Tracks), or one whose thing is in
-- the object's name ("Gold Dust: 3/10" for a Sack of Gold Dust): its text
local function inObjectives(name)
    if type(name) ~= "string" or name == "" then return false end
    local low = name:lower()
    local one = low:gsub("s$", "")
    for _, o in ipairs(openObjectives()) do
        local t, th = o[1]:lower(), o[2]
        if t:find(low, 1, true) or (#one > 3 and t:find(one, 1, true)) or (#th > 3 and low:find(th, 1, true)) then return o[1] end
    end
    return false
end
ns.objTagInObjectives = inObjectives
-- Objects that give a quest's items (A Net Disaster's Fishing Traps give Half-Eaten Fish): from the data add-on
-- (QuestieDB and our logs) and learned when you loot them (ItineraryDB.questObjects, account-wide):
-- object id = { item id = item name }
local function objectId(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind == "GameObject" and tonumber(id) or nil
end
local function itemsOf(id)
    local a = ItineraryDB and ItineraryDB.questObjects and ItineraryDB.questObjects[id]
    local b = ns.DATA_QUEST_OBJECTS and ns.DATA_QUEST_OBJECTS[id]
    if a and b then
        local m = {}
        for k, v in pairs(b) do m[k] = v end
        for k, v in pairs(a) do m[k] = v end
        return m
    end
    return a or b
end
-- the objective one of the object's items is for, while it's open
local function itemObjective(guid)
    local items = itemsOf(objectId(guid))
    if not items then return false end
    local objs = openObjectives()
    for _, n in pairs(items) do
        local low = type(n) == "string" and n:lower()
        if low and low ~= "" then
            for _, o in ipairs(objs) do
                if o[2] == low or (#o[2] > 3 and o[2]:find(low, 1, true)) then return o[1] end
            end
        end
    end
    return false
end
ns.objTagItemObjective = itemObjective
-- looting an object: its items that an open objective asks for are remembered for that object
function ns.objTagLearnLoot()
    if not (ItineraryDB and GetNumLootItems and GetLootSourceInfo) then return end
    local objs
    for slot = 1, (tonumber((GetNumLootItems())) or 0) do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local name = item and select(2, GetLootSlotInfo(slot))
        if item and type(name) == "string" and name ~= "" then
            local src = { GetLootSourceInfo(slot) }
            for k = 1, #src, 2 do
                local id = objectId(src[k])
                if id then
                    objs = objs or openObjectives()
                    local low = name:lower()
                    for _, o in ipairs(objs) do
                        if o[2] == low then
                            ItineraryDB.questObjects = ItineraryDB.questObjects or {}
                            ItineraryDB.questObjects[id] = ItineraryDB.questObjects[id] or {}
                            ItineraryDB.questObjects[id][item] = name
                            break
                        end
                    end
                end
            end
        end
    end
end
-- is it a quest object, and the objective to show under its name
local function questObject(u)
    local QL = C_QuestLog
    local lines = objectiveLines(u)
    if #lines > 0 then return "objective", table.concat(lines, "\n") end
    if type(QL) == "table" and type(QL.UnitIsRelatedToActiveQuest) == "function" then
        local ok, r = pcall(QL.UnitIsRelatedToActiveQuest, u)
        if ok and r then return "quest", itemObjective(softGUID(u)) or inObjectives(ns.objTagName(u)) or nil end
    end
    local t = itemObjective(softGUID(u))
    if t then return "item", t end
    local name = ns.objTagName(u)
    t = inObjectives(name)
    if t then return "log", t end
    if stepNames(name) then return "step", nil end
    return false
end
local function writeTag(open)
    local v = open and "1" or "0"
    if getCV(TAG_CV) ~= v then setCV(TAG_CV, v) end
end
-- Blizzard's own name on that nameplate, when it shows (a nameplate add-on may hide it)
local function plateName(plate)
    local ok, fs = pcall(function()
        local uf = plate.UnitFrame
        if type(uf) ~= "table" or (uf.IsForbidden and uf:IsForbidden()) then return nil end
        if not uf:IsVisible() or (uf.GetEffectiveAlpha and uf:GetEffectiveAlpha() < 0.1) then return nil end
        local n = uf.name
        if type(n) == "table" and n.IsVisible and n:IsVisible() and (n:GetText() or "") ~= "" then return n end
        return nil
    end)
    return ok and fs or nil
end
-- the name tag: our own name on the nameplate when the game's isn't showing, and the objective under it
local function tagLine(unit)
    local L = tag.line
    if not (tag.open and unit and UnitIsUnit(unit, "softinteract")) then return end
    local CN = C_NamePlate
    local plate = type(CN) == "table" and type(CN.GetNamePlateForUnit) == "function" and CN.GetNamePlateForUnit(unit)
    if not plate then
        if L then L:Hide() end
        return
    end
    local own = plateName(plate)
    local name = not own and ns.objTagName("softinteract") or nil
    local obj = tag.kind ~= "other" and tag.text or nil
    if not (name or obj) then
        if L then L:Hide() end
        return
    end
    if not L then
        L = CreateFrame("Frame", nil, UIParent)
        L:SetSize(220, 30)
        L.name = L:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        L.text = L:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        for _, fs in ipairs({ L.name, L.text }) do
            local font, size = fs:GetFont()
            if font then fs:SetFont(font, size or 12, "OUTLINE") end
        end
        L.text:SetTextColor(1, 0.82, 0)
        tag.line = L
    end
    L:SetParent(plate)
    L:SetFrameStrata("HIGH")
    L:ClearAllPoints()
    L:SetAllPoints(plate)
    L.name:ClearAllPoints(); L.text:ClearAllPoints()
    if name then
        L.name:SetPoint("BOTTOM", plate, "CENTER", 0, 0)
        L.name:SetText(name)
        L.name:Show()
        L.text:SetPoint("TOP", L.name, "BOTTOM", 0, -2)
    else
        L.name:Hide()
        L.text:SetPoint("TOP", own, "BOTTOM", 0, -2)
    end
    L.text:SetText(obj or "")
    L.text:SetShown(obj ~= nil)
    L.unit = unit
    L:Show()
end
local function hideLine() if tag.line then tag.line:Hide(); tag.line.unit = false end end
-- the soft target changed: open the nameplate for it or not
local function tagCheck(force)
    if not tagsActive() or tag.combat then return end
    local g = softGUID("softinteract")
    if g == tag.guid and not force then return end
    tag.guid, tag.open, tag.kind, tag.text = g, false, "none", nil
    if g and isObject("softinteract") then
        local q, t = questObject("softinteract")
        tag.kind, tag.text = q or "other", t
        tag.open = q and true or (tagMode() == "all")
    end
    writeTag(tag.open)
    if not tag.open then hideLine() end
end
ns.objTagCheck = tagCheck
-- /iti tags: what the game gives for the object in front of you, for bug reports
function ns.objTagDebug()
    local u = "softinteract"
    local function yn(v) return v and "yes" or "no" end
    ns.print(string.format("tags: %s%s; SoftTargetInteract %s, IconGameObject %s, NameplateInteract %s%s",
        tagMode(), glimmerOn() and " (left to Glimmer)" or (tagsActive() and "" or " (not active)"),
        tostring(getCV("SoftTargetInteract")), tostring(getCV("SoftTargetIconGameObject")), tostring(getCV(TAG_CV)),
        tag.combat and ", resting in combat" or ""))
    local guid = softGUID(u)
    if not guid then
        ns.print("soft target: none - the game picks no object here (stand close, face it; it shows an icon over it when picked)")
        return
    end
    local name = ns.objTagName(u)
    local apiObj
    if type(UnitIsGameObject) == "function" then local ok, r = pcall(UnitIsGameObject, u); apiObj = ok and yn(r) or "error" else apiObj = "no API" end
    local QL = C_QuestLog
    local rel = "no API"
    if type(QL) == "table" and type(QL.UnitIsRelatedToActiveQuest) == "function" then
        local ok, r = pcall(QL.UnitIsRelatedToActiveQuest, u); rel = ok and yn(r) or "error"
    end
    local lines = objectiveLines(u)
    local items = itemsOf(objectId(guid))
    local il = {}
    for _, n in pairs(items or {}) do il[#il + 1] = n end
    local io = itemObjective(guid)
    ns.print(string.format("soft target: %s (%s, UnitExists %s); object: %s; quest related: %s; tooltip objectives: %s; gives: %s%s; in your quest log by name: %s; step names it: %s",
        tostring(name), tostring(guid), yn(UnitExists(u)), apiObj, rel, #lines > 0 and table.concat(lines, " / ") or (type(C_TooltipInfo) == "table" and "none" or "no API"),
        #il > 0 and table.concat(il, ", ") or "nothing known", io and (" (" .. io .. ")") or "", yn(inObjectives(name)), yn(stepNames(name))))
    local CN = C_NamePlate
    local plate = type(CN) == "table" and type(CN.GetNamePlateForUnit) == "function" and CN.GetNamePlateForUnit(u)
    local L = tag.line
    ns.print(string.format("tag: %s (%s%s); its nameplate: %s%s; our label: %s", tag.open and "open" or "closed", tostring(tag.kind),
        tag.text and (": " .. tag.text) or "", plate and "there" or "none", plate and (plateName(plate) and ", the game's name shows" or ", no name of the game's") or "",
        (L and L.unit and L:IsShown()) and ("shown" .. (L.name:IsShown() and (" (" .. tostring(L.name:GetText()) .. ")") or "")) or "not shown"))
end
function ns.applyObjTags(say)
    local a = ItineraryDB and ItineraryDB.auto
    if not a then return end
    if getCV(TAG_CV) == nil then
        if say and tagMode() ~= "off" then ns.print("object name tags: this game client has no nameplates for objects (" .. TAG_CV .. ")") end
        return
    end
    if tagsActive() then
        -- your own values (the ones node icons kept, when it changed them first); a setting added later is
        -- kept the first time it's changed
        local s = a.objTagsSaved
        if not s then s = { [TAG_CV] = getCV(TAG_CV) or false }; a.objTagsSaved = s end
        for k in pairs(TAG_BASE) do
            if s[k] == nil then
                local nv = a.nodeIconsSaved and a.nodeIconsSaved[k]
                if nv ~= nil then s[k] = nv else s[k] = getCV(k) or false end
            end
        end
        if not (InCombatLockdown and InCombatLockdown()) then
            for k, v in pairs(TAG_BASE) do if getCV(k) ~= nil then setCV(k, v) end end
            tagCheck(true)
        end
        if say then ns.print(tagMode() == "all" and "object name tags: every object you can click, within about 15 yards around you"
            or "object name tags: quest objects you can click, within about 15 yards around you, with their objective") end
    else
        hideLine()
        tag.guid, tag.open = false, false
        local s = a.objTagsSaved
        -- (while Glimmer does it, Itinerary only rests: your values stay kept for when it's switched off)
        if s and tagMode() == "off" then
            if not glimmerOn() and s[TAG_CV] then setCV(TAG_CV, s[TAG_CV]) end
            -- the interact settings node icons uses only when it doesn't keep them on
            for k in pairs(TAG_BASE) do
                if s[k] and (a.nodeIcons == false or not SOFT[k]) then setCV(k, s[k]) end
            end
            a.objTagsSaved = nil
        end
        if say and glimmerOn() and tagMode() ~= "off" then ns.print("object name tags: Glimmer (NaowhForever QoL) is on and does this, so Itinerary leaves it to Glimmer") end
    end
end
do
    local tf = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                         "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "QUEST_LOG_UPDATE", "LOOT_OPENED" }) do
        pcall(tf.RegisterEvent, tf, e)
    end
    tf:SetScript("OnEvent", function(_, event, unit)
        if not ItineraryDB then return end
        if event == "LOOT_OPENED" then pcall(ns.objTagLearnLoot) return end
        if event == "PLAYER_REGEN_DISABLED" then
            -- (just before the lockdown: close it, rest until combat ends)
            if tagsActive() then tag.combat = true; tag.guid = false; writeTag(false); hideLine() end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if tag.combat then tag.combat = false; ns.applyObjTags() end
            return
        end
        if not tagsActive() then return end
        if event == "PLAYER_SOFT_INTERACT_CHANGED" then tagCheck() return end
        if event == "NAME_PLATE_UNIT_ADDED" then pcall(tagLine, unit) return end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            if tag.line and tag.line.unit == unit then hideLine() end
            return
        end
        if event == "QUEST_LOG_UPDATE" and tag.guid then
            -- (the count went up, or the objective is done: its line, or no tag)
            local unit = tag.line and tag.line.unit
            tagCheck(true)
            if unit and tag.open then pcall(tagLine, unit) end
        end
    end)
    -- (in case the client has no PLAYER_SOFT_INTERACT_CHANGED: a look four times a second)
    local acc = 0
    tf:SetScript("OnUpdate", function(_, el)
        acc = acc + (tonumber(el) or 0)
        if acc < 0.25 then return end
        acc = 0
        if ItineraryDB and tagsActive() then tagCheck() end
    end)
end

local TRACK = { mining = "Find Minerals", herbalism = "Find Herbs" }
local trackSaid
local function trackingList()
    local out = {}
    local M = C_Minimap
    if not (M and M.GetNumTrackingTypes and M.GetTrackingInfo) then return nil end
    for i = 1, M.GetNumTrackingTypes() do
        local info = M.GetTrackingInfo(i)
        -- spell: a tracking ability (Find Minerals, Find Treasure, Track Beasts) - only one at a time; the
        -- others (flight masters, mailboxes, trainers ...) are map filters that stay on alongside
        if type(info) == "table" then
            out[#out + 1] = { i = i, name = info.name, active = info.active,
                              spell = info.type == "spell" or (info.spellID and info.spellID > 0) or false }
        else
            local name, _, active, category, _, spellID = M.GetTrackingInfo(i)
            out[#out + 1] = { i = i, name = name, active = active, spell = category == "spell" or (spellID and spellID > 0) or false }
        end
    end
    return out
end
-- what gathering tracking saw, for /iti track (and the last 30 tries in ItineraryDB.trackLog)
local function trackLog(msg)
    if not ItineraryDB then return end
    local l = ItineraryDB.trackLog or {}
    ItineraryDB.trackLog = l
    l[#l + 1] = (date and date("%H:%M:%S") or "") .. " " .. msg
    while #l > 30 do table.remove(l, 1) end
end
ns.trackLog = trackLog
function ns.trackState()
    local M = C_Minimap
    local parts = { "C_Minimap " .. tostring(M ~= nil), "SetTracking " .. tostring(M and M.SetTracking ~= nil),
        "types " .. tostring(M and M.GetNumTrackingTypes and M.GetNumTrackingTypes()),
        "texture " .. tostring(GetTrackingTexture and GetTrackingTexture()),
        "dead " .. tostring(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")),
        "mining " .. tostring(ns.profKnown("mining")) }
    for _, t in ipairs(trackingList() or {}) do
        if t.spell then parts[#parts + 1] = tostring(t.name) .. (t.active and "*" or "") end
    end
    return table.concat(parts, ", ")
end
function ns.applyGatherTracking()
    local a = ItineraryDB and ItineraryDB.auto
    local c = C()
    if not (a and a.gatherTrack ~= false and c and c.prof and c.prof.list) then trackLog("setting off or no professions picked") return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then trackLog("dead") return end
    -- the gathering profession you have that has a tracking spell, the first you picked first
    local want
    for _, k in ipairs(c.prof.list) do
        if TRACK[k] and ns.profKnown(k) then want = TRACK[k]; break end
    end
    if not want then trackLog("no gathering profession with tracking known") return end
    local list = trackingList()
    if not list then
        if not trackSaid then trackSaid = true; ns.print("gathering tracking: this game client has no tracking list to switch") end
        return
    end
    -- a gathering profession just learned (or the first time Itinerary sees it) takes over the tracking once;
    -- after that, something else you track is left alone
    local fresh = c.trackFor ~= want
    local idx
    for _, t in ipairs(list) do
        if t.name == want then
            idx = t.i
            if t.active then
                -- after dying the list can still say it's on while the tracking itself is gone (no tracking icon):
                -- switch it off and on again, once per resurrection
                local tex = GetTrackingTexture and GetTrackingTexture()
                local stale = ns.trackAfterDeath and (GetTrackingTexture == nil or tex == nil)
                if not stale then c.trackFor = want; ns.trackAfterDeath = nil; trackLog("on: " .. ns.trackState()) return true end
                trackLog("stale after death, off and on: " .. ns.trackState())
                ns.trackAfterDeath = nil
                pcall(C_Minimap.SetTracking, idx, false)
                C_Timer.After(0.3, function() pcall(C_Minimap.SetTracking, idx, true) end)
                return nil -- the next try checks it
            end
        end
    end
    if not idx then trackLog("not in the list: " .. ns.trackState()) return end -- not in the list yet (just learned): the next try gets it
    if not fresh then
        for _, t in ipairs(list) do
            if t.active and t.spell and t.name and t.name ~= "" and t.name ~= NONE then trackLog("other tracking on: " .. ns.trackState()) return true end -- something is tracked: yours
        end
    end
    if C_Minimap.SetTracking then
        local ok, err = pcall(C_Minimap.SetTracking, idx, true)
        trackLog("SetTracking " .. idx .. " -> " .. tostring(ok) .. " " .. tostring(err or "") .. ": " .. ns.trackState())
        if ok then
            c.trackFor = want
            ns.trackAfterDeath = nil
            if fresh then ns.print("gathering tracking: " .. want .. " on") end
            return nil -- the next try checks that it took (it can fail right after a resurrection)
        elseif not trackSaid then trackSaid = true; ns.print("gathering tracking: the game didn't let Itinerary switch it on - click " .. want .. " in your spellbook") end
    end
end

do
    local tf = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_UNGHOST", "PLAYER_ALIVE", "SKILL_LINES_CHANGED",
                         "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED", "CHAT_MSG_SKILL",
                         "PLAYER_DEAD" }) do
        pcall(tf.RegisterEvent, tf, e)
    end
    local pending
    tf:SetScript("OnEvent", function(_, event)
        if not (ItineraryDB and ItineraryCharDB) then return end
        if event == "PLAYER_LOGIN" then ns.applyNodeIcons(); ns.applyObjTags() end
        if event ~= "SPELLS_CHANGED" then trackLog("event " .. event) end
        if event == "PLAYER_DEAD" then ns.trackAfterDeath = true return end
        -- back alive: a chain still waiting from when you released (as a ghost) mustn't swallow this one
        if event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then pending = false end
        -- a moment later, once the game has its tracking state (and never in a loop with its own update);
        -- a spell just learned can take a few seconds to show up in the tracking list, so try a few times
        if pending then return end
        pending = true
        local tries = { 1, 3, 6, 10, 16 }
        local function try(n)
            C_Timer.After(tries[n] - (tries[n - 1] or 0), function()
                local ok, done = true, nil
                if not (InCombatLockdown and InCombatLockdown()) then ok, done = pcall(ns.applyGatherTracking) end
                if not ok then trackLog("error: " .. tostring(done)) end
                if (done or not ok or n == #tries) then pending = false else try(n + 1) end
            end)
        end
        try(1)
    end)
end
