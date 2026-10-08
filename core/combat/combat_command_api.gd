class_name CombatCommandApi
extends RefCounted

var state:CombatState
var group:GroupCombatState
var zones:CombatZoneState
var orchestrator:RoundOrchestrator
var action_policy:GroupActionPolicy
var ability_scheduler:AbilityScheduler

func _init(combat_state:CombatState,group_state:GroupCombatState,zone_state:CombatZoneState,round_orchestrator:RoundOrchestrator,scheduler:AbilityScheduler=null)->void:
	state=combat_state
	group=group_state
	zones=zone_state
	orchestrator=round_orchestrator
	action_policy=GroupActionPolicy.new(group_state,zone_state)
	ability_scheduler=scheduler

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


func set_manual_block(source_id:String,body_zones:Array[String])->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	if not combatant.can_manual_block():
		return {"ok":false,"reason":"manual_block_unavailable"}
	var normalized:Array[String]=[]
	for raw_zone in body_zones:
		var body_zone:=String(raw_zone)
		if body_zone in ["head","chest","arms","waist","legs"] and not normalized.has(body_zone):
			normalized.append(body_zone)
	if normalized.is_empty():
		return {"ok":false,"reason":"invalid_block_zone"}
	combatant.combat_stats["manual_block_zones"]=normalized
	return {"ok":true,"reason":"ok","zones":normalized}

func clear_manual_block(source_id:String)->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null:
		return {"ok":false,"reason":"invalid_combatant"}
	combatant.combat_stats.erase("manual_block_zones")
	combatant.combat_stats.erase("manual_block_zone")
	return {"ok":true,"reason":"ok"}

func available_actions(source_id:String,ability_definitions:Dictionary={})->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant","basic_attack":false,"manual_block":false,"navigation":[],"abilities":{}}
	var navigation:Array[int]=[]
	if zones!=null and orchestrator!=null:
		var current:=zones.zone_of(source_id)
		for candidate in [current-1,current+1]:
			if candidate>=CombatZoneState.MIN_ZONE and candidate<=CombatZoneState.MAX_ZONE and zones.ordinary_navigation_allowed(source_id,candidate):
				navigation.append(candidate)
	var abilities:Dictionary={}
	for raw_id in ability_definitions.keys():
		var ability_id:=String(raw_id)
		var definition:Dictionary=ability_definitions[raw_id]
		var targets:=action_policy.valid_targets(source_id,definition)
		var cooldown_ready:=true
		if ability_scheduler!=null:
			var cooldowns:Dictionary=ability_scheduler.cooldowns_by_combatant.get(source_id,{})
			cooldown_ready=AbilityRuntime.can_use(ability_id,cooldowns,state.round_number)
		var mana_cost:=int(definition.get("mana_cost",0))
		var resource_ready:=combatant.mana>=mana_cost
		abilities[ability_id]={
			"available":cooldown_ready and resource_ready and not targets.is_empty(),
			"targets":targets,
			"cooldown_ready":cooldown_ready,
			"resource_ready":resource_ready,
			"mana_cost":mana_cost
		}
	return {
		"ok":true,
		"reason":"ok",
		"active_opponent_id":group.active_opponent(source_id),
		"basic_attack":bool(basic_attack_intent(source_id).get("ok",false)),
		"manual_block":combatant.can_manual_block(),
		"navigation":navigation,
		"abilities":abilities
	}
