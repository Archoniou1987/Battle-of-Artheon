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

func _weapon_attack_profiles(combatant:CombatantState)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var weapons:Array=combatant.combat_stats.get("weapon_profiles",[])
	for weapon_index in range(weapons.size()):
		var weapon:Dictionary=weapons[weapon_index]
		var configured:Array=weapon.get("attack_profiles",[])
		if configured.is_empty():
			configured=[{
				"id":"basic",
				"delivery_type":"MELEE",
				"min_zone_distance":0,
				"max_zone_distance":0,
				"damage_min":float(weapon.get("damage_min",0.0)),
				"damage_max":float(weapon.get("damage_max",0.0)),
				"damage_type":String(weapon.get("damage_type","slashing"))
			}]
		for raw_profile in configured:
			if not raw_profile is Dictionary:
				continue
			var profile:Dictionary=raw_profile.duplicate(true)
			profile["id"]=String(profile.get("id","basic"))
			profile["weapon_index"]=weapon_index
			profile["delivery_type"]=String(profile.get("delivery_type","MELEE")).to_upper()
			profile["min_zone_distance"]=int(profile.get("min_zone_distance",0))
			profile["max_zone_distance"]=int(profile.get("max_zone_distance",0 if profile["delivery_type"]=="MELEE" else 2))
			profile["two_zone_hit_modifier"]=float(profile.get("two_zone_hit_modifier",-50.0))
			profile["damage_min"]=float(profile.get("damage_min",weapon.get("damage_min",0.0)))
			profile["damage_max"]=float(profile.get("damage_max",weapon.get("damage_max",profile["damage_min"])))
			profile["damage_type"]=String(profile.get("damage_type",weapon.get("damage_type","slashing")))
			result.append(profile)
	if result.is_empty():
		result.append({
			"id":"basic","weapon_index":0,"delivery_type":"MELEE",
			"min_zone_distance":0,"max_zone_distance":0,"two_zone_hit_modifier":-50.0,
			"damage_min":float(combatant.combat_stats.get("main_hand_damage",0.0)),
			"damage_max":float(combatant.combat_stats.get("main_hand_damage",0.0)),
			"damage_type":String(combatant.combat_stats.get("main_hand_damage_type","slashing"))
		})
	return result

func basic_attack_intent(source_id:String,attack_profile_id:String="basic")->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	var target_id:=group.active_opponent(source_id)
	if target_id.is_empty():
		return {"ok":false,"reason":"no_active_opponent"}
	for profile in _weapon_attack_profiles(combatant):
		if String(profile.get("id",""))!=attack_profile_id:
			continue
		if action_policy.valid_targets(source_id,profile).has(target_id):
			return {"ok":true,"reason":"ready","source_id":source_id,"target_id":target_id,"attack_profile":profile}
	return {"ok":false,"reason":"target_out_of_reach"}

func _available_basic_attacks(source_id:String)->Array[Dictionary]:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return []
	var target_id:=group.active_opponent(source_id)
	if target_id.is_empty():
		return []
	var result:Array[Dictionary]=[]
	for profile in _weapon_attack_profiles(combatant):
		if action_policy.valid_targets(source_id,profile).has(target_id):
			result.append(profile.duplicate(true))
	return result

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
		"basic_attack":not _available_basic_attacks(source_id).is_empty(),
		"basic_attacks":_available_basic_attacks(source_id),
		"manual_block":combatant.can_manual_block(),
		"navigation":navigation,
		"abilities":abilities
	}

func cast_ability(source_id:String,target_id:String,ability_id:String)->Dictionary:
	if ability_scheduler==null:
		return {"ok":false,"reason":"scheduler_unavailable"}
	var definition:=AbilityCatalog.definition(ability_scheduler.definitions,ability_id)
	if definition.is_empty():
		return {"ok":false,"reason":"ability_unavailable"}
	if not AbilityCatalog.assigned_abilities(ability_scheduler.loadouts,source_id).has(ability_id):
		return {"ok":false,"reason":"ability_unavailable"}
	var intent:=ability_intent(source_id,target_id,definition)
	if not bool(intent.get("ok",false)):
		return intent
	var cooldowns:Dictionary=ability_scheduler.cooldowns_by_combatant.get(source_id,{})
	if not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return {"ok":false,"reason":"cooldown"}
	var source:=state.get_combatant(source_id)
	var mana_cost:=int(definition.get("mana_cost",0))
	if source==null or source.mana<mana_cost:
		return {"ok":false,"reason":"insufficient_resource"}
	var event:=ability_scheduler.cast_event(state,source_id,target_id,ability_id)
	if event==null:
		return {"ok":false,"reason":"cast_rejected"}
	state.queue_event(event)
	return {"ok":true,"reason":"queued","event_id":event.event_id}


func queue_basic_attack(source_id:String,rolls:Dictionary={},attack_profile_id:String="basic")->Dictionary:
	var intent:=basic_attack_intent(source_id,attack_profile_id)
	if not bool(intent.get("ok",false)):
		return intent
	var target_id:=String(intent.get("target_id",""))
	var profile:Dictionary=intent.get("attack_profile",{})
	var damage_min:=float(profile.get("damage_min",0.0))
	var damage_max:=float(profile.get("damage_max",damage_min))
	var raw_damage:=(damage_min+damage_max)/2.0
	var event:=state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,{
		"raw_damage":raw_damage,
		"zone":"chest",
		"damage_type":String(profile.get("damage_type","slashing")),
		"rolls":rolls.duplicate(true),
		"weapon_index":int(profile.get("weapon_index",0)),
		"delivery_type":String(profile.get("delivery_type","MELEE")),
		"min_zone_distance":int(profile.get("min_zone_distance",0)),
		"max_zone_distance":int(profile.get("max_zone_distance",0)),
		"two_zone_hit_modifier":float(profile.get("two_zone_hit_modifier",-50.0)),
		"generates_ap":true
	})
	state.queue_event(event)
	return {"ok":true,"reason":"queued","event_id":event.event_id,"target_id":target_id,"attack_profile_id":attack_profile_id}
