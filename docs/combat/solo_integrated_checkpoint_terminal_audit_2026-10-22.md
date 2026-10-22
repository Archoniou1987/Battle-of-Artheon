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

## Crash gap with consumed potions (post ABI #316)

ABI #316 succeeded on `237336ad1c8eb7b4e5dadbc03878b0eed095cef5`, verifying that real NPC victory and defeat each persist exactly one consumed elixir charge and do not duplicate drops.

The following *new* regression coverage is not yet CI-verified:

- `tests/map/solo_live_elixir_defeat_runner.gd` now explicitly stages the **defeat terminal snapshot** after spending a potion and completing a checkpointed death. It checks that the expedition file still has original charges, then simulates relaunch with `SoloExpeditionLaunchGate.inspect`. Recovery must publish exactly one debit, full-health retreat and cleared manifest.
- `tests/map/solo_live_elixir_victory_crash_runner.gd` stages the **victory world snapshot** from a genuine terminal GroupCombatSimulator with an elixir EFFECT journal, without publishing the expedition file. It checks the original save still has precombat charges, then simulates relaunch. Launch recovery must publish the verified victory, persist one debit and one loot settlement, clear the manifest, and remain unchanged on another reopen.

Both exercises preserve the canonical combat engines and world commit services and modify only test coverage and CI registration. Do not call the crash-gap coverage complete until the user confirms a green ABI workflow on the new HEAD.

## ABI #317 and consumable edge cases

ABI #317 succeeded on `e25b477392322c652fa27ac097f7b9ee3aa97dfe`. This verifies the full crash gap after terminal victory and defeat snapshots, including exactly one spent potion charge and idempotent world/loot publication.

The next package extends `tests/map/solo_live_elixir_round_runner.gd` rather than creating another expensive CI workflow:
- The real combatant is marked stunned for the upcoming round. Elixir selection is rejected before any round, event ID, charge or checkpoint mutation.
- An owned but fully depleted potion remains invalid, and a rejected order does not start the round; its original fixture charges are restored before execution.
- One equipped health potion has both a `heal` and a `mana` component. Canonical CombatEngine records two EFFECT events; the journal counts **one item use**, decrements **one** charge, enforces **one shared cooldown**, and reconstructs the same debit after restart.
- Existing checks of tampered event payload, overspending, cooldown across slots, repeat restart, and terminal publication remain active.

New edge assertions are **pending CI** on the updated HEAD. No production combat formulas or settlement rules were modified.


## Mobile scene integration — after ABI #318

ABI #318 succeeded on `344b2f4182d7ea3bd89acbda25d2f5fe10185b7e`: stun, zero-charge refusal, and a two-component heal+mana potion now pass alongside the canonical checkpoint suite. The core Solo combat integration is green for the documented contracts.

The next package begins **UI layout integration**, without touching combat execution, save state, balance or NPC encounters. The existing `solo_live_map.gd` viewport previously rendered all 10 map columns directly into the main vertical scroller, causing excessive width on a narrow phone, and positioned its `round_button` *after* a potentially long combat log.

The map now has an independently horizontally scrollable area with 44px minimum tiles; the main action button is above the log, with a 56px minimum height. ABI, potion, attack and defense touch controls use larger minimum heights. A new headless Godot smoke test `tests/map/solo_live_mobile_layout_runner.gd` instantiates the actual scene and validates map parentage, scroll modes, action order and touch targets.

**Not yet visually approved**: portrait and landscape screenshots / real device input are still required; static scene smoke does not establish UX or visual quality. No new gameplay systems have been added.


## ABI #319 — manual defense touch contract

ABI #319 succeeded on `18dde95d96cf304cb88f30abe1ae3bbfeed46bc6`: the Solo mobile layout scene tree smoke test is green.

The touch-selection layer now holds exactly the number of manual block zones permitted by `CombatModifierService.manual_block_zone_capacity` / PAR073. At full capacity, selecting another zone deselects an earlier one; tapping to remove a necessary last selection restores it. When capacity is zero, all defense choices are disabled. This prevents avoidable rejected orders from normal touch interaction, but **does not bypass** the existing `CombatCommandApi` authoritative server-side validation.

The existing Godot scene smoke runner now tests 2-zone switching and deselection. These modifications await the next ABI CI check; no combat math or item persistence changed.


## ABI #320 and HP visualization

ABI #320 passed on `c6e7200bf68c3eb05db8e5409d8d1a31e45b3f8c`. Mobile defense-zone switching is confirmed.

The next UI layer adds a live hero HP ProgressBar and a separate row for **each** NPC from `SoloLiveNpcCombat.combat_view()`. Progress bars only render `hp` and `max_hp` supplied by the canonical combat snapshot; they never independently compute injuries or death. The UI clamps display into 0..maximum and shows numeric values via tooltip, alongside the existing combat summary. Old NPC rows are removed on refresh, avoiding stale opponents.

The existing headless scene smoke runner covers two NPC bars, zero HP, a new snapshot with no NPCs, and HP clamping. This visualization layer awaits the next CI run. Avatar illustrations, equipment portraits and full arena layout are separate remaining presentation tasks.
