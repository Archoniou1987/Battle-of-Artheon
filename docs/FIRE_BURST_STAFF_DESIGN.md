# BoA — FIRE_BURST / Огненный посох урона (design contract v0.1)

Status: **design staged; not executable**. This file does not add a usable generated weapon or executable ABI. Numeric tuning is provisional, pending Lv40 Combat Engine benchmark.

## Scope

- School: Fire (`fire`), archetype: `STAFF_FIRE_BURST` (proposed new 2H archetype).
- Four weapon ABI slots: proposed IDs `ABI801`–`ABI804` (reserve only; check ID allocations before production).
- Role: high first-10-round burst, mana-limited; not sustainable physical-DPS superiority beyond round 20 without gear/consumables.
- Reference parameters: `PAR150` Spell Power, `PAR015` mana regen, existing mana and fire-resistance/penetration PAR. Existing EFF module owns burning; no duplicate status.
- The base 2H staff physical damage is NOT yet specified in canonical v1.2. Do not invent physical autoattack scaling or enable broken generation until defined.

## ABI proposals (numbers are design placeholders, not approved balance)

| Slot | ABI proposal | Mechanic | Proposed Lv40 base damage | Mana | CD |
| --- | --- | --- | ---: | ---: | ---: |
| 1 | ABI801 Fireball / Огненный шар | Direct fire hit; applies weak EFF burning on hit; standard ability | 155 | 35 | 1 |
| 2 | ABI802 Fire Blast / Огненный взрыв | Instant-eligible additional cast; direct fire damage; no extra guaranteed crit until tested | 90 | 30 | 2 |
| 3 | ABI803 Ignite / Воспламенение | Strong direct fire hit, bonus when target is already burning; never silently consume EFF stacks | 175 | 45 | 3 |
| 4 | ABI804 Pyroblast / Пиробласт | Strong single-target finishing direct fire attack, high mana and longer cooldown | 300 | 75 | 5 |

All damage amounts above are *nominal before fire resistance and PAR150*, not actual observed combat damage. Exact rank 1–100 curves and SP coefficients require calibration; do not hard-code them into the canonical catalog based on these placeholders.

## Confirmed two-ABI rule

- Existing input behavior: resources are deducted immediately and an action is locked immediately.
- Up to two ABI may be selected in one round only if **at least one** is `instant_bonus_eligible`; at most one Instant per round.
- The **second selected** ABI costs `ceil(normal_mana_cost * 1.25)` and receives +1 additional cooldown round, whichever ABI is selected second.
- First selection remains untouched; no retroactive mana or CD rewrites.
- Spell effects resolve in the player's **selection order** within their actor's actions. Do not confuse this with `application_timing: instant`: current runtime treats it as resolve timing, and forbids direct instant damage. A separate extra-cast eligibility flag and compatible order handling are needed.
- Preserve existing PvP/PvE end-of-round death finalization and intercombatant tempo scheduling.
- Selection number is assigned on lock; ability UI must display incremental cast costs before the second action.
- No change to physical archetypes or their one-ABI limit.

## Safe integration gates

1. Establish usable 2H magic staff item bridge in ItemGenerator v1.2 and ItemV12InstanceFactory (existing `STAFF_ATTACK` is a preliminary template only; current physical factory rejects staffs).
2. Add ABI801–804 as canonical executable IDs and ten-rank damage definitions; derive calibrated values from a single anchor, not iterative rounding.
3. Reuse EFF burning; check damage over time, stacking, and fire resistance.
4. Extend `AbilityScheduler` for one extra eligible cast per actor per round with immediate resource spending, incremental CD and order index. Update round resolution to honor player action order *within that actor*; existing `application_timing` behavior must not reorder Fireball/Blast.
5. Run Godot import, item factory test, 1/10/20/40/60/75/100 ABI rank tests, and 25-vs-10000HP benchmarks for short/medium/long combat intervals.
6. Tune damage/mana against approved physical Lv40 reference. No numeric balances are accepted until tests pass.

This is a mechanical design staging document: it is deliberately not a claim that Fire Staff is playable.