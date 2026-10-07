class_name ActionResolverCases
extends RefCounted

static func run() -> bool:
	var ok := true
	var state := CombatState.new()
	var source := CombatantState.new("source", "Source", 1, 100)
	var target := CombatantState.new("target", "Target", 1, 100)
	state.add_combatant(source)
	state.add_combatant(target)
	var engine := CombatEngine.new(state, {})

	var projectile := AbilityRuntime.build_action_event(state, "source", "target", "ABI_TEST", {
		"delivery_type": "PROJECTILE",
		"target_scope": "SINGLE",
		"components": [{"kind":"damage","amount":7,"damage_type":"fire"}],
		"rolls":{"hit":1}
	})
	ok = ok and projectile.kind == CombatEvent.Kind.ACTION
	ok = ok and String(projectile.payload.get("delivery_type", "")) == "PROJECTILE"
	engine.resolve_event(projectile)
	ok = ok and String(projectile.result.get("outcome", "")) == "dispatched"
	var child_ids:Array = projectile.result.get("child_event_ids", [])
	ok = ok and child_ids.size() == 1
	engine.resolve_pending_events()
	ok = ok and target.hp == 93
	var projectile_damage:CombatEvent=state.event_log[state.event_log.size()-1]
	var projectile_attack:CombatEvent=state.event_log[state.event_log.size()-2]
	ok = ok and projectile_attack.parent_event_id == projectile.event_id
	ok = ok and projectile_damage.parent_event_id == projectile_attack.event_id
	ok = ok and String(projectile_attack.payload.get("ability_id",""))=="ABI_TEST"
	ok = ok and String(projectile_attack.payload.get("delivery_type",""))=="PROJECTILE"
	ok = ok and String(projectile_damage.payload.get("ability_id",""))=="ABI_TEST"
	ok = ok and String(projectile_damage.payload.get("delivery_type",""))=="PROJECTILE"

	var legacy := AbilityRuntime.build_damage_event(state, "source", "target", "ABI_LEGACY", {
		"damage": 3,
		"damage_type": "physical"
	})
	ok = ok and legacy.kind == CombatEvent.Kind.ACTION
	ok = ok and legacy.payload.get("components", []).size() == 1


	var mixed := AbilityRuntime.build_action_event(state, "source", "target", "ABI_MIXED", {
		"delivery_type": "AREA",
		"target_scope": "ALL_ENEMIES",
		"components": [
			{"kind":"damage","amount":2,"damage_type":"frost"},
			{"kind":"effect","effect_id":"EFF_UNKNOWN","base_chance":80}
		]
	})
	engine.resolve_event(mixed)
	ok = ok and int(mixed.result.get("dispatched_component_count", 0)) == 2
	ok = ok and mixed.result.get("child_event_ids", []).size() == 2
	ok = ok and mixed.result.get("unsupported_components", []).is_empty()

	var unsupported := AbilityRuntime.build_action_event(state, "source", "target", "ABI_FUTURE", {
		"components": [{"kind":"future_component"}]
	})
	engine.resolve_event(unsupported)
	ok = ok and String(unsupported.result.get("outcome", "")) == "no_supported_components"
	ok = ok and unsupported.result.get("unsupported_components", []).has("future_component")

	var definitions := {"ABI_SCHEDULED":{"delivery_type":"DIRECT","target_scope":"SINGLE","components":[{"kind":"damage","amount":1,"damage_type":"lightning"}],"mana_cost":1,"cooldown_rounds":1}}
	var loadouts := {"source":["ABI_SCHEDULED"]}
	var scheduler := AbilityScheduler.new(definitions, loadouts)
	source.mana = 10
	var scheduled:Array[CombatEvent] = scheduler.ready_events(state, "source", "target")
	ok = ok and scheduled.size() == 1
	ok = ok and scheduled[0].kind == CombatEvent.Kind.ACTION
	ok = ok and String(scheduled[0].payload.get("ability_id", "")) == "ABI_SCHEDULED"

	if not ok:
		print("ACTION_RESOLVER_CASES=FAIL hp=",target.hp," projectile=",projectile.result," mixed=",mixed.result," unsupported=",unsupported.result," scheduled=",scheduled.size())
		for logged_event in state.event_log:
			print("ACTION_EVENT id=",logged_event.event_id," kind=",logged_event.kind," parent=",logged_event.parent_event_id," payload=",logged_event.payload," result=",logged_event.result)
	return ok
