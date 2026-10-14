class_name GroupCombatCases
extends RefCounted

static func run(balance:Dictionary) -> bool:
	return _one_vs_many_structure() and _pending_death_stays_until_end_round(balance) and _active_replacement_after_death(balance) and _combat_finish()

static func _state(enemy_count:int)->CombatState:
	var state:=CombatState.new()
	state.add_combatant(TestFixtureLoader.new_combatant("player","Player",10,100))
	for i in range(enemy_count):
		state.add_combatant(TestFixtureLoader.new_combatant("e%d"%i,"Enemy",10,100))
	return state

static func _group(state:CombatState,enemy_count:int)->GroupCombatState:
	var group:=GroupCombatState.new(state)
	group.add_member("players","player")
	for i in range(enemy_count):
		group.add_member("enemies","e%d"%i)
	return group

static func _one_vs_many_structure()->bool:
	var state:=_state(3)
	var group:=_group(state,3)
	if not group.set_active_opponent("player","e0"): return false
	var external:Array[String]=group.alternative_targets("player")
	return group.team_of("player")=="players" and group.living_enemies("player").size()==3 and group.active_opponent("player")=="e0" and external.size()==2 and external.has("e1") and external.has("e2")

static func _pending_death_stays_until_end_round(balance:Dictionary)->bool:
	var state:=_state(2)
	var group:=_group(state,2)
	group.set_active_opponent("player","e0")
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"player","e0",{"amount":150.0,"damage_type":"physical"}))
	if state.get_combatant("e0").hp!=-50: return false
	if not group.living_enemies("player").has("e0"): return false
	var summary:=orchestrator.end_round()
	GroupCombatController.new(group).after_end_round(summary)
	return not group.living_enemies("player").has("e0")

static func _active_replacement_after_death(balance:Dictionary)->bool:
	var state:=_state(3)
	var group:=_group(state,3)
	group.set_active_opponent("player","e0")
	var controller:=GroupCombatController.new(group)
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"player","e0",{"amount":150.0,"damage_type":"physical"}))
	if group.active_opponent("player")!="e0": return false
	var sync:=controller.after_end_round(orchestrator.end_round())
	return group.active_opponent("player")=="e1" and String(sync.get("active_replacements",{}).get("player",{}).get("to",""))=="e1" and group.alternative_targets("player").size()==1

static func _combat_finish()->bool:
	var state:=_state(1)
	var group:=_group(state,1)
	var controller:=GroupCombatController.new(group)
	controller.initialize_active_opponents()
	if controller.combat_finished(): return false
	state.get_combatant("e0").death_finalized=true
	group.prune_finalized_deaths()
	return controller.combat_finished() and controller.winning_team()=="players"
