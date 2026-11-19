# Solo expedition → town return: authoritative closing boundary

## Verified baseline

ABI Branch Tests #291 passed on commit
`471e357dfbe70fa67b5825c12701a2c4fd4ad1e9`.

## Ownership and durability

The town currently writes player progression and inventory to two
legacy files, while Solo expedition persistence writes a single
atomic snapshot. Copying expedition rewards straight into legacy files
before both files are durable can result in duplicated/lost items.

New `SoloTownReturnService.close_for_town` checks an existing valid,
active expedition and no pending combat manifest. It writes status
`exited` and an immutable return receipt (sorted owned item IDs) in
the expedition's **single atomic save**, without modifying the town
files. It refuses a second normal exit and treats an already completed
matching return as idempotent.

`load_returned_owner` reads that same closed snapshot and
reconstructs a dedicated ItemRepository with exactly the player's
owned item instances. Unclaimed ground drops are not transferred to
town. Item instance IDs, stats, equipment and elixir references are
preserved; the still-closed expedition remains available for audit.

This establishes the safe canonical **handoff boundary**. It does
NOT yet write the returned state to the legacy town files or activate
the returned character in the village UI. Those changes require
moving the town writer/loader over to a single canonical snapshot
or a separately transactional migration protocol. Do not claim the
full town ↔ expedition loop is complete until that integration and its
crash tests pass.

## ABI test

`tests/map/solo_town_return_runner.gd` covers active and pending
combat rejection, atomic exit, repeated idempotent close, restored
character with original town equipment and earned quest item,
unclaimed ground loot excluded from the city's repository,
original town state unmodified, invalid player refusal, and
persistent expedition exit state.

The early ABI branch workflow runs the return runner alongside
the existing town→expedition owner tests.

New package is not yet Godot-CI-verified.


## 2026-10-22 — Repeatable Solo expeditions

The first real browser playtest confirmed three NPC victories, return to town and working out-of-combat HP regeneration, then exposed a terminal `expedition_closed` launch gate preventing the next expedition. Implemented a **verified archival handoff** rather than deleting or rewriting the closed snapshot.

- Town Map gate offers **Начать новую экспедицию** for a closed expedition.
- `SoloTownExpeditionBridge.archive_adopted_expedition` checks closed/returned status, no pending combat manifest and matching canonical-town `return_origin` for the exact closed expedition SHA. Failure is fail-closed. It moves the old expedition snapshot to a unique archive file before using the canonical town owner for the next trip.
- `SoloLiveNpcCombat._next_attempt` skips preexisting checkpoint, receipt and terminal paths: identical stable NPC/player IDs across trips must never overwrite or confuse their durable combat artifacts.
- `tests/map/solo_town_save_adoption_runner.gd` now validates a second expedition with acquired owned loot, immutable archived bytes, exclusion of unclaimed drops and pending-manifest archive refusal.
- No battle mechanics or Arena layout were modified. **Run manual ABI Branch Tests before a new Web Preview deployment**. Keep browser storage intact; do not clear the site data.


## 2026-10-22 — Browser return conflict recovery

Live Web Preview reported `town_snapshot_conflict` when finishing a subsequent expedition. This is a real divergent canonical town/expedition revision (not a touch-input failure). Existing automatic `adopt_closed_expedition` correctly **refuses to replace** a city that no longer matches the expedition's departure fingerprint.

Two separate protections were implemented:
1. During `main.gd` expedition handoff, the town is explicitly marked handed off before changing scenes, preventing a second town write from the source scene's `_exit_tree`. It does not suppress saves during ordinary town gameplay, nor if the scene transition fails.
2. On a failed return with exact reason `town_snapshot_conflict`, the map UI offers an explicit confirmation dialog. Only upon confirmation, `adopt_closed_expedition_preserving_town` checks the already-closed and validated return, writes the **original town envelope bytes** to a unique SHA-named readable city archive and verifies both bytes and canonical format, rechecks the town revision, then commits the expedition's owned inventory, HP/mana and progression to the current canonical town. The old town-only items and modifications remain in the archive, **not silently merged** into the new active city. Cancellation keeps both saves untouched. A follow-up adoption uses the existing idempotent receipt contract.
3. `tests/map/solo_town_save_adoption_runner.gd` includes a divergent city-only generated item and expedition-only earned item; tests automatic refusal, untouched city until explicit recovery, exact archive bytes, readability, retained expedition reward and repeated adoption idempotency.

No automatic conflict resolution or deletion of player data. CI must pass before the Web Preview can exercise this flow; users should keep browser site data intact.
