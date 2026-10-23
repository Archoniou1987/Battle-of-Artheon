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

If a legacy expedition is active, its most recently saved character and world
are selected and location is `map`. A divergent city-only change is **not
silently merged**: the old town file remains intact for explicit recovery.

If the expedition is fully exited, the saved return receipt is checked. When
it proves the city already adopted that exact expedition, the **later town
character and inventory** are imported together with the expedition world and
unclaimed world items (so subsequent town crafting is not rolled back). If
the receipt cannot prove adoption, the returned expedition owner is selected
and the old city remains untouched. A collision of item ownership between
returned city and unclaimed world fails migration rather than duplicating
an item. These are one-time historical migration checks, not ongoing
city/expedition reconciliation.

An unresolved legacy pending combat blocks migration rather than discarding
checkpoint/terminal artifacts or importing an inconsistent player. Finish/
recover that fight using the old version before migration. A corrupted
existing GameState never silently falls back to a legacy owner.

After successful migration all normal navigation and save writes use the
single GameState; no future handoff between town and expedition.

## Regression coverage

`tests/map/solo_game_state_runner.gd`: atomic creation, city→map→city,
world position, loot, restart, repeat map entry, failed stale city writer,
legacy active expedition with diverged city, closed return with later city crafting and world loot, source files byte-for-byte intact,
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
