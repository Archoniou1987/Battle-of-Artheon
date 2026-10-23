# Real two-battle Solo persistence bridge — 2026-10-21

## Verified handoff boundary

`ExpeditionSaveService.publish_verified_combat(path, combat_snapshot,
encounter_key, expedition_id, player_id, expected_base_sha256)`
is an explicit, opt-in bridge that takes the world produced by a *real*
completed checkpointed combat and publishes it into the expedition-wide
save. It is not a replacement for combat settlement.

Before replacing the expedition, it:
- reads the existing valid expedition and verifies its revision (payload
  SHA-256) has not changed since the battle was started;
- reads the matching independently verified `MapWorldCommitService`
  battle snapshot with the exact encounter, expedition and player IDs;
- rejects already-published encounter IDs and requires receipt
  marker and NPC defeat tombstone;
- delegates to `ExpeditionSaveService.save`, which verifies item
  ownership disjointness, previous marker/tombstone monotonicity,
  reconstruction and atomic file replacement.

The combat snapshot remains immutable evidence and the expedition file
is the canonical cross-encounter state. The source battle checkpoint and
receipt are acknowledged by the existing atomic battle-finalization
path, not by the new publisher.

## New integration test

`tests/map/expedition_two_real_fights_runner.gd` exercises:
1. saving a fresh expedition before any fight;
2. map contact with NPC 1, real resumable group fight, terminal
   checkpoint, once-only reward settlement on the hex;
3. publishing the verified result and rejecting duplicate publishing;
4. reading a fresh expedition, manually claiming the original item
   using the full 5-second `GroundLootService` path, saving it;
5. map contact with NPC 2, another real group fight and separate
   verified terminal snapshot/receipt, publishing against the updated
   expedition revision;
6. a second restart: both combat receipts/tombstones present, first
   item remains in inventory, second remains on the hex, original
   instance IDs and durability retained.

## Remaining limitations

This is an opt-in bridge and integration test, not yet the default
playable expedition runtime coordinator. A crash between completing
the battle-world snapshot and publishing its result into the
expedition-wide file requires a reconciliation/retry mechanism.
The player/expedition save's hash must be captured from the pre-battle
save and passed with the completed snapshot. The Debug Map Viewer
still uses the older single-encounter snapshot for pickup and must be
migrated to use the expedition-wide owner after recovery is designed.

No new CI is automatically run; the test is early in the manually
triggered ABI Branch Tests workflow.

Last verified CI: #287 / 39636698373, success on
f8f7369b7c5fd01a64c58a79b499d59e621d334a.
