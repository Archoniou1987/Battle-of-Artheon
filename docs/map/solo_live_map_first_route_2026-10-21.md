# First playable Solo map navigation — 2026-10-21

Previous verified ABI #295 (39666908176) succeeded at
153761fe9d5034334761fab0822c9a00d1de7776.

## Implemented route

The village's "Карта" navigation now offers "Начать экспедицию" for a
player without an expedition and "Продолжить экспедицию" for an active,
verified expedition. It commits the canonical town snapshot before the
initial handoff to SoloTownExpeditionBridge, with an immutable origin
fingerprint. A pending combat or corrupt expedition still blocks entry.

New standalone scene:
- scenes/main/solo_live_map.tscn
- scenes/main/solo_live_map.gd
- core/map/solo_live_map_session.gd

The scene reopens exactly the saved expedition and character, creates a
12x12 TacticalMapState grid, places the saved player at their saved
hex and accepts ONLY one adjacent HexGrid step per input. The step is
committed through ExpeditionSaveService.save before any success is
displayed; failed storage rolls back the live hex and authoritative
expedition position. Closing the expedition seals its return receipt,
then adopts owned items into the canonical town snapshot BEFORE
changing back to the village scene. Incomplete combat manifests block
both movement and return.

The runner tests initial save, non-adjacent refusal, saved steps after
restart, retained item instance, pending-combat return refusal,
successful closed expedition checkout, city item uniqueness and scene
resource loading. It runs early in the existing ABI workflow.

## Explicit limits

This is a **first real persistent movement slice**, not the full
procedural campaign map. It uses an empty all-passable 12x12 grid
rather than themed region/NPC generation. No NPCs, attacks, pathfinding,
movement timers, fog memory, loot interaction or live Arena are wired
into this new scene. The debug viewer remains independent and
synthetic; no real combat is falsely simulated.

Do not add NPC map contacts until the full battle UI and settlement
adapter are connected safely. One fixed expedition identifier per
player means new expeditions after successful exit are not yet
rotated; that lifecycle needs dedicated work.

New package has not yet passed Godot CI.
