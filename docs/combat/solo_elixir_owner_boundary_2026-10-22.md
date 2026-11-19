# Solo elixirs — owner/read contract before mutation (2026-10-22)

## Baseline
The user-confirmed ABI #309 passed at `5cd7cbf270e2058b9ae3781a452c07a81e84e33b`. This new elixir contract package needs a separate ABI run.

## Why the elixir boundary is different from abilities

The existing `CombatElixirService.use` immediately spends a charge in a persistent `ItemRepository` instance and directly resolves a canonical `CombatEngine` EFFECT. This is correct for an Arena fight that owns its character and repository.

A suspended Solo group fight has a durable **CombatCheckpoint** with HP, mana, EFF, RNG, cooldowns and combat events, but its manifest pins the pre-combat **ExpeditionSaveService** repository revision. On restart, a fresh repository object is loaded from the pinned precombat world, not from the combat checkpoint. Simply calling `CombatElixirService.use` in Solo would therefore risk free potion reuse, missing charge deductions, or inconsistent settlement if the game crashed. Moreover, the defeat recovery currently enforces strict repository identity, while victory settlement independently stages a world snapshot. They must share one verified consumables ledger.

## Changes in this package

- Introduced `SoloCombatElixirLoadout.inspect(character,repository)`: a **read-only** four-slot projection. It uses the canonical belt slot capacity, real inventory ownership, existing quickslot IDs, `CombatElixirService.validate_components`, live charges, maximum charges and item cooldown metadata.
- Each slot is either locked, empty, valid or explicitly invalid. Duplicate item ownership/assignment and locked-slot mismatches fail closed.
- `SoloLiveNpcCombat.combat_view` exposes `elixir_loadout` on the same read-only view as character HP, five ABI slots and disclosed EFF.
- The Solo map screen displays four slot IDs and charges without promising that a click can yet consume the item.
- A new regression `tests/map/solo_live_elixir_loadout_runner.gd` checks actual belt/equipment items, 4 accessible slots, ownership, duplication, no charge mutation on projection, a changed charge count reflected from the authoritative repository, and invalid consumable components.
- Added the regression to the existing ABI workflow alongside all prior map/ABI/Combat tests.

## Next safety-critical writable step (NOT implemented in this package)

1. Capture an immutable per-encounter elixir-use journal (source item instance, original charges, remaining charges, round, shared cooldown, and resolved event IDs) inside the existing **GroupCombatCheckpointService**, validated with its hash and roster/owner.
2. Restore charge/cooldown use precisely and exactly once across a resumed encounter, with no action replay and no charge reset. For mid-round immediate consumption, either checkpoint an explicit preparation-phase boundary or refuse premature publication until a full durable round is completed.
3. Verify the journal against the pinned original `ItemRepository`, while also preventing cross-item charge mutation, consumable item substitution and forged use.
4. Reconcile the exact charge deltas when staging **both** the winner's world receipt snapshot and the loss/respawn terminal snapshot. No charge is awarded back on defeat.
5. Ensure both publication paths remain idempotent across a crash after staging, and add a real-NPC full round regression. Only after this succeeds enable Solo elixir-use buttons.

No new elixir formula, shared cooldown policy, alternative EFFECT engine or second inventory system should be created.
