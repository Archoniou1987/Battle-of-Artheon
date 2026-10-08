class_name OpportunityActionResolver
extends RefCounted

## Optional extra-action policy for combatants acting outside their primary action.
## This is not an engagement restriction: every combatant still owns a normal primary action.
## Opportunity Base Attack and ABI rolls are independent and may both trigger.

const DEFAULT_BASE_ATTACK_CHANCE:=25.0
const DEFAULT_ABILITY_CHANCE:=20.0

var group:GroupCombatState
var base_attack_chance:float
var ability_chance:float
var zones:CombatZoneState

func _init(group_state:GroupCombatState,base_chance:float=DEFAULT_BASE_ATTACK_CHANCE,abi_chance:float=DEFAULT_ABILITY_CHANCE,zone_state:CombatZoneState=null)->void:
	group=group_state
	zones=zone_state
	base_attack_chance=clampf(base_chance,0.0,100.0)
	ability_chance=clampf(abi_chance,0.0,100.0)

func decide_against(target_id:String,actors:Array[String],rolls_by_actor:Dictionary)->Array[Dictionary]:
	var decisions:Array[Dictionary]=[]
	for actor_id in actors:
		if not group.living_enemies(target_id).has(actor_id):
			continue
		var actor:=group.combat_state.get_combatant(actor_id)
		if actor==null or not actor.is_alive():
			continue
		var rolls:Dictionary=rolls_by_actor.get(actor_id,{})
		var base_roll:=int(rolls.get("base_attack",100))
		var abi_roll:=int(rolls.get("ability",100))
		if CombatMath.roll_success(base_attack_chance,base_roll):
			decisions.append({"kind":"BASE_ATTACK","source_id":actor_id,"target_id":target_id,"roll":base_roll})
		if CombatMath.roll_success(ability_chance,abi_roll):
			decisions.append({"kind":"ABILITY","source_id":actor_id,"target_id":target_id,"roll":abi_roll})
	return decisions

func base_attack_event(decision:Dictionary,payload:Dictionary):
	var source_id:=String(decision.get("source_id",""))
	var target_id:=String(decision.get("target_id",""))
	var source:=group.combat_state.get_combatant(source_id)
	if source==null or source.is_death_finalized():
		return null
	var requested_weapon_index:=int(payload.get("weapon_index",-1))
	var requested_profile_id:=String(payload.get("attack_profile_id",""))
	var selected:Dictionary={}
	for profile in WeaponAttackProfile.all(source):
		if requested_weapon_index>=0 and int(profile.get("weapon_index",-1))!=requested_weapon_index:
			continue
		if not requested_profile_id.is_empty() and String(profile.get("id",""))!=requested_profile_id:
			continue
		if zones!=null and not CombatReachPolicy.valid_enemy_targets(source_id,zones,profile).has(target_id):
			continue
		if selected.is_empty():
			selected=profile
		elif requested_weapon_index<0 and requested_profile_id.is_empty():
			# Never guess between multiple canonical weapon profiles.
			return null
	if selected.is_empty():
		return null
	var rolls:Dictionary=Dictionary(payload.get("rolls",{})).duplicate(true)
	var damage_roll:=float(rolls.get("damage",randf()))
	rolls["damage"]=damage_roll
	var hit_count:=maxi(1,int(selected.get("hit_count",1)))
	var hit_index:=int(payload.get("hit_index",0))
	if hit_index<0 or hit_index>=hit_count:
		return null
	var per_hit:Array=rolls.get("hits",[])
	if hit_index<per_hit.size() and per_hit[hit_index] is Dictionary:
		var merged:=rolls.duplicate(true)
		merged.erase("hits")
		for key in Dictionary(per_hit[hit_index]).keys(): merged[key]=Dictionary(per_hit[hit_index])[key]
		rolls=merged
	var damage_min:=float(selected.get("damage_min",0.0))
	var damage_max:=float(selected.get("damage_max",damage_min))
	var data:Dictionary={
		"raw_damage":CombatMath.roll_damage(damage_min,damage_max,damage_roll),
		"damage_min":damage_min,"damage_max":damage_max,"damage_roll":damage_roll,
		"damage_type":String(selected.get("damage_type","slashing")),
		"zone":String(payload.get("zone","chest")),"rolls":rolls,
		"source":"opportunity_base_attack","source_kind":"weapon","opportunity_action":true,
		"is_weapon_attack":true,"is_extra_attack":true,"generates_ap":false,
		"weapon_index":int(selected.get("weapon_index",0)),
		"attack_profile_id":String(selected.get("id","basic")),
		"hit_index":hit_index,"hit_count":hit_count,
		"delivery_type":String(selected.get("delivery_type","MELEE")),
		"min_zone_distance":int(selected.get("min_zone_distance",0)),
		"max_zone_distance":int(selected.get("max_zone_distance",0)),
		"two_zone_hit_modifier":float(selected.get("two_zone_hit_modifier",-50.0)),
		"uses_magic_hit":bool(selected.get("uses_magic_hit",false)),
		"magic_hit_modifier":float(selected.get("magic_hit_modifier",0.0)),
		"magic_hit_roll":int(rolls.get("magic_hit",1)),
		"uses_physical_block":not bool(selected.get("uses_magic_hit",false)),
		"bypass_physical_mitigation":not String(selected.get("damage_type","slashing")).to_lower() in ["physical","slashing","piercing","chopping","blunt"]
	}
	return group.combat_state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,data)


func ability_event(decision:Dictionary,ability_id:String,definition:Dictionary,target_ids:Array[String]=[]):
	var source_id:=String(decision.get("source_id",""))
	var target_id:=String(decision.get("target_id",""))
	if zones!=null and not CombatReachPolicy.valid_enemy_targets(source_id,zones,definition).has(target_id):
		return null
	var event:=AbilityRuntime.build_action_event(group.combat_state,source_id,target_id,ability_id,definition)
	if not target_ids.is_empty():
		event.payload["target_ids"]=target_ids.duplicate()
	event.payload["opportunity_action"]=true
	return event


func choose_ability(ready_abilities:Array[Dictionary])->Dictionary:
	# Phase 10 baseline policy: caller supplies only currently valid/ready abilities.
	# Higher ai_priority wins; stable input order breaks ties.
	var chosen:Dictionary={}
	var best_priority:=-2147483648
	for ability in ready_abilities:
		if ability.is_empty():
			continue
		var priority:=int(ability.get("ai_priority",0))
		if chosen.is_empty() or priority>best_priority:
			chosen=ability
			best_priority=priority
	return chosen.duplicate(true)
