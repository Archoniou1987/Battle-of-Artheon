# ABI003 Fireball / EFF003 Burning — test contract

State: first implementable backend slice, **not final combat balance**. Branch:
`feature/character-inventory-ui-v1` (Godot 4.5.1).

## Canonical identifiers and file ownership

- ABI001 is the canonical MH/OH ordinary weapon attack, defined by `ParAttackContract`. It is **not** the old test Fireball.
- ABI002 is intentionally not defined in the canonical ABI catalog by this change.
- ABI003 is **Fireball**, defined by `data/abilities/catalog.json`.
- EFF003 is **Burning**, defined by `data/effects/catalog.json`.
- Older `data/test/abilities.json` fixtures keep their legacy mechanics under `TEST_ABI_FIREBALL` and `TEST_ABI_LIGHTNING`; the unrelated old EFF003 Madness fixture is `TEST_EFF_MADNESS`. Never merge test fixtures into the production catalog.

## ABI003 — Fireball

- One selected enemy; PROJECTILE delivery, uses the shared magic-hit check.
- One base `damage` component: **100 FIRE** before PAR scaling, critical damage and resistance.
- One `effect` component: applies EFF003 at **100% base effect chance** when the magic hit succeeds, before resistance checks. It is not a separate 100-damage packet.
- A successful action may cause both base damage and the effect; hit and effect are tied to the same cast roll.
- Magic damage continues through existing `PAR150` and `PAR190/PAR191` handling. No new parallel Magic Engine.
- **Mana cost: 10** per cast. **Ability cooldown: 1 full round** between casts (rounds 1, 3, 5, 7 are valid; 2, 4, 6, 8 reject casting). PAR018 reduction formula remains a later task.
- The ability is available as canonical data and engine events. **The five Arena ABI buttons are still UI-only** until the separate integration stage.

## EFF003 — Burning

- Damage over time, no immediate EFF damage on the cast round.
- **10 FIRE damage per stack per active round**, starting on the round following first application.
- **ONE shared duration timer**, `duration_rounds = 3`, for all stacks on a target. Each new successful application refreshes that single duration to 3 rounds; it does not postpone an already-active DoT tick.
- `stacking = shared_duration`, `max_stacks = 3` on one target: one effect record containing `stacks` and `remaining_rounds`.
- At the 3-stack cap, another application **keeps 3 stacks and refreshes the same timer**, without creating another timer or effect record.
- Tick events use the shared `DAMAGE` pipeline: FIRE resistance and global damage reduction apply. DoT does not independently roll to crit in this implementation.
- Remaining duration decreases at round end. Death still finalizes only after end-round effects.

## Deterministic nine-round acceptance scenario

Caster uses ABI003 in rounds **1, 3, 5, 7** against a 1000 HP target
with zero resistance and no regeneration. Casting is rejected by cooldown
in rounds 2, 4, 6, 8. The three stacks of Burning have **one common timer**,
which refreshes on rounds 3, 5, and 7. No cast in round 9.

| Round | Fireball base | Burning tick | Total damage | Target HP | Mana | Stacks | Shared timer remaining |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 100 | 0 | 100 | 900 | 90 | 1 | 3 |
| 2 | 0 | 10 | 10 | 890 | 90 | 1 | 2 |
| 3 | 100 | 20 | 120 | 770 | 80 | 2 | 2 |
| 4 | 0 | 20 | 20 | 750 | 80 | 2 | 1 |
| 5 | 100 | 30 | 130 | 620 | 70 | 3 | 2 |
| 6 | 0 | 30 | 30 | 590 | 70 | 3 | 1 |
| 7 | 100 | 30 | 130 | 460 | 60 | 3 | 2 |
| 8 | 0 | 30 | 30 | 430 | 60 | 3 | 1 |
| 9 | 0 | 30 | 30 | 400 | 60 | 0 | 0 |

Checks: **400 base + 200 DoT = 600 total damage**, four casts cost
40 mana, three stacks max, one DoT packet per round, expiry at round 9.
Round 10 additionally tests rejection at 9 mana.

Test: `tests/combat/abi003_fireball_runner.gd`; workflow: `ABI Branch Tests`.
The test uses an explicit `magic_hit_roll = 1` for deterministic results. Real casts
without an override now draw a seeded roll from the combat engine rather than always
using 1.

## Deliberately deferred

Final AP costs, PAR018 formula, magic critical and projectile
unification, school aliases (frost vs water, lightning vs air), visual icons, and
interactive Arena ABI button wiring. No user-approved rules were invented for them.
