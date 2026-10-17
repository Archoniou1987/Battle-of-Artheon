# Battle of Artheon — ABI Test Lab v1

Development-only, isolated from the persistent player. Accessible from Arena →
**ABI Lab** in the wrapped header. Godot 4.5.1.

## Mobile UI v1.1 (tabbed)

The old full-height vertically-scrolling dialog made the **Cast** and **Results**
controls inaccessible on narrow Android screens. The new dialog has three
tabs: **Способность** (preset, damage, level and rolls), **PAR** (select and
apply one or more rating/defence overrides) and **Результаты** (live engine
event log). The action row **Новый тест / Применить ABI / Пропустить**
is outside the tab scroll containers and remains visible at all times.
After a cast or skipped round the dialog automatically switches to Results.

For canonical ABI003, the non-editable ability name, FIRE type, 10-mana
cost and 1-round cooldown are shown in one compact summary rather than
four inert input rows. Synthetic ABI presets show editable fields.
The dialog dimensions are bounded by the viewport (92% width, 82% height,
subject to a 310×340 minimum), on both portrait and landscape.

The expanded UI smoke now checks tab labels and visibility, fixed action
placement, bounded viewport height, preset switching, automatic navigation
to Results, and preservation of persistent player resources.

## Scope and exact boundaries

- Uses **real** `AbilityRuntime`, `AbilityScheduler`, `CombatEngine`,
  `RoundOrchestrator`, `PhysicalArmourService`, `RatingMatrix` and
  `EffectCatalog`. There is no alternative formula in UI or test tools.
- Presets:
  - `ABI003` — canonical Fireball, base FIRE 100 (editable for isolated balance
    experiments), 10 mana, 1 full cooldown round, applies EFF003.
  - `LAB_PHYSICAL` — generated physical ABI with an editable damage packet
    (default 100). Choose slashing/piercing/chopping/blunt.
  - `LAB_MAGIC` — generated elemental ABI with an editable damage packet
    (default 100). Choose fire/water/air/earth/dark/light.
- Canonical `ABI001` is the **basic MH/OH weapon attack**, managed by
  `ParAttackContract`; it is not repurposed as a custom lab spell.
- Custom abilities accept a label, temporary mana cost and cooldown.
  Changing any setting starts a new, isolated run upon next cast.
- Two independent levels (caster/dummy, 1–100), deterministic hit and critical
  rolls (1–100) and explicit editable PAR values; unmodified ratings start at
  zero. Deterministic rolls are only test overrides.
- Each click **Cast** or **Skip** advances one full round. A cast rejected by
  cooldown or insufficient mana still advances the round, so EFF ticks/expiry
  continue. The log contains ACTION, ATTACK, DAMAGE, EFF and exact engine
  results, current dummy HP, mana, damage and active effect stacks/duration.
- No persistent `CharacterState` or `ItemRepository` references,
  `resources_changed` emissions, equipment mutations or write-backs.

## Editable PAR values (ONLY implemented combat consumers)

Caster:
`PAR030` (hit rating), `PAR033` (critical chance rating),
`PAR035` (critical damage rating), `PAR125` (flat armour penetration),
`PAR126` (percentage armour penetration), `PAR150` (magic damage rating).

Dummy:
`PAR034` (anti-critical rating), `PAR101` (flat chest armour),
`PAR135` (general percentage damage reduction), `PAR190` (all-magic
resistance rating), `PAR191–196` (individual fire/water/air/earth/dark/light
resistance ratings).

Rating PARs are recalculated by the canonical `RatingMatrix` according to
the **character level**. Flat armour remains subject to the existing physical
armour rating conversion and critical damage runs through the existing
`CombatEngine` chain. Missing and unfinished PARs are NOT silently treated as
implemented: `PAR018` and unimplemented elemental penetration/damage PARs
cannot be selected.

## Known limitations / follow-ups

- No connection yet to the five production Arena ABI slots.
- These are **test-created** combatants with 10,000 HP each and 500 test mana,
  not the equipment/level progression build of the actual player.
- The lab shows calculations for the existing combat engine as-is. It does
  **not** claim an approved final design for magic critical, all spell delivery
  modes, magic school aliases (`frost` vs `water`, `lightning` vs `air`),
  or PAR018 mana reductions.
- The physical laboratory presets test an ability `ATTACK` path, not
  `ABI001`'s real weapon-hand equipment path. For ABI001 tests use existing
  weapon and PAR regression suites.
- Effects use canonical EFF definitions: EFF003 has one shared refreshed
  three-round duration, maximum three stacks, 10 FIRE per stack/round.
- The results display the authoritative **engine event chain**, not
  predictions based on UI-only maths.

## QA gates

`ABI Branch Tests` workflow checks:

1. `tests/combat/abi003_fireball_runner.gd` — real Fireball 100, mana10,
   cooldown1, shared-duration EFF003.
2. `tests/combat/abi_test_lab_runner.gd` — magic100, physical100, flat
   armour, percentage penetration, PAR150/190/191, critical rating, rejects
   unsupported PAR018.
3. `tests/ui/abi_test_lab_open_runner.gd` — opens from Arena and keeps
   persistent player HP/mana and ArenaCombatSession state untouched.

Use one batch CI run after the entire change set to minimise GitHub Actions
costs. No full visual UX manual test is claimed without a real play session.
