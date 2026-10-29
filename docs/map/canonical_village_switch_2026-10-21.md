# Village canonical save switch — 2026-10-21

Verified baseline: ABI #293 success, commit 18536c4bde80fc88d0cc2e6ac9ee5df1313570f5.

## Changes

The starting village now prefers SoloTownSaveService.DEFAULT_PATH. If a
canonical town snapshot exists, the scene loads its CharacterState and
ItemRepository and never reads or writes the legacy progression/inventory
files. If the existing canonical snapshot is damaged it does NOT silently
fall back to stale legacy data. Arena/inventory/character mutation is
blocked; this requires an explicit recovery path.

If no canonical town snapshot exists, the village performs its existing
legacy initialization, then creates a single verified atomic snapshot.
Once initialized, subsequent saves of inventory, progression and Arena
HP/MP go through one revision-checked canonical writer. The old files
are retained as non-authoritative migration sources, not deleted.
Local Arena has a narrowly explicit in-combat save allowance; normal
world combat remains blocked in the default town writer.

Return from a completed expedition can replace an existing town save
ONLY if its player state still matches the verified pre-departure
fingerprint held inside the expedition save. Divergent or changed city
state is rejected, not merged. Repeating the same return after an
already adopted snapshot is idempotent.

## Tests

- tests/map/solo_town_canonical_migration_runner.gd: initial import,
  reopening, stale legacy owner write rejection and local Arena saving.
- tests/map/solo_town_save_adoption_runner.gd: existing city snapshot
  before departure, earned item on return, ground loot excluded, repeat
  adoption and stale revision refusal.

## Remaining boundaries

- The canonical village source is now wired, but the live playable map
  launch/exit is not yet wired to Main scene; the Debug Map Viewer is
  not the authoritative world.
- Legacy tests that explicitly assert the old separate JSON files
  require migration to the new canonical contract before those suites
  can be used to verify new persistence.
- Current canonical town save does not yet store the legacy offline
  regeneration wall-clock timestamp; restoring this without
  double-counting is a separate follow-up.
- Production multi-expedition rotation and automated checkout from
  an active expedition require further gameplay integration.

This package is NOT yet CI-verified.
