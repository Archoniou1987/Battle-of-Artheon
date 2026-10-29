# Solo Ground Loot — Real Combat Settlement Adapter (2026-10-21)

## Scope

Mandatory Solo Final-v1 direction: combat reward appears on the actual
hex cell and is NOT inserted automatically into the player's inventory.
Pickup remains a separate **5-second world action**. The lower/right
`На клетке` UI and generic NPC/quest object resolver are subsequent work.

## Opt-in integrated path

`HexMapTurnService.finalize_group_victory_atomic(..., now_unix, ground_loot_solo=true)`
performs the following while map movement is still paused:

1. Settle the real terminal group fight using its checkpoint and once-only
   `MapCombatSettlementService` receipt. This calculates the loot only once.
2. `GroundLootSettlementAdapter.migrate` checks the committed encounter
   marker and assigned player, validates every item before touching world
   state, and moves all unclaimed drops from the encounter pool to
   `ExpeditionState.world_state.ground_item_instances` with the same
   item IDs and combat coordinates.
3. Remove the old per-encounter loot pool from this expedition and record
   the `ground_loot_settled_encounters` marker. The immutable settlement
   receipt remains tied to the same SHA; it cannot be rerolled or replayed
   to resurrect a removed pool.
4. Commit the real winner's current HP/Mana and one atomic world snapshot.
5. Acknowledge the receipt/checkpoint only AFTER the world snapshot
   verifies; only then release the map pause.

The earlier `finalize_group_victory_atomic` default remains unchanged
(`ground_loot_solo=false`) until the existing callers/UI have been migrated
and previous regression tests replaced. No Combat Engine, damage or
round-resolution formula changes.

## Consequences

- Solo combat drops in the opt-in path use the ground registry's
  `policy=expedition`. They are not subject to the old 15-minute
  `EncounterLootPool` timer.
- Items require the same-cell 5-second `GroundLootService` pickup and
  slot/weight checks. After pickup/drop, the scene owner must call
  `MapWorldCommitService.save_progress` to preserve changes atomically.
- Object ownership, quest objects, manual NPC attack, and the actual
  lower/right `На клетке` display remain work for future integration.
- The snapshot schema is currently single encounter. Multi-encounter
  world snapshot rotation remains an outstanding structural limitation
  before a full expedition playthrough can be considered complete.
- Old pool claim APIs exist only for legacy tests/callers and should
  eventually be migrated rather than kept as the Solo default.

## Validation

Early ABI Branch Tests includes
`tests/map/ground_loot_combat_e2e_runner.gd`: real hex contact, two NPCs,
terminal checkpoint, settlement and ground conversion, atomic bundle,
journal cleanup, reload, NPC tombstones, 5-second manual claim,
atomic post-claim save, and no duplicate reward after restart.

**CI for this new adapter package has not been run yet.** The last confirmed
green run was ABI #280 (39620467141), SHA 00b40666484b9155f5ed938db02dd52920e399b6.
