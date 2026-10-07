class_name CombatSimulator
extends RefCounted

const HIT_ZONES := ["head", "chest", "arms", "waist", "legs"]
var state: CombatState
var engine: CombatEngine
var ability_scheduler: AbilityScheduler
var orchestrator: RoundOrchestrator
var rng := RandomNumberGenerator.new()
var max_rounds: int = 100

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
	var round:=orchestrator.begin_round()
	_regenerate_mana()
	var first:=state.get_combatant(first_id)
	var second:=state.get_combatant(second_id)
	if first!=null and second!=null and not first.is_death_finalized() and not second.is_death_finalized():
		_queue_ready_abilities(first,second)
		_queue_ready_abilities(second,first)
		engine.resolve_pending_events()
	_lock_basic_attack(round,first,second)
	_lock_basic_attack(round,second,first)
	orchestrator.resolve_locked_actions(round)
	orchestrator.end_round()

func _regenerate_mana()->void:
	for combatant in state.combatants.values():
		var regen:=maxi(0,int(combatant.combat_stats.get("mana_regen",0)))
		combatant.mana=mini(combatant.max_mana,combatant.mana+regen)

func _queue_ready_abilities(source:CombatantState,target:CombatantState)->void:
	for event in ability_scheduler.ready_events(state,source.combatant_id,target.combatant_id): state.queue_event(event)
func _lock_basic_attack(round:CombatRound,attacker:CombatantState,defender:CombatantState)->void:
	if attacker==null or defender==null or attacker.is_death_finalized() or defender.is_death_finalized() or not _tempo_allows_attack(attacker.tempo): return
	var weapon_attacks:=maxi(1,int(attacker.combat_stats.get("weapon_attack_count",1)))
	for weapon_index in range(weapon_attacks):
		if _weapon_attack_available(attacker,weapon_index):
			round.lock_action(_make_basic_attack(attacker,defender,weapon_index>0,weapon_index))
	if attacker.tempo>0.0 and CombatMath.roll_success(minf(attacker.tempo,100.0),_roll()): round.lock_action(_make_basic_attack(attacker,defender,true,0))
func _weapon_attack_available(attacker:CombatantState,weapon_index:int)->bool:
	var profile:=_weapon_profile(attacker,weapon_index)
	var requirement:=String(profile.get("requires_off_hand_type",""))
	if requirement.is_empty(): return true
	var equipped_types:Array=attacker.combat_stats.get("equipped_item_types",[])
	return equipped_types.has(requirement)

func _make_basic_attack(attacker:CombatantState,defender:CombatantState,extra:bool,weapon_index:int)->CombatEvent:
	var profile:=_weapon_profile(attacker,weapon_index)
	return state.create_event(CombatEvent.Kind.ATTACK,attacker.combatant_id,defender.combatant_id,{"raw_damage":_weapon_damage(profile),"zone":HIT_ZONES[rng.randi_range(0,HIT_ZONES.size()-1)],"damage_type":String(profile.get("damage_type","slashing")),"rolls":_attack_rolls(),"is_extra_attack":extra,"generates_ap":not extra,"weapon_index":weapon_index})
func _weapon_profile(attacker:CombatantState,weapon_index:int)->Dictionary:
	var profiles:Array=attacker.combat_stats.get("weapon_profiles",[])
	if not profiles.is_empty():
		return profiles[clampi(weapon_index,0,profiles.size()-1)]
	return {"damage_min":float(attacker.combat_stats.get("main_hand_damage_min",attacker.combat_stats.get("main_hand_damage",1.0))),"damage_max":float(attacker.combat_stats.get("main_hand_damage_max",attacker.combat_stats.get("main_hand_damage",1.0))),"damage_type":String(attacker.combat_stats.get("main_hand_damage_type","slashing"))}
func _weapon_damage(profile:Dictionary)->float:
	var minimum:=float(profile.get("damage_min",1.0)); var maximum:=float(profile.get("damage_max",minimum))
	if maximum<minimum: var swap:=minimum; minimum=maximum; maximum=swap
	return rng.randf_range(minimum,maximum)
func _tempo_allows_attack(tempo:float)->bool:
	if tempo<=-100.0:return false
	if tempo>=0.0:return true
	return CombatMath.roll_success(100.0+tempo,_roll())
func _attack_rolls()->Dictionary:
	return {"hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"counterattack":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll(),"counterattack_rolls":{"hit":_roll(),"reaction":_roll(),"dodge":_roll(),"auto_block":_roll(),"block_crush":_roll(),"crit":_roll(),"on_hit_effect":_roll(),"manual_block_effect":_roll()}}
func _roll()->int:return rng.randi_range(1,100)
func _both_alive(first_id:String,second_id:String)->bool:return not state.get_combatant(first_id).is_death_finalized() and not state.get_combatant(second_id).is_death_finalized()
