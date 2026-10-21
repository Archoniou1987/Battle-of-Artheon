class_name GroupCombatSimulator
extends RefCounted

var state:CombatState
var group:GroupCombatState
var controller:GroupCombatController
var engine:CombatEngine
var orchestrator:RoundOrchestrator
var attack_pipeline:CombatAttackPipeline
var max_rounds:int=999

## Empty by default: legacy tests and Arena never persist implicitly.
var checkpoint_path := ""
var checkpoint_encounter_key := ""
var checkpoint_roster_fingerprint := ""
var round_in_progress := false
## Only this field certifies a fully completed run_round() boundary.
var last_completed_round := 0

func enable_checkpoint(encounter_key: String, roster_fingerprint: String, path: String = GroupCombatCheckpointService.DEFAULT_PATH) -> Dictionary:
	if not GroupCombatCheckpointService._valid_identity(encounter_key,roster_fingerprint) or not GroupCombatCheckpointService._valid_path(path):
		return {"ok":false,"reason":"invalid_checkpoint_configuration"}
	if state.round_number == 0 and GroupCombatCheckpointService.initial_roster_fingerprint(state) != roster_fingerprint:
		return {"ok":false,"reason":"checkpoint_initial_roster_mismatch"}
	checkpoint_path = path
	checkpoint_encounter_key = encounter_key
	checkpoint_roster_fingerprint = roster_fingerprint
	return {"ok":true}

func _init(combat_state:CombatState,group_state:GroupCombatState,balance:Dictionary={}) -> void:
	state=combat_state
	group=group_state
	controller=GroupCombatController.new(group)
	engine=CombatEngine.new(state,balance)
	orchestrator=RoundOrchestrator.new(state,engine,group)
	## Group and duel simulators must share the engine RNG and resolution path.
	attack_pipeline=CombatAttackPipeline.new(state,1,engine)
	controller.initialize_active_opponents()

func run() -> Dictionary:
	while not controller.combat_finished() and state.round_number<max_rounds:
		var step: Dictionary = run_round()
		if not bool(step.get("ok",false)):
			return {"outcome":"round_failed","reason":String(step.get("reason","unknown")),"winning_team":"","rounds":state.round_number,"dead_ids":_finalized_dead_ids()}
		if step.has("checkpoint_ok") and not bool(step["checkpoint_ok"]):
			# An in-memory round succeeded, but its persistence did not.
			# Never advertise a rewardable winner after a failed commit.
			return {"outcome":"checkpoint_write_failed","reason":String(step.get("checkpoint_reason","unknown")),"winning_team":"","rounds":state.round_number,"dead_ids":_finalized_dead_ids()}
	var winner:=controller.winning_team()
	return {"outcome":"timeout" if not controller.combat_finished() else ("draw" if winner.is_empty() else "winner:"+winner),"winning_team":winner,"rounds":state.round_number,"dead_ids":_finalized_dead_ids()}

func run_round() -> Dictionary:
	if controller.combat_finished():
		return {"ok":false,"reason":"combat_finished","battle_outcome":"winner:"+controller.winning_team()}
	round_in_progress = true
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
	last_completed_round = state.round_number
	round_in_progress = false
	var result: Dictionary = {"ok":true,"round":state.round_number,"summary":summary,"sync":sync,"battle_outcome":"winner:"+controller.winning_team() if controller.combat_finished() and not controller.winning_team().is_empty() else ("draw" if controller.combat_finished() else "ongoing")}
	if not checkpoint_path.is_empty():
		var stored: Dictionary = GroupCombatCheckpointService.save(self, checkpoint_path, checkpoint_encounter_key, checkpoint_roster_fingerprint)
		result["checkpoint_ok"] = bool(stored.get("ok",false))
		if not bool(stored.get("ok",false)):
			result["checkpoint_reason"] = String(stored.get("reason","checkpoint_failed"))
	return result

func _finalized_dead_ids()->Array[String]:
	var result:Array[String]=[]
	for raw_id in state.combatants.keys():
		var combatant:=state.get_combatant(String(raw_id))
		if combatant!=null and combatant.is_death_finalized():
			result.append(String(raw_id))
	result.sort()
	return result
