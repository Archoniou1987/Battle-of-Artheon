# Solo Expedition Save V1 — pre-combat and multi-encounter foundation (2026-10-21)

## Why this exists

`MapWorldCommitService` was designed to verify **one terminal battle**,
store its immutable settlement receipt and acknowledge the checkpoint.
It cannot create a valid empty expedition before the first encounter
or change the anchored receipt identity for later encounters.

`ExpeditionSaveService` is a separate, versioned, atomic expedition-wide
save container. It is independent from battle checkpoints and can store
`ExpeditionState` (including map position, loot on the ground, NPC
tombstones and encounter marker ledgers), `ItemRepository` and complete
`CharacterState` without fabricating a completed battle.

## Contract

- `save(path,expedition,player,repository)` writes a SHA-256 envelope into
  a temporary `user://` file, verifies it by reconstructing all three
  owners, then replaces the real file. Never overwrites an invalid
  existing snapshot or changes expedition/player identity.
- `read(path,expedition_id,player_id)` verifies the checksum, schema,
  owner identities, item references, equipment/inventory restoration,
  ground loot and ledger consistency.
- Unique owned item IDs are disjoint from ground item IDs and legacy
  encounter pools; existing items are never reconstructed by duplication.
- Existing combat marker SHA mappings, tombstones and ground migration
  receipts are **monotonic** across saves: a later checkpoint cannot
  silently discard or rewrite an earlier victory.
- `import_committed_world` accepts a *verified* old
  `MapWorldCommitService` snapshot as the seed for this expedition save,
  but refuses to overwrite a pre-existing expedition snapshot.
- Explicit `completed`, `exited` and `expired` states are durable.
  A closed expedition is not silently reopened/overwritten.

## Tests

`tests/map/expedition_save_runner.gd` runs early in ABI Branch Tests.
It verifies an initial save with no battle receipt, restored world/player
position, progressive recording of two encounter histories and two
persistent items in different hexes, protection from ledger rollback,
wrong-owner rejection and durable explicit expedition closure.

## What is NOT yet integrated

- The full live battle coordinator still finishes to the older verified
  battle-world snapshot. Its next migration step must sync a committed
  terminal receipt into `ExpeditionSaveService` without two competing
  authoritative files or early receipt acknowledgement.
- The new service is a **persistence foundation**, not yet a playable
  launch/return/exit scene and not a claim that two live battles have
  been completed through it. The multi-encounter test uses committed
  ledger-shaped fixtures to check cumulative persistence semantics.
- Map UI pickup currently saves through `MapWorldCommitService`; it must
  eventually switch to this expedition-wide save owner once the migration
  and recovery flow is complete.
- Full normal exit cleanup, crash recovery mid-combat and default live
  encounter wiring remain separate tasks.
- MP remains a later possibility, not an implementation objective.

Last verified green CI: ABI #286, run 39635013660, SHA
d436626657c0d44dc34e3744b25c7bdc60cd51e0.
This new save package is NOT yet CI-verified.
