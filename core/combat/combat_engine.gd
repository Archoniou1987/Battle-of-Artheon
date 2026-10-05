class_name CombatEngine
extends RefCounted

## Central event dispatcher. Individual resolvers will remain small and testable.

var state: CombatState


func _init(combat_state: CombatState) -> void:
	state = combat_state


func resolve_pending_events() -> void:
	while not state.pending_events.is_empty():
		var event: CombatEvent = state.pending_events.pop_front()
		resolve_event(event)


func resolve_event(event: CombatEvent) -> void:
	match event.kind:
		CombatEvent.Kind.ATTACK:
			_resolve_attack(event)
		CombatEvent.Kind.DAMAGE:
			_resolve_damage(event)
		CombatEvent.Kind.EFFECT:
			_resolve_effect(event)
	state.record_event(event)


func _resolve_attack(event: CombatEvent) -> void:
	# Attack delivery/active-defence pipeline will be expanded independently.
	event.set_result("resolved", true)


func _resolve_damage(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	if target == null:
		event.set_result("error", "target_not_found")
		return

	var raw_amount := float(event.payload.get("amount", 0.0))
	var final_damage := CombatMath.final_damage_floor(raw_amount)
	var applied := target.apply_damage(final_damage)
	event.set_result("final_damage", final_damage)
	event.set_result("hp_removed", applied)
	event.set_result("connected", true)


func _resolve_effect(event: CombatEvent) -> void:
	# EFF lifecycle/stacking is deliberately isolated from Attack and Damage.
	event.set_result("resolved", true)
