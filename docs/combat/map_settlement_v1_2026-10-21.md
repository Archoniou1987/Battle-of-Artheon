# BOA Map Combat Settlement V1 — 2026-10-21

## Problem

Group-combat round checkpoints already preserve a terminal winner and prevent
replaying the final combat round. They are **not sufficient** for exactly-once
world consequences: mobile process death can happen between a successful combat
check, NPC removal, loot rolling, expedition save and inventory save.

The existing `MapCombatOutcomeService.resolve_group_victory` is intentionally
unchanged in this phase to preserve existing contracts and prior CI behavior.
A new explicit, opt-in, staged settlement adapter sits between the combat
checkpoint and `ExpeditionState`, exposed through `HexMapTurnService`.

## Transaction boundary

`MapCombatSettlementService.stage(session, expedition, map, bridge, character, item_repo, loot_service, chances, encounter_key, receipt_path, now_unix)`:

1. Validate a completed **player-win** group battle, real terminal checkpoint
   on disk, matching round/event counters, exact participating NPC instances,
   finalized enemy death and the player's persistent/combat IDs.
2. Roll all NPC possessions **exactly once**, preserving item instance IDs and
   original item definitions. Assign ownership to the winning character.
3. Write a **standalone** versioned SHA-256 receipt to a `user://` temporary
   file and atomically rename. No NPC death, inventory changes or loot pools
   are applied before the receipt is durably staged.
4. Existing matching receipts are returned unchanged; mismatched/stale or
   corrupted receipts are rejected rather than overwritten or re-rolled.

`MapCombatSettlementService.apply(receipt_path, encounter_key, expedition, map, bridge, character, item_repo)`:

1. Verify envelope integrity, identity of expedition, character, NPC cohort,
   saved positions, rolled reward instances and ownership.
2. Reject missing/moved/coincident NPC IDs *before* any world mutation.
3. Restore only missing reward item instance definitions, without overwriting
   current item durability, ownership, upgrades or inventory data.
4. Resolve living NPC deaths through `MapNpcBridge.resolve_death`; if they are
   already dead, do not attempt to kill them again.
5. Persist the loot pool in `ExpeditionState.world_state.encounter_loot_pools`
   and an immutable encounter receipt hash in
   `world_state.committed_combat_outcomes` **once**. If that same marker is
   present on replay, suppress pool re-creation: the original items may have
   been claimed, expired or removed. Regenerated map NPCs are still killed
   again, since the new scene's entities start alive.
6. Return `needs_world_save: true`. This means the current owner of
   expedition/item/world storage MUST flush its own durable snapshots.

`settle(...)` combines stage and apply for the normal path. Crash recovery
can call `apply(...)` directly with fresh ExpeditionState, ItemRepository
and MapNpcBridge objects.

The live hex-map orchestration entry point is `HexMapTurnService`:
- `move_player(...)` still triggers contact using `HexEncounterCoordinator` and pauses patrol/turn movement.
- `begin_resumable_group_combat(encounter,...)` opens that existing encounter via `MapEncounterCombatService.begin_resumable`, or resumes a saved checkpoint after map regeneration.
- `resolve_group_victory_durable(session,...)` stages+applies the actual world settlement and only then releases the coordinator's combat pause.
- `recover_settled_group_victory(...)` reapplies a previously persisted journal on a regenerated map before gameplay continues.
Existing non-persistent `resolve_group_victory` remains untouched.

## Recovery matrix

| Crash point | Durable object | Recovery |
|---|---|---|
| Before end-round checkpoint | Previous completed checkpoint | Resume battle from last committed round |
| After end-round checkpoint, before stage | Terminal combat checkpoint | Validate victory; stage one deterministic reward receipt |
| After stage, before applying death/loot | Terminal checkpoint + receipt | Rebuild world, replay exact receipt, never re-roll |
| After applying death, before expedition save | Receipt | Rebuild NPCs; reapply their deaths and once-only pool |
| After expedition save, scene recreated | Expedition ledger + receipt | Re-kill fresh map entities, do not recreate pool or resurrect claimed drops |
| After durable world+inventory save | Expedition record + receipt | Future integration can safely acknowledge/compact the journal, after confirming both snapshots |

## Explicit limitations and next integration boundary

- This package supplies the **world-level settlement mechanism**, not
  an already wired player-facing map battle UI. In `scenes/main/main.gd`
  there is currently a training Arena but no world map battle scene lifecycle.
- No automatic deletion/acknowledgement of settlement receipt or combat
  checkpoint is implemented here. Clearing them before both world AND
  item/inventory persistence is durable risks exactly the same exploit this
  journal prevents. Integrate acknowledgement with those existing saves in
  the next package.
- The journal is scoped to a **single active encounter**. Its default file
  path is `user://map_combat_settlement_v1.json`. Concurrent fights,
  stacked expedition sessions and cross-device sync require separate
  encounter-keyed storage/coordination.
- SHA-256 checks accidental truncation or alteration. It is not a
  cryptographic anti-cheat signature. Game-authoritative online settlement
  remains a separate future requirement.
- ItemRepository already owns existing item instance IDs; this adapter
  does not move items into player inventory automatically. The winner still
  claims the pool through `EncounterLootPool`/`ExpeditionState`.
- `MapCombatOutcomeService.resolve_victory` and the legacy grouped result
  APIs are unchanged; callers must opt into this durable route.
- Source-round reproducibility is governed by
  `GroupCombatCheckpointService`, not by this settlement service.

## CI

`tests/map/map_combat_settlement_resume_runner.gd` covers a real
`MapEncounterCombatService.begin_resumable` + `GroupCombatSimulator.run`
terminal battle; staging before and after victory; no world mutation before
staging; crash reconstruction before commit; restoring missing item instances;
strict one-time loot ownership; replay after expedition snapshot reload with
respawned NPC map; replay after one claimed item; rejected wrong
encounter/expedition/player and corrupted receipt. It runs near the start
of the manually triggered `ABI Branch Tests` workflow.

**CI for this new settlement package is pending** until manually run.
