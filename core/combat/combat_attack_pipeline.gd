class_name CombatAttackPipeline
extends RefCounted

const HIT_ZONES := ["head", "chest", "arms", "waist", "legs"]
var state:CombatState
var ability_scheduler:AbilityScheduler
var rng:=RandomNumberGenerator.new()
var combat_engine: CombatEngine

func _init(combat_state:CombatState,seed_value:int=1,p_engine:CombatEngine=null)->void:
	state=combat_state
	combat_engine=p_engine
	rng.seed=seed_value
	if combat_engine!=null:
		combat_engine.combat_rng.seed=seed_value
		rng=combat_engine.combat_rng
	ability_scheduler=AbilityScheduler.new(AbilityCatalog.load_json("res://data/test/abilities.json"),AbilityCatalog.load_json("res://data/test/ability_loadouts.json"))

## Add the chosen automatic ABI to the same sealed round plan as weapon strikes.
func lock_ready_abilities(round:CombatRound,source:CombatantState,target:CombatantState)->void:
	for event in ability_scheduler.ready_events(state,source.combatant_id,target.combatant_id):
		round.lock_action(event)

func queue_ready_abilities(source:CombatantState,target:CombatantState)->void:
	for event in ability_scheduler.ready_events(state,source.combatant_id,target.combatant_id): state.queue_event(event)
## Player orders may supply one body zone per canonical weapon constituent.
## Empty zones retain historical NPC/autoplay random targeting.
func basic_hit_count(attacker: CombatantState) -> int:
	if attacker == null or attacker.is_death_finalized():
		return 0
	var weapon_indices: Array[int] = []
	for profile in WeaponAttackProfile.all(attacker):
		var index := int(profile.get("weapon_index",-1))
		if not weapon_indices.has(index):
			weapon_indices.append(index)
	var count := 0
	for index in weapon_indices:
		if _weapon_attack_available(attacker,index):
			count += maxi(1,int(_weapon_profile(attacker,index).get("hit_count",1)))
	return count

func lock_basic_attack(round:CombatRound,attacker:CombatantState,defender:CombatantState,body_zones:Array[String]=[])->void:
	if attacker==null or defender==null or attacker.is_death_finalized() or defender.is_death_finalized() or CombatTempoService.is_stunned(attacker, state.round_number): return
	var weapon_indices:Array=[]
	var canonical_profiles:=WeaponAttackProfile.all(attacker)
	if canonical_profiles.is_empty():
		return
	# Canonical multi-weapon profiles may expose several weapon indices, but
	# each base attack action still groups all weapon constituents together.
	for profile in canonical_profiles:
		var weapon_index:=int(profile.get("weapon_index",-1))
		if not weapon_indices.has(weapon_index):
			weapon_indices.append(weapon_index)
	weapon_indices.sort()
	# One normal Base Attack (all MH/OH and multi-hit constituents) shares one AP group.
	# Base attacks are determined by weapons; Tempo grants no additional hits.
	var ap_group_id:=state.next_event_id
	var zone_offset := 0
	for raw_weapon_index in weapon_indices:
		var weapon_index:=int(raw_weapon_index)
		if _weapon_attack_available(attacker,weapon_index):
			var events := _make_basic_attacks(attacker,defender,false,weapon_index,ap_group_id,body_zones,zone_offset)
			zone_offset += events.size()
			for event in events:
				round.lock_action(event)
func _weapon_attack_available(attacker:CombatantState,weapon_index:int)->bool:
	var profile:=_weapon_profile(attacker,weapon_index)
	if profile.is_empty():
		return false
	var requirement:=String(profile.get("requires_off_hand_type",""))
	if requirement.is_empty(): return true
	var equipped_types:Array=CombatModifierService.equipped_item_types(attacker)
	return equipped_types.has(requirement)

func _make_basic_attacks(attacker:CombatantState,defender:CombatantState,extra:bool,weapon_index:int,ap_group_id:int=-1,body_zones:Array[String]=[],zone_offset:int=0)->Array[CombatEvent]:
	var profile:=_weapon_profile(attacker,weapon_index)
	var result:Array[CombatEvent]=[]
	var hit_count:=maxi(1,int(profile.get("hit_count",1)))
	for hit_index in range(hit_count):
		var rolls:=_attack_rolls()
		var damage_roll:=float(rolls["damage"]) if rolls.has("damage") else rng.randf()
		rolls["damage"]=damage_roll
		var selected_zone := body_zones[zone_offset + hit_index] if zone_offset + hit_index < body_zones.size() else HIT_ZONES[rng.randi_range(0,HIT_ZONES.size()-1)]
		var payload:=WeaponAttackProfile.attack_payload(profile,rolls,selected_zone,{
			"is_extra_attack":extra,
			"generates_ap":not extra,
			"ap_group_id":ap_group_id if ap_group_id>=0 else state.next_event_id,
			"weapon_index":weapon_index,
			"hit_index":hit_index
		})
		result.append(state.create_event(CombatEvent.Kind.ATTACK,attacker.combatant_id,defender.combatant_id,payload))
	return result

func _weapon_profile(attacker:CombatantState,weapon_index:int)->Dictionary:
	var matches:Array[Dictionary]=[]
	for profile in WeaponAttackProfile.all(attacker):
		if int(profile.get("weapon_index",-1))==weapon_index:
			matches.append(profile)
	if matches.size()==1:
		return matches[0]
	var selected:Dictionary={}
	for profile in matches:
		if bool(profile.get("is_default",false)):
			if not selected.is_empty():
				return {}
			selected=profile
	return selected
func _weapon_damage(profile:Dictionary)->float:
	var minimum:=float(profile.get("damage_min",1.0)); var maximum:=float(profile.get("damage_max",minimum))
	if maximum<minimum: var swap:=minimum; minimum=maximum; maximum=swap
	return rng.randf_range(minimum,maximum)
func _attack_rolls()->Dictionary:
	if combat_engine!=null:
		return combat_engine.complete_attack_rolls({})
	return {"hit":_roll(),"magic_hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"counterattack":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll(),"counterattack_rolls":{"hit":_roll(),"magic_hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll()}}
func _roll()->int:return rng.randi_range(1,100)
func _both_alive(first_id:String,second_id:String)->bool:return not state.get_combatant(first_id).is_death_finalized() and not state.get_combatant(second_id).is_death_finalized()
