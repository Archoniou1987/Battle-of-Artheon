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

Tempo decides whether the declared movement executes; it never substitutes another action or destination.
- Tempo >= 0: declared Navigation is not penalized by Tempo.
- -100 < Tempo < 0: success chance is 100 + Tempo percent.
- Tempo <= -100: movement fails.
A failed movement still consumes the declared action.

## 4. Simultaneous round contract

The start-of-round snapshot determines what actions/targets are legal. Technical processing order must not create initiative.

Round order:
1. lock choices from start-of-round state;
2. Base Attacks;
3. ABI immediate resolution;
4. calculate/apply immediate damage;
5. Movement;
6. active EFF processing;
7. PAR015/PAR016 end-round regeneration for combatants with HP > 0;
8. life/death finalization;
9. battle-end check.

Immediate ABI damage (for example Frostbolt damage) applies in the casting round.
A new persistent EFF/status created during that round becomes active from the next round. It cannot cancel an action already valid and declared in the current round.

Internal HP may be negative before finalization. A combatant alive at round start remains round-present and zone-controlling until the life/death phase. Healing before finalization may rescue negative HP. Passive PAR016 regeneration does not: it only applies while HP > 0 after timed effects. PAR015 restores mana at the same boundary, capped by max mana; PAR013 is not a combat-round regeneration source. Neither pool regenerates more than once per round.

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
