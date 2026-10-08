class_name CombatSimulator
extends RefCounted

const HIT_ZONES := ["head", "chest", "arms", "waist", "legs"]
var state: CombatState
var engine: CombatEngine
var ability_scheduler: AbilityScheduler
var orchestrator: RoundOrchestrator
var rng := RandomNumberGenerator.new()
var max_rounds: int = 999

func _init(combat_state: CombatState, balance: Dictionary = {}, seed_value: int = 1) -> void:
	state = combat_state
	engine = CombatEngine.new(state, balance)
	orchestrator = RoundOrchestrator.new(state, engine)
	rng.seed = seed_value
	ability_scheduler = AbilityScheduler.new(AbilityCatalog.load_json("res://data/test/abilities.json"), AbilityCatalog.load_json("res://data/test/ability_loadouts.json"))

func run_duel(first_id: String, second_id: String) -> Dictionary:
	while _both_alive(first_id, second_id) and state.round_number < max_rounds: _run_round(first_id, second_id)
	var first := state.get_combatant(first_id); var second := state.get_combatant(second_id); var outcome := "timeout"
	if not first.is_alive() and not second.is_alive(): outcome = "draw"
	elif first.is_alive() and not second.is_alive(): outcome = first_id
	elif second.is_alive() and not first.is_alive(): outcome = second_id
	var winner_id := ""
	var loser_id := ""
	if outcome == first_id:
		winner_id = first_id
		loser_id = second_id
	elif outcome == second_id:
		winner_id = second_id
		loser_id = first_id
	return {"outcome":outcome,"winner_id":winner_id,"loser_id":loser_id,"rounds":state.round_number,"first_hp":first.hp,"second_hp":second.hp,"first_mana":first.mana,"second_mana":second.mana,"events":state.event_log.size()}

func _run_round(first_id:String,second_id:String)->void:
	# Keep the legacy duel smoke simulator independent from spatial movement.
	# Combat v2's orchestrator is used only when it has a complete spatial context.
	var round:CombatRound
	if orchestrator!=null:
		round=orchestrator.begin_round()
	else:
		state.begin_round()
		round=CombatRound.new(state.round_number)
	regenerate_mana()
	var first:=state.get_combatant(first_id)
	var second:=state.get_combatant(second_id)
	lock_basic_attack(round,first,second)
	lock_basic_attack(round,second,first)
	orchestrator.resolve_locked_actions(round)
	# ABI is the second immediate phase. Start-of-round participants may finish
	# their established actions even when Base Attack has driven HP below zero.
	if first!=null and second!=null and not first.is_death_finalized() and not second.is_death_finalized():
		queue_ready_abilities(first,second)
		queue_ready_abilities(second,first)
		engine.resolve_pending_events()
	orchestrator.end_round()

func regenerate_mana()->void:
	for combatant in state.combatants.values():
		var regen:=maxi(0,int(combatant.combat_stats.get("mana_regen",0)))
		combatant.mana=mini(combatant.max_mana,combatant.mana+regen)

func queue_ready_abilities(source:CombatantState,target:CombatantState)->void:
	for event in ability_scheduler.ready_events(state,source.combatant_id,target.combatant_id): state.queue_event(event)
func lock_basic_attack(round:CombatRound,attacker:CombatantState,defender:CombatantState)->void:
	if attacker==null or defender==null or attacker.is_death_finalized() or defender.is_death_finalized() or not _tempo_allows_attack(attacker.tempo): return
	var weapon_indices:Array=[]
	var canonical_profiles:=WeaponAttackProfile.all(attacker)
	# Legacy damage fields describe one main-hand attack. Canonical multi-weapon
	# profiles may expose additional weapon indices, but the compatibility
	# fallback must never invent a second/off-hand attack.
	for profile in canonical_profiles:
		var weapon_index:=int(profile.get("weapon_index",-1))
		if not weapon_indices.has(weapon_index):
			weapon_indices.append(weapon_index)
	weapon_indices.sort()
	# One normal Base Attack (all MH/OH and multi-hit constituents) shares one AP group.
	# Tempo-generated extra attacks remain outside that AP-producing action.
	var ap_group_id:=state.next_event_id
	for raw_weapon_index in weapon_indices:
		var weapon_index:=int(raw_weapon_index)
		if _weapon_attack_available(attacker,weapon_index):
			for event in _make_basic_attacks(attacker,defender,false,weapon_index,ap_group_id):
				round.lock_action(event)
	if attacker.tempo>0.0 and CombatMath.roll_success(minf(attacker.tempo,100.0),_roll()):
		for event in _make_basic_attacks(attacker,defender,true,0):
			round.lock_action(event)
func _weapon_attack_available(attacker:CombatantState,weapon_index:int)->bool:
	var profile:=_weapon_profile(attacker,weapon_index)
	if profile.is_empty():
		return false
	var requirement:=String(profile.get("requires_off_hand_type",""))
	if requirement.is_empty(): return true
	var equipped_types:Array=attacker.combat_stats.get("equipped_item_types",[])
	return equipped_types.has(requirement)

func _make_basic_attacks(attacker:CombatantState,defender:CombatantState,extra:bool,weapon_index:int,ap_group_id:int=-1)->Array[CombatEvent]:
	var profile:=_weapon_profile(attacker,weapon_index)
	var result:Array[CombatEvent]=[]
	var hit_count:=maxi(1,int(profile.get("hit_count",1)))
	for hit_index in range(hit_count):
		var rolls:=_attack_rolls()
		var damage_roll:=rng.randf()
		rolls["damage"]=damage_roll
		var damage_min:=float(profile.get("damage_min",0.0))
		var damage_max:=float(profile.get("damage_max",damage_min))
		result.append(state.create_event(CombatEvent.Kind.ATTACK,attacker.combatant_id,defender.combatant_id,{
			"raw_damage":CombatMath.roll_damage(damage_min,damage_max,damage_roll),
			"damage_min":damage_min,"damage_max":damage_max,"damage_roll":damage_roll,
			"zone":HIT_ZONES[rng.randi_range(0,HIT_ZONES.size()-1)],
			"damage_type":String(profile.get("damage_type","slashing")),"rolls":rolls,
			"is_extra_attack":extra,"generates_ap":not extra,"ap_group_id":ap_group_id if ap_group_id>=0 else state.next_event_id,"weapon_index":weapon_index,
			"is_weapon_attack":true,"attack_profile_id":String(profile.get("id","basic")),
			"hit_index":hit_index,"hit_count":hit_count,
			"delivery_type":String(profile.get("delivery_type","MELEE")),
			"min_zone_distance":int(profile.get("min_zone_distance",0)),
			"max_zone_distance":int(profile.get("max_zone_distance",0)),
			"two_zone_hit_modifier":float(profile.get("two_zone_hit_modifier",-50.0)),
			"uses_magic_hit":bool(profile.get("uses_magic_hit",false)),
			"magic_hit_modifier":float(profile.get("magic_hit_modifier",0.0)),
			"magic_hit_roll":int(rolls.get("magic_hit",1)),
			"uses_physical_block":not bool(profile.get("uses_magic_hit",false)),
			"bypass_physical_mitigation":not String(profile.get("damage_type","slashing")).to_lower() in ["physical","slashing","piercing","chopping","blunt"]
		}))
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
func _tempo_allows_attack(tempo:float)->bool:
	if tempo<=-100.0:return false
	if tempo>=0.0:return true
	return CombatMath.roll_success(100.0+tempo,_roll())
func _attack_rolls()->Dictionary:
	return {"hit":_roll(),"magic_hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"counterattack":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll(),"counterattack_rolls":{"hit":_roll(),"magic_hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll()}}
func _roll()->int:return rng.randi_range(1,100)
func _both_alive(first_id:String,second_id:String)->bool:return not state.get_combatant(first_id).is_death_finalized() and not state.get_combatant(second_id).is_death_finalized()
