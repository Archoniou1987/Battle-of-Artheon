# BOA Group Combat Round Checkpoint V1 — 2026-10-21

## Scope / owner

This contract saves **one active world/group combat encounter** after a completed round. It is an optional feature of `GroupCombatSimulator`, enabled by `MapEncounterCombatService.begin_resumable(...)`. It does NOT change Arena training-session semantics, UI geometry, normal CharacterState progression/inventory saves, loot rules or the legacy `CombatSimulator.run_duel` loop.

**Restore boundary:** finish End Round (including timed EFF, deferred actions, death finalization, Tempo bookkeeping and active-target reassignment) -> persist -> begin the NEXT round after process restart. No checkpoint of uncommitted selections, queued events, ongoing `CombatRound` or UI Mind Game clicks. `run_round()` returns `checkpoint_ok` when persistence is enabled; `run()` halts with `checkpoint_write_failed` rather than reporting a rewardable winner if the disk commit failed. Each saved checkpoint is a single file in `user://`.

### Stored state

- Format: `BOA_GROUP_COMBAT_CHECKPOINT_V1`, `schema_version: 1`, `encounter_key` and initial roster/gear fingerprint. Opening a *different* encounter or using changed PAR/loadout equipment rejects resume.
- Both alive and finalized-dead combatants: canonical PAR/combat stats, equipment-derived attack profiles, HP/mana/AP, armour/resistances, active EFF records, source/stack IDs, duration and reveal state, Tempo/debt/stun/immunity, weapon skills, persistent combat loadouts.
- Combat round index, next unique event ID, complete resolved `CombatEvent` log with lineage/result, damage attribution, current team membership and active opponents, engagement locks.
- Engine PRNG `RandomNumberGenerator.state` encoded as a decimal STRING (never JSON float), next EFF stack ID, physical balance and test-only EFF overrides; shared RNG used by `CombatAttackPipeline`. A SHA-256 fingerprint of the canonical EFF catalog rejects outdated definitions after an incompatible content update.
- ABI scheduler definitions/loadouts, per-combatant cooldown and one-cast-per-round ledger; remaining persistent action schedule; simulator maximum rounds.
- `terminal` flag. A terminal saved combat can be inspected after restart and cannot execute another round. It is retained until external world consequences have been durably committed and acknowledged.

### File and trust boundary

- Default: `user://group_combat_checkpoint_v1.json`; callers may choose another `user://` path (e.g. isolated test runs).
- A JSON envelope contains an unmodified serialized payload STRING and SHA-256 of exactly that string. This detects accidental truncation/alteration, but is **not** anti-cheat authentication. A modified payload with a recomputed hash is still treated as local untrusted input and structure-validated.
- Save writes `.tmp` and renames it over the previous complete checkpoint. A temporary file is never considered a committed checkpoint. Limit 5 MiB, 32 combatants, 10k rounds/events. Stale schema, invalid numeric limits, invalid team/active target, duplicate/orphan event IDs, impossible EFF/cooldown shapes and wrong encounter identity are rejected, not silently reset.
- `MapEncounterCombatService.begin_resumable` first builds the expected current NPC/player roster, hashes immutable initial combat contracts and either returns `resumed=false` with a configured fresh `GroupCombatSimulator`, or `resumed=true` with a fully restored one. A corrupt/stale save causes `ok=false`; callers must explicitly discard it and decide what happens next.

### World-outcome integration

**Important:** World map authority and loot/reward transactions still belong to `MapCombatOutcomeService` and the owner's world persistence. Call `MapEncounterCombatService.acknowledge_resolved_encounter(path)` only AFTER NPC death/removal, loot rights and associated world saves are committed. A terminal checkpoint is intentionally NOT auto-cleared on victory. This is a necessary replay guard but not yet a cross-file atomic world transaction; integrating battle outcome acknowledgement into the persisted world scene remains future work.

### CI

- `tests/combat/group_combat_checkpoint_runner.gd`: two real 1-vs-2 NPC map encounters, 3 rounds then process-style reload using a fresh map roster, 6 more rounds. Every post-reload round is compared against an uninterrupted matching CombatEngine stream, including real ABI003 / ABI004, EFF003 / EFF004, RNG, event ancestry, active opponents, cooldown and effect sequence. Corruption, wrong encounter and wrong roster signature cannot silently restart a fight.
- `tests/combat/group_combat_terminal_checkpoint_runner.gd`: real end-of-round combat victory, terminal checkpoint retained on disk, restored terminal state refuses further combat, explicit acknowledgement clears it, checks schema version mismatch and rejects an in-progress-round checkpoint.

CI is **pending** for this update until the single manual `ABI Branch Tests` run completes. Do not call these tests passing before then.

## Compatibility notes

Existing `GroupCombatSimulator.new(...).run_round()` callers remain fully in-memory unless checkpointing was opted in. Existing training Arena remains a fresh duel on each opening. This package introduces the persistence **engine contract + map encounter entry point**; it does NOT yet wire game-scene lifecycle into an expedition UI or implement cross-file transactional map/loot persistence.
