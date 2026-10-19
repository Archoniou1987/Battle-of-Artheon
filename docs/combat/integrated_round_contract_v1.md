# Battle of Artheon — Integrated Combat Round V1 contract

Approved gameplay rules (2026-10-19). The document specifies the TARGET architecture;
individual rules must not be marked implemented without code + CI evidence.

## Sealed simultaneous intentions
- Each actor (player or NPC) chooses its combat actions before the round is resolved.
- After the actor submits End Round, that actor's attack zones, block zones and optional
  single ABI are locked; the other actor's intentions must not alter the submission.
- No damage is calculated from the submitted plan before the round resolution starts.
- Submission is validated before changing HP/mana, starting cooldowns, or advancing a round.
- Execution phase order is fixed; the player does not choose the order of attacks and ABI.

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

## Ability timing
All choices are locked before any combat event resolves.
- Early, before physical damage: pure buffs, pure debuffs, cleansing/dispelling.
  Cleansing is a support-style action, but may remove **beneficial enemy buffs** as
  well as harmful effects on allies; targeting must be explicit.
- Late, following physical attacks: direct damage, control and healing ABI.
  Healing remains subject to deferred death at end of round and the one-hit
  one-shot death contract.
- Mixed ABI containing damage or control is late **as a whole**. Never peel an
  early debuff component out of a late damaging ABI.
- Do not infer timing from ABI name or merely from whether it produces an EFF.
  A dedicated categorical definition/contract must be validated by the runtime.
- Persistent EFF ticks run according to their own end-round lifecycle; character
  death is finalized afterward. Previously finalized corpses cannot act or heal.

## Current implementation status at contract creation
- Existing CombatSimulator and GroupCombatSimulator support physical attacks plus
  a separate ABI phase, but do NOT yet implement this full locked plan and timing.
- Arena ABI buttons and ability selection are not yet wired to its Combat session.
- Core scheduler should enforce the shared one-ABI-per-round cap and equipment
  loadouts MH-only; targeted tests must verify this.
- Cleansing/dispelling still requires a canonical runtime component and explicit
  ally/enemy target authorization; do not fake it by using the current effect payload.

## Required E2E checks before acceptance
1. Two daggers yield 2 physical attacks + at most 1 ABI in a single round.
2. OH does not increase the available active ABI list; armour ABI remain usable.
3. 1–4 arbitrary non-adjacent blocks work in live Arena and shared Combat.
4. Changing selections after End Round cannot change that round's results.
5. Mixed damaging/control ABI do not execute in early phase.
6. Buff/debuff/dispel precede physical damage; heal happens in late phase.
7. EFF stacking/expiry and deferred death/one-shot rules remain intact.
8. Dead, stunned, invalid and duplicate casts cannot consume an ABI slot, mana or cooldown.
