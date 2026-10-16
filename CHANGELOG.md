# Changelog

## Unreleased

### New
- Gather mode has two sets of spots (Settings > Professions > Gather data: Both, Shipped or Own), in different
  colours on the map: the shipped spawn spots and our own, which grows silently on every character (any
  profession, gather mode on or off) from the nodes you gather and the ones that come within about 20 yards.
  Itinerary_Data 1.1 holds both sets (OwnNodes.lua: our finds from the beta) and the node object ids.
- **Open the training window** (Settings > Trainer, on): talking to a trainer you came to train at (the
  route's trainer stop or a trainer instruction) skips the dialogue and opens the training window, so with Buy
  class skills on it's one click. Hold Shift to see the dialogue.
- **Own icon**: a brass compass in the AddOns list and on the minimap button.
- **Trainer tooltips everywhere**: every trainer instruction has a READY TO LEARN tooltip on hover (class
  trainers, weapon masters and profession trainers), also when a trainer visit is your current step
  (hover its title).
- **Profession trainers** are recorded when you open them: the profession, its ranks and recipes with
  skill, level and price. The tooltip lists only what that trainer teaches, minus what you already
  know (cooks don't all teach the same recipes).
- **Editor: Ends at step** for along-the-way steps: the step where it stops showing. It follows the step
  when you add, hide or move steps.
- **Level jumps in route packs**: a route can skip a section above a level; it's decided once when you
  get there.

- **Gather mode** (`/iti gather`, experimental): a farming route. The arrow leads from one spot where a herb
  or ore vein of your skill can spawn to the next; the zone's spots show on the minimap and world map; nodes
  you find that aren't known yet are remembered.
- **Itinerary_Data** add-on (GPL v3, separate): where every class trainer, profession trainer, weapon master
  and tool vendor stands, and the herb and ore spawn spots for gather mode. Itinerary works without it.
- **Gathering tracking** (Settings > Professions): Find Herbs / Find Minerals is switched on when no minimap
  tracking is on. **Node icons**: the game's interact icons over herbs, ore veins and chests close by.

### Changed
- Two grind steps in a row (one for "if you finished the side quest", one for "if not"): only the one that
  fits shows. Steps the guide meant for a different experience rate are left out.
- More of the guide's conditions are kept: steps for a profession skill range (Cooking below 50 - only if you picked
  it), for when you're short of money, for when your weapon is weaker than a reward, "not finished yet" and "not in
  your log".
- Along the way: the same objectives from two guide steps show once, and tiers of the same items (cloth for 60,
  then 240) one at a time.
- Steps the guide marks for a profession you know (Rough Stones to blacksmith into sharpening stones) only show
  when you know it.
- The same objectives twice along the way (with and without a side quest like Lost Book): only the fuller one.
- A guide's tiers of one item (4 Chunks of Boar Meat for Pie for Billy, then 10 and 50 for Cooking) show one at a
  time under along the way, and a quest's collect goes away once that quest is handed in.
- Pie for Billy has a step to get the boar meat before its turn-in (the guide only collected it along the way).
- The best-selling quest reward gets a gold coin in the corner of its name box instead of a golden frame (the frame was hard to tell
  apart from the game's highlight on the reward you pick).
- Items a guide collects for another quest (Crag Boar Ribs for Beer Basted Boar Ribs on the Stocking Jetsteam
  step) are an along-the-way entry of their own ("For Beer Basted Boar Ribs") instead of part of that step.
- Stocking Jetsteam's bears and boars are along the way until its turn-in (through the Grizzled Den).
- The same along-the-way entry from two guide steps shows once.
- Target button: with enemy nameplates on, a step's mob kinds are tried closest first (alive, not tagged by
  someone else, not fighting another player) instead of in the guide's order. `/iti target` shows what it sees.
- Buying class skills: before level 10 only the worthwhile skills are bought.
- Timed quests (Durnan's Scalding Mornbrew and the like): the time left from the game's quest timer shows on
  the instruction that runs until its turn-in (or on your step when there is none), counting down.
- Coldridge Valley crowded start: The Troll Cave, The Stolen Journal and Senir's Observations (and The
  Adventurer) are back in; A New Threat is picked up after the mail delivery and worked on along the way, and
  handed in before Senir's Observations only if it's done by then.
- Gathering tracking switches on right after you learn Mining or Herbalism (it tries again for a few
  seconds until the game lists the new tracking), also over another tracking that was on, once.
- Gathering tracking comes back after you're resurrected, also when the game still lists it as on.
- Gathering tracking no longer mistakes the map filters (flight masters, mailboxes, trainers ...) for tracking you
  switched on yourself: it was never switched on with them active.
- A turn-in the route only does "if it's done by now" isn't listed as one to go back for when you passed it.
- Steps for an item you need to have (RestedXP `.itemcount`) only show while you have it (or, for "fewer
  than", while you don't). "Eat the Herb Baked Eggs" instructions get the eggs on an item button and stay
  hidden while their buff is up, until a minute before it runs out (the buff is learned the first time you eat).
- "Die and respawn at the spirit healer" instructions and steps are done once you're alive again.
- An along-the-way quest objective hands over to the route's own step for that quest: from there that
  step shows the counts instead of both.
- A "turn in / accept it if you pass by" instruction isn't listed when the route does the same as one of
  the next steps.
- Profession instructions only show when you can pay for what they're for (secondary professions after
  the money for your next class skills, a new rank when you have its price).
- Along-the-way objectives: one objective per line, the count in the hint colour; finished ones stay listed, greyed.
- Memory use is shown in the settings button's tooltip (Itinerary, all addons, the top 5), measured only
  while you hover it. The footer display and its setting are gone (measuring every few seconds could
  cause small stutters).

### Fixed
- The guide's vendor visits ("Vendor trash" at a named vendor, "Sell junk", buying from someone) are done when you
  open that vendor; before, only the starting-area ones were.
- The class trainer instruction no longer shows when its tooltip says there's nothing new: both now go by the
  trainer's recorded list against your spellbook.
- Class trainer instructions in every starting area: with Itinerary_Data all class trainers are known (before,
  only trainers you had opened were known, so e.g. the Shadowglen rogue trainer never showed up).
- The trainer instruction no longer waits for a route trainer stop a few steps ahead when that stop is
  itself shown as an instruction.
- Profession trainers that WoW Forever added (like the junior trainers in the starting areas) are
  picked up as soon as you target, hover or open them.

## 1.2.0 (2026-10-15)
First version in this repository.
- Route panel with hints, INSTRUCTIONS and ALONG THE WAY cards, upcoming steps and your pace against a
  reference run; waypoint arrow in several styles; colour schemes (Itinerary, Amethyst, Frost, Ember,
  Slate).
- Quest, item and target buttons with key bindings.
- Automation: accept and turn in route quests, quest dialogue, junk selling, hearthstone, flights, class
  skills (worthwhile ones first, with a reserve), weapon skills (off by default), professions and their
  tools.
- Class trainers and weapon masters close by as instructions, with what they have for you.
- Professions: up to two main professions plus secondary ones, money planned for learning them and
  their tools, the starting-zone book reward used for a gathering profession.
- Abandon steps for quests a route drops.
- Route editor (hints, items, items to collect, XP targets, along the way, auction house / self-found
  steps, save with a quick reload) and recorder (hints, instructions until a quest is turned in,
  along-the-way objectives; Shift + right-click on the route button, REC light in the footer).
- Routes are shared as import strings or come from route packs (separate add-ons); Itinerary itself
  ships without routes.
- User manual (MANUAL.md).
