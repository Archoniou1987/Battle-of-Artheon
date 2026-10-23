class_name EngagementCases
extends RefCounted

static func run(balance:Dictionary)->bool:
	return _player_priority() and _npc_contest() and _two_round_lock() and _player_overrides_npc_lock() and _dead_requester_cannot_force_target(balance) and _death_bypass(balance)

static func _context()->Dictionary:
	var state:=CombatState.new()
	state.add_combatant(TestFixtureLoader.new_combatant("player","Player",10,100))
	state.add_combatant(TestFixtureLoader.new_combatant("e0","E0",10,100))
	state.add_combatant(TestFixtureLoader.new_combatant("e1","E1",10,100))
	state.add_combatant(TestFixtureLoader.new_combatant("e2","E2",10,100))
	var group:=GroupCombatState.new(state)
	group.add_member("players","player")
	group.add_member("enemies","e0")
	group.add_member("enemies","e1")
	group.add_member("enemies","e2")
	group.set_active_opponent("player","e0")
	return {"state":state,"group":group,"controller":GroupCombatController.new(group)}

static func _player_priority()->bool:
	var x:=_context()
	var controller:GroupCombatController=x["controller"]
	controller.engagement.request_change("player","e1","e1","NPC",1)
	controller.engagement.request_change("player","e2","player","PLAYER",100)
	controller.engagement.resolve_end_round(10)
	return x["group"].active_opponent("player")=="e2"

static func _npc_contest()->bool:
	var x:=_context()
	var controller:GroupCombatController=x["controller"]
	controller.engagement.request_change("player","e1","e1","NPC",70)
	controller.engagement.request_change("player","e2","e2","NPC",20)
	controller.engagement.resolve_end_round(10)
	return x["group"].active_opponent("player")=="e2"

static func _two_round_lock()->bool:
	var x:=_context()
	var controller:GroupCombatController=x["controller"]
	controller.engagement.request_change("player","e1","player","PLAYER",50)
	controller.engagement.resolve_end_round(10)
	if not controller.engagement.is_locked("player",11): return false
	if not controller.engagement.is_locked("player",12): return false
	if controller.engagement.is_locked("player",13): return false
	controller.engagement.request_change("player","e2","e2","NPC",1)
	controller.engagement.resolve_end_round(11)
	if x["group"].active_opponent("player")!="e1": return false
	controller.engagement.request_change("player","e2","e2","NPC",1)
	controller.engagement.resolve_end_round(13)
	return x["group"].active_opponent("player")=="e2"

static func _player_overrides_npc_lock()->bool:
	var x:=_context()
	var controller:GroupCombatController=x["controller"]
	controller.engagement.request_change("player","e1","e1","NPC",1)
	controller.engagement.resolve_end_round(10)
	if x["group"].active_opponent("player")!="e1": return false
	if not controller.engagement.is_locked("player",11): return false
	controller.engagement.request_change("player","e2","player","PLAYER",100)
	# Player may request an override immediately, but still faces the charging NPC
	# for the whole round. Every engagement change is applied only at End Round.
	if x["group"].active_opponent("player")!="e1": return false
	controller.engagement.resolve_end_round(11)
	return x["group"].active_opponent("player")=="e2" and controller.engagement.is_locked("player",12)

static func _death_bypass(balance:Dictionary)->bool:
	var x:=_context()
	var state:CombatState=x["state"]
	var group:GroupCombatState=x["group"]
	var controller:GroupCombatController=x["controller"]
	controller.engagement.request_change("player","e1","player","PLAYER",50)
	controller.engagement.resolve_end_round(10)
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"player","e1",{"amount":150.0,"damage_type":"physical"}))
	var summary:=orchestrator.end_round()
	controller.after_end_round(summary)
	return group.active_opponent("player")=="e0" and not controller.engagement.is_locked("player",state.round_number)


static func _dead_requester_cannot_force_target(balance:Dictionary)->bool:
	var x:=_context()
	var state:CombatState=x["state"]
	var controller:GroupCombatController=x["controller"]
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	controller.engagement.request_change("player","e1","e1","NPC",1)
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"player","e1",{"amount":150.0,"damage_type":"physical"}))
	var summary:=orchestrator.end_round()
	controller.after_end_round(summary)
	return x["group"].active_opponent("player")=="e0"
