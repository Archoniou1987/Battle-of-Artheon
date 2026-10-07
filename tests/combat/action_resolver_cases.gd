class_name ActionResolverCases
extends RefCounted

static func run() -> bool:
	var ok := true
	var state := CombatState.new()
	var source := CombatantState.new("source", 1, 100)
	var target := CombatantState.new("target", 1, 100)
	state.add_combatant(source)
	state.add_combatant(target)
	var engine := CombatEngine.new(state, {})

	var projectile := AbilityRuntime.build_action_event(state, "source", "target", "ABI_TEST", {
		"delivery_type": "PROJECTILE",
		"target_scope": "SINGLE",
		"components": [{"kind":"damage","amount":7,"damage_type":"fire"}]
	})
	ok = ok and projectile.kind == CombatEvent.Kind.ACTION
	ok = ok and String(projectile.payload.get("delivery_type", "")) == "PROJECTILE"
	engine.resolve_event(projectile)
	ok = ok and String(projectile.result.get("outcome", "")) == "dispatched"
	var child_ids:Array = projectile.result.get("child_event_ids", [])
	ok = ok and child_ids.size() == 1
	engine.resolve_pending_events()
	ok = ok and target.hp == 93
	var child:CombatEvent = state.event_log[state.event_log.size() - 1]
	ok = ok and child.parent_event_id == projectile.event_id
	ok = ok and String(child.payload.get("ability_id", "")) == "ABI_TEST"
	ok = ok and String(child.payload.get("delivery_type", "")) == "PROJECTILE"

	var legacy := AbilityRuntime.build_damage_event(state, "source", "target", "ABI_LEGACY", {
		"damage": 3,
		"damage_type": "physical"
	})
	ok = ok and legacy.kind == CombatEvent.Kind.ACTION
	ok = ok and legacy.payload.get("components", []).size() == 1

	return ok
