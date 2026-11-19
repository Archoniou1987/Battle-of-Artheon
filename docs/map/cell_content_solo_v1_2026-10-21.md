# Cell Content Solo — read-only interaction boundary (2026-10-21)

## Approved purpose

The hex map handles movement and vision. The lower (portrait) or right
(landscape) panel has a primary **«На клетке»** tab showing compact icons
for things located at the player's CURRENT cell: ground items, alive NPCs,
animals, quest objects, resources and future interactions.

`CellContentService.inspect_current_cell(map,bridge,expedition,player,now)`
is the first read-only data projection. It merges:
- `GroundLootService.items_at` — item instance ID and inspect/pick-up
  action hints; no automatic pickup.
- `MapNpcBridge.npc_at` — only live NPCs with visible display name, level,
  aggression and inspect/attack hints.
- `MapCell.object_ids` — inspect-only until real typed world-object
  metadata/action validation exists.
- Resource `MapArea` on this cell, while not depleted, with inspect/gather
  hints and data-defined gather duration.

**Important:** UI action hints are not authorization. The future
`InteractionResolver` must re-check every action against actual map,
NPC, inventory and quest state. In particular, whether an aggressive NPC
initiates an encounter is independent from the player's permission to
attack it manually; an animal can be peaceful but attackable. Both use
the same real Combat Engine (not a separate hunting damage model).

The projection does not create a new authoritative registry. The owners
remain `ExpeditionState`, `TacticalMapState`, `MapNpcBridge`,
`ItemRepository` and future quest/world-object services.

## Deliberate exclusions

- No changes to existing combat formulas, AI aggro rules, or map
  collision/encounter triggering. Manual attack and hunting actions
  will need a safe encounter entry point in a future package.
- No actual clickable «На клетке» widget yet; the debug map viewer
  still has legacy separate loot dialogs and test controls.
- No generic object interaction without schema/permission validation.
- No multiplayer services; Solo-First / MP-Compatible.

## Test

Early ABI Branch Tests step `tests/map/cell_content_solo_runner.gd`
covers per-cell aggregation, no remote loot, inspect/pickup/attack/gather
hints, no inventory side effects, removal of dead NPCs and automatic
content change as the player walks to a neighboring cell.

Last CI confirmed passing for previous Combat→GroundLoot package:
#282 / 39623454707 on dd738e761e8bc3df5c8029c4ef862a81e468b115.
The new projection/test has not yet run CI.
