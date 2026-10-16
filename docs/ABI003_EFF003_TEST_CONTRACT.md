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
- `mana_cost = 0`, `cooldown_rounds = 0` are **temporary test placeholders**, not approved design values; PAR018 must be integrated before choosing final costs and cooldowns.
- The ability is available as canonical data and engine events. **The five Arena ABI buttons are still UI-only** until the separate integration stage.

## EFF003 — Burning

- Damage over time, no immediate EFF damage on the cast round.
- **10 FIRE damage per stack per completed round**, on the next three rounds after application.
- `duration_rounds = 3`; each stack has its own start time and expiry.
- `stacking = stack`, `max_stacks = 3` on one target.
- The fourth application while three stacks are active does **not** add a fourth stack and does not reset existing timers.
- Tick events use the shared `DAMAGE` pipeline: FIRE resistance and global damage reduction apply. DoT does not independently roll to crit in this implementation.
- Remaining duration decreases at round end. Death still finalizes only after end-round effects.

## Deterministic six-round acceptance scenario

Caster uses ABI003 in rounds 1–4 against a 1000 HP target with zero resistance and no regeneration.
Magic hit succeeds; criticals are disabled in this fixture. No casts on rounds 5–6.

| Round | Fireball base | Burning ticks | Total damage | Target HP after round | Active stacks after round |
|---|---:|---:|---:|---:|---:|
| 1 | 100 | 0 | 100 | 900 | 1 |
| 2 | 100 | 10 | 110 | 790 | 2 |
| 3 | 100 | 20 | 120 | 670 | 3 |
| 4 | 100 | 30 | 130 | 540 | 2 |
| 5 | 0 | 20 | 20 | 520 | 1 |
| 6 | 0 | 10 | 10 | 510 | 0 |

Test: `tests/combat/abi003_fireball_runner.gd`; workflow: `ABI Branch Tests`.
The test uses an explicit `magic_hit_roll = 1` for deterministic results. Real casts
without an override now draw a seeded roll from the combat engine rather than always
using 1.

## Deliberately deferred

Final mana/AP/cooldown costs, PAR018 formula, magic critical and projectile
unification, school aliases (frost vs water, lightning vs air), visual icons, and
interactive Arena ABI button wiring. No user-approved rules were invented for them.
