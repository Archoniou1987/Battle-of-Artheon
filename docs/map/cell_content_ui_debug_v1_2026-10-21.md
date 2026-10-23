# Cell Content UI / Debug Map Viewer — 2026-10-21

## Current step

The successfully CI-tested read-only `CellContentService` is now
presented by a reusable compact `CellContentPanel` in the map viewer.
Its two initial tabs are «На клетке» and «События»; the first shows
compact icon-only representations of Ground Items, living NPCs, resource
areas and map objects. Selecting an icon reveals a short label and
the available **action hints** (inspect, pick_up, attack, gather).

The panel is placed in the existing `Root/Sidebar`, which the Debug Map
Viewer already moves **below the square map in portrait** and **right of
the square map in landscape**. The player cell projection refreshes on
regeneration and on each completed movement step.

A new explicit `set_cell_content_context(expedition, character, bridge)`
entry point allows the caller to connect the existing real owners.
Without this context, the Debug Map Viewer supplies an empty/temporary
expedition and NPC bridge, so the panel can only display map objects
already registered in the tactical map, not fabricated loot or NPCs.
This is intentional; the debug canvas's synthetic entity-role markers
are not live `NpcInstance` objects.

## Deliberately not implemented

- No actual pickup/drop button in the panel, no 5-second action UI yet.
  GroundLootService owns that mechanic, and a future command gateway
  must call it with persistence acknowledgement after a successful claim.
- No manual NPC fight, hunt, quest or trade mutation from a selection.
  The panel emits `entry_selected` only. The UI must not bypass actual
  world permissions or battle-start coordination.
- Legacy debug reward dialog remains temporarily available for old
  test flows; it is **not** the new Solo Final-v1 target.
- No MP/PvP runtime services; Solo-First / MP-Compatible.

## Tests

`tests/ui/cell_content_panel_runner.gd` validates tab creation,
compact icons, icon selection signal, location change and stale-icon
clearing. The test is an early ABI Branch Tests step, next to
`tests/map/cell_content_solo_runner.gd`. No CI has run against this
new UI package yet.

Previously confirmed successful: ABI #283 / 39630532389 on
d22042d5e480b2f61809f13caed7bd34b4bf7ea2.
