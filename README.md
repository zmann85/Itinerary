<p align="center"><img src="manual/logo.png" alt="Itinerary" width="160"></p>

# Itinerary

A step-by-step leveling companion for WoW Forever: a route panel, a waypoint arrow and a lot of small
automation, built around routes you record and edit yourself.

<p align="center"><img src="manual/route-panel.png" alt="The route panel" width="434"></p>

Itinerary ships **without routes**. Record your own with the recorder, import one somebody shared, or
install a route pack (a separate addon with its own license). Trainer, vendor and gathering positions come
in the separate `Itinerary_Data` add-on (GPL v3); without it Itinerary learns them as you meet them.

## What it does
- **Route panel**: the current step (accept, complete, turn in, travel, fly, hearth, train, grind, ...) with
  hints, live objective counts, an INSTRUCTIONS card for things to keep doing, an ALONG THE WAY section for
  side objectives and items to collect, the next few steps and your pace against a reference run.
- **Waypoint arrow**: points at the current step's NPC, objective area or travel path, with distance and the
  instruction text above it. Several arrow styles; colour schemes for the whole UI.
- **Map pins**: your next stops as numbered pins on the world map and minimap, with a dotted line between them.
- **Quest and item buttons**: secure buttons for the step's usable items, the hearthstone, and a target
  button that finds the step's mobs or NPC (with key bindings).
- **Automation** (each part can be switched off; hold Shift to do things by hand): accept and turn in route
  quests, click through quest dialogue, sell junk, set the hearthstone, take flights, buy class skills
  (worthwhile ones first, keeping some money back), learn professions and buy their tools.
- **Trainers**: instructions when a class trainer, weapon master or profession trainer with something
  for you is close by, with a tooltip of what's ready to learn and what it costs.
- **Professions**: pick up to two main professions plus secondary ones; Itinerary plans the money for
  learning them and their tools and uses the starting-zone book reward for a gathering profession.
- **Gather mode**: a farming route from one herb or ore spawn spot to the next, with map pins; nodes you
  find are remembered.
- **Route editor and recorder**: record a route while you play (quests, trainers, flights, hearthstone,
  hints, instructions, along-the-way objectives), change any step and everything it can do (every step type,
  conditions, waypoints, dialogue, macros), drag a step's waypoints into place on the world map, and share
  routes as import strings.
- **Group play**: share every quest you accept with your group (optional).

## Commands
`/iti` show/hide the panel, `/iti settings`, `/iti edit` (route editor), `/iti recorder`, `/iti routes`,
`/iti next`, `/iti back`, `/iti gather`, `/iti debug`. The full guide is in [MANUAL.md](MANUAL.md), what changed in [CHANGELOG.md](CHANGELOG.md).

## License
All rights reserved - see [LICENSE.txt](LICENSE.txt). Libraries and credited sounds keep their own licenses.
