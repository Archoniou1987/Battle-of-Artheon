class_name CombatState
extends RefCounted

## Owns deterministic simulation state for one combat.

var round_number: int = 0
var combatants: Dictionary = {}
var event_log: Array[CombatEvent] = []
var pending_events: Array[CombatEvent] = []
var next_event_id: int = 1


func add_combatant(combatant: CombatantState) -> void:
	combatants[combatant.combatant_id] = combatant


func get_combatant(combatant_id: String) -> CombatantState:
	return combatants.get(combatant_id) as CombatantState


func begin_round() -> void:
	round_number += 1


func create_event(
	kind: CombatEvent.Kind,
	source_id: String,
	target_id: String,
	payload: Dictionary = {},
	parent_event_id: int = -1
) -> CombatEvent:
	var event_payload := payload.duplicate(true)
	event_payload["round"] = round_number
	var event := CombatEvent.new(next_event_id, kind, source_id, target_id, event_payload, parent_event_id)
	next_event_id += 1
	return event


func queue_event(event: CombatEvent) -> void:
	pending_events.append(event)


func record_event(event: CombatEvent) -> void:
	event_log.append(event)
