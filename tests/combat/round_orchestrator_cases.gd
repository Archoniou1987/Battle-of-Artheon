class_name RoundOrchestratorCases
extends RefCounted

static func run(balance:Dictionary) -> bool:
	var cases:Dictionary={
		"locked":_locked_actions_finish(balance),
		"dead_source_deferred":_dead_source_keeps_deferred_until_death_phase(balance),
		"living_source_deferred":_living_source_resolves_deferred(balance),
		"heal_rescue":_pending_death_can_be_healed(balance),
		"heal_insufficient":_insufficient_heal_still_dies(balance),
		"finalized_no_heal":_finalized_death_cannot_be_healed(balance),
		"persistent_aoe":_persistent_aoe_ticks(balance),
		"zone_aoe":_zone_aoe_follows_occupants_after_movement(balance),
		"deferred_death":_deferred_damage_finalizes_death(balance),
		"kill_attribution":_kill_attribution_uses_fatal_round_total(balance),
		"combined_forced_movement":_combined_forced_movement_uses_one_step(balance),
		"forced_tie":_opposing_forced_tie_stays_put(balance),
		"forced_formula":_forced_movement_uses_data_driven_contest(balance),
		"forced_invalid_jump":_forced_movement_rejects_non_adjacent_effect(balance),
		"movement_edges":_movement_edges_and_root(balance),
		"navigation_forced_exclusive":_navigation_and_forced_are_exclusive(balance)
	}
	for case_name in cases:
		if not bool(cases[case_name]): print("ROUND_CASE_FAIL=",case_name)
	return not cases.values().has(false)

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
	if state.get_combatant("a").is_death_finalized() or state.get_combatant("b").is_death_finalized(): return false
	var summary:=orchestrator.end_round()
	return summary.get("dead_ids",[]).size()==2 and state.get_combatant("a").is_death_finalized() and state.get_combatant("b").is_death_finalized()

static func _dead_source_keeps_deferred_until_death_phase(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var round:=orchestrator.begin_round()
	var deferred:=state.create_event(CombatEvent.Kind.DAMAGE,"b","a",{"amount":3.0,"damage_type":"physical","source":"deferred"})
	orchestrator.defer_event(deferred,true,true)
	round.lock_action(_lethal(state,"a","b"))
	orchestrator.resolve_locked_actions(round)
	var summary:=orchestrator.end_round()
	return summary.get("resolved_deferred_event_ids",[]).has(deferred.event_id) and state.get_combatant("a").hp==7

static func _living_source_resolves_deferred(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	var deferred:=state.create_event(CombatEvent.Kind.DAMAGE,"a","b",{"amount":3.0,"damage_type":"physical","source":"deferred"})
	orchestrator.defer_event(deferred,true,true)
	var summary:=orchestrator.end_round()
	return summary.get("resolved_deferred_event_ids",[]).has(deferred.event_id) and state.get_combatant("b").hp==7

static func _pending_death_can_be_healed(balance:Dictionary)->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",1,100)
	hero.hp=20
	state.add_combatant(hero)
	state.add_combatant(CombatantState.new("ally","Ally",1,100))
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"ally","hero",{"amount":50.0,"damage_type":"physical"}))
	if hero.hp!=-30 or hero.visible_hp()!=0 or hero.is_death_finalized(): return false
	hero.restore_hp(40)
	var summary:=orchestrator.end_round()
	return hero.hp==10 and hero.visible_hp()==10 and not hero.is_death_finalized() and not summary.get("dead_ids",[]).has("hero")

static func _insufficient_heal_still_dies(balance:Dictionary)->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",1,100)
	hero.hp=20
	state.add_combatant(hero)
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"hero","hero",{"amount":50.0,"damage_type":"physical"}))
	hero.restore_hp(20)
	var summary:=orchestrator.end_round()
	return hero.hp==-10 and hero.visible_hp()==0 and hero.is_death_finalized() and summary.get("dead_ids",[]).has("hero")

static func _finalized_death_cannot_be_healed(balance:Dictionary)->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",1,100)
	hero.hp=-5
	state.add_combatant(hero)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance))
	orchestrator.begin_round(); orchestrator.end_round()
	var healed:=hero.restore_hp(100)
	return healed==0 and hero.hp==-5 and hero.is_death_finalized()

static func _persistent_aoe_ticks(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("caster","Caster",1,100))
	state.add_combatant(CombatantState.new("t0","T0",1,100))
	state.add_combatant(CombatantState.new("t1","T1",1,100))
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var initial:=AbilityRuntime.build_action_event(state,"caster","t0","ABI_DOT_AREA",{
		"delivery_type":"AREA","target_scope":"ALL_ENEMIES","duration_rounds":3,
		"components":[{"kind":"damage","amount":10.0,"damage_type":"fire","full_targets":2}]
	})
	initial.payload["target_ids"]=["t0","t1"]
	state.queue_event(initial); engine.resolve_pending_events()
	orchestrator.register_from_action(initial)
	if state.get_combatant("t0").hp!=90 or state.get_combatant("t1").hp!=90: return false
	orchestrator.begin_round(); orchestrator.end_round()
	if state.get_combatant("t0").hp!=80 or state.get_combatant("t1").hp!=80: return false
	orchestrator.begin_round(); orchestrator.end_round()
	return state.get_combatant("t0").hp==70 and state.get_combatant("t1").hp==70

static func _zone_aoe_follows_occupants_after_movement(balance:Dictionary)->bool:
	var state:=CombatState.new()
	for id in ["caster","leaver","enterer"]:
		state.add_combatant(CombatantState.new(id,id,1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","caster")
	groups.add_member("B","leaver")
	groups.add_member("B","enterer")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("caster",CombatZoneState.ZONE_1)
	zones.set_zone("leaver",CombatZoneState.ZONE_2)
	zones.set_zone("enterer",CombatZoneState.ZONE_3)
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine,groups,zones)
	orchestrator.begin_round()
	orchestrator.register_zone_effect("caster",CombatZoneState.ZONE_2,{
		"delivery_type":"AREA","duration_rounds":3,
		"components":[{"kind":"damage","amount":10.0,"damage_type":"fire","full_targets":5}]
	},3)
	orchestrator.end_round()
	if state.get_combatant("leaver").hp!=100: return false
	orchestrator.begin_round()
	# Both enemies move in the same direction relative to team B: leaver retreats
	# to its edge while enterer advances into the active effect zone.
	# Move sequentially for this test: it verifies that EFF queries occupants
	# after Movement, while swap/Contest behavior has its own regression case.
	zones.set_zone("leaver",CombatZoneState.ZONE_3)
	if not orchestrator.queue_movement_request("enterer",CombatZoneState.ZONE_2,1,true,"forced",{"stats":[],"flat_power":1.0}): return false
	orchestrator.end_round()
	var ok:=state.get_combatant("leaver").hp==100 and state.get_combatant("enterer").hp==90 and zones.zone_of("leaver")==CombatZoneState.ZONE_3 and zones.zone_of("enterer")==CombatZoneState.ZONE_2
	if not ok: print("ZONE_AOE_STATE leaver_hp=",state.get_combatant("leaver").hp," enterer_hp=",state.get_combatant("enterer").hp," leaver_zone=",zones.zone_of("leaver")," enterer_zone=",zones.zone_of("enterer"))
	return ok


static func _deferred_damage_finalizes_death(balance:Dictionary)->bool:
	var state:=_duel_state()
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	var deferred:=state.create_event(CombatEvent.Kind.DAMAGE,"a","b",{"amount":20.0,"damage_type":"physical","source":"deferred"})
	orchestrator.defer_event(deferred,true,true)
	var summary:=orchestrator.end_round()
	return state.get_combatant("b").is_death_finalized() and summary.get("dead_ids",[]).has("b")


static func _kill_attribution_uses_fatal_round_total(balance:Dictionary)->bool:
	var state:=CombatState.new()
	for id in ["a","b","victim"]:
		state.add_combatant(CombatantState.new(id,id,1,100))
	var engine:=CombatEngine.new(state,balance)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"a","victim",{"amount":60.0,"damage_type":"physical"}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"b","victim",{"amount":50.0,"damage_type":"physical"}))
	var summary:=orchestrator.end_round()
	if summary.get("kill_attribution",{}).get("victim",[])!=["a"]: return false
	var state2:=CombatState.new()
	for id in ["a","b","victim"]:
		state2.add_combatant(CombatantState.new(id,id,1,100))
	var engine2:=CombatEngine.new(state2,balance)
	var orchestrator2:=RoundOrchestrator.new(state2,engine2)
	orchestrator2.begin_round()
	engine2.resolve_event(state2.create_event(CombatEvent.Kind.DAMAGE,"a","victim",{"amount":60.0,"damage_type":"physical"}))
	engine2.resolve_event(state2.create_event(CombatEvent.Kind.DAMAGE,"b","victim",{"amount":60.0,"damage_type":"physical"}))
	var tied:Array=orchestrator2.end_round().get("kill_attribution",{}).get("victim",[])
	return tied==["a","b"]


static func _combined_forced_movement_uses_one_step(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("a","A",1,100))
	state.add_combatant(CombatantState.new("b","B",1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_1); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_2,1,true,"forced",{"stats":[],"flat_power":10.0}): return false
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_2,1,true,"forced",{"stats":[],"flat_power":5.0}): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and bool(results[0].get("moved",false)) and zones.zone_of("a")==CombatZoneState.ZONE_2 and float(results[0].get("contest_power",0.0))==15.0


static func _opposing_forced_tie_stays_put(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("a","A",1,100))
	state.add_combatant(CombatantState.new("b","B",1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_2); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_3,1,true,"forced",{"stats":[],"flat_power":10.0}): return false
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_1,1,true,"forced",{"stats":[],"flat_power":10.0}): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and not bool(results[0].get("moved",true)) and String(results[0].get("reason",""))=="movement_locked" and zones.zone_of("a")==CombatZoneState.ZONE_2



static func _forced_movement_uses_data_driven_contest(balance:Dictionary)->bool:
	var state:=CombatState.new()
	var a:=CombatantState.new("a","A",1,100)
	a.stats["STR"]=4.0
	state.add_combatant(a); state.add_combatant(CombatantState.new("b","B",1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_2); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_3,1,true,"forced",{"stats":["STR"],"flat_power":1.0,"multiplier":2.0}): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and bool(results[0].get("moved",false)) and float(results[0].get("contest_power",0.0))==10.0 and zones.zone_of("a")==CombatZoneState.ZONE_3


static func _forced_movement_rejects_non_adjacent_effect(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("a","A",1,100)); state.add_combatant(CombatantState.new("b","B",1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_1); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_3,1,true,"forced",{"flat_power":99.0}): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and not bool(results[0].get("moved",true)) and zones.zone_of("a")==CombatZoneState.ZONE_1

static func _movement_edges_and_root(balance:Dictionary)->bool:
	var state:=CombatState.new()
	var a:=CombatantState.new("a","A",1,100)
	var b:=CombatantState.new("b","B",1,100)
	state.add_combatant(a); state.add_combatant(b)
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_1); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_1-1,1,true,"forced",{"flat_power":10.0}): return false
	var edge:=orchestrator.resolve_movement_phase()
	if edge.size()!=1 or bool(edge[0].get("moved",true)) or zones.zone_of("a")!=CombatZoneState.ZONE_1: return false
	a.active_effects.append({"start_round":state.round_number+1,"remaining_rounds":2,"definition":{"kind":"root"}})
	orchestrator.begin_round()
	if orchestrator.queue_movement_request("a",CombatZoneState.ZONE_2,1,true,"forced",{"flat_power":99.0}): return false
	return zones.zone_of("a")==CombatZoneState.ZONE_1


static func _navigation_and_forced_are_exclusive(balance:Dictionary)->bool:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("a","A",1,100))
	state.add_combatant(CombatantState.new("b","B",1,100))
	var groups:=GroupCombatState.new(state)
	groups.add_member("A","a"); groups.add_member("B","b")
	var zones:=CombatZoneState.new(groups)
	zones.set_team_flag("A",CombatZoneState.ZONE_1); zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_1); zones.set_zone("b",CombatZoneState.ZONE_3)
	var orchestrator:=RoundOrchestrator.new(state,CombatEngine.new(state,balance),groups,zones)
	orchestrator.begin_round()
	if not orchestrator.queue_movement_request("a",CombatZoneState.ZONE_2,1,true,"navigation"): return false
	if orchestrator.queue_movement_request("a",CombatZoneState.ZONE_2,1,true,"forced",{"flat_power":100.0}): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and zones.zone_of("a")==CombatZoneState.ZONE_2
