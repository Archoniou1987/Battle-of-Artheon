class_name CombatCommandApi
extends RefCounted

const BODY_ZONES:Array[String]=["head","chest","arms","waist","legs"]

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
	var block_zone_count:=CombatModifierService.manual_block_zone_capacity(combatant)
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
	var basic_attacks:=_available_basic_attacks(source_id)
	var default_sequence:=default_weapon_attack_sequence(source_id)
	return {
		"ok":true,
		"reason":"ok",
		"active_opponent_id":group.active_opponent(source_id),
		"basic_attack":not basic_attacks.is_empty(),
		"basic_attacks":basic_attacks,
		"default_weapon_attack_sequence":Array(default_sequence.get("attacks",[])) if bool(default_sequence.get("ok",false)) else [],
		"body_zones":BODY_ZONES.duplicate(),
		"default_body_zone":"chest",
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
	var zone_validation:=_validate_attack_roll_zones(rolls)
	if not bool(zone_validation.get("ok",false)):
		return zone_validation
	var requested_zone:=String(rolls.get("zone","chest"))
	var intent:=basic_attack_intent(source_id,attack_profile_id,weapon_index)
	if not bool(intent.get("ok",false)):
		return intent
	var target_id:=String(intent.get("target_id",""))
	var profile:Dictionary=intent.get("attack_profile",{})
	var hit_count:=maxi(1,int(profile.get("hit_count",1)))
	var event_ids:Array[int]=[]
	# Every constituent hit of one Base Attack shares an AP group. AP is awarded
	# by the engine to the first connected hit in that group, never more than once.
	var ap_group_id:=int(rolls.get("ap_group_id",state.next_event_id))
	for hit_index in range(hit_count):
		var event_rolls:=_basic_attack_hit_rolls(rolls,hit_index)
		var damage_roll:=float(event_rolls.get("damage",randf()))
		event_rolls["damage"]=damage_roll
		var payload:=WeaponAttackProfile.attack_payload(profile,event_rolls,String(event_rolls.get("zone",requested_zone)),{
			# AP belongs to the whole Base Attack action. Any connected constituent
			# may earn it; the engine deduplicates by ap_group_id.
			"generates_ap":not bool(event_rolls.get("suppress_ap",false)),
			"ap_group_id":ap_group_id,
			"hit_index":hit_index,
			"hit_count":hit_count
		})
		var event:=state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,payload)
		state.queue_event(event)
		event_ids.append(event.event_id)
	return {"ok":true,"reason":"queued","event_id":event_ids[0],"event_ids":event_ids,"hit_count":hit_count,"target_id":target_id,"weapon_index":int(profile.get("weapon_index",-1)),"attack_profile_id":attack_profile_id}


func default_weapon_attack_sequence(source_id:String,rolls_by_weapon:Dictionary={})->Dictionary:
	var combatant:=state.get_combatant(source_id)
	if combatant==null or combatant.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	var target_id:=group.active_opponent(source_id)
	if target_id.is_empty():
		return {"ok":false,"reason":"no_active_opponent"}
	var by_weapon:Dictionary={}
	for profile in _weapon_attack_profiles(combatant):
		var weapon_index:=int(profile.get("weapon_index",-1))
		if not by_weapon.has(weapon_index):
			by_weapon[weapon_index]=[]
		by_weapon[weapon_index].append(profile)
	var attacks:Array[Dictionary]=[]
	var weapon_indices:Array=by_weapon.keys()
	weapon_indices.sort()
	# Canonical PAR057 limits the ordinary MH/OH ABI001 sequence.
	# Legacy and NPC combatants without a PAR snapshot retain their existing profiles.
	if combatant.combat_stats.has("par_attack_count"):
		var allowed_attacks:=clampi(int(combatant.combat_stats.get("par_attack_count", 1)), 1, 2)
		while weapon_indices.size()>allowed_attacks:
			weapon_indices.pop_back()
	for raw_weapon_index in weapon_indices:
		var weapon_index:=int(raw_weapon_index)
		var profiles:Array=by_weapon[weapon_index]
		var selected:Dictionary={}
		if profiles.size()==1:
			selected=Dictionary(profiles[0])
		else:
			for raw_profile in profiles:
				var candidate:Dictionary=raw_profile
				if bool(candidate.get("is_default",false)):
					if not selected.is_empty():
						return {"ok":false,"reason":"multiple_default_attack_profiles","weapon_index":weapon_index}
					selected=candidate
			if selected.is_empty():
				continue
		var requirement:=String(selected.get("requires_off_hand_type",""))
		if not requirement.is_empty() and not CombatModifierService.equipped_item_types(combatant).has(requirement):
			continue
		if not action_policy.valid_targets(source_id,selected).has(target_id):
			continue
		var request:Dictionary={"weapon_index":weapon_index,"attack_profile_id":String(selected.get("id","basic"))}
		if rolls_by_weapon.has(weapon_index):
			request["rolls"]=Dictionary(rolls_by_weapon[weapon_index]).duplicate(true)
		elif rolls_by_weapon.has(String.num_int64(weapon_index)):
			request["rolls"]=Dictionary(rolls_by_weapon[String.num_int64(weapon_index)]).duplicate(true)
		attacks.append(request)
	if attacks.is_empty():
		return {"ok":false,"reason":"no_default_weapon_attacks"}
	return {"ok":true,"reason":"ready","attacks":attacks}


func queue_default_weapon_attacks(source_id:String,rolls_by_weapon:Dictionary={})->Dictionary:
	var sequence:=default_weapon_attack_sequence(source_id,rolls_by_weapon)
	if not bool(sequence.get("ok",false)):
		return sequence
	return queue_weapon_attack_sequence(source_id,Array(sequence.get("attacks",[])))


func queue_weapon_attack_sequence(source_id:String,attacks:Array[Dictionary])->Dictionary:
	if attacks.is_empty():
		return {"ok":false,"reason":"empty_attack_sequence"}
	var source:=state.get_combatant(source_id)
	if source==null or source.is_death_finalized():
		return {"ok":false,"reason":"invalid_combatant"}
	if source.combat_stats.has("par_attack_count"):
		var allowed:=clampi(int(source.combat_stats.get("par_attack_count",1)),1,2)
		if attacks.size()>allowed:
			return {"ok":false,"reason":"par057_attack_limit","allowed_attacks":allowed}
		var seen_weapons:Dictionary={}
		for request in attacks:
			var index:=int(request.get("weapon_index",-1))
			if index<0 or index>=allowed or seen_weapons.has(index):
				return {"ok":false,"reason":"invalid_par057_attack_sequence"}
			seen_weapons[index]=true
	# Validate the whole sequence before queueing anything. A rejected OH/profile
	# must never leave an already queued MH attack behind.
	for attack_index in range(attacks.size()):
		var request:Dictionary=attacks[attack_index]
		var request_rolls:Dictionary=Dictionary(request.get("rolls",{})).duplicate(true)
		if request.has("zone"):
			request_rolls["zone"]=String(request.get("zone","chest"))
		var zone_validation:=_validate_attack_roll_zones(request_rolls)
		if not bool(zone_validation.get("ok",false)):
			return {"ok":false,"reason":"sequence_attack_rejected","attack_index":attack_index,"attack_reason":"invalid_body_zone","body_zone":String(zone_validation.get("body_zone","")),"hit_index":int(zone_validation.get("hit_index",-1)),"queued_event_ids":[]}
		var intent:=basic_attack_intent(source_id,String(request.get("attack_profile_id","basic")),int(request.get("weapon_index",-1)))
		if not bool(intent.get("ok",false)):
			return {"ok":false,"reason":"sequence_attack_rejected","attack_index":attack_index,"attack_reason":String(intent.get("reason","")),"queued_event_ids":[]}
	var sequence_event_ids:Array[int]=[]
	var attack_results:Array[Dictionary]=[]
	var ap_group_id:=state.next_event_id
	for attack_index in range(attacks.size()):
		var request:Dictionary=attacks[attack_index]
		var profile_id:=String(request.get("attack_profile_id","basic"))
		var weapon_index:=int(request.get("weapon_index",-1))
		var attack_rolls:Dictionary=Dictionary(request.get("rolls",{})).duplicate(true)
		if request.has("zone"):
			attack_rolls["zone"]=String(request.get("zone","chest"))
		# All MH/OH and multi-hit constituents belong to one Base Attack AP group.
		attack_rolls["ap_group_id"]=ap_group_id
		var result:=queue_basic_attack(source_id,attack_rolls,profile_id,weapon_index)
		attack_results.append(result)
		for event_id in Array(result.get("event_ids",[])):
			sequence_event_ids.append(int(event_id))
	return {"ok":true,"reason":"queued","event_ids":sequence_event_ids,"attack_count":attacks.size(),"attacks":attack_results}


func _validate_attack_roll_zones(rolls:Dictionary)->Dictionary:
	var shared_zone:=String(rolls.get("zone","chest"))
	if not BODY_ZONES.has(shared_zone):
		return {"ok":false,"reason":"invalid_body_zone","body_zone":shared_zone,"hit_index":-1,"allowed_body_zones":BODY_ZONES.duplicate()}
	var per_hit:Array=rolls.get("hits",[])
	for hit_index in range(per_hit.size()):
		if not per_hit[hit_index] is Dictionary:
			continue
		var hit_zone:=String(Dictionary(per_hit[hit_index]).get("zone",shared_zone))
		if not BODY_ZONES.has(hit_zone):
			return {"ok":false,"reason":"invalid_body_zone","body_zone":hit_zone,"hit_index":hit_index,"allowed_body_zones":BODY_ZONES.duplicate()}
	return {"ok":true,"reason":"ok"}

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
