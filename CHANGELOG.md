# Changelog

## v2.1.3 (2026-10-19)

### Fixed
- Flying didn't happen when the route's flight was an instruction ("Fly to Redridge" under Instructions while
  the step was "Head to the Redridge Mountains"): talking to the flight master now flies you there as it does
  when the flight is the step itself. That's how most of the routes' flights are written. The arrow points to
  the flight master until you're in the air, and only then to the step's place.
- A flight leads to the nearest flight master of your side, not only the one the route names: the guide may mean
  either of two ("Dungar Longdrink or Thor") or you come back to the route from somewhere else. The arrow, the
  target button and the instruction ("At Dungar Longdrink") go there; only flight masters on the continent of
  the route's own count. Itinerary_Data 1.5 lists where they stand.

## v2.1.2 (2026-10-19)

### New
- `/iti dump` writes the route you follow - every step as Itinerary built it for you, with quest names, zone
  coordinates and chapters - as JSON into the saved variables (SavedVariables\Itinerary.lua, at the next /reload
  or logout), to use it outside the game. Its first field, "about", explains the structure. `/iti dump clear`
  removes it.

### Fixed
- "Ready to learn" listed higher ranks of talent spells you haven't taken (Seal of Command Rank 2 without the
  talent): a spell whose first rank no trainer teaches (a talent or a quest) shows its next ranks only once you
  have it.
- A skill WoW Forever renamed (Blessing of Salvation is Salvation now) stayed "ready to learn" under its old name
  after you learned it; the old name is also dropped from the list at your next trainer visit.
- The trainer instruction sent an Undead paladin in Undercity to Mary Edras, the first aid trainer, for class
  skills: a route's trainer stop at someone known as a profession trainer no longer counts as a class trainer
  (unless you opened them as yours). The same goes for pet, demon and portal trainers, weapon masters and riding
  instructors (the route still visits them for what they teach). Itinerary_Data 1.4 lists who they are.

## v2.1.1 (2026-10-19)

### New
- A small **×** on each instruction dismisses it: one from the route is done; a trainer, weapon master or
  profession instruction waits for your next level.

### Fixed
- A "Vendor trash" errand the route keeps along the way without an end stayed an instruction long after you'd
  left (Corina Steele's showed in Dun Morogh): every vendor errand now runs next to the next few steps only.
- Weapon masters: the shipped list of where they stand counted for nobody (its faction mark wasn't read), and a
  visit's list replaced what the master was known to teach (a character who knew 2h Swords already hid them).
- Your own copy of a route version that isn't installed any more (a newer route pack ships only the latest two
  versions) came up empty. It now builds on the newest installed version of that route, with your edits on top.

## v2.1.0 (2026-10-18)

### New
- **Portrait on the target button**: the button shows the face of the mob or NPC it would target now (the one
  on a nameplate it picked, your target when that's one of them, or one you hover), round like the game's unit
  frames, and its tooltip names it. The face stays when they leave nameplate range or you clear your target.
  Faces of the NPCs and mobs you target, hover or meet on your step are remembered for all your characters, so
  the button can show them before they're in sight; someone you've never met keeps the usual icon.
- **Object name tags** (Settings > Quests): a quest object you can click close by (within about 15 yards, in
  any direction) gets a nameplate with its name and the quest objective under it. Quest objects are the ones
  your quest log names and the ones that give an item a quest asks for (Fishing Traps for Half-Eaten Fish: known
  from the data add-on, and learned when you loot one). *All* names herbs, ore veins and chests too; NPCs, doors
  and mailboxes never get one, and it's hidden in combat. The name shows even when a nameplate add-on hides the
  game's own. While Glimmer (NaowhForever QoL) is on, it's left to Glimmer. `/iti tags` says what the game
  picked and why it gets a tag or not.

### Changed
- **Optional buys are instructions**, like food and vendor trash: a weapon "if you can afford it", items for a
  quest later, potions if in stock and the auction house's "buy these for quicker turn-ins" no longer stop
  the route. Click one to point the arrow at the vendor; it's done when you have the items or close that
  vendor or the auction house. Buys the route needs and a hunter's arrows stay steps.
- *Quest sparkles* moved to Settings > Quests. The target and item buttons' tooltips show their key and point
  to Keys in Itinerary's settings.
- Itinerary_Data 1.3: which objects give the items a quest asks for (for the name tags).

### Fixed
- A quest you had left out (skipped where you'd take it, or abandoned) and take after all: when the route had
  already gone past its steps, it now goes back to them (The Great Outdoors jumped ahead to buying a Wooden
  Mallet).

## v2.0.0 (2026-10-18)

### New
- **Route editor: everything a route step can do**: besides accept, quest, turn in, go, do, train and xp there
  are fly, flight path, hearth, home (make an inn your home), dungeon, abandon and sell junk; hover a type for
  what it does. Switches for **Optional** and **Death skip**. A **Conditions** page (quests in your log, level,
  zone, items, a buff, professions, money, your weapon, level jumps) and a **More** page (trainer kind, when a
  travel step is done, dialogue, a macro button, waypoints and kill-area spots). Quest steps take objectives
  (`12:2`), accept steps a level, the NPC field several names. The route's name line in the header is short
  ("edits make your own copy"); hover it for the whole story.
- **Route editor: waypoints and kill areas you can see and change**: on the More page, the step's waypoints
  (ending at its point) and kill-area spots as lists - type coordinates, set a waypoint's radius, move one to
  where you stand, change the order, remove one, add at your position or by clicking the world map. While the
  editor is open, the world map draws the selected step instead of your next stops: its point, numbered
  waypoints with a line, and its spots; drag a pin to move it, right-click to remove it. Each one's zone can be
  changed too (type a zone's name, the start of it or its map ID), coordinates can come with a zone
  (`Westfall 56.3, 47.5`) or as a pasted `/way` line, and a step without a point gets one by typing it in.
- **Route editor: search the step list**: a search box over the list; the chapter's steps whose text has what
  you type (quest steps by the quest's name) drop down under it, and a click on one takes the list to that
  step and selects it. *All steps* searches the whole route.
- **Route editor: Ends at step** for along-the-way steps: the step where it stops showing. It follows the
  step when you add, hide or move steps.
- **Buttons from the quest itself**, for any route: an open objective that asks for an emote ("Sit near the
  campfire", "Salute Guard Thomas") gets a macro button for it (targeting whoever the objective names), and a
  quest item in your bags with a Use effect gets its button when the objective or the quest's name mentions
  it. Shared routes keep emote macros (/hug, /pray, /roar ... are allowed in imported item-button macros now).
- **The recorder records much more**: quest items you use (on the quest step's item button), emotes you do
  right before an objective moves (a macro button on the quest step), abandoned
  quests, weapon masters, vendors (food, drink and bags as an errand, anything else as a step with Collect,
  or *Vendor trash* / *Repair*), dungeons (at the entrance, and the quests you finish inside), boats and
  zeppelins to the other continent (at the dock), the Deeprun Tram, death skips (back at the spirit healer
  far from where you died), and the way you walk to each step as its waypoints when it isn't about straight.
  New button **Level here**: a step done at your level and XP right now, for "grind to here".
- **Which route a new character gets** is decided in three levels: your **default** for a race and class
  ("make default" in the route list; also for imported and your own routes), then the **route packs in your
  order** (Settings > General > Route packs; a new pack goes to the bottom), then the **pack's own order**.
  The route list shows your default on top and, with several packs, which pack each route is from.
- **Route pack choices**: a route pack can offer on/off choices of its own (for example which dungeons your
  route includes). They show as switches in Settings > General under Route packs and are kept per
  character; the pack decides which of its steps and chapters they leave out. A change rebuilds your route
  with a quick reload. Switches your route doesn't use (an older route version without choices, another
  pack's route) are dimmed and need no reload.
- **Level jumps**: a route can skip a section above a level; it's decided once when you get there.
- **Your next stops on the maps**: numbered pins in route order on the world map (also the continent map)
  and on the minimap, with a dotted line between them on the world map. Steps at the same place share one
  pin ("2-3"). Settings > Travel: how many on each map (Off, Current, Next 3, Next 5; default Next 5) and the
  line. On the minimap only the first pin stays at the edge when it's out of range.
- **Death skips are always an instruction**: a death skip a route has as a step of its own shows next to the
  steps after it, like all the others. With a place to die at, the arrow leads there first; reaching it
  doesn't tick the death skip off (only being alive again does), and two in a row show one after the other.
- **Death skips at the arrow** (Settings > Arrow, on): "Die and respawn at the spirit healer" always shows
  above the waypoint arrow, also when *Instructions at the arrow* is off.
- **Share quests in a group** (Settings > Quests, off): in a group, every quest you accept is shared with the
  others right away (when it can be shared), so whoever is behind doesn't have to run to the quest giver.
  Quests a group member shared with you aren't shared back.
- **In dungeons** (Settings > General, Show by default): Hide puts the route panel, the arrow and the item
  buttons away inside a dungeon or raid; they're back when you leave. The minimap button (or `/iti`) shows
  them there for that visit.
- **Open the training window** (Settings > Trainer, on): talking to a trainer you came to train at (the
  route's trainer stop or a trainer instruction) skips the dialogue and opens the training window, so with Buy
  class skills on it's one click. Hold Shift to see the dialogue.
- **Trainer tooltips everywhere**: every trainer instruction has a READY TO LEARN tooltip on hover (class
  trainers, weapon masters and profession trainers), also when a trainer visit is your current step (hover
  its title).
- **Profession trainers** are recorded when you open them: the profession, its ranks and recipes with skill,
  level and price. The tooltip lists only what that trainer teaches, minus what you already know (cooks don't
  all teach the same recipes).
- **Gather mode** (`/iti gather`, experimental): a farming route. The arrow leads from one spot where a herb or
  ore vein of your skill can spawn to the next; the zone's spots show on the minimap and world map. Two sets of
  spots (Settings > Professions > Gather data: Both, Shipped or Own), in different colours on the map: the
  shipped spawn spots and your own, which grows silently on every character (any profession, gather mode on or
  off) from the nodes you gather and the ones that come within about 20 yards.
- **Gathering tracking** (Settings > Professions): Find Herbs / Find Minerals is switched on when no minimap
  tracking is on. **Node icons**: the game's interact icons over herbs, ore veins and chests close by.
- **Itinerary_Data** add-on (GPL v3, a folder of its own in the same download): where every class trainer,
  profession trainer, weapon master and tool vendor stands, which ranks a profession trainer teaches, and the
  herb and ore spawn spots for gather mode (shipped spots and finds from the beta). Itinerary works without it.
- **Own icon**: a brass compass in the AddOns list and on the minimap button.

### Changed
- **Errands at a vendor are instructions**, not stops of their own: vendor trash at a named vendor, buying a
  drink, food and water, bags, repairs. Click one to point the arrow at that vendor; it's done when you open
  them (selling junk: any vendor). The arrow doesn't lead there by itself. Buying what the route needs (a
  quest item, a weapon, arrows) stays a step.
- **Weapon skills** (Settings > Trainer) is **Route** by default: only the weapon skills the route trains get
  a training hint, not every weapon your class can learn. A choice you made yourself stays.
- Buying class skills: only the worthwhile skills (new setting Settings > Trainer > Only worthwhile skills,
  on); with it off, the others too from level 10.
- Over the arrow, trainer instructions are one line, "Skills to learn nearby - click the instruction panel to
  go there", until you click one (the arrow doesn't lead there before).
- Profession instructions only show when you can pay for what they're for (secondary professions after the
  money for your next class skills, a new rank when you have its price).
- Target button: with enemy nameplates on, a step's mob kinds are tried closest first (alive, not tagged by
  someone else, not fighting another player). A step after one particular mob (one kind, one of it needed)
  puts it first, ahead of anything closer, until you have what you need from it. `/iti target` shows what it
  sees.
- Route steps can depend on more: a profession's skill range (only if you picked that profession), knowing a
  profession, being short of money, your weapon being weaker than a reward, a quest not finished yet or not in
  your log, and the experience rate. Of two grind steps for "side quest done" and "not done", only the one
  that fits shows.
- Steps for an item you need to have only show while you have it (or, for "fewer than", while you don't).
  Food instructions ("Eat the Herb Baked Eggs") get the food on an item button and stay hidden while its buff is
  up, until a minute before it runs out (the buff is learned the first time you eat).
- Along the way: one objective per line, the count in the hint colour; finished ones stay listed, greyed. The
  same objectives or the same entry from two steps show once (the fuller one); tiers of one item (4, then 10
  and 50) show one at a time; a quest's collect goes away once that quest is handed in; items collected for
  another quest are an entry of their own. An objective hands over to the
  route's own step for that quest: from there that step shows the counts instead of both.
- Next steps: steps that are done already are left out (an abandon step for a quest you handed in or never
  took).
- "Get the flight path" steps for a flight path you have already are done: Itinerary notes your flight paths
  whenever the flight map opens.
- "Die and respawn at the spirit healer" instructions and steps are done once you're alive again.
- A "turn in / accept it if you pass by" instruction isn't listed when the route does the same as one of the
  next steps.
- A turn-in the route only does "if it's done by now" isn't listed as one to go back for when you passed it.
- The "skipped steps" line: right-click it if you're not doing those quests; quests of a chapter you've left
  drop off it by themselves (unless ready to hand in).
- Timed quests: the time left from the game's quest timer shows on the instruction that runs until its
  turn-in (or on your step when there is none), counting down.
- The best-selling quest reward gets a gold coin in the corner of its name box instead of a golden frame (the
  frame was hard to tell apart from the game's highlight on the reward you pick).
- Gathering tracking switches on right after you learn Mining or Herbalism (it tries again for a few seconds
  until the game lists the new tracking), also over another tracking that was on, once; it comes back after
  you're resurrected; and the map filters (flight masters, mailboxes, trainers ...) no longer count as
  tracking you switched on yourself.
- Memory use is shown in the settings button's tooltip (Itinerary, all addons, the top 5), measured only while
  you hover it. The footer display and its setting are gone (measuring every few seconds could cause small
  stutters).
- **Faster late in a route**: the "skipped steps" line no longer looks through every step behind you after
  each kill, loot or quest update. Near the end of a 1-60 route that took several milliseconds every time
  (small hitches in fights); now it's well under one, anywhere on the route.
- Gather mode in zones with many spots (Arathi, Burning Steppes, Stranglethorn) costs a fraction of what it
  did, and its spots only go on the world map while the map is open (they're placed when you open it).
  Your own spell casts and the arrow on steps without a place of their own cost less too.

### Fixed
- Target button on a kill step: a kill objective ("Kobold Workers slain") counts only the mob of that name, so a
  step's other mobs that merely share a word (the Kobold Vermin of the quest before) are no longer targeted;
  objectives for items still go by shared words, and a kill credit no mob is called like as before.
- Target button with along-the-way quests: your step's own mobs come first (one range band ahead), so the
  workers of your step win over the vermin you also kill for a book along the way, unless one of those is
  right next to you.
- Buying at a trainer with another dialogue option (a quest, unlearning talents): the training window stayed
  closed unless the route had sent you there, so nothing was bought. Now it opens wherever Itinerary would buy
  or learn something: your class trainer with skills to buy, a weapon master with a weapon skill to buy (Buy
  weapon skills on), the trainer of a profession you picked with something to learn. The training option is
  found by its icon first, never the one for unlearning talents.
- Recorder: a weapon master was recorded as a class trainer visit (a step waiting for class skills); now it's a
  train step for the weapon skill you learned there, and nothing when you only had a look.
- Route editor: your first change to a route from a pack (which makes your own copy) no longer jumps the
  editor to step 1; it stays on the step you're changing.
- Route editor: the name box of your own route is wider and shows a long name from its start (it showed the
  end of it).
- Money conditions worked the wrong way round: a step for when you can afford something showed only while you
  couldn't, and "until you have 10 copper" only once you had it.
- Riding and lockpicking conditions no longer stop the route with an error; riding counts as known with any
  riding skill (Wolf Riding, Horse Riding...). A step can have a skill range (Cooking from 10 to below 50).
- A hearth step no longer skips itself in the zone you're in when the route goes on somewhere else.
- "Abandon X" for a quest that's finished and handed in later on the route is done without abandoning it.
- A route's vendor visits (vendor trash at a named vendor, selling junk, buying from someone) are done when
  you open that vendor; before, only some were.
- An item that starts the step's quest gets its button even when it has no spell (Croaky's Head).
- A "die and respawn" instruction waits for the quest hand-ins and pick-ups right there.
- Camping 101 quests for professions you didn't pick (or know) aren't taken; a step with two of them only
  names the one that's yours.
- Profession instructions only send you to a trainer who teaches what you need (Kitta Firewind at the Tower of
  Azora teaches only Expert Enchanting, a village trainer only Apprentice): Itinerary_Data knows the ranks from
  the trainers' titles; a trainer you opened counts by what they showed you.
- Profession trainers that WoW Forever added (like the junior trainers in the starting areas) are picked up as
  soon as you target, hover or open them.
- Class trainer instructions in every starting area: with Itinerary_Data all class trainers are known (before,
  only trainers you had opened were known).
- The class trainer instruction no longer shows when its tooltip says there's nothing new: both go by the
  trainer's recorded list against your spellbook.
- The trainer instruction no longer waits for a route trainer stop a few steps ahead when that stop is itself
  shown as an instruction.
- Settings: a switch with a longer label is wider instead of cut off (Panel > Instructions: "In the panel").
- Credits: *Meow* is "Cat Meow 2" by Cat Stevens (SoundBible.com, CC BY 3.0); LICENSE.txt names every library
  with its author and license, and the manual has a Credits and license section.

## v1.2.0 (2026-10-15)
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
