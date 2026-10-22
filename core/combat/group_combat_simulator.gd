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

## Validate the WHOLE player's submission before begin_round(), RNG
## consumption or any checkpoint mutation. Auto callers use empty orders
## and retain their previous simulator behavior.
func player_controls(player_id: String) -> Dictionary:
	var player := state.get_combatant(player_id)
	if player == null or group.team_of(player_id) != "players" or player.is_death_finalized():
		return {"ok":false,"reason":"player_controls_unavailable"}
	var capacity := CombatModifierService.manual_block_zone_capacity(player)
	if capacity < 1 or capacity > 4 or not player.can_manual_block():
		capacity = 0
	var next_round := state.round_number + 1
	var options: Array[Dictionary] = []
	var scheduler: AbilityScheduler = attack_pipeline.ability_scheduler
	var equipped: Array = AbilityCatalog.assigned_abilities(scheduler.loadouts,player_id)
	var cd: Dictionary = scheduler.cooldowns_by_combatant.get(player_id,{})
	var policy := GroupActionPolicy.new(group)
	for raw_id in equipped:
		var ability_id := String(raw_id)
		var definition := AbilityCatalog.definition(scheduler.definitions,ability_id)
		if definition.is_empty():
			continue
		var is_ally := String(definition.get("target_team","ENEMY")).to_upper() == "ALLY"
		var target_id := player_id if is_ally else controller.ensure_active_opponent(player_id)
		var ready := not CombatTempoService.is_stunned(player,next_round) and player.hp > 0
		ready = ready and scheduler.can_cast_this_round(player_id,next_round)
		ready = ready and AbilityRuntime.can_use(ability_id,cd,next_round)
		ready = ready and player.mana >= int(definition.get("mana_cost",0))
		ready = ready and AbilityRuntime.validate_definition(ability_id,definition).is_empty()
		ready = ready and policy.valid_ability_targets(player_id,definition).has(target_id)
		options.append({
			"id":ability_id,"name":String(definition.get("name",ability_id)),
			"available":ready,"target_id":target_id,
			"target_label":"Себя" if is_ally else "Противник",
			"mana_cost":int(definition.get("mana_cost",0)),
			"cooldown_until":int(cd.get(ability_id,0))
		})
	return {
		"ok":true,
		"attack_count":attack_pipeline.basic_hit_count(player),
		"block_capacity":capacity,
		"stunned":CombatTempoService.is_stunned(player,next_round),
		"zones":CombatCommandApi.BODY_ZONES.duplicate(),
		"target_id":group.active_opponent(player_id),
		"abilities":options
	}

func _validate_player_orders(orders: Dictionary) -> Dictionary:
	var player_id := String(orders.get("player_id",""))
	var controls := player_controls(player_id)
	if not bool(controls.get("ok",false)) or controller.combat_finished():
		return {"ok":false,"reason":"invalid_player_orders_owner"}
	var attack_value: Variant = orders.get("attack_zones",null)
	var block_value: Variant = orders.get("block_zones",null)
	if not attack_value is Array or not block_value is Array:
		return {"ok":false,"reason":"invalid_player_order_format"}
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	for raw in attack_value:
		if not raw is String or not CombatCommandApi.BODY_ZONES.has(raw):
			return {"ok":false,"reason":"invalid_attack_zone"}
		attacks.append(String(raw))
	for raw in block_value:
		if not raw is String or not CombatCommandApi.BODY_ZONES.has(raw) or blocks.has(String(raw)):
			return {"ok":false,"reason":"invalid_block_zone"}
		blocks.append(String(raw))
	if bool(controls["stunned"]):
		if not attacks.is_empty() or not blocks.is_empty():
			return {"ok":false,"reason":"stunned_cannot_queue_physical_actions"}
	else:
		if attacks.size() != int(controls["attack_count"]):
			return {"ok":false,"reason":"invalid_attack_zone_count","expected":int(controls["attack_count"])}
		if blocks.size() != int(controls["block_capacity"]):
			return {"ok":false,"reason":"invalid_block_zone_count","expected":int(controls["block_capacity"])}
	var ability_value: Variant = orders.get("ability_id","")
	if not ability_value is String:
		return {"ok":false,"reason":"invalid_player_ability_format"}
	var ability_id := String(ability_value)
	var ability_target := ""
	if not ability_id.is_empty():
		if bool(controls["stunned"]):
			return {"ok":false,"reason":"stunned_cannot_cast"}
		var available := false
		for raw_option in Array(controls.get("abilities",[])):
			var option: Dictionary = raw_option
			if String(option.get("id","")) != ability_id:
				continue
			if not bool(option.get("available",false)):
				return {"ok":false,"reason":"player_ability_unavailable"}
			available = true
			ability_target = String(option.get("target_id",""))
			break
		if not available:
			return {"ok":false,"reason":"player_ability_not_equipped"}
	return {
		"ok":true,"player_id":player_id,
		"attack_zones":attacks,"block_zones":blocks,
		"stunned":bool(controls["stunned"]),
		"ability_id":ability_id,"ability_target":ability_target
	}

func run_round(player_orders: Dictionary = {}) -> Dictionary:
	if controller.combat_finished():
		return {"ok":false,"reason":"combat_finished","battle_outcome":"winner:"+controller.winning_team()}
	var selected: Dictionary = {}
	if not player_orders.is_empty():
		selected = _validate_player_orders(player_orders)
		if not bool(selected.get("ok",false)):
			return selected
		# The existing CombatCommandApi is the only authority for manually
		# defended zones, including the equipped PAR073 capacity.
		var commands := CombatCommandApi.new(state,group,null,orchestrator,attack_pipeline.ability_scheduler)
		var owner_id := String(selected["player_id"])
		var manual_result: Dictionary
		if bool(selected["stunned"]) or Array(selected["block_zones"]).is_empty():
			manual_result = commands.clear_manual_block(owner_id)
		else:
			var selected_blocks: Array[String] = selected["block_zones"]
			manual_result = commands.set_manual_block(owner_id,selected_blocks)
		if not bool(manual_result.get("ok",false)):
			return {"ok":false,"reason":"manual_block_rejected","detail":String(manual_result.get("reason","unknown"))}
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
		if not selected.is_empty() and actor_id == String(selected["player_id"]):
			var chosen_zones: Array[String] = selected["attack_zones"]
			attack_pipeline.lock_basic_attack(round,actor,target,chosen_zones)
		else:
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
		if not selected.is_empty() and actor_id == String(selected["player_id"]):
			# Explicit "no ABI" is a real player choice. Never fall back
			# to the automatic spell picker for a manually controlled hero.
			var ability_id := String(selected.get("ability_id",""))
			if not ability_id.is_empty():
				var commands := CombatCommandApi.new(state,group,null,orchestrator,attack_pipeline.ability_scheduler)
				var cast := commands.cast_ability(actor_id,String(selected["ability_target"]),ability_id)
				if not bool(cast.get("ok",false)):
					# Preflight must prevent this branch. Mark the round as
					# failed; do not accept an incomplete action set.
					return {"ok":false,"reason":"prevalidated_ability_cast_failed","detail":String(cast.get("reason","unknown"))}
				for ability_event in state.pending_events:
					round.lock_action(ability_event)
				state.pending_events.clear()
		else:
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
