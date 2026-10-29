class_name CombatDiagnostics
extends RefCounted

## Read model for combat diagnostics. It exposes engine inputs/results; it does
## not recalculate combat formulas for UI consumers.

static func combatant_trace(combatant:CombatantState, round_number:int) -> Dictionary:
	if combatant == null:
		return {}
	return {
		"id": combatant.combatant_id,
		"name": combatant.display_name,
		"level": combatant.level,
		"hp": combatant.visible_hp(),
		"hp_internal": combatant.hp,
		"max_hp": combatant.max_hp,
		"mana": combatant.mana,
		"max_mana": combatant.max_mana,
		"combat_stats": CombatModifierService.combat_readout(combatant, round_number),
		"active_effects": CombatModifierService.active_effects(combatant, round_number),
		"can_manual_block": combatant.can_manual_block(),
		"can_auto_block": combatant.can_auto_block(),
		"death_finalized": combatant.is_death_finalized()
	}

static func event_trace(event:CombatEvent) -> Dictionary:
	return {
		"id": event.event_id,
		"round": int(event.payload.get("round", 0)),
		"kind": int(event.kind),
		"source_id": event.source_id,
		"target_id": event.target_id,
		"parent_event_id": event.parent_event_id,
		"payload": event.payload.duplicate(true),
		"result": event.result.duplicate(true),
		"outcome": String(event.result.get("outcome", ""))
	}

## Canonical event audit for a completed round. This is a read-only
## projection, never an alternative damage/ABI/EFF calculation. The GUI may
## render the event detail separately without leaking mechanics into UI.
static func round_trace(combat_state: CombatState, round_number: int) -> Dictionary:
	var traces: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	var duplicate_ids: Array[int] = []
	var missing_parent_ids: Array[int] = []
	var attack_by_source: Dictionary = {}
	var abi_by_source: Dictionary = {}
	var applied_effect_by_id: Dictionary = {}
	var periodic_by_id: Dictionary = {}
	var weapon_attacks := 0
	var abi_casts := 0
	var applied_effects := 0
	var periodic_ticks := 0
	if combat_state == null:
		return {"round":round_number, "events":traces, "valid_event_lineage":false, "reason":"missing_combat_state"}
	for event in combat_state.event_log:
		if int(event.payload.get("round",-1)) != round_number:
			continue
		traces.append(event_trace(event))
		if seen_ids.has(event.event_id):
			duplicate_ids.append(event.event_id)
		seen_ids[event.event_id] = true
		if event.kind == CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)) and not bool(event.payload.get("is_counterattack",false)):
			weapon_attacks += 1
			attack_by_source[event.source_id] = int(attack_by_source.get(event.source_id,0)) + 1
		if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("source_kind","")) == "ability":
			abi_casts += 1
			abi_by_source[event.source_id] = int(abi_by_source.get(event.source_id,0)) + 1
		if event.kind in [CombatEvent.Kind.DAMAGE,CombatEvent.Kind.EFFECT] and String(event.payload.get("source","")) == "effect":
			periodic_ticks += 1
			var periodic_id: String = String(event.payload.get("effect_id",""))
			periodic_by_id[periodic_id] = int(periodic_by_id.get(periodic_id,0)) + 1
		elif event.kind == CombatEvent.Kind.EFFECT and bool(event.result.get("resolved",false)) and not String(event.payload.get("effect_id","")).is_empty():
			applied_effects += 1
			var applied_id: String = String(event.payload.get("effect_id",""))
			applied_effect_by_id[applied_id] = int(applied_effect_by_id.get(applied_id,0)) + 1
	# A parent can be recorded after the child by the queue policy; only
	# inspect lineage after all round events have been collected.
	for trace in traces:
		var parent_id := int(trace.get("parent_event_id",-1))
		if parent_id >= 0 and not seen_ids.has(parent_id):
			missing_parent_ids.append(parent_id)
	return {
		"round": round_number,
		"events": traces,
		"event_count": traces.size(),
		"weapon_attacks":weapon_attacks,
		"weapon_attacks_by_source":attack_by_source,
		"abi_casts":abi_casts,
		"abi_casts_by_source":abi_by_source,
		"applied_effects":applied_effects,
		"applied_effects_by_id":applied_effect_by_id,
		"periodic_ticks":periodic_ticks,
		"periodic_ticks_by_id":periodic_by_id,
		"duplicate_event_ids":duplicate_ids,
		"missing_parent_event_ids":missing_parent_ids,
		"valid_event_lineage":duplicate_ids.is_empty() and missing_parent_ids.is_empty()
	}
