# Battle of Artheon — Integrated Combat Round V1 contract

Approved gameplay rules (2026-10-19). The document specifies the TARGET architecture;
individual rules must not be marked implemented without code + CI evidence.

## Sealed simultaneous intentions
- Each actor (player or NPC) chooses its combat actions before the round is resolved.
- After the actor submits End Round, that actor's attack zones, block zones and optional
  single ABI are locked; the other actor's intentions must not alter the submission.
- No damage is calculated from the submitted plan before the round resolution starts.
- Submission is validated before changing HP/mana, starting cooldowns, or advancing a round.
- Players never choose ordering inside a phase. An ABI's manually chosen
  `instant` mode is resolved before the standard calculation, independent
  of whether the ABI buffs, debuffs, heals, cleanses or deals damage.
  `standard` ABI share the current round's ordinary damage/healing phase.

## Action budget
- Ordinary physical attacks: 1–2 per round, determined by equipped MH/OH profiles (PAR057).
  MH and OH have separate physical hit resolution; both are compatible with the ABI cast.
- Manual blocks: 1–4 distinct body zones according to PAR073, **any combination**.
  Adjacent zones are NOT required. A separate automatic shield block remains independent.
- Active ABI: 0–1 successfully committed cast per actor per round across ALL active ABI
  (weapon and armour), including direct or area/zone use.
- The 2 weapon attacks + 1 ABI example means 3 offensive **actions**, not necessarily
  3 successful hits or 3 damage events. Multi-component ABI remains only one cast.
- Weapon active ABI loadout: MH only (up to 3). OH active ABI are not granted even
  when OH item carries ability definitions. Armour ABI (chest/head) use the other 2
  slots independently. OH physical attacks and on-hit effects still work.
- EFF are stateful, autonomous effects and consume NO active ABI budget when ticking,
  stacking, expiring or resolving their ongoing effects.

## Manual ABI timing: two phases in ONE round (2026-10-19)
A hand-authored ABI has exactly one hidden configuration field:

```json
"application_timing": "standard"
```

The only two supported values:
- `instant`: execute at the **beginning of the current round** after all
  actions have been selected and sealed, BEFORE standard attack/damage
  resolution. Thus a stat buff/debuff can modify the current round's combat
  calculations, and cleanse can remove an active effect before those checks.
- `standard`: execute in the **ordinary end-of-round combat calculation**,
  alongside physical attacks, damaging ABI, control and healing.

There is **no delayed ABI**, no next-round cast queue, and no retry or
cancellation introduced by the timing setting. Both cast types apply to the
current round. Cast payment, cooldown and one-ABI limit are shared; a selected
ABI is not triggered immediately on button press, only after End Round locks
all intentions. Provisional death from current-round hits does NOT cancel an
actor's already-locked standard ABI. Death is finalized after the EFF phase,
subject to the existing one-shot rule.

No auto-inference from EFF kind, ability role, or component composition.
The timing applies to the ABI as a whole, including mixed compositions.
Production ability entries explicitly set the field. For legacy fixtures
without a field, `standard` is the default.

EFF periodic lifetime is distinct from the timing of its casting ABI.
Autonomous EFF ticks retain their own start, stacking and end-round rules.
A newly inflicted periodic effect does not retroactively change earlier
damage results, regardless of the ABI timing setting.

### Instant effect surprise / disclosure rule (2026-10-19)
An `instant` ABI may apply a BUFF or DEBUFF in the opening phase. That
new effect modifies this round's combat calculations immediately, but is
**not visible to either fighter until end_round**. Dispel/cleanse in that
same round cannot remove this undisclosed EFF, even if the other instant
ABI is processed later. It becomes visible at the end-round boundary,
and is first eligible for cleanse in **the following round**.

The runtime must keep separate:
- `start_round` — when stat/control modifiers actually become active;
- `revealed` — whether EFF UI is permitted to show the effect;
- `dispel_available_round` — earliest round in which cleanse can remove it.

`end_round` marks surviving hidden effects as revealed after periodic
effects and death finalization. This does **not** change actual activation
or EFF durations. Already-known effects from previous rounds remain
eligible for cleansing this round. Ordinary standard-phase EFF have
their existing next-round activation and visibility lifecycle.
This is a rule about EFF visibility, NOT a next-round ABI cast.

## Implementation status (2026-10-19)
- CONFIRMED in ABI Branch Tests #39267341295 on commit `a9beb86`:
  player/NPC simultaneous healing and ordinary attacks, subsequent DoT/HoT
  lifecycle, live Arena ABI selection, cooldown enforcement, MH-only equipment
  ABI availability, EFF visuals and resolved combat journal.
- CONFIRMED in Combat Tests #39254568436 on commit `8be7ea6`:
  integrated Arena MH/OH strikes and one selected ABI. Later ABI workflow
  also executes Arena integration regressions.
- Implemented: sealed Arena inputs, 1 active ABI per actor/round, independent
  physical attacks, support-target routing for current 1v1 Arena, and
  end-round death finalization.
- Implemented: two phase slots for the manually set ABI timing;
  `instant` enters this round's opening phase and `standard` enters this
  round's shared combat phase. EFF retain separate start/tick semantics.
- VERIFIED in ABI Branch Tests #39319522076, commit `ce997b4`:
  `application_timing` uses only `instant` (beginning of current round)
  and `standard` (same-round shared calculation). Both player and NPC
  passed targeted instant-vs-standard Arena tests. There is no scheduled ABI.
- NEW REGRESSION COVERAGE (PENDING CI): `round_effect_death_regression_runner.gd`
  checks damage/inline healing/HoT order, one-shot with healing, DoT and
  HoT tick order, lethal one-shot DoT, cleanse of shared stacked DoT,
  skipping not-yet-active EFF, and finalized death exactly once.
  Test suite is included in the existing manual ABI Branch Tests workflow.
- Implemented: native `cleanse` ABI removes active EFF of declared polarity.
  Explicit `target_team: "ALLY"|"ENEMY"` and
  `{"kind":"cleanse","dispel_polarity":"DEBUFF"|"BUFF","max_effects":1}`
  specify the target and how many effect records to remove.
- NEW surprise-EFF contract (PENDING CI): a fresh instant-applied BUFF
  or DEBUFF is active this round, concealed in EFF displays until end_round,
  and immune to same-round dispelling regardless of instant action order.
  A revealed earlier-round effect is still removable. CI scenarios test
  both instant orders with existing ArenaCombatSession and ensure next-round
  cleanse becomes possible. Existing same-effect shared-duration stack
  refresh may require separate per-stack disclosure semantics.
- Remaining limitations: no interactive ally-target picker for larger groups
  or finalized player-facing ABI artwork. Do not infer success of unexecuted
  regression tests from earlier successful CI runs.

## Required E2E checks before acceptance
1. Two daggers yield 2 physical attacks + at most 1 ABI in a single round.
2. OH does not increase the available active ABI list; armour ABI remain usable.
3. 1–4 arbitrary non-adjacent blocks work in live Arena and shared Combat.
4. Changing selections after End Round cannot change that round's results.
5. A mixed ABI has one explicit timing; no type-based early-phase guessing.
6. Instant ABI is processed first in the sealed current round; standard
   ABI resolves with ordinary damage and healing in the *same* round.
   HP calculations must preserve equal net results despite traversal order,
   including overheal and negative provisional HP, except one-shot.
7. EFF stacking/expiry and deferred death/one-shot rules remain intact.
8. Dead, stunned, invalid and duplicate casts cannot consume an ABI slot, mana or cooldown.
