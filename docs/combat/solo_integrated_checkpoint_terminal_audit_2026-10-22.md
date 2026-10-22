# Integrated Solo battle — checkpoint / terminal audit (2026-10-22)

## Verified baseline
ABI Branch Tests #312 (commit `30f42496c3cce6e72cc523c09cc93a259577d36f`) succeeded. This includes canonical PAR/Combat, equipment-bound ABI + EFF, manual attacks and blocks, per-round potion use, shared cooldown, mana-potion-funded ABI, and checkpoint restoration.

## Contract audit
- The only action execution chain is `SoloLiveNpcCombat.play_round -> GroupCombatSimulator.run_round -> RoundOrchestrator`. The action order is validated before `begin_round`. An optional elixir resolves canonical `CombatEngine` EFFECT events at round start, before locked attacks and ABI casts.
- Kills remain provisional within the round, with finalization at `RoundOrchestrator.end_round`. No new special-case death code introduced by potions.
- CombatCheckpoint persists the combatants, completed effects and events, RNG, pending ability cooldown state and event IDs. The elixir ledger derives one paid item use per event-component group and shared cooldown without re-running effects.
- On victory, the current repository must exactly match the original expedition repository with verified spent consumable charges before world settlement / loot publication.
- On defeat, terminal staging reconstructs spent charges from the saved checkpoint and original expedition repository; launch recovery independently validates the exact resulting repository.
- Ground pickup remains 2s Solo and separate from any combat item deduction.

## Newly added regression
`tests/map/solo_live_elixir_defeat_runner.gd` creates a genuine expedition with a belt and health consumable, fights a real NPC, commits the first drink in a round checkpoint, then advances to an actual defeat through the existing CombatEngine. It restarts from the terminal checkpoint, stages and publishes defeat, verifies the original expedition remained precombat until publication, then reopens the world and verifies exactly one charge was spent, HP was restored, the character returned to the starting hex, and the expedition was not published again. The new runner is registered with the established ABI workflow.

## Important boundary
This new defeat-specific regression has NOT been CI-verified. The successful #312 run predates it. The package makes no gameplay changes beyond this additional audit coverage.

## Follow-up priorities
1. Get CI confirmation of the new loss + consumed-charge recovery scenario.
2. Run focused adversarial tests for victory with potions, terminal crash between staged snapshot and publication, checkpoint tampering and abnormal restoration paths.
3. Separately expand coverage for combined potion components, full depletion, stun and two NPC combatants; preserve the existing canonical engine instead of parallel formulas.


## ABI #313–#314 failure diagnosis and repair

- #313: terminal defeat recovery rejected the new elixir stage with `defeat_repository_changed`.
- #314: a direct JSON round-trip of an otherwise untouched fixture repository failed the previous `numeric_json_roundtrip_preserves_item_identity` test **before** settlement.
- That isolates the cause to representation-sensitive repository comparison, not an actual missing elixir deduction. The first patch normalized only `charges`; the fixture demonstrated that nested numeric metadata must be compared safely as well.
- Replaced the string comparison with a recursive value comparator checking ALL dictionary keys and array elements, allowing mathematically equivalent int/float values at any depth and requiring exact type/value for strings, booleans and null.
- Expanded tests to reject different charge values, altered item names, nested elixir-component changes and missing unrelated inventory items. Victory and defeat paths use the same comparator.
- This repair still requires a **new CI run**; do not infer a green test from this documentation.
