class_name GroupCombatSimulator
extends RefCounted

var state:CombatState
var group:GroupCombatState
var controller:GroupCombatController
var engine:CombatEngine
var orchestrator:RoundOrchestrator
var attack_pipeline:CombatAttackPipeline
var max_rounds:int=999

func _init(combat_state:CombatState,group_state:GroupCombatState,balance:Dictionary={}) -> void:
	state=combat_state
	group=group_state
	controller=GroupCombatController.new(group)
	engine=CombatEngine.new(state,balance)
	orchestrator=RoundOrchestrator.new(state,engine,group)
	attack_pipeline=CombatAttackPipeline.new(state,1)
	controller.initialize_active_opponents()

func run() -> Dictionary:
	while not controller.combat_finished() and state.round_number<max_rounds:
		run_round()
	var winner:=controller.winning_team()
	return {"outcome":"timeout" if not controller.combat_finished() else ("draw" if winner.is_empty() else "winner:"+winner),"winning_team":winner,"rounds":state.round_number,"dead_ids":_finalized_dead_ids()}

func run_round() -> Dictionary:
	if controller.combat_finished():
		return {"ok":false,"reason":"combat_finished","battle_outcome":"winner:"+controller.winning_team()}
	var round:=orchestrator.begin_round()
	var round_targets:Dictionary={}
	var actors:Array[String]=[]
	for raw_id in group.combatant_team.keys():
		actors.append(String(raw_id))
	actors.sort()
	for actor_id in actors:
		var actor:=state.get_combatant(actor_id)
		if actor==null or actor.is_death_finalized() or not actor.is_alive():
			continue
		var target_id:=controller.ensure_active_opponent(actor_id)
		var target:=state.get_combatant(target_id)
		if target==null or target.is_death_finalized():
			continue
		round_targets[actor_id]=target_id
		attack_pipeline.lock_basic_attack(round,actor,target)
	# All combat intents are sealed before any action is resolved. Preparation
	# ABI are the only actions which modify stats before shared combat resolution.
	for actor_id in actors:
		var actor:=state.get_combatant(actor_id)
		if actor==null or actor.is_death_finalized():
			continue
		# ABI keeps the target selected for this round, even if its HP fell below zero.
		# Retargeting happens only after end-round death finalization.
		var target_id:=String(round_targets.get(actor_id,""))
		var target:=state.get_combatant(target_id)
		if target==null or target.is_death_finalized():
			continue
		attack_pipeline.lock_ready_abilities(round,actor,target)
	orchestrator.resolve_locked_actions(round)
	var summary:=orchestrator.end_round()
	var sync:=controller.after_end_round(summary)
	return {"ok":true,"round":state.round_number,"summary":summary,"sync":sync,"battle_outcome":"winner:"+controller.winning_team() if controller.combat_finished() and not controller.winning_team().is_empty() else ("draw" if controller.combat_finished() else "ongoing")}

func _finalized_dead_ids()->Array[String]:
	var result:Array[String]=[]
	for raw_id in state.combatants.keys():
		var combatant:=state.get_combatant(String(raw_id))
		if combatant!=null and combatant.is_death_finalized():
			result.append(String(raw_id))
	result.sort()
	return result
