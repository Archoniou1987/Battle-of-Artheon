class_name PhysicalAttackCases
extends RefCounted

## Deterministic smoke cases for the physical attack pipeline.

static func run(balance: Dictionary) -> bool:
	return (
		_case_miss(balance)
		and _case_dodge(balance)
		and _case_block(balance)
		and _case_connected_zero_damage(balance)
	)


static func _base_state() -> CombatState:
	var state := CombatState.new()
	var attacker := CombatantState.new("hero", "Hero", 10, 100)
	var defender := CombatantState.new("enemy", "Enemy", 10, 100)
	state.add_combatant(attacker)
	state.add_combatant(defender)
	state.begin_round()
	return state


static func _attack(state: CombatState, rolls: Dictionary, damage: float = 20.0) -> CombatEvent:
	return state.create_event(
		CombatEvent.Kind.ATTACK,
		"hero",
		"enemy",
		{"raw_damage": damage, "zone": "chest", "damage_type": "slashing", "rolls": rolls}
	)


static func _case_miss(balance: Dictionary) -> bool:
	var state := _base_state()
	var event := _attack(state, {"hit": 100})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "miss" and state.get_combatant("enemy").hp == 100


static func _case_dodge(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["dodge"] = 40.0
	var event := _attack(state, {"hit": 1, "dodge": 1})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "dodge" and state.get_combatant("enemy").hp == 100


static func _case_block(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["manual_block_zone"] = "chest"
	var event := _attack(state, {"hit": 1, "block_crush": 100})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "manual_block" and state.get_combatant("enemy").hp == 100


static func _case_connected_zero_damage(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").armour["chest"] = {"slashing": 5000.0}
	var event := _attack(state, {"hit": 1, "crit": 100}, 0.5)
	var engine := CombatEngine.new(state, balance)
	state.queue_event(event)
	engine.resolve_pending_events()
	if state.event_log.size() != 2:
		return false
	var damage_event: CombatEvent = state.event_log[1]
	return (
		event.result.get("outcome") == "connected"
		and damage_event.result.get("final_damage") == 0
		and damage_event.result.get("connected") == true
		and state.get_combatant("enemy").hp == 100
	)
