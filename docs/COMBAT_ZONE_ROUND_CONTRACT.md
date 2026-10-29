# Combat Zone & Round Contract

Status: approved combat-v2 foundation. This document supersedes older engagement assumptions where they conflict.

## 1. Spatial model

Combat uses three absolute linear zones: `ZONE_1 <-> ZONE_2 <-> ZONE_3`.
Each team has a flag side (ZONE_1 or ZONE_3). Forward means away from that team's flag; backward means toward it.

Zones do not imply class. Any combatant may occupy any zone.

## 2. Targeting and reach

Targets are not reserved by engagements. A combatant may select any valid target allowed by team, zone and action reach.

- Melee reach: current zone only (distance 0).
- Ranged/ABI reach is data-driven.
- Same/adjacent zones have no default distance penalty.
- Two-zone reach is allowed only when the weapon/ABI permits it and applies its configured Hit or Magic Hit penalty.
- Ranged weapons may attack targets in their own zone.
- Equipment/loadout is fixed for the whole battle.
- Offensive actions never affect allies; support/healing actions never affect enemies. Friendly fire is an engine invariant.

## 3. Ordinary Navigation

Navigation is the combatant's action for the round: no Base Attack or ABI in the same round.
It requests exactly one adjacent-zone transition. Positive Tempo never grants extra zone movement.

Direction is relative to the combatant's team flag:
- backward movement is allowed even while an enemy occupies the current zone;
- forward movement by ordinary Navigation is blocked while any enemy occupies the current zone.

Special movement ABI may bypass the forward-line rule when explicitly defined. Charge is movement only: it has no inherent damage and moves at most one adjacent zone.

Accumulated Tempo is not a per-action success roll. Movement is allowed while the character is not in an explicitly scheduled stunned round and has no other movement lock (e.g. root). Negative Tempo is retained for the end-of-round stun threshold, not applied as a random navigation penalty. A failed movement still consumes the declared action.

## 4. Simultaneous round contract

The start-of-round snapshot determines what actions/targets are legal. Technical processing order must not create initiative.

Round order:
1. PAR015/PAR016 regenerate HP/mana for previously alive combatants at round opening;
2. capture start-of-round snapshot and lock choices;
3. Base Attacks;
4. ABI immediate resolution;
5. calculate/apply immediate damage;
6. Movement;
7. active EFF processing;
8. life/death finalization;
9. battle-end check.

Immediate ABI damage (for example Frostbolt damage) applies in the casting round.
A new persistent EFF/status created during that round becomes active from the next round. It cannot cancel an action already valid and declared in the current round.

Internal HP may be negative before finalization. A combatant alive at round start remains round-present and zone-controlling until the life/death phase. Healing before finalization may rescue negative HP. Passive PAR016 regeneration does not: it applies only at the next round's opening to combatants still alive from the previous round. PAR015 restores mana at that same opening boundary, capped by max mana; PAR013 is not a combat-round regeneration source. Neither pool regenerates at round end or more than once per round.

## 5. EFF and zone effects

Persistent area effects are attached to a zone, not a frozen list of target IDs. When an active zone EFF ticks, it queries the valid occupants of that zone at that phase.
A newly created EFF does not tick in its creation round.
The EFF retains its source/owner even if that source later dies, while the battle continues.

Root prohibits zone changes while active, including ordinary and forced movement. Stun/Freeze/Fear use hard-control semantics (Tempo -100) for their active rounds.

## 6. Movement contests

Opposing forced/special movement requests are resolved in Movement phase, not by arbitrary event order.
Effects declare their contest stat/formula. Same-direction forces may combine; opposing groups contest. Equal result cancels movement. Regardless of combined force, one movement resolution changes a combatant by at most one adjacent zone unless a future ability explicitly defines a different topology.

## 7. Death and battle result

Death is finalized only in the life/death phase. After finalization, battle end is checked immediately.
If all opposing teams are eliminated in the same round, the result is a draw. Lingering EFF does not keep an otherwise finished battle alive.

Kill attribution is not last-hit based. For a target finalized dead, aggregate damage by source in the fatal round; the highest total receives the kill. Exact ties award a kill to every tied source.

## Persistent HP and mana (Arena integration)

- `CharacterState.current_hp` and `current_mana` are the persistent resource values. PAR010/PAR011 and active equipment determine the maximums; equipping never replenishes current resources and unequipping immediately clamps both pools.
- Combat starts from the current character pools via `CharacterCombatBuilder`. An accepted Arena round writes the finalized HP/mana back through `CharacterState.commit_combat_resources` (checks fighter ownership and unchanged maximums), then the village saves the existing progression file's `resources` field.
- Reopening Arena and restarting the game preserve those current values. Inventory and Character screens show current/max values. At zero HP, Arena cannot run another round.
- Training-only recovery is explicit: the Arena level settings panel has a **Test: restore HP and mana** action. This is not a general recovery rule or an automatic heal on victory/defeat.
- PAR015 (mana/round) and PAR016 (HP/round) apply once at the shared **begin-round phase**, before action locking. Mana-cost reduction (PAR018) and AP/Tempo persistence remain separate systems.

## Out-of-combat HP and mana recovery (approved)

- PAR012 is **percent of MaxHP per 10 seconds**. PAR017 is **flat HP per 10 seconds**. Both combine additively: `HP per 10 sec = MaxHP * PAR012 / 100 + PAR017`. PAR013 is **flat mana per 10 seconds**. PAR015 and PAR016 continue to apply in combat only, per round.
- Recovery uses real elapsed seconds and persistent fractional progress, so ten 1-second advances match one 10-second advance. No dependence on render FPS. Both pools are capped by their PAR maximums.
- At startup, offline elapsed time since `regen_saved_unix` is processed **without a time cap**, after loading the saved equipment. The progression save schema remains v1, adding an optional timestamp and fractional fields. Legacy saves without timestamps cannot retroactively recover unknown time.
- An Arena combat session suspends the out-of-combat clock; the saved `regen_paused` flag prevents retroactive out-of-combat recovery if the app quits during combat. On normal exit, the timestamp restarts from exit time.
- At 0 HP, passive recovery does not revive the character (nor restore mana). Recovery requires an explicit mechanic; the Arena debug refill remains available to testers.

## Tempo PAR019–021: accumulated control and explicit stun

- PAR019 defines the character's starting positive Tempo. Combat stores `base_tempo` separately from mutable `tempo`. The starting value is capped by PAR020.
- PAR020 is a positive upper cap with canonical baseline **100**, including bonuses from active equipment; negative Tempo has no floor.
- PAR021 is fixed Tempo regeneration **at the start of every round**, including the stunned round and both immunity rounds. It never increases Tempo beyond PAR020.
- Incoming control subtracts Tempo once when the effect lands, even while immune. Persistent effect records never repeatedly subtract the same control through overlays.
- If a living combatant has Tempo ≤ −100 **at the end of a non-immune round**, a stun is scheduled for the **next round**. The trigger pays up to 100 negative Tempo (`min(0, tempo + 100)`) without discarding the remaining debt.
- The stunned round blocks attacks, ABI, active defences and movement. At the **end** of that stunned round, add `50% × base_tempo` exactly once, capped by PAR020.
- The **two following complete rounds** are stun-immune. Control continues accumulating and PAR021 still regenerates, but no stun or −100 payment occurs. A new stun can first be scheduled at the end of the next non-immune round.
- Positive Tempo does **not** grant extra attacks. A low/negative Tempo is not itself a reason to cancel actions until the scheduled stunned round begins. Death is finalized before Tempo stun/rebound processing.
