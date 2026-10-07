class_name RoundOrchestratorCases
extends RefCounted

static func run(balance:Dictionary) -> bool:
	return _locked_actions_finish(balance) and _dead_source_cancels_deferred(balance) and _living_source_resolves_deferred(balance) and _persistent_aoe_ticks(balance)

static func _duel_state()->CombatState:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("a","A",1,10))
	state.add_combatant(CombatantState.new("b","B",1,10))
	return state

static func _lethal(state:CombatState,source:String,target:String)->CombatEvent:
	return state.create_event(CombatEvent.Kind.ATTACK,source,target,{"raw_damage":50.0,"zone":"chest","damage_type":"slashing","rolls":{"hit":1,"crit":100}})

static func _locked_actions_finish(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var round:=orchestrator.begin_round()
	round.lock_action(_lethal(state,"a","b"))
	round.lock_action(_lethal(state,"b","a"))
	orchestrator.resolve_locked_actions(round)
	var summary:=orchestrator.end_round()
	return summary.get("dead_ids",[]).size()==2 and not state.get_combatant("a").is_alive() and not state.get_combatant("b").is_alive()

static func _dead_source_cancels_deferred(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var round:=orchestrator.begin_round()
	var deferred:=state.create_event(CombatEvent.Kind.DAMAGE,"b","a",{"amount":3.0,"damage_type":"physical","source":"deferred"})
	orchestrator.defer_event(deferred,true,true)
	round.lock_action(_lethal(state,"a","b"))
	orchestrator.resolve_locked_actions(round)
	var summary:=orchestrator.end_round()
	return summary.get("canceled_deferred_event_ids",[]).has(deferred.event_id) and state.get_combatant("a").hp==10

static func _living_source_resolves_deferred(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	var deferred:=state.create_event(CombatEvent.Kind.DAMAGE,"a","b",{"amount":3.0,"damage_type":"physical","source":"deferred"})
	orchestrator.defer_event(deferred,true,true)
	var summary:=orchestrator.end_round()
	return summary.get("resolved_deferred_event_ids",[]).has(deferred.event_id) and state.get_combatant("b").hp==7

static func _persistent_aoe_ticks(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("caster","Caster",1,100))
	state.add_combatant(CombatantState.new("t0","T0",1,100))
	state.add_combatant(CombatantState.new("t1","T1",1,100))
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var payload:={"ability_id":"ABI_DOT_AREA","delivery_type":"AREA","target_scope":"ALL_ENEMIES","components":[{"kind":"damage","amount":10.0,"damage_type":"fire","full_targets":2}]}
	orchestrator.register_persistent_action("caster",["t0","t1"],payload,3)
	orchestrator.begin_round(); orchestrator.end_round()
	if state.get_combatant("t0").hp!=90 or state.get_combatant("t1").hp!=90: return false
	orchestrator.begin_round(); orchestrator.end_round()
	return state.get_combatant("t0").hp==80 and state.get_combatant("t1").hp==80
