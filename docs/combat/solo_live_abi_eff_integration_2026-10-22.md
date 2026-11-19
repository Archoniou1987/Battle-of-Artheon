# Live Solo ABI/EFF integration — equipped spells, manual casts, checkpoint (2026-10-22)

## Verified starting point

ABI #307 passed on `7cb38ddbded83166156a2eacff31de38166b4004` (manual hit/body-zone controls, common group combat engine, checkpointed rounds).

**This ABI integration package is not yet verified by Godot CI.**

## Contracts preserved

- **One canonical engine:** Solo continues using the real `GroupCombatSimulator`, its `RoundOrchestrator`, `CombatAttackPipeline`, `CombatCommandApi`, `AbilityScheduler`, `CombatEngine` and `GroupCombatCheckpointService`. It does NOT construct an `ArenaCombatSession`.
- **Production ability definitions only:** New Solo fights replace the generic group simulator's **test fixtures** with `res://data/abilities/catalog.json`. Each fighter's actual canonical `combat_stats["abilities"]` supplies the loadout (equipment for the hero; NPC template for enemies). Undefined/development-only IDs never become executable spells.
- **Five equipped slots:** The Solo view reads the existing `EquipmentAbilityLoadout.build` order: three main-weapon ABI slots, one chest and one head. Empty or undefined slots remain disabled. There is no new inventory or ability storage model.
- **One selected ABI per round:** The player can explicitly choose an equipped ABI or **no cast** alongside independent physical hit zones and manual block zones. All input validation, including target, mana, stun, cooldown, full-zone selections and loadout ownership, precedes `begin_round()`. Failed requests must not change the round, event IDs, RNG, resources, effects, or checkpoint.
- **Single resolution path:** A valid manual ABI goes through `CombatCommandApi.cast_ability`, which calls the existing `AbilityScheduler.cast_event`. Its canonical ACTION `CombatEvent` is sealed into the SAME group round; `CombatRound` preserves instant/standard phase ordering and end-of-round death finalization. No separate spell damage or EFF calculations.
- **No player autocast while manually controlled:** Passing an explicit player's orders (even `ability_id=""`) disables automatic ABI selection **for that actor only**. NPC automatically choose their equipped ABI according to the existing one-per-round policy. Unmodified `GroupCombatSimulator.run_round()` callers continue using its original auto policy.
- **Preserved checkpoint ownership:** Real ability definitions, actor loadouts, cooldowns, once-per-round cast markers, mana, effects and complete event history live in the one `GroupCombatCheckpointService` payload. Recovery uses the saved scheduler; it must not overwrite it with a newly loaded catalog.
- **Read-only EFF and combat log:** After a round, the scene projects disclosed, unexpired effects (BUFF/DEBUFF, stack count and duration) directly from combatants, while using `ArenaCombatLog` only to render the canonical resolved CombatEvent ancestry. Hidden instant effects remain hidden until disclosure.

## Tests

`tests/map/solo_live_manual_abi_runner.gd` constructs real character + item repository with an equipped sword ABI003 and chest ABI004. It checks production definitions, five visible equipped positions, rejection of fixture-only spell IDs with no RNG/time/world changes, exactly one player healing cast in round 1, actual EFF004, mana cost, cooldown saved as round 3, checkpoint recovery of all ability state, cooldown rejection prior to round 2, and explicit no-cast in round 2. It also attempts the equipped offensive ABI003 if combat remains active.

This new runner is wired into `.github/workflows/abi-branch-tests.yml`, alongside existing combat/Arena/ABI/EFF, map, group checkpoint and manual target/block tests. Avoid extra standalone GitHub Actions runs.

## Remaining work

- **Solo elixirs:** Shared cooldown, charge depletion and atomic recovery of item instances on restart require a separate durable resource boundary. The current package intentionally does NOT claim elixirs finished.
- Target selection for large NPC cohorts, full avatar/ability icon UX, complete group AI, effects tooltips and mobile refinements.
- Broader map patrol/aggro/regions are outside this combat-control package.

No user-facing feature is considered CI verified until the user confirms a successful ABI workflow for the new commit.
