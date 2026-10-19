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

## Ability timing
All choices are locked before any combat event resolves.
- Early, before physical damage: pure buffs, pure debuffs, cleansing/dispelling.
  Cleansing is a support-style action, but may remove **beneficial enemy buffs** as
  well as harmful effects on allies; targeting must be explicit.
- Shared combat resolution: physical MH/OH attacks, damaging ABI, control ABI and
  healing ABI are peer actions in the SAME round. There is NO rule that all
  physical strikes must complete before damaging/healing ABI. A deterministic
  internal event traversal must NOT grant a combat advantage purely by traversal order.
  Healing is not an early preparatory buff. It contributes to the round's HP
  outcome alongside damage; deferred death is checked only at end of round.
- HP damage/healing accounting must be order-independent: compute individual
  post-mitigation hit results and healing contributions, then reconcile the
  provisional net HP for the round (and clamp displayed/final surviving HP as
  appropriate). In particular, a healing amount must not be discarded merely
  because the current provisional HP temporarily exceeds MaxHP before subsequent
  hits. A single lethal one-shot hit >= MaxHP remains fatal even if net HP > 0.
  EFF tick lifecycle retains its own semantics and runs before death finalization.
- Mixed ABI containing damage or control belongs to the shared combat resolution
  **as a whole**. Never peel an early debuff component out of a damaging/control ABI.
  Round-preparation debuffs and buffs are the sole exception to simultaneous
  damage/healing calculation; do not turn ordinary ABI damage or healing into
  mandatory subphases.
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
- IMPLEMENTED (pending GitHub CI): the canonical `cleanse` ABI component removes
  matching beneficial/harmful EFF records, including their current stacks.
  Use `combat_role: "CLEANSE"`, explicit `target_team: "ALLY"|"ENEMY"`,
  and component `{"kind":"cleanse","dispel_polarity":"DEBUFF"|"BUFF","max_effects":1}`.
  Ally/enemy target validation runs in the Command API and in group-aware CombatEngine.
- IMPLEMENTED (pending GitHub CI): `combat_role: "BUFF"|"DEBUFF"|"CLEANSE"`
  on a pure effect/cleanse ABI executes it in the preparation phase; mixed damage,
  healing or control resolves in the shared phase instead.
- Arena ABI controls, full submission locking and player-controlled ABI targeting are
  NOT yet connected to the real Arena session; these are the next integration stage.
- Current event processing is sequential for internal bookkeeping; it preserves
  damage/healing HP commutativity with a final HP cap, but complete event-order
  invariance of every secondary interaction (e.g. concurrent dispel/rebuff) remains
  an explicit future integration check.

## Required E2E checks before acceptance
1. Two daggers yield 2 physical attacks + at most 1 ABI in a single round.
2. OH does not increase the available active ABI list; armour ABI remain usable.
3. 1–4 arbitrary non-adjacent blocks work in live Arena and shared Combat.
4. Changing selections after End Round cannot change that round's results.
5. Mixed damaging/control ABI do not execute in early phase.
6. Buff/debuff/dispel apply before combat calculation; damage/heal/control/physical
   are peer round actions, not sequential priority classes. Verify both
   damage-before-heal and heal-before-damage yield the same final HP, including
   overheal near MaxHP and negative provisional HP, except the one-shot override.
7. EFF stacking/expiry and deferred death/one-shot rules remain intact.
8. Dead, stunned, invalid and duplicate casts cannot consume an ABI slot, mana or cooldown.
