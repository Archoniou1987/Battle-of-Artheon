# Battle of Artheon — ABI Test Lab

The laboratory is a **development-only, isolated** CombatEngine sandbox. Its
synthetic presets are not game abilities, are never generated on equipment, and
do not exist in `data/abilities/catalog.json`.

## Active presets

- `LAB_PHYSICAL`: controlled physical damage and hit/crit checks.
- `LAB_MAGIC`: six schools, raw magic damage, optional per-component
  `spell_power_scale` K, canonical magic resistance.
- `LAB_HEAL`: controlled healing and optional support effects on self/ally.

The lab can attach a test EFF by explicit `test_effect_id` when exercising
DoT/HoT lifecycles. Such EFF are mechanical regression fixtures, not
approved production ABI. No old `ABI001–006` spell or training preset is
loaded from the game catalog.

Each run uses isolated CombatantState objects and
AbilityRuntime → AbilityScheduler → CombatEngine → RoundOrchestrator.
No persistent character HP, mana, inventory, or equipment is mutated.

PAR150 is absolute Spell Power (SP); ABI scaling is `base + K × SP` with
optional nonnegative K. K=0 preserves base output; no DR is applied to SP.
Direct magic % buffs and magic resistance are separate calculations.

## QA

- `tests/combat/abi_test_lab_runner.gd` checks physical, magic/SP,
  EFF delayed DoT, healing, delayed HoT, and rejected invalid presets.
- `tests/ui/abi_test_lab_open_runner.gd` checks UI panels and
  persistence isolation.
- Real weapon ABI301–308, ABI401–408, ABI501–508 and ABI601–606 are
  verified by their corresponding v1.2 weapon integration runners.

The deprecated Fireball/Healing ability contract and its dedicated CI tests
were removed after the user confirmed those ABI were temporary.
