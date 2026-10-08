class_name CombatCommandApi
extends RefCounted

var state:CombatState
var group:GroupCombatState
var zones:CombatZoneState
var orchestrator:RoundOrchestrator
var action_policy:GroupActionPolicy

func _init(combat_state:CombatState,group_state:GroupCombatState,zone_state:CombatZoneState,round_orchestrator:RoundOrchestrator)->void:
	state=combat_state
	group=group_state
	zones=zone_state
	orchestrator=round_orchestrator
	action_policy=GroupActionPolicy.new(group_state,zone_state)

func select_active_opponent(source_id:String,target_id:String,definition:Dictionary={})->Dictionary:
	if not action_policy.valid_targets(source_id,definition).has(target_id):
		return {"ok":false,"reason":"invalid_target"}
	if not group.set_active_opponent(source_id,target_id):
		return {"ok":false,"reason":"invalid_target"}
	return {"ok":true,"reason":"ok","target_id":target_id}

func request_navigation(source_id:String,to_zone:int,tempo_roll:int=1)->Dictionary:
	if orchestrator==null or zones==null:
		return {"ok":false,"reason":"spatial_context_unavailable"}
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	if not orchestrator.queue_movement_request(source_id,to_zone,tempo_roll,false,"navigation"):
		return {"ok":false,"reason":"movement_rejected"}
	return {"ok":true,"reason":"queued","from_zone":zones.zone_of(source_id),"to_zone":to_zone}

func basic_attack_intent(source_id:String)->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	var target_id:=group.active_opponent(source_id)
	if target_id.is_empty():
		return {"ok":false,"reason":"no_active_opponent"}
	if not action_policy.valid_targets(source_id,{"min_zone_distance":0,"max_zone_distance":0}).has(target_id):
		return {"ok":false,"reason":"target_out_of_reach"}
	return {"ok":true,"reason":"ready","source_id":source_id,"target_id":target_id}

func ability_intent(source_id:String,target_id:String,definition:Dictionary)->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	if not action_policy.valid_targets(source_id,definition).has(target_id):
		return {"ok":false,"reason":"target_out_of_reach"}
	return {"ok":true,"reason":"ready","source_id":source_id,"target_id":target_id}
