# Itinerary – User Manual

Itinerary guides you through leveling one step at a time: what to do now, where to go, and what to keep
doing on the way. It also takes care of the busywork in between: quests, dialogue, junk, trainers,
professions and flights.

**Contents**
1. [Getting started](#1-getting-started)
2. [The route panel](#2-the-route-panel)
3. [The waypoint arrow](#3-the-waypoint-arrow)
4. [Item and target buttons](#4-item-and-target-buttons)
5. [Moving through the route](#5-moving-through-the-route)
6. [Trainers, weapon masters and professions](#6-trainers-weapon-masters-and-professions)
7. [Automation](#7-automation)
8. [Routes: choosing, recording, editing, sharing](#8-routes-choosing-recording-editing-sharing)
9. [Settings](#9-settings)
10. [Commands](#10-commands)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Getting started

1. Put the `Itinerary` folder into `World of Warcraft\_classic_\Interface\AddOns` and start the game.
2. Log in. The **route panel** and the **waypoint arrow** appear.
3. A new character is asked once which **professions** it will take. Pick up to two main professions
   and any secondary ones (Cooking, First Aid, Fishing). You can change this later in the settings.
4. Itinerary picks the route made for your race and class. **Itinerary itself ships without routes.** If
   you have none yet, the panel says "No route loaded". Then:
   - **record your own** while you play (see [Recording](#recording-a-route)),
   - **import** a route someone shared with you (`/iti import`), or
   - install a **route pack**, a separate add-on folder next to Itinerary.
5. Optional but recommended: the **`Itinerary_Data`** folder next to Itinerary. It tells Itinerary where
   every class trainer, profession trainer, weapon master and tool vendor stands, so trainer
   instructions work from the start, and it holds the herb and ore spots for gather mode. Without it,
   Itinerary learns trainers and vendors as you meet them.

The **minimap button** (the brass compass):

| Click | Does |
|---|---|
| Click | Show or hide the route panel |
| Right-click | Show or hide the arrow |
| Shift + click | Open the settings |

---

## 2. The route panel

<p align="center"><img src="manual/route-panel.png" alt="The route panel" width="430"></p>

From top to bottom:

- **Header**: the step type (ACCEPT, COMPLETE, TURN IN, GO, FLY, TRAIN, …), the current chapter and the
  route's level range. A thin bar along the top shows how far through the chapter you are. Click the
  header to open the **chapter list** and jump to any chapter.
- **The step**: what to do now, with the NPC, quest names coloured by difficulty, and live objective
  counts (*Rockjaw Trogg slain 3/10*).
- **Hint**: a line under the step with extra advice (*Unequip your shirt so you can sell it*). Items and
  spells in the text show their icon. Hover them for the tooltip; Shift-click links them in chat.
- **INSTRUCTIONS**: things to keep doing next to your step. Examples: sell junk, use your hearthstone,
  learn new skills at a trainer close by, a weapon master, a profession trainer, "don't sell the meat".
  Click an instruction that has a place, and the arrow points there. Click it again to go back to the
  route.
- **ALONG THE WAY** (green): side objectives you work on while you go, with live counts. These are quest
  objectives or items to collect (*Crag Boar Rib 2/6*). Once the route reaches its own step for that
  quest, that step shows the counts instead. A "turn in / accept it if you pass by" that the route does
  as one of the next steps anyway isn't listed as an instruction too.
- **Next steps**: a preview of what comes after.
- **Footer**:
  - **Level timer**: time on this level and your pace against the route's reference run. Hover it for
    every level's time; scroll on it for more.
  - **REC** (red, pulsing): you are recording a route. Click it to open the recorder.
  - **Route button** (note icon):
    - Click: the route list.
    - Right-click: the route editor.
    - Shift + right-click: the recorder.
  - **Gear**: the settings. Hover it to see how much memory Itinerary and your top 5 addons use
    (measured only while you hover).
  - **‹ ›**: one step back or forward.

**Moving the panel**: Alt + right-click the panel to unlock it, drag it, then Alt + right-click again to
lock it.

---

## 3. The waypoint arrow

<p align="center"><img src="manual/arrow.png" alt="The waypoint arrow" width="128"></p>

The arrow points at your step's target and shows the distance in yards. It follows the route's path
(into a cave, along a road). It skips waypoints you've already passed. For kill or collect steps it
points at the area where the mobs are.

- Above the arrow you see the current **instructions** in short form (you can turn this off, and set
  the font size).
  Trainer visits show there as one line, *Skills to learn nearby*: the arrow only leads to a trainer once
  you click its instruction.
- Hover the arrow for the step's details.
- **Alt + right-click** the arrow to unlock it, drag it, then Alt + right-click again to lock it.
- Arrow styles (Settings > Arrow):
  - **Itinerary**, **Gold**, **White**, **Big**
  - **Guide**: green when you're heading the right way, red when the target is behind you
  - **Classic**: the game's minimap arrow

---

## 4. Item and target buttons

Next to the panel sit small action buttons. Each one can have a **key binding**: set them in
Settings > Keys, or in the game's key bindings under *Itinerary*.

- **Quest item buttons (up to 4)**: the usable items your step needs (a quest item to use at a spot, a
  book to learn a profession). Your **Hearthstone** shows on hearth steps, with its cooldown.
- **Target button**: one press finds what your step is about:
  - **Enemies**: it targets the nearest of the step's mobs, marks it with a **skull**, and tags it with
    an instant spell (Judgement, Earth Shock, Shadow Word: Pain, Moonfire, Arcane Shot, Fire Blast,
    Curse of Agony, Throw, Charge…). Spam it on a contested spawn to tag it first.
    With enemy nameplates on and a step with several kinds of mobs, it goes for the kind that's closest
    and worth it: alive, not tagged by someone else, not fighting another player (out of combat; in
    combat the last pick stays). Among mobs of the same name the game picks.
  - **NPCs**: it targets the NPC you need to talk to and marks them with an orange circle. Press the key
    again to talk to them. That's handy for taking a contested escort quest first.

Which corner of the panel the buttons sit at: Settings > Panel > *Item & target buttons*.

---

## 5. Moving through the route

You rarely have to touch anything:

- **Quest steps** tick off from your quest log: accepted, objectives done, turned in.
- **Travel steps** tick off when you arrive. Flights, hearths, flight paths and setting your hearthstone
  tick off when you do them.
- **Trainer steps** tick off when you've trained. **Grind steps** tick off at the XP they ask for.
- Steps that don't apply to you are skipped. This covers another class's quests, quests you already
  did, a quest that isn't offered to you, and a quest you dropped.
- **Death skips** ("Die and respawn at the spirit healer") are done once you're alive again.
- **Steps for an item** only show while you have it, e.g. "Cook the Small Eggs" only with Small Eggs in
  your bags.
- **Food buffs**: "Eat the Herb Baked Eggs" puts the eggs on an item button and stays hidden while their
  buff is up, until a minute before it runs out. Itinerary learns which buff an item gives the first time
  you eat it.

**Skipping a quest**: if you skip a step where you would *accept* a quest (›), that quest is dropped. Its
later steps and all follow-up quests are left out too, and chat tells you how many. Taking the quest
anyway (or going back with ‹) brings them back. Abandoning a quest in your quest log drops it the same
way.

**Lost?**
- `/iti find` goes to the first step you haven't done.
- `/iti goto <number>` jumps to a step.
- `/iti chapter <number>` jumps to a chapter. You can also click the panel header for the chapter list.

---

## 6. Trainers, weapon masters and professions

**Class trainer.** When new skills worth buying are waiting and you can pay for them, an instruction
appears as soon as a trainer of your class is **within 400 yards**: *Train new skills at …*. Hover it
for **READY TO LEARN**, which lists each skill with its icon and price, and how much money you have.
Worthwhile skills are green, and they're bought first; before level 10 only those are bought. You choose which skills count as worthwhile (and
which are never bought) in Settings > Trainer.

**Money kept back**: from level 6 on, buying keeps a small reserve for your next skills. It starts at
40 copper at level 6, doubles every other level, and stops at 5 gold.

**Weapon masters.** The same kind of instruction appears for weapon skills you don't have yet, at a weapon
master within 400 yards: *Train 2h Swords, 1h Swords and Polearms at Woo Ping*. Hover it for the list
and prices.
- Settings > Trainer > *Weapon skills* chooses which skills count: **All** (every weapon your class can
  use), **Route** (only the ones the route trains) or **Off**.
- Buying them for you is **off** by default (*Buy weapon skills*).
- Every weapon master you open is remembered with his skills and prices.

**Instruction or step?** Settings > Trainer > *Trainer visits* decides how a trainer close by is shown:
- **Instruction** (default): it shows next to your step and the arrow stays on the route.
- **Step**: it becomes your current step and the arrow leads you there.

**Professions.**
- **Two gathering professions**: the first one is learned at its trainer as soon as you have the money
  (usually after the first quest and selling junk). The second comes free from the starting zone's
  **book reward**, which Itinerary picks for you; the book then gets an item button.
- **Tools**: the gathering tools are bought at the first vendor you open when the money covers them
  *and* learning your first profession.
- **Next rank**: when Journeyman, Expert or Artisan is ready, a trainer is close by and you can pay for
  it, you get an instruction to go learn it.
- No profession instruction shows while you can't afford what it's for.
- **New trainers**: WoW Forever adds profession trainers Classic doesn't have (like the junior trainers
  in the starting areas). Itinerary learns one as soon as you target it, hover it or open it, and from
  then on its instructions show up for all your characters.
- **Finding herbs and ore**: *Gathering tracking* switches on Find Herbs or Find Minerals when no minimap
  tracking is on (after logging in or dying); tracking you picked yourself stays. *Node icons* (on by
  default) turns on the game's interact icons: an icon floats over the nearest herb, vein or chest within
  about 20 yards, in any direction.
- **Secondary professions** come last: only with money to spare, and only when your next class skills
  are paid for.
- **Hover any profession trainer instruction** for its READY TO LEARN list: the profession or its next
  rank (green), then the recipes **that trainer** teaches and your skill allows, with the skill they need
  and their prices. Trainers of the same profession don't all teach the same recipes (cooks especially),
  so every trainer you open is remembered with its own list, for all your characters. A trainer you
  haven't opened yet shows the profession and its ranks only.

**Gather mode (experimental).** A farming route instead of the leveling route, e.g. at max level:
`/iti gather` (or Settings > Professions > *Gather mode*) switches it on and off.
- The arrow leads to the nearest spot where a herb or ore vein **your skill can gather** can spawn. Once
  you've been there, it moves on to the next one; › skips a spot. Spots you've visited count again after
  10 minutes (nodes respawn).
- The zone's spots show on the minimap (green: herbs, orange: ore; faded: visited) and on the world map.
- The panel shows how many spots are left in the zone, how many nodes you gathered and your rate per hour.
- Two sets of spots, picked in Settings > Professions > **Gather data**: *Shipped* (where nodes can spawn, from
  Itinerary_Data; map dots: herbs green, ore orange), *Own* (ours: the finds baked into Itinerary_Data plus every
  node gathered or passed on your account; herbs blue, ore pink) or *Both* (the default; a shipped spot we found
  too shows in our colours).
- Your own set grows by itself, silently, on every character - whatever your professions and with gather mode
  off: every node you gather, and every herb or vein that comes within about 20 yards.
- Your leveling route waits where you left it. While gather mode is on, the panel shows only gathering:
  no route instructions, along-the-way objectives, quest items or route pins.
- Needs the `Itinerary_Data` folder next to Itinerary.

**Every trainer instruction has this tooltip**: class trainers, weapon masters and profession trainers,
whether it shows as an instruction or as your step (hover the step's title).

---

## 7. Automation

Every part can be turned off in the settings. **Hold Shift** while talking to an NPC or opening a trainer
to do things by hand that time.

| What | Default | Where |
|---|---|---|
| Accept and hand in quests (only the route's quests, or all) | on | Quests |
| Click through quest dialogue | on | Quests |
| Pick plain armor rewards (white/green armor only) | off | Quests |
| Gold coin on the best-selling reward | on | Quests |
| Sell grey items at any vendor | on | Quests |
| Take the route's flight when you talk to the flight master | on | Travel |
| Set your hearthstone on a "make this inn your home" step | on | Travel |
| Resurrect at the spirit healer (death skips) | on | Travel |
| Buy class skills at your trainer | off | Trainer |
| Open the training window at a trainer you came to train at (Shift: dialogue) | on | Trainer |
| Buy weapon skills at a weapon master | off | Trainer |
| Learn your professions at their trainer | on | Professions |
| Buy gathering tools | on | Professions |

**Self-found play**: Settings > Quests > *Auction house steps* > **Skip** leaves out every step that sends you
to the auction house (steps marked *Auction house* in the editor, and any step at an auctioneer), and shows
the steps marked *Self-found only* instead.

---

## 8. Routes: choosing, recording, editing, sharing

### Choosing a route
Click the **route button** in the panel footer. The list shows:
- the routes for your race and class (with their versions),
- your own routes,
- routes for other races of your class.

Pick one to switch. `/iti routes` lists them in chat. Your place on each route is kept per character.

### Recording a route

<p align="center"><img src="manual/recorder.png" alt="The recorder" width="400"></p>
Open the **recorder**: Shift + right-click the route button, `/iti recorder`, or the *Recorder* button
in the editor. Press **Record** and play. From then on, these become steps on their own:
- quests you accept, finish and turn in (with where you were and what you fought)
- trainers, flight paths, flights
- your hearthstone and where you set it

A new zone starts a new chapter.

While recording, the panel footer shows a red **REC**. *Pause* stops recording for a while. *Stop* (two
clicks) ends it, and the route stays in your route list.

Type into the recorder's text box and add your own:

| Button | Becomes |
|---|---|
| **Add hint** | A hint under the last recorded step |
| **Add instruction** | An instruction from here to the end of the chapter, or until the picked quest is turned in |
| **Along the way** | The picked quest's objectives as a side objective from here on, with live counts |
| **Add step** | A to-do step at your position |
| **Waypoint here** | A travel step to where you stand |
| **New chapter** | The next step starts a chapter with this name |
| **Undo last** | Removes the last recorded step |

The **Quest** button picks a quest from your log (click: next, Shift-click: back). *Add instruction* and
*Along the way* use it.

### Editing a route

<p align="center"><img src="manual/route-editor.png" alt="The route editor" width="760"></p>
Open the **route editor**: right-click the route button, or `/iti edit`. On the left is the step list
(with chapters). On the right are the selected step's details.

- **Type**: accept, complete, turn in, go, do, train, xp.
- **Fields**:
  - **Text**
  - **Hint**
  - **Quest IDs**
  - **NPC**
  - **Mobs**
  - **Items**: Shift-click items from your bags to put them on the item buttons.
  - **Collect**: Shift-click an item, then set the count, e.g. `2886 Crag Boar Rib x6`.
  - **Level**: for XP steps:

    | You type | Done when |
    |---|---|
    | `5` | you reach level 5 |
    | `3 1200xp` | you're 1200 XP into level 3 |
    | `3 50%` | you're halfway through level 3 |
    | `4 -300xp` | you're within 300 XP of level 4 |

  - **Ends at step**: for an *Along the way* step, the step number where it stops showing. Left empty, it
    shows until it's done, the chapter ends, or a later step completes or turns in its quest.
  - **New chapter**
- **Buttons**:
  - **My position**: puts the step's waypoint where you stand.
  - **Use target**: your target becomes the NPC, or is added to the mobs if it's an enemy.
  - **Insert after**: adds a step after the selected one.
  - **Hide / Show / Delete**
  - **Move up / down**: steps you added.
  - **Undo changes**
  - **Along the way**: the step runs alongside the following steps until it's done. A quest objective
    run this way hands over to a later step of the same quest: from there that step shows the counts.
  - **Go to step**
  - **For everyone / Auction house / Self-found only** (click to switch): an *Auction house* step is left
    out for players who skip auction house steps (self-found). A *Self-found only* step shows only for
    them, e.g. buying a vendor item instead of the auction house one.
- **Save**: your changes work in the route immediately. *Save* writes them to disk now (a quick reload).
  Otherwise that happens when you log out.

A route that came with a route pack is never changed. Your first edit makes **your own copy**, and you go
on with the copy. *Make a copy*, *New route* and *Undo all edits* are in the toolbar.

### Sharing a route
In the editor, **Export** gives you a text. Copy it with Ctrl+C and send it. The other player uses
**Import** (or `/iti import`), pastes it with Ctrl+V, and gets it as a new route of their own.

---

## 9. Settings

Open them with the gear in the panel footer, Shift + click on the minimap button, or `/iti settings`.

| Tab | What's there |
|---|---|
| General | Panel and minimap button on/off, the game's quest tracker, quest sparkles, step sound, forget this character |
| Quests | Accept/hand in, which quests, dialogue, reward picking, sell junk, auction house steps |
| Travel | Flights, hearthstone, spirit healer, map pins |
| Trainer | Buy class skills, open the training window, trainer visits (instruction/step), weapon skills, buy weapon skills, the worthwhile/skip list per class |
| Professions | Learn at the trainer, main and secondary professions, first profession, gather mode, gathering tracking, node icons, gathering tools |
| Panel | Color scheme (Itinerary, Amethyst, Frost, Ember, Slate), instructions card, item links, style, opacity, size, text shadow, grow direction, button corner, lock |
| Arrow | Arrow on/off, style, instructions above it and their size, tooltip, lock |
| Keys | Key bindings for the target and item buttons, and how the target button behaves |

<details>
<summary><b>Screenshots of every settings tab</b> (click to open)</summary>

| General | Quests |
|---|---|
| <img src="manual/settings-general.png" alt="General" width="330"> | <img src="manual/settings-quests.png" alt="Quests" width="330"> |
| **Travel** | **Trainer** |
| <img src="manual/settings-travel.png" alt="Travel" width="330"> | <img src="manual/settings-trainer.png" alt="Trainer" width="330"> |
| **Professions** | **Panel** |
| <img src="manual/settings-professions.png" alt="Professions" width="330"> | <img src="manual/settings-panel.png" alt="Panel" width="330"> |
| **Arrow** | **Keys** |
| <img src="manual/settings-arrow.png" alt="Arrow" width="330"> | <img src="manual/settings-keys.png" alt="Keys" width="330"> |

</details>

---

## 10. Commands

| Command | Does |
|---|---|
| `/iti` | Show or hide the route panel |
| `/iti settings` | Settings |
| `/iti next` / `/iti back` | One step forward / back |
| `/iti goto <n>` | Jump to step n |
| `/iti find` | Go to the first step you haven't done |
| `/iti chapters`, `/iti chapter <n>` | Chapter list / jump to chapter n |
| `/iti routes`, `/iti routes all`, `/iti route <id>` | List routes / all routes / switch |
| `/iti edit` | Route editor |
| `/iti recorder` | Recorder |
| `/iti record` | Editor's quick record: quests you take that the route doesn't have are added to it |
| `/iti export`, `/iti import` | Share a route |
| `/iti professions` | Profession picker |
| `/iti gather` | Gather mode on/off |
| `/iti arrow`, `/iti pins`, `/iti minimap` | Toggle the arrow, map pins, minimap button |
| `/iti lock`, `/iti unlock` | Lock or unlock panel and arrow |
| `/iti reset` | Start this route over from its first unfinished step |
| `/iti wipe yes` | Forget everything saved for this character (settings stay) |
| `/iti factoryreset yes` | Itinerary as if just installed (all settings, routes and progress) |
| `/iti debug` | Details about the current step, trainers and weapons (for bug reports) |
| `/iti target` | What the target button looks for and which nameplate it picks |
| `/iti track` | What gathering tracking sees and did lately |

---

## 11. Troubleshooting

- **The panel says "No route loaded".** You have no route for this character yet. Record one, import
  one, or install a route pack. If you were on a route from a pack that's no longer installed, your place
  on it is kept. Install the pack again and you continue where you were.
- **The route jumped ahead or seems wrong.** `/iti find` goes back to the first step you haven't done.
  `/iti back` undoes a skip.
- **A quest step doesn't tick off.** Quests the giver doesn't offer you (a missing pre-quest, too low
  level) are skipped after a moment. `/iti debug` shows what the game reports for the step's quests.
- **No trainer instruction.** The trainer must be within 400 yards, and you need the money for a
  worthwhile skill on top of the reserve. `/iti debug` shows money, what's waiting and the trainers
  close by.
- **Something looks broken.** Type `/console scriptErrors 1`, then `/reload`. Send the error message
  together with the `/iti debug` output.
