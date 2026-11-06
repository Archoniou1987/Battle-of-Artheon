# Solo crash recovery — terminal combat to expedition publication (2026-10-21)

## Verified previous state

ABI #288 / 39638670081 passed on 57c01fda2ce41ecb259eda241163b3dcbb527179.
The real two-battle path originally published the completed battle-world snapshot
immediately into ExpeditionSaveService. A crash between the two saves left an
unpublished battle result whose checkpoint/receipt had already been acknowledged.

## Additions

`ExpeditionSaveService.recover_pending_combat(save_path, terminal_snapshot,
encounter_key, expedition_id, player_id, expected_base_sha256)` is an
explicit idempotent recovery entry point:

1. Require a valid previously verified **terminal combat world snapshot**.
2. Read and verify the canonical expedition save.
3. If the exact encounter marker and tombstone already exist with the same
   receipt SHA, return success with `already_published=true`; do not mutate.
4. If they do not exist, require the expedition payload hash to be exactly
   the pre-battle revision. A newer/changed expedition is never overwritten.
5. Publish the existing verified snapshot through the same protected
   `publish_verified_combat` pathway. No loot rolling or second settlement.
6. Keep terminal snapshot until a successful publication is confirmed.

The early ABI `expedition_two_real_fights_runner.gd` now simulates the
crash gap after *both* real terminal combats, rejects stale revision
recovery, performs safe recovery and retries it idempotently, checking
uniqueness and continued first-fight rewards at the final restart.

## Boundaries

This adds the recovery **operation**, not yet the automatic startup
orchestrator that discovers and invokes it on application launch. A future
session manifest needs to store the pre-battle revision, receipt identity,
and terminal snapshot path before entering combat.

A crash before the terminal atomic world snapshot exists still needs the
existing round-boundary checkpoint/replay flow, not this recovery helper.
Do not delete the combat snapshot until the expedition publication is
confirmed. The old single-encounter world and new expedition save still
coexist as two durability stages; the full startup coordinator remains
outstanding.

No automatic CI was triggered for this change.
