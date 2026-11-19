# BOA Atomic Map World Commit V1 — 2026-10-21

## Purpose and authority

The already-passing round checkpoint and combat settlement receipt correctly
freeze combat and RNG/loot at specific boundaries. The remaining crash window
was storing changes to **expedition, item repository and player inventory in
different files**. An NPC can be dead in one state while its rewards are still
missing or unclaimed in another.

`MapWorldCommitService` introduces an **opt-in single-encounter world snapshot**
in `user://map_world_commit_v1.json`. It owns one complete, consistent state
for the map activity: `ExpeditionState.to_dict()`,
`ItemRepository.to_dict()`, the persistent `CharacterState`'s canonical
progression and current HP/mana, inventory, equipment, elixir quickslots,
traits, bag capacity, and the immutable combat settlement identity. The
snapshot also contains an explicit ledger of defeated NPC instance IDs and
their original locations so the world does not respawn defeated enemies after
the original combat checkpoint/receipt are deleted.

**IMPORTANT:** This snapshot does *not* automatically override the older city
`scenes/main/main.gd` character progression/inventory save files.
They remain separate. The future map-scene loader MUST regard the world
snapshot as authoritative for this expedition, rather than immediately
overwriting it with stale legacy files. No world-map player-facing scene is
wired in this package.

## Recommended map runtime entry point

`HexMapTurnService.finalize_group_victory_atomic(session, encounter_key,
expedition, map, bridge, character, repository, loot_service, chances,
receipt_path, checkpoint_path, world_snapshot_path, now_unix)` is the
**preferred single-call path** for actual gameplay. While the coordinator's
combat pause remains active, it stages and applies the once-only settlement,
commits the canonical winner's HP/mana, writes and verifies the atomic bundle,
acknowledges the old receipt/checkpoint, and **only then** releases movement.
On failure it returns a specific reason without unpausing; the staged
receipt/battle remains recoverable.

The multi-step API below remains useful for targeted tests, recovery and
older callers that explicitly manage the map's pause themselves.

## Required completion sequence

1. Actual NPC map contact through `HexMapTurnService`, opening a resumable
   group battle using `MapEncounterCombatService.begin_resumable`.
2. Complete the round through `GroupCombatSimulator`; the terminal
   checkpoint must be on disk.
3. `HexMapTurnService.resolve_group_victory_durable` stages the once-only
   settlement receipt, applies NPC deaths and the loot pool and records an
   immutable `committed_combat_outcomes` hash in the expedition.
4. Persist the canonical player's live combat HP/mana into the owned
   `CharacterState` using `commit_combat_resources` and its actual
   `ItemRepository`. **Do not fabricate or silently heal resources.**
5. `MapWorldCommitService.commit(session, encounter_key, expedition, map,
   bridge, character, repository, receipt_path, checkpoint_path, snapshot_path)`
   verifies the receipt, a real disk terminal checkpoint, the player's
   HP/mana consistency, the NPCs' final deaths/removal and owner identities.
   It builds one complete snapshot including the NPC tombstones. It writes
   a temporary file, independently reloads/validates that temporary snapshot
   and atomically renames it to the target path. Failure does not authorize
   deleting the receipt or checkpoint.
6. Only after an independently readable, verified snapshot exists, call
   `MapWorldCommitService.acknowledge(snapshot_path, receipt_path,
   checkpoint_path, encounter_key, expedition_id, player_id)`.
   This checks the snapshot and verifies remaining receipt/checkpoint
   identity before removing only the redundant files. It is safe to call
   again if the process stopped between the two deletions.
7. On restart, `MapWorldCommitService.read(...)` supplies the restored
   expedition, repository and character together. The map generator should
   call `is_defeated_spawn(expedition,npc_id)` before spawning enemies and
   `reconcile_map(expedition,map,bridge)` before enabling movement/chases.
   Reconciliation validates every present NPC's expected coordinates before
   mutating the map, then kills any regenerated defeated NPC, and is
   idempotent.

**Map activity must remain blocked from saving an older competing state
between steps 3 and 6.** For the normal path use
`HexMapTurnService.finalize_group_victory_atomic`, which keeps the pause.
The older `resolve_group_victory_durable` is a lower-level API and still
releases the coordinator flag after settlement, so callers using it must
enforce their own write/movement barrier.

## After journal cleanup: claiming and expiring loot

Future loot operations must persist to the *same* atomic world snapshot.
Use `MapWorldCommitService.save_progress(snapshot_path, encounter_key,
expedition, character, repository)`, not separate expedition/inventory files,
to capture the claim, item ownership or TTL expiration. Before replacement it
checks the existing world snapshot, owner, receipt marker and unmodified
NPC tombstones and refuses any pool that would re-create a previously claimed
or expired item. This replacement is also validated via a temporary snapshot
before renaming.

The world snapshot remains authoritative after receipt acknowledgement.
The receipt's original SHA-256 is preserved as a marker but NOT recomputed
from a parsed JSON Dictionary, because Godot numeric representations can
change across serialization boundaries. The snapshot's own SHA-256 envelope
covers the entire stored data and checks corruption/truncation; neither hash
is anti-cheat authentication.

## Crash recovery matrix

| Crash boundary | Source of truth | Action |
|---|---|---|
| During battle | Last round checkpoint | Resume group combat |
| Terminal fight before receipt | Terminal round checkpoint | Stage actual outcome once |
| Receipt before world application | Once-only receipt | Replay exact NPC death/loot |
| World mutated, no atomic bundle yet | Receipt + checkpoint | Rebuild map and replay |
| Bundle written, before acknowledgement | Verified bundle | Restore bundle first; acknowledge later |
| After first redundant file deletion | Verified bundle | Re-run acknowledgement |
| After both files deleted | Verified bundle with NPC tombstones | Restore world and suppress defeated NPCs |
| Loot claimed or expired | Updated atomic bundle | Restore inventory/repository/expedition together |

## Scope and limitations

- Single **active** encounter/expedition per snapshot path in V1. Do not
  reuse the same path for an unrelated character or expedition. Multi-encounter
  compaction/rotation, cloud sync and multiplayer are outside this package.
- The new service does not start battles, grant XP, re-roll rewards, or
  change combat formulas. Legacy Arena remains unaffected.
- Legacy city progression and equipment saves are not migrated or modified.
  Future map UI and startup integration must explicitly resolve ownership
  between city saves and this authoritative expedition bundle.
- Local disk corruption may make a snapshot unreadable. The service rejects
  corrupted data instead of silently spawning NPCs or replaying loot.
  Backups/migrations can be added separately.
- Item claims/expires must be followed by `save_progress` to become durable;
  do not assume an in-memory claim survives process death.

## CI

The early `ABI Branch Tests` group adds
`tests/map/map_world_commit_runner.gd` next to the existing group checkpoint,
real map reward and staged settlement tests. It exercises real hex NPC contact,
real terminal group fight, refusal of premature acknowledgement, rejection of
uncommitted player resources, one atomic disk bundle, standalone restoration
after receipt/checkpoint cleanup, NPC respawn suppression, once-only claim and
TTL expiry across snapshot updates, stale loot rollback prevention and
corrupted snapshot rejection, wrong NPC positions before reconciliation,
and the single-call hex map finalize/ack path with movement paused until
all persistence boundaries have committed.

**The new bundle package has not passed Godot CI yet.** Only the preceding
settlement and combat packages were green on run #39582768207.
