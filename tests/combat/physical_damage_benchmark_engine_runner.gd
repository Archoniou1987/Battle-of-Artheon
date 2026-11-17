extends SceneTree

## One real combat slice toward the approved Lv40 benchmark.
## A stationary target receives real MH/OH and ABI actions from CombatEngine.
## This smoke is intentionally short; it is not a 1000-battle result.
const LEVEL := 40
const DUMMY_HP := 10000
const ROUNDS := 12
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)
		print("BENCHMARK_ENGINE_FAIL=",label)

func _run() -> void:
	var hero := CharacterState.new("BENCHMARK_HERO","Benchmark Hero",LEVEL)
	for primary in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[primary]=90
	var repository := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repository,"SWORD_DEF",LEVEL,"purple",20261117,"MH")
	_check(not item.is_empty(),"weapon_generated")
	if item.is_empty():
		_finish()
		return
	_check(hero.equip("main_hand",String(item["instance_id"]),repository),"weapon_equipped")
	var previous_clear := ArenaCombatSession.training_dummy_clear_defaults
	var previous_items: Dictionary = ArenaCombatSession.training_dummy_items.duplicate(true)
	ArenaCombatSession.training_dummy_clear_defaults = true
	ArenaCombatSession.training_dummy_items = {}
	var session := ArenaCombatSession.new(hero,repository)
	ArenaCombatSession.training_dummy_clear_defaults = previous_clear
	ArenaCombatSession.training_dummy_items = previous_items
	var player := session.fighter(true)
	var dummy := session.fighter(false)
	_check(player != null and dummy != null,"combatants_built")
	if player == null or dummy == null:
		_finish()
		return
	dummy.max_hp = DUMMY_HP
	dummy.hp = DUMMY_HP
	dummy.combat_stats["dodge_rating_percent"] = 0.0
	dummy.combat_stats["shield_auto_block_rating_percent"] = 0.0
	dummy.combat_stats["anti_crit_rating_percent"] = 0.0
	dummy.combat_loadout["can_auto_block"] = false
	dummy.combat_stats.erase("manual_block_zones")
	# Find a rating giving 20% using the canonical armour curve,
	# avoiding a duplicated formula in the benchmark.
	var low := 0.0
	var high := 10000.0
	for _i in range(32):
		var middle := (low+high)*0.5
		var reduction := CombatRatingCurves.diminishing(CombatRatingCurves.armour_raw_pct(middle,LEVEL),"armour")
		if reduction < 20.0:
			low = middle
		else:
			high = middle
	var armour_rating := (low+high)*0.5
	for zone in ["head","chest","arms","waist","legs"]:
		dummy.armour[zone] = {"slashing":armour_rating,"piercing":armour_rating,"chopping":armour_rating,"blunt":armour_rating}
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	session.engine.combat_rng.seed = 20261117
	var attacks := CombatAttackPipeline.new(session.state,20261117,session.engine)
	var abilities: Array = item.get("abilities",[])
	var cursor := 0
	var cast_count := 0
	for _round_index in range(ROUNDS):
		if dummy.is_death_finalized():
			break
		var round: CombatRound = session.orchestrator.begin_round()
		var cooldowns: Dictionary = session.ability_scheduler.cooldowns_by_combatant.get(session.player_id,{})
		var decision := PhysicalDamageBenchmarkPolicy.choose(abilities,session.ability_scheduler.definitions,cooldowns,session.state.round_number,player.action_points,player.max_action_points,cursor)
		var selected := String(decision.get("id",""))
		if not selected.is_empty():
			var definition: Dictionary = session.ability_scheduler.definitions.get(selected,{})
			# Do not bypass the production AP, CD and cast contract.
			var target_id := session.player_id if String(definition.get("target_team","")).to_upper()=="ALLY" else ArenaCombatSession.ENEMY_ID
			var action := session.ability_scheduler.cast_event(session.state,session.player_id,target_id,selected)
			if action != null:
				round.lock_action(action)
				cursor = int(decision.get("cursor",cursor))
				cast_count += 1
		attacks.lock_basic_attack(round,player,dummy,["chest","chest"])
		session.orchestrator.resolve_locked_actions(round)
		session.orchestrator.end_round()
	var metrics := PhysicalDamageBenchmarkMetrics.collect(session.state.event_log,session.player_id,ArenaCombatSession.ENEMY_ID)
	_check(session.state.round_number > 0,"real_rounds")
	_check(int(metrics.get("total_damage",0)) > 0,"real_damage")
	_check(int(Dictionary(metrics.get("mh",{})).get("attempts",0)) > 0,"real_weapon_attacks")
	_check(cast_count > 0,"real_ability_casts")
	print("PHYSICAL_DAMAGE_BENCHMARK_ENGINE=", "PASS" if errors.is_empty() else "FAIL",
		" rounds=",session.state.round_number," casts=",cast_count,
		" damage=",metrics.get("total_damage",0)," errors=",errors)
	_finish()

func _finish() -> void:
	quit(0 if errors.is_empty() else 1)
