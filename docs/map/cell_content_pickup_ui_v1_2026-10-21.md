# Cell Content UI — World-backed Solo Pickup (2026-10-21)

## Scope

After ABI #284 passed on commit `74a778414a4b5f7994e1370e489d7d4899b151a7`,
the existing Debug Map Viewer's `CellContentPanel` now supports a
five-second item pickup progress UI plus explicit cancellation.

The UI still contains compact item/NPC/world-object icons. Selecting an
item reveals a **Поднять (5 сек.)** button. Picking up is never automatic;
other object types remain read-only and require their own validated action
entry points.

## Durable authority boundary

`DebugMapViewer.set_cell_content_context(expedition, character, bridge,
repository, encounter_key, snapshot_path)` now accepts all required owner
references. To enable world pickup, the caller must provide the actual
expedition, character, repository, completed encounter identity and verified
atomic world snapshot path. The default Debug Map Viewer has **no**
authoritative character/world bundle and therefore cannot mutate items.

On pickup:

1. `MapWorldCommitService.read` verifies the existing snapshot/owner.
2. `GroundLootService.begin_pickup` validates current cell, item and
   ownership. The UI displays five seconds of progress.
3. Movement selection, battle entry, explicit cancellation or rebuilding
   the map cancels the pending pickup.
4. `GroundLootService.finish_pickup` revalidates action time, location,
   permissions, inventory slot/weight limits and item uniqueness.
5. `MapWorldCommitService.save_progress` commits the new expedition,
   repository and inventory **together**. On failure the UI rolls back the
   new inventory ownership and ground registry to their prior in-memory
   state and does not report success.
6. Projection refreshes so that the item disappears from the current cell
   only after the saved pickup.

## Not yet solved

- The standalone synthetic Debug Map Viewer doesn't create actual
  persisted playable expedition objects. A full map-world scene/orchestrator
  must provide its actual owners to this interface.
- Existing legacy pop-up loot tests and UI remain for compatibility, but
  the new Solo design is the compact **На клетке** tab.
- Manual NPC attack, peaceful animal hunting, world quest interactions,
  expedition save rotation across multiple fights and complete rollback
  under disk failure all need broader integration tests.
- For a future MP runtime, server-validated actions replace local UI
  clocks; they are not required for Solo Final-v1.

## Tests

`tests/ui/cell_content_panel_runner.gd` extends its previous UI smoke
check with pickup request and cancellation signals, selected item identity,
5-second progress display and reset. This UI package is unverified by CI
until a manually triggered ABI Branch Tests run.
