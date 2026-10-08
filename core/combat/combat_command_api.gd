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
	return WeaponAttackProfile.all(combatant)

func basic_attack_intent(source_id:String,attack_profile_id:String="basic",weapon_index:int=-1)->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	var target_id:=group.active_opponent(source_id)
	if target_id.is_empty():
		return {"ok":false,"reason":"no_active_opponent"}
	var matching_profiles:Array[Dictionary]=[]
	for profile in _weapon_attack_profiles(combatant):
		if String(profile.get("id",""))!=attack_profile_id:
			continue
		if weapon_index>=0 and int(profile.get("weapon_index",-1))!=weapon_index:
			continue
		matching_profiles.append(profile)
	if matching_profiles.is_empty():
		return {"ok":false,"reason":"attack_profile_unavailable"}
	if weapon_index<0 and matching_profiles.size()>1:
		return {"ok":false,"reason":"ambiguous_attack_profile","attack_profile_id":attack_profile_id}
	var profile:Dictionary=matching_profiles[0]
	if action_policy.valid_targets(source_id,profile).has(target_id):
		return {"ok":true,"reason":"ready","source_id":source_id,"target_id":target_id,"weapon_index":int(profile.get("weapon_index",-1)),"attack_profile":profile}
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
	var block_zone_count:=maxi(1,int(combatant.combat_stats.get("manual_block_zone_count",1)))
	if normalized.size()!=block_zone_count:
		return {"ok":false,"reason":"invalid_block_zone_count","required_zone_count":block_zone_count}
	var indices:Array[int]=[]
	for body_zone in normalized:
		indices.append(["head","chest","arms","waist","legs"].find(body_zone))
	indices.sort()
	for i in range(1,indices.size()):
		if indices[i]!=indices[i-1]+1:
			return {"ok":false,"reason":"non_contiguous_block_zones"}
	combatant.combat_stats["manual_block_zones"]=normalized
	return {"ok":true,"reason":"ok","zones":normalized,"zone_count":block_zone_count}

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


func cast_zone_ability(source_id:String,zone_id:int,ability_id:String)->Dictionary:
	if ability_scheduler==null or zones==null:
		return {"ok":false,"reason":"scheduler_unavailable"}
	var source:=state.get_combatant(source_id)
	if source==null or source.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	if zone_id<CombatZoneState.MIN_ZONE or zone_id>CombatZoneState.MAX_ZONE:
		return {"ok":false,"reason":"invalid_zone"}
	var definition:=AbilityCatalog.definition(ability_scheduler.definitions,ability_id)
	if definition.is_empty() or not AbilityCatalog.assigned_abilities(ability_scheduler.loadouts,source_id).has(ability_id):
		return {"ok":false,"reason":"ability_unavailable"}
	var source_zone:=zones.zone_of(source_id)
	var distance:=absi(zone_id-source_zone)
	var min_distance:=int(definition.get("min_zone_distance",0))
	var max_distance:=int(definition.get("max_zone_distance",2 if String(definition.get("delivery_type","DIRECT")).to_upper()!="MELEE" else 0))
	if not CombatReachPolicy.can_reach(distance,min_distance,max_distance):
		return {"ok":false,"reason":"target_out_of_reach"}
	var cooldowns:Dictionary=ability_scheduler.cooldowns_by_combatant.get(source_id,{})
	if not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return {"ok":false,"reason":"cooldown"}
	if source.mana<int(definition.get("mana_cost",0)):
		return {"ok":false,"reason":"insufficient_resource"}
	var event:=ability_scheduler.cast_zone_event(state,source_id,zone_id,ability_id)
	if event==null:
		return {"ok":false,"reason":"cast_rejected"}
	state.queue_event(event)
	return {"ok":true,"reason":"queued","event_id":event.event_id,"target_zone_id":zone_id}

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


func queue_basic_attack(source_id:String,rolls:Dictionary={},attack_profile_id:String="basic",weapon_index:int=-1)->Dictionary:
	var intent:=basic_attack_intent(source_id,attack_profile_id,weapon_index)
	if not bool(intent.get("ok",false)):
		return intent
	var target_id:=String(intent.get("target_id",""))
	var profile:Dictionary=intent.get("attack_profile",{})
	var damage_min:=float(profile.get("damage_min",0.0))
	var damage_max:=float(profile.get("damage_max",damage_min))
	var hit_count:=maxi(1,int(profile.get("hit_count",1)))
	var event_ids:Array[int]=[]
	for hit_index in range(hit_count):
		var event_rolls:=_basic_attack_hit_rolls(rolls,hit_index)
		var damage_roll:=float(event_rolls.get("damage",randf()))
		event_rolls["damage"]=damage_roll
		var raw_damage:=CombatMath.roll_damage(damage_min,damage_max,damage_roll)
		var event:=state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,{
			"raw_damage":raw_damage,
			"damage_min":damage_min,
			"damage_max":damage_max,
			"damage_roll":damage_roll,
			"zone":String(event_rolls.get("zone",profile.get("zone","chest"))),
			"damage_type":String(profile.get("damage_type","slashing")),
			"rolls":event_rolls,
			"weapon_index":int(profile.get("weapon_index",0)),
			"is_weapon_attack":true,
			"attack_profile_id":attack_profile_id,
			"hit_index":hit_index,
			"hit_count":hit_count,
			"delivery_type":String(profile.get("delivery_type","MELEE")),
			"min_zone_distance":int(profile.get("min_zone_distance",0)),
			"max_zone_distance":int(profile.get("max_zone_distance",0)),
			"two_zone_hit_modifier":float(profile.get("two_zone_hit_modifier",-50.0)),
			"uses_magic_hit":bool(profile.get("uses_magic_hit",false)),
			"magic_hit_modifier":float(profile.get("magic_hit_modifier",0.0)),
			"magic_hit_roll":int(event_rolls.get("magic_hit",1)),
			"uses_physical_block":not bool(profile.get("uses_magic_hit",false)),
			"bypass_physical_mitigation":not String(profile.get("damage_type","slashing")).to_lower() in ["physical","slashing","piercing","chopping","blunt"],
			# AP belongs to the Base Attack action, not to every hit of a multi-hit profile.
			"generates_ap":hit_index==0
		})
		state.queue_event(event)
		event_ids.append(event.event_id)
	return {"ok":true,"reason":"queued","event_id":event_ids[0],"event_ids":event_ids,"hit_count":hit_count,"target_id":target_id,"weapon_index":int(profile.get("weapon_index",-1)),"attack_profile_id":attack_profile_id}


func queue_weapon_attack_sequence(source_id:String,attacks:Array[Dictionary])->Dictionary:
	if attacks.is_empty():
		return {"ok":false,"reason":"empty_attack_sequence"}
	# Validate the whole sequence before queueing anything. A rejected OH/profile
	# must never leave an already queued MH attack behind.
	for attack_index in range(attacks.size()):
		var request:Dictionary=attacks[attack_index]
		var intent:=basic_attack_intent(source_id,String(request.get("attack_profile_id","basic")),int(request.get("weapon_index",-1)))
		if not bool(intent.get("ok",false)):
			return {"ok":false,"reason":"sequence_attack_rejected","attack_index":attack_index,"attack_reason":String(intent.get("reason","")),"queued_event_ids":[]}
	var sequence_event_ids:Array[int]=[]
	var attack_results:Array[Dictionary]=[]
	for request in attacks:
		var profile_id:=String(request.get("attack_profile_id","basic"))
		var weapon_index:=int(request.get("weapon_index",-1))
		var attack_rolls:Dictionary=Dictionary(request.get("rolls",{})).duplicate(true)
		if request.has("zone"):
			attack_rolls["zone"]=String(request.get("zone","chest"))
		var result:=queue_basic_attack(source_id,attack_rolls,profile_id,weapon_index)
		attack_results.append(result)
		for event_id in Array(result.get("event_ids",[])):
			sequence_event_ids.append(int(event_id))
	return {"ok":true,"reason":"queued","event_ids":sequence_event_ids,"attack_count":attacks.size(),"attacks":attack_results}


func _basic_attack_hit_rolls(rolls:Dictionary,hit_index:int)->Dictionary:
	var per_hit:Array=rolls.get("hits",[])
	if hit_index<per_hit.size() and per_hit[hit_index] is Dictionary:
		var merged:=rolls.duplicate(true)
		merged.erase("hits")
		for raw_key in Dictionary(per_hit[hit_index]).keys():
			merged[raw_key]=Dictionary(per_hit[hit_index])[raw_key]
		return merged
	var shared:=rolls.duplicate(true)
	shared.erase("hits")
	return shared
