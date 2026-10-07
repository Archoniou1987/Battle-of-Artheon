class_name OpportunityActionCases
extends RefCounted

static func run()->bool:
	return _independent_rolls() and _active_opponent_not_restricted() and _dead_actor_cannot_start_opportunity() and _base_attack_uses_attack_pipeline() and _ability_uses_action_pipeline() and _zone_reach_controls_opportunity_events()

static func _context()->Dictionary:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("player","Player",10,100))
	state.add_combatant(CombatantState.new("e0","E0",10,100))
	state.add_combatant(CombatantState.new("e1","E1",10,100))
	state.add_combatant(CombatantState.new("e2","E2",10,100))
	var group:=GroupCombatState.new(state)
	group.add_member("players","player")
	group.add_member("enemies","e0")
	group.add_member("enemies","e1")
	group.add_member("enemies","e2")
	group.set_active_opponent("player","e0")
	return {"state":state,"group":group,"resolver":OpportunityActionResolver.new(group,25.0,20.0)}

static func _independent_rolls()->bool:
	var x:=_context()
	var resolver:OpportunityActionResolver=x["resolver"]
	var actors:Array[String]=["e1","e2"]
	var decisions:Array[Dictionary]=resolver.decide_against("player",actors,{
		"e1":{"base_attack":10,"ability":10},
		"e2":{"base_attack":10,"ability":90}
	})
	var e1_base:=false
	var e1_abi:=false
	var e2_base:=false
	var e2_abi:=false
	for decision in decisions:
		var key:=String(decision.get("source_id",""))+":"+String(decision.get("kind",""))
		if key=="e1:BASE_ATTACK": e1_base=true
		if key=="e1:ABILITY": e1_abi=true
		if key=="e2:BASE_ATTACK": e2_base=true
		if key=="e2:ABILITY": e2_abi=true
	return e1_base and e1_abi and e2_base and not e2_abi

static func _active_opponent_not_restricted()->bool:
	var x:=_context()
	var resolver:OpportunityActionResolver=x["resolver"]
	var actors:Array[String]=["e0"]
	var decisions:Array[Dictionary]=resolver.decide_against("player",actors,{"e0":{"base_attack":1,"ability":1}})
	var has_base:=false
	var has_abi:=false
	for decision in decisions:
		if String(decision.get("source_id",""))!="e0": continue
		if String(decision.get("kind",""))=="BASE_ATTACK": has_base=true
		if String(decision.get("kind",""))=="ABILITY": has_abi=true
	return has_base and has_abi

static func _dead_actor_cannot_start_opportunity()->bool:
	var x:=_context()
	x["state"].get_combatant("e1").hp=-10
	var actors:Array[String]=["e1","e2"]
	var decisions:Array[Dictionary]=x["resolver"].decide_against("player",actors,{
		"e1":{"base_attack":1,"ability":1},
		"e2":{"base_attack":100,"ability":100}
	})
	for decision in decisions:
		if String(decision.get("source_id",""))=="e1": return false
	return true

static func _base_attack_uses_attack_pipeline()->bool:
	var x:=_context()
	var resolver:OpportunityActionResolver=x["resolver"]
	var decision:Dictionary={"kind":"BASE_ATTACK","source_id":"e1","target_id":"player"}
	var event:=resolver.base_attack_event(decision,{
		"raw_damage":10.0,
		"damage_type":"slashing",
		"zone":"chest",
		"rolls":{"hit":1,"reaction":100,"crit":100}
	})
	return event.kind==CombatEvent.Kind.ATTACK and bool(event.payload.get("opportunity_action",false))


static func _ability_uses_action_pipeline()->bool:
	var x:=_context()
	var resolver:OpportunityActionResolver=x["resolver"]
	var decision:Dictionary={"kind":"ABILITY","source_id":"e1","target_id":"player"}
	var event:=resolver.ability_event(decision,"ABI_EXT",{
		"delivery_type":"PROJECTILE",
		"target_scope":"SINGLE",
		"components":[{"kind":"damage","amount":7,"damage_type":"fire"}]
	})
	return event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI_EXT" and bool(event.payload.get("opportunity_action",false))


static func _zone_reach_controls_opportunity_events()->bool:
	var x:=_context()
	var group:GroupCombatState=x["group"]
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("players",CombatZoneState.ZONE_1)
	zones.set_team_flag("enemies",CombatZoneState.ZONE_3)
	zones.set_zone("player",CombatZoneState.ZONE_1)
	zones.set_zone("e1",CombatZoneState.ZONE_3)
	var resolver:=OpportunityActionResolver.new(group,25.0,20.0,zones)
	var decision:Dictionary={"source_id":"e1","target_id":"player"}
	var melee:=resolver.base_attack_event(decision,{"raw_damage":10.0,"damage_type":"physical"})
	if melee!=null: return false
	var short_abi:=resolver.ability_event(decision,"ABI_SHORT",{"delivery_type":"PROJECTILE","max_zone_distance":1,"components":[{"kind":"damage","amount":7,"damage_type":"physical"}]})
	if short_abi!=null: return false
	var ranged_abi:=resolver.ability_event(decision,"ABI_LONG",{"delivery_type":"PROJECTILE","max_zone_distance":2,"components":[{"kind":"damage","amount":7,"damage_type":"physical"}]})
	return ranged_abi!=null
