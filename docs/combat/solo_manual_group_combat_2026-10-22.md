# Solo live combat — player-selected attacks and blocks (2026-10-22)

## Baseline and purpose

Last confirmed green baseline is ABI #306 at commit `26344e67e684f029c74a99f5f4d30f527acd3f44`. This manual-input integration has **not** passed CI yet.

Connect the **actual** Solo map encounter to human combat orders without creating a second combat simulator, bypassing the checkpoint, or independently calculating damage.

## Current integration

1. `SoloLiveNpcCombat.start/resume` still construct and restore **the existing** `GroupCombatSimulator`; the real `CharacterCombatBuilder`, NPC builders, group controllers and end-of-round death order are untouched.
2. `GroupCombatSimulator.player_controls(player_id)` reports attack-hit count from the actual `WeaponAttackProfile`, manual zone capacity from the canonical `PAR073`, and next-round stun state.
3. The optional `run_round({"player_id","attack_zones","block_zones"})` validates **all selections before starting the round or consuming RNG**. Attack zones are exactly one per canonical physical strike; the selected distinct manual block zones must equal PAR073 capacity. Duplicate/invalid zones are rejected without advancing combat.
4. Manual blocks are delegated to **`CombatCommandApi.set_manual_block`**, never to a new block formula. For each normal player hit, `CombatAttackPipeline.lock_basic_attack` uses the player's chosen target zone while all combat events still resolve in the standard `RoundOrchestrator` and `CombatEngine`.
5. The NPC uses the existing automatic attack and ability selection unchanged. When the caller omits orders, legacy automated `run_round()` is unchanged. Stunned players skip both attack and manual block for that round.
6. `GroupCombatCheckpointService` remains the only journal. It serializes the resolved events (including chosen zones), the canonical fighter's block zones, RNG state, effects, resources and remaining NPC cohort.
7. The Solo map scene now renders real player and NPC HP/mana, a selectable zone for each physical strike, available manual block selections, and the last resolved combat event log using existing `ArenaCombatLog` as a **view-only adapter**. The in-progress battle screen does not instantiate an Arena combat owner.
8. The existing authoritative victory, defeat, loot, checkpoint resume, town return and Solo 2-second pickup flows remain in place.

## Test and acceptance

`tests/map/solo_live_manual_combat_runner.gd` exercises an actual map NPC fight, checks invalid orders cannot advance a round or write a checkpoint, verifies that selected body zones appear on resolved `CombatEvent` objects, and ensures PAR073 manual blocks, event history and HP presentation survive process-style remount. It then selects a different zone combination in the following round.

This runner joins the full `ABI Branch Tests` workflow and is complemented by all existing Arena, PAR, checkpoint and physical-combat tests.

## Not yet integrated

- Player ABI, shared elixir cooldown / charges, effect selection and instant spell actions **inside the Solo group fight**. These are separate next-stage contracts; don't describe them as finished.
- Final Arena layout with attack/block icons, full avatar panels and individual effect tooltips.
- True multiplayer control ownership, complex map patrol/aggro spatial attacks.

Never relax CI error checking to mask expected failures. No CI task should be launched automatically without user instruction; the user runs ABI manually.
