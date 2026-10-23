# Single GameState storage — Solo v1 (2026-10-23)

## Durable owner

Production writes **one** file: `user://solo_game_state_v1.json`, with checked
`BOA_SOLO_GAME_STATE_V1` envelope. It contains one character, one item
repository, and world state (currently encoded by the existing ExpeditionState
serializer), including `solo_game_location_v1 = town | map`. The verified
combat world-publisher writes to that **same** path. No separate town save is
written after bootstrap. Legacy town-expedition adoption, town fingerprints,
close/return receipts and conflict-dialog are no longer in the production
navigation path.

The internal historical type `ExpeditionState` is a compatibility adapter
for the already-tested world/loot/Combat Engine contracts; it does not mean
another durable player snapshot. Location changes do not reset map exploration,
NPC tombstones, loot or the saved hex. Future map/region rules can evolve
independently of the character owner.

`SoloGameStateService` APIs:
- `bootstrap`: verify current owner or perform one-time safe migration.
- `read`: reload character + repository + world + location.
- `save_town`: persist city mutations to the same owner; revision check
  prevents stale writes (it does not compare two player saves).
- `set_location`: persist city/map switch; refuse during pending combat.

The Arena training screen's transient selection does not persist; its player
resources/items still commit to GameState. In-progress Solo map NPC combat
continues to use the existing manifest + checkpoint + terminal receipt.
These are *recovery journals*, not a second independently writable character.

## Legacy migration

Original files are **never deleted, renamed or written during migration**:
- `user://solo_town_save_v1.json`
- `user://solo_expedition_save_v1.json`
- older progression/inventory files when neither canonical legacy file exists.

If there is a legacy expedition, its most recently saved character and world
are chosen for import. If active, the new location is `map`. If fully exited,
the new location is `town` (the world remains). A legacy city-only difference
is **not silently merged** into an active expedition: the original legacy town
file remains untouched for explicit future recovery. This is a migration-only
historical ambiguity, not ongoing two-way reconciliation.

An unresolved legacy pending combat blocks migration rather than discarding
checkpoint/terminal artifacts or importing an inconsistent player. Finish/
recover that fight using the old version before migration. A corrupted
existing GameState never silently falls back to a legacy owner.

After successful migration all normal navigation and save writes use the
single GameState; no future handoff between town and expedition.

## Regression coverage

`tests/map/solo_game_state_runner.gd`: atomic creation, city→map→city,
world position, loot, restart, repeat map entry, failed stale city writer,
legacy active expedition with diverged city, source files byte-for-byte intact,
legacy pending-combat fail-closed, idempotent migration.

Legacy bridge and adoption regression runners remain untouched and run against
custom test paths, proving that old saves still parse and can be inspected.

## Intentionally not part of this update

Professions and production timers; future global region design; server-authority
for multiplayer; rewriting battle checkpoint/terminal journals. These features
may add sections to GameState later but must not add another durable player
owner.

Run ABI Branch Tests manually first, then Web Preview. Preserve browser
storage; clearing site data deletes local `user://` saves.
