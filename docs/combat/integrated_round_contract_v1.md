# Battle of Artheon — Integrated Combat Round V1 contract

Approved gameplay rules (2026-10-19). The document specifies the TARGET architecture;
individual rules must not be marked implemented without code + CI evidence.

## Sealed simultaneous intentions
- Each actor (player or NPC) chooses its combat actions before the round is resolved.
- After the actor submits End Round, that actor's attack zones, block zones and optional
  single ABI are locked; the other actor's intentions must not alter the submission.
- No damage is calculated from the submitted plan before the round resolution starts.
- Submission is validated before changing HP/mana, starting cooldowns, or advancing a round.
- Players never choose ordering inside the simultaneous resolution phase. Pre-resolution
  buff/debuff/cleanse is a special exception; physical attacks, damage ABI, control
  and healing are peer actions resolved from the same sealed round intent.

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

## Hand-authored ABI application timing (2026-10-19 decision)
The ability designer controls **one hidden field**, not automatic role/EFF inference:

```json
"application_timing": "immediate"
```

Allowed values:
- `immediate` — execute the ABI in the current round's sealed resolution,
  before ordinary weapon attacks. Its stat EFF can influence this round's
  weapon calculations. Direct ABI damage and healing contribute to the same
  provisional HP total as physical damage; final HP/death is decided at
  end_round. This is **not** an action on clicking the button.
- `next_round` — commit the cast and pay mana/start cooldown/use this
  round's one-ABI allowance, but activate the **whole ability** once in the
  following round. If its caster is finalized dead or its target invalid at
  activation, the normal combat resolution rejects it; the paid cast is not
  refunded or retried.

No automatic inference from `combat_role`, EFF `kind`, DoT/HoT, stun or
whether a component deals damage. Mixed abilities inherit one timing as a
whole. Legacy/test fixture definitions without this field default to
`immediate`, but hand-authored production ABI declare it explicitly.

EFF durations/stacks retain their separate periodic tick contracts:
shared-duration DoT/HoT does not tick on application, and keeps its full
future tick count even if the ABI itself was immediate. A delayed ability's
EFF is applied only when the delayed ABI resolves.

Other boundaries stay unchanged: choices are sealed before resolution,
ordinary hits/ABI/HP healing all count within one round, one-shot overrides
net healing, and death finalization runs after EFF.

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
- Implemented: early buffs/debuffs/cleansing and shared resolution of damage,
  healing and control. A pure prep ABI applies an EFF from the current round,
  whereas ordinary EFF retain their own start/tick lifecycle.
- NEW hand-authored timing (PENDING CI): `application_timing` replaces
  all previous EFF/role timing checks; only two enum values are validated.
  A next-round ABI is stored as a sealed intent and activated once next
  round without paying mana twice. New tests cover immediate defence,
  delayed healing/damage, cooldown payment and death cancellation.
- Implemented: native `cleanse` ABI removes active EFF of declared polarity.
  Explicit `target_team: "ALLY"|"ENEMY"` and
  `{"kind":"cleanse","dispel_polarity":"DEBUFF"|"BUFF","max_effects":1}`
  specify the target and how many effect records to remove.
- Remaining limitations: no interactive ally-target picker for larger groups,
  no finalized player-facing ABI artwork, and no comprehensive guarantee
  that *every* concurrent secondary interaction (such as cleanse vs.
  simultaneous re-buff) is independent of internal event traversal order.
  These require separate E2E acceptance rather than inferred CI success.

## Required E2E checks before acceptance
1. Two daggers yield 2 physical attacks + at most 1 ABI in a single round.
2. OH does not increase the available active ABI list; armour ABI remain usable.
3. 1–4 arbitrary non-adjacent blocks work in live Arena and shared Combat.
4. Changing selections after End Round cannot change that round's results.
5. A mixed ABI has one explicit timing; no type-based early-phase guessing.
6. Immediate ABI is processed in the sealed current round before weapon
   attacks; next-round ABI fires exactly once next round. HP damage/healing
   must have the same final net outcome regardless of processing order,
   including overheal and negative provisional HP, except one-shot.
7. EFF stacking/expiry and deferred death/one-shot rules remain intact.
8. Dead, stunned, invalid and duplicate casts cannot consume an ABI slot, mana or cooldown.
