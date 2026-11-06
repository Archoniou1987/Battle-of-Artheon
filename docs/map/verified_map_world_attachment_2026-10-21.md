# Verified map-world binding — Solo Final-v1 (2026-10-21)

## Goal and scope

The Debug Map Viewer's «На клетке» tab must not acquire mutable
GroundLoot from a synthetic map and fabricated character. The data owner
is the exact real expedition loaded from a **verified** atomic
`MapWorldCommitService` snapshot.

## Implementation

- New `core/map/map_cell_world_session.gd` binds a verified world
  snapshot to a live `TacticalMapState` and `MapNpcBridge`, restoring
  the canonical expedition, ItemRepository and CharacterState.
  It refuses missing/invalid snapshots, inactive expeditions, player
  identity mismatch, player-location mismatch, and unreconciled defeated
  NPCs. Its `current_cell` uses `CellContentService`.
- The atomic battle completion in `HexMapTurnService` persists the
  player's actual hex (`expedition.player_position`) before the world
  commit. If the commit fails, the in-memory position is restored.
- `DebugMapViewer.attach_verified_cell_world` accepts a snapshot,
  identities and a live NPC bridge after the map is already generated
  and reconciled, validates with `MapCellWorldSession.open` and binds
  the restored owners to the existing CellContentPanel.
- On each completed hex movement in a bound world, the new player
  location is saved using `MapWorldCommitService.save_progress`
  before the UI and collision logic observe the new cell. On failure,
  the player entity position is rolled back and movement stops.
- Debug map regeneration now clears all old expedition, repository and
  character references instead of attaching an old save to a new map.

## Boundaries (important)

This is the **verified attachment mechanism**, not yet a full Solo
expedition launch/recovery scene. The actual game owner must construct
the playable map, reconstruct NPCs, apply `reconcile_map`, and align
the player position with its saved expedition before calling
`attach_verified_cell_world`. The Debug Map Viewer currently
generates synthetic NPC/map representations and cannot safely infer
their ownership from an unrelated save.

The atomic world snapshot remains **single-encounter V1**. A general
expedition save/restore lifecycle (before the first fight, after
multiple encounters, normal exit, defeat) still requires a separate
world-save architecture update.

## Regression gates

- `tests/map/ground_loot_combat_e2e_runner.gd` additionally verifies
  that the atomic victory snapshot contains player coordinates and
  that the reconstructed, reconciled map attaches to the real saved
  GroundLoot inventory owners.
- `tests/map/debug_map_viewer_runner.gd` rejects nonexistent world
  snapshot attachment and checks map regeneration clears old mutable
  state.
- These scripts are already part of the ABI Branch Tests workflow;
  no new additional GitHub Actions workflow is needed.

New code awaits manually initiated Godot 4.5.1 CI. Previous package
success: ABI #285, run 39633145177 on daf514779d736f1df61d2fd7d5f201d7097b7ed0.
