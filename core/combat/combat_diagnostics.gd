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
