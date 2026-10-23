# Changelog

## Unreleased

### Fixed
- The *Talent points* instruction never showed on WoW Forever: its talents are a talent tree of the newer kind, and
  the old ways of asking for unspent points don't exist there. It reads the tree's points now, and clicking it
  opens the talent window.

### Changed
- Resetting a character (Settings > Quests > *This character*, or `/iti wipe yes`) keeps its level times (when it
  reached each level). Route progress, trainer and profession data are forgotten as before; a new character with a
  deleted one's name and a factory reset still start with none.

## v2.1.18 (2026-10-23)

### Added
- The target button shows the faces of the routes' NPCs and mobs before you've met them: Itinerary_Data (1.6) now
  has them, read in game on the beta. A creature it has no face for is read in game as before.

### Changed
- The target button only remembers the faces of NPCs and mobs your route has (or that it's after right now), not
  every creature you target or hover. That list grew all the way through leveling (about 850 after the beta, kept
  in every character's memory).
- Your party members' quest progress no longer makes Itinerary look over your route again; only your own does.

### Fixed
- A remembered face could belong to the creature read just before it: a human NPC with a Voidwalker's face, many of
  them after the beta. A face is now remembered only once the game has that creature's own model. The
  faces remembered so far are cleared once and come back as you meet them again.

## v2.1.17 (2026-10-22)

### Fixed
- A "get the flight path" step was passed as soon as you got there once any flight map had opened (the Ironforge
  flight path on arriving by tram): WoW Forever's flight map also lists the flight paths you haven't found yet, and
  those counted as yours. Only the one you're at and the ones you can fly to count now; the old list is dropped.

## v2.1.16 (2026-10-22)

### Added
- Your first profession's apprentice bag (Apprentice's Herb Pouch, Mining Pack, Skinning Satchel) is bought with
  its gathering tool, at a vendor that sells it (Settings > Professions > *Gathering tools*). Only one: you have
  one reagent bag slot, so none for your second profession, and none while you have one of the three or
  something is in that slot. The bag goes into your reagent bag slot by itself (the game puts a bag you buy in
  your first free bag slot): moved there right after the buy, out of combat. The Skyborne start's "Buy a
  [Skinning Knife]" step with the satchel ended with only the knife.

### Fixed
- Along-the-way tasks that ended before the route's next step of its own were never shown - Falling With Style's
  Walk on Air (and its button) on the Skyborne start, and about 50 a route: travel hints, objectives and kills the
  guide has you do alongside. They now last through that next step, where the guide shows them too.
- A bag on your bag bar or in the reagent bag slot counts as one you have, for a step's items and the panel's
  counts (the game's item count can leave those out).
- A step that collects items for a quest you're on (the Small Spider Legs for Recipe of the Kaldorei) was
  passed when you had already done the next step (The Glowing Fruit picked up on the way), and the route then
  waited at the hand-in. It now waits until you have the items, and a hand-in you get to without them takes you
  back to them.
- Route editor: a text box goes back to the start of its text when you leave it, also without a change (a long
  hint you had moved through showed only its end). Picking another step while you're still in a box shows that
  step's text in it, and what you typed is saved to the step you typed it for - it went to the step you picked.
- An optional buy with its items at a vendor (the Skyborne Rogue's "Buy and equip a [Shortsword]" at Destin
  Thriceforged, weapons, food, the auction house's lists) showed under *Along the way* as an item count
  ("[Shortsword] 0/1") instead of as an instruction you can click for the arrow. It's an instruction now, with the
  count on its line (several items: each with its count under it).
- At the class trainer, a skill left because the money for your professions comes first (their tools and learning
  them, up to level 4) now says so in chat, like one left for the class skill reserve. It was left without a word
  (Stealth on a level 2 rogue).
- Finding your place from your quests (after a reset, a new route, `/iti find`): a few quests handed in or picked
  up early, just ahead of where you are (a quest finished on the way, the next hub's quests taken already), could
  move you past steps of yours - sometimes by dozens of steps - and a lot of them right after your place could
  send you back to the route's start. Your place now stays where it is.

## v2.1.15 (2026-10-22)

### Added
- A target button per kind of mob: a step (with its along-the-way objectives) after several kinds of mobs shows
  one button for each (up to 4, your step's first), with that mob's face; clicking one targets only that kind.
  The target key goes for all of them as before, and its key label shows on the kind it would take now.
- Settings > Keys > *Skip mobs already in a fight* (off): the target key passes over a mob that already has a
  target of its own (the one you just tagged, or one someone else tagged), goes on with the game's tab target
  (twice at most) and casts no tag spell on a busy one - also in combat. For tagging one fresh mob after the
  other in contested places; the next enemy can be another mob close by.
- Talent points you haven't spent are an instruction (*Spend your 2 talent points*) until you spend them; click it
  to open your talents, its × hides it until your next level. Settings > Trainer > *Talent points* (on).
- Settings > Keys > *Tag spell* (under *Tag with a spell*, per class): Automatic (the first of the list you
  know), another one of the list, auto attack, or any spell you type. One you don't know yet stays Automatic
  until you learn it.

### Changed
- Settings > Panel > *Item & target buttons* is now the target buttons' corner: the item buttons start at the
  other corner on the same side, and both grow towards each other (bottom left: target buttons up from the
  bottom, item buttons down from the top). Too many for the panel's height: the item buttons move one column
  out. With the target button off, the item buttons take the chosen corner as before.
- Your place on a route you start fresh (a new route, *This character* reset, `/iti reset`, a route that's no
  longer installed) and `/iti find` come from the quests you've done: Itinerary looks for where the steps you've
  done (your quest log, the quests you've handed in) stop and the open ones begin, and takes you there - trips,
  hearth settings and flights in between, and quests you skipped here and there, no longer stop it one by one.
  When it's unclear, the place where the route goes on in the zone you're in wins, then a chapter for your level.
  Quests in your log whose steps are behind it show in the skipped line. A new character starts at the beginning
  as before; at login it waits until the quest log is complete.
- Lighter in game. The route you switch away from is let go at once instead of staying in memory until the next
  reload; going back to a route pack's route then takes a reload (it already did for any other one). On a route
  of your own, the route packs' step pools aren't kept either. The other routes' chapter lists, the second copy
  of every waypoint list and kill area, the editor's keys for each step (made when the editor first needs them)
  and a copy of the shipped class skills are gone: about 1.3 MB less with a route pack route. The shipped class
  skills no longer go into the saved variables (only what trainers showed you), so the file is smaller too.
- Your own routes are kept packed - one short string each, in memory and in the saved variables - except the one
  you're on: a recorded 1-30 run took ~650 KB of memory on every character of the account, packed it's ~30 KB.
  Switching to one of them takes a reload, like switching to a route pack's route (not for a route you made in
  this session). The first login with this version packs them; nothing about them changes.
- Faster panel updates with professions picked: the spending plan, the class skills you could learn and whether
  a gathering book is still ahead on the route are worked out once per update instead of up to 17 times (each
  walked the class's skill list, the book check the rest of the route): an update takes about 1 ms instead of
  10-16 ms in our tests, the trainer check every 2 seconds 0.4 ms instead of 3-5 ms, with a sixteenth of the
  garbage.

### Fixed
- Share quests in a group: taking several quests from one NPC, the second share reached a group member while the
  quest window of the first was still open ("Bob is busy.") and they never got it. Quests are shared one after the
  other now, a few seconds apart, and someone who was busy gets it again a moment later, someone too far away once
  they're near you. Every 10 seconds the quests shared this way are checked against your group: whoever near you
  still hasn't got one gets it again - not after they declined it, can't take it, have done it or have a full quest
  log; at most 5 times, for 30 minutes after you took it. The repeats' chat lines are left out (but "... has
  accepted your quest").

## v2.1.14 (2026-10-21)

### Added
- Bank steps: on a "Deposit these into your bank" / "Withdraw these" step, opening the bank puts the items in or
  takes them out, one after the other, and the next bank step's too (withdraw, then deposit at the same banker).
  Chat says what moved. A deposit is done once none of its items are in your bags, a withdrawal once the bank has
  none of them left (also one you never had). Settings > Route > *Bank steps* (on); hold Shift to do it yourself.
  In the editor: *Deposit* and *Withdraw* on the More page (Shift-click the items).
- Settings > Route > *Group quests* (Show): the routes' group quests (Tharil'zun, Wanted: Gath'Ilzogg, the Slag
  Pit chain), and with them on, the guide's solo versions of those parts are left out. Skip: for playing alone -
  the group quests are left out and the solo versions are in. Editor: *Group* on the Conditions page.
- Your Hearthstone in the route: "Grind until your Hearthstone is ready" (or "<5 minutes") is done by itself when
  it is, and stays done after you hearth; a hearth step is passed while your Hearthstone is on cooldown, and one
  to a home you didn't set (Stormwind with your hearth in Goldshire) is left out. A shaman's Astral Recall counts.
  Editor: *Hearthstone* and *Hearth set to* on the Conditions page, `hearthstone ready` / `hearthstone <25m` in
  *Done in*.
- Escorts wait for your group (Settings > Quests, on): an escort or fight that starts the moment you accept it,
  from the NPC who also takes the quest before it (Rescue OOX-17/TN!, The Absent Minded Prospector, Jail Break!),
  is only accepted in a group once nobody near you still has that quest to hand in - nobody gets left out. The
  quest window waits, chat names who you're waiting for, and it's accepted by itself once they're ready. Solo,
  and contested escorts with nothing to hand in there first, are taken at once as before.

### Changed
- The settings window is shorter: one line per setting, its explanation when you hover it (the window used to
  grow to its longest tab with every explanation written out, taller than many screens). The window is as tall as
  the tab you're on, keeps its top edge where you put it, and scrolls when a tab doesn't fit on your screen.
  A new tab **Route** has the settings for what the route does (group quests, skip overlevelled steps, bank steps,
  auction house steps), out of Quests. A setting that only works with the one above it is indented under it with a
  thin line from it, and its tooltip says what it's part of (*Which quests* and *Escorts wait for your group* under
  *Accept and hand in*, the pin counts and the line under *Map pins*, *...only worthwhile ones* under *Buy class
  skills*). *Which quests* says it's about the quests picked up for you; finished ones are handed in either way.
- The step sound also plays when an objective along the way that takes a while is done (kill or loot objectives,
  items to collect), as for your own step - one sound when both are done at once; not when you abandon or skip it.

### Fixed
- After a route pack update moved the step numbers, you kept your old step *number* rather than your step
  (the check that should find it again never got to run), and your hand skips stayed on the old numbers - on
  other steps now. Your step is found again by what it is (and by the steps around it, if it changed itself),
  and the skips, "not offered" marks and places reached move with their steps; one whose step the update took
  out goes. Itinerary keeps what those steps are from now on, so this works from the next update. (Which build
  your place belongs to is told from the route's steps as built, so changing the route pack's choices counts as
  well; a place saved without it is checked by whether your step is still where it was.)
- The arrow pointed at an instruction you clicked (a trainer) stayed there after you dismissed that
  instruction with its ×, with nothing left to click to get it back: it's back on the route now, also when
  the instruction goes away by itself.
- The skipped quests list showed a quest whose skipped step was an objective step as "Quest 1076": it names it now
  (Devils in Westfall).
- Editor: clicking a step showed its Hint (or Text) blank or only its end - a long text opened scrolled to the
  end, and a hint of several lines showed nothing. The fields now show from the start, with line breaks as `\n`
  (type `\n` for a new line; it's saved as a real line break).

## v2.1.13 (2026-10-20)

### Changed
- The route's pins on the world map sit on top of the game's quest symbols (quest givers, the quests in your log,
  the tracked quest), which covered them; your own arrow, your group and the map's waypoint stay on top.

### Fixed
- Click through the arrow didn't work after a reload or login: the arrow took the mouse again (the game turns a
  frame's mouse back on when it gets its hover script, which was set after the click-through).

## v2.1.12 (2026-10-20)

### Added
- Settings > Arrow > Click through the arrow (off): while the waypoint arrow is locked, your mouse goes through
  it to whatever is behind it. Unlocked (Arrow position), it takes the mouse again so you can drag it.

## v2.1.11 (2026-10-20)

### Added
- Your own sound for a finished step: put .ogg or .mp3 files in Interface\AddOns\Itinerary_Sounds\ (a folder
  of your own, so an update doesn't touch it) and name them in Settings > Sounds; each becomes a pick. The
  sounds your other add-ons share (EllesmereUI, WeakAuras, SharedMedia packs - LibSharedMedia) are picks too.
  A sound that can't play says so in chat (a file added while the game runs is found after a restart).

### Changed
- The step sound has its own settings tab, Sounds (it was under General); the tabs are two rows of five.

## v2.1.10 (2026-10-20)

### Changed
- The quest chain only shows when you hover the quest name on your step: the "+N follow-ups" after the name is
  gone (the chain's tooltip says how many follow-ups skipping it leaves out).

## v2.1.9 (2026-10-20)

### Added
- Settings > Quests > Skip overlevelled steps (on): off, the route doesn't leave anything out for your level.
  Quests in your log that a level skip left out show in the panel's skipped line, marked "your level"; going
  back to one brings its quest back. Chat says when a part of a chapter is skipped for your level.
- Settings > Keys: a second key for the target button and each quest item button, as in the game's Key
  Bindings. Changing or clearing one keeps the other; the button tooltips name both.
- Quest chains on your step: a quest the route takes follow-ups of later says so after its name ("+7
  follow-ups"), and hovering the quest name shows its chain - the quests before it (done ones checked), this
  one and the ones after it, each with where the route takes it - and what skipping it leaves out.

### Fixed
- A guide's level jump (Westfall 13-15 is skipped when you get there at 15 or above) skipped the rest of the
  chapter when you reached that level in the middle of it after the route was walked again from the start (a
  route change, /iti find), and with it the hand-ins of quests you had done. A part you've begun is no longer
  skipped, and a quest that's done is always handed in, also on steps marked "skip from level N".
- A pick-up step for several quests waited for a quest you had skipped, abandoned or weren't offered (Testing the
  Wells taken, Murloc Gills left out: the step stayed at 1/2 until you skipped it). Such a quest no longer holds up
  the others, as for hand-ins. The panel's count leaves out the quests you left out, and an objective step for
  two objectives of one quest no longer shows a quest count.
- The panel's skipped line listed every quest of a step you skipped, also one whose part of it you had done
  anyway ("Accept Testing the Wells, Murloc Gills" skipped to leave out Murloc Gills: Testing the Wells, in your
  log and done, showed as a skipped quest still open). A quest of a skipped step is only listed while its part of
  the step isn't done.

## v2.1.8 (2026-10-20)

### Fixed
- Quest automation took a quest the route only picks up when you already have its items (take it and hand it in
  at once, like Pearl Diving) whenever you talked to its quest giver, so it sat in your log with nothing in the
  route working on it. Such a quest is now only taken while you have the items.
- A route step can check several items (all of them must be in your bags, or all missing); before, only one of
  them counted.
- A hand-in or objective step for several quests waited for a quest you had skipped, abandoned or weren't
  offered (An Aggressive Defense handed in, Culling the Threat skipped: the step stayed at 1/2). Such a quest no
  longer holds up the others.

## v2.1.7 (2026-10-20)

### Fixed
- A quest step meant for players without a profession (Bathran's Hair without [Find Herbs], the wolves of
  Wolves at Our Heels below Cooking 50) was left out when you hadn't picked that profession, so neither version
  of the objective showed. Leaving out "below" steps of a profession you didn't pick now applies to profession
  steps only ("Cook until 50"), not to a quest's own steps.

## v2.1.6 (2026-10-19)

### Fixed
- An escort quest step (Therylune's Escape, The Defias Traitor) stayed open after the escort made it: the game
  sets the quest complete but can leave its escort objective unfinished. A complete quest now counts as every
  objective done, in the step and in the panel's lines. `/iti debug` lists the objectives of the step's quests
  as the game gives them.
- The arrow skipped someone to talk to on the way when you already stood at the step's own place: on "Talk to
  The Threshwackonator 4100 to start the escort" after taking the quest from Gelkak, it pointed at Gelkak (where
  you lead the robot) instead of the robot. The arrow still joins a path at its closest point, but no longer
  past an NPC on the way you haven't reached yet.

## v2.1.5 (2026-10-19)

### Fixed
- Lua errors on every mouseover of an enemy (dead ones too) in a dungeon fight. WoW Forever's engine keeps the
  names, GUIDs and tooltip lines of creatures secret from add-ons there, and Itinerary's look for profession
  trainers searched them. Every place that reads a creature's name, GUID or tooltip (trainers, the target
  button and its faces, name tags, gather spots, the recorder, NPC dialogue) now skips a secret value instead.

### Changed
- The target button always goes for your step's own mobs before the ones of an along-the-way objective,
  however close those are (it used to prefer them only by a little, so one right next to you won). An
  along-the-way mob wins only when none of your step's mobs is in reach, or the ones in view are tagged by
  someone else. A mob an along-the-way step is after on its own (one of it needed) now comes first only among
  the along-the-way ones.

## v2.1.4 (2026-10-19)

### New
- Along the way: the small × that instructions have is on side objectives too. It hides the entry on this
  character - a Camping 101 quest you're not doing, items you don't want to collect (with all their tiers), a
  quest's objectives. The target and item buttons leave hidden entries out; the route's own steps for that
  quest still come. Settings > Panel > Hidden along the way lists them; click one, or Show all, to bring them
  back.

### Changed
- The profession question for a new character (and `/iti professions`) has the look of the settings window:
  professions as chips, the first main profession as a switch, Save and Later, × and Escape to close.

### Fixed
- The target button didn't find the next step's NPC while you still had the last one targeted: "Talk on second
  press" had turned its key into Interact with Target for any friendly NPC you had targeted, so the next
  presses talked to the old one (or did nothing) until you cleared your target. Now only an NPC of the step
  you're on makes the next press talk, and a new step undoes it right away.

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
