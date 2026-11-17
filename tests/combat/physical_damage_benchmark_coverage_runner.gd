extends SceneTree

## Diagnostic coverage: every approved physical weapon archetype against one
## passive Lv40 dummy. NOT a final 1000-fight balance measurement; it identifies
## unavailable ABI and insufficient fixture coverage before statistical runs.
const LEVEL := 40
const DUMMY_HP := 10000
const DIAGNOSTIC_ROUNDS := 24
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("BENCHMARK_COVERAGE_FAIL=",name)

static func _armour_rating() -> float:
	# Invert the actual production armour curve; target 20% after DR.
	var low := 0.0
	var high := 10000.0
	for _i in range(35):
		var mid := (low+high)*0.5
		if CombatRatingCurves.diminishing(CombatRatingCurves.armour_raw_pct(mid,LEVEL),"armour") < 20.0:
			low=mid
		else:
			high=mid
	return (low+high)*0.5

func _run() -> void:
	var completed := 0
	for raw_archetype in ItemV12InstanceFactory.PHYSICAL_ARCHETYPES:
		var archetype := String(raw_archetype)
		if _check_archetype(archetype,completed):
			completed += 1
	_check(completed==ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.size(),"all_archetypes_started")
	print("PHYSICAL_DAMAGE_BENCHMARK_COVERAGE=", "PASS" if failures.is_empty() else "FAIL",
		" archetypes=",completed," expected=",ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _check_archetype(archetype: String, index: int) -> bool:
	var hero := CharacterState.new("BENCH_DIAG_"+archetype,archetype,LEVEL)
	# Level 40 exists in the benchmark only; progression currently clamps at 20.
	hero.progression.level = LEVEL
	hero.level = LEVEL
	for primary in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[primary]=90
	var repository := ItemRepository.new()
	var hand := "2H" if ItemV12InstanceFactory.TWO_HAND_ARCHETYPES.has(archetype) else "MH"
	var item := ItemV12InstanceFactory.grant_weapon(hero,repository,archetype,LEVEL,"purple",202611170+index,hand)
	if item.is_empty():
		_check(false,archetype+"_weapon")
		return false
	if not hero.equip("main_hand",String(item["instance_id"]),repository):
		_check(false,archetype+"_equip")
		return false
	var previous_clear := ArenaCombatSession.training_dummy_clear_defaults
	var previous_items: Dictionary = ArenaCombatSession.training_dummy_items.duplicate(true)
	ArenaCombatSession.training_dummy_clear_defaults=true
	ArenaCombatSession.training_dummy_items={}
	var session := ArenaCombatSession.new(hero,repository)
	ArenaCombatSession.training_dummy_clear_defaults=previous_clear
	ArenaCombatSession.training_dummy_items=previous_items
	var actor := session.fighter(true)
	var dummy := session.fighter(false)
	if actor==null or dummy==null:
		_check(false,archetype+"_fighters")
		return false
	dummy.max_hp=DUMMY_HP
	dummy.hp=DUMMY_HP
	dummy.combat_stats["dodge_rating_percent"]=0.0
	dummy.combat_stats["shield_auto_block_rating_percent"]=0.0
	dummy.combat_stats["anti_crit_rating_percent"]=0.0
	dummy.combat_loadout["can_auto_block"]=false
	dummy.combat_stats.erase("manual_block_zones")
	var rating := _armour_rating()
	for zone in ["head","chest","arms","waist","legs"]:
		dummy.armour[zone]={"slashing":rating,"piercing":rating,"chopping":rating,"blunt":rating}
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID]=[]
	var seed := 202611170+index
	session.engine.combat_rng.seed=seed
	var pipeline := CombatAttackPipeline.new(session.state,seed,session.engine)
	var abilities: Array = item.get("abilities",[])
	var effect_catalog := EffectCatalog.load_json()
	var cursor := 0
	var casts: Dictionary = {}
	for raw_id in abilities:
		casts[String(raw_id)]=0
	for _i in range(DIAGNOSTIC_ROUNDS):
		if dummy.is_death_finalized():
			break
		var round: CombatRound = session.orchestrator.begin_round()
		var cd: Dictionary = session.ability_scheduler.cooldowns_by_combatant.get(session.player_id,{})
		var decision := PhysicalDamageBenchmarkPolicy.choose(abilities,session.ability_scheduler.definitions,cd,session.state.round_number,actor.action_points,actor.max_action_points,cursor)
		var chosen := String(decision.get("id",""))
		if not chosen.is_empty():
			var definition: Dictionary = session.ability_scheduler.definitions.get(chosen,{})
			var target_id := session.player_id if String(definition.get("target_team","")).to_upper()=="ALLY" else ArenaCombatSession.ENEMY_ID
			var trigger := String(definition.get("trigger_previous_round",""))
			var eligible := PhysicalDamageBenchmarkConditions.prime_previous_round(session.state,session.player_id,trigger)
			if eligible:
				eligible = PhysicalDamageBenchmarkConditions.prime_charges(chosen,actor,dummy,effect_catalog,session.state.round_number)
			var event: CombatEvent = session.ability_scheduler.cast_event(session.state,session.player_id,target_id,chosen) if eligible else null
			if event!=null:
				round.lock_action(event)
				cursor=int(decision.get("cursor",cursor))
				casts[chosen]=int(casts.get(chosen,0))+1
		pipeline.lock_basic_attack(round,actor,dummy,["chest","chest"])
		session.orchestrator.resolve_locked_actions(round)
		session.orchestrator.end_round()
	var metrics := PhysicalDamageBenchmarkMetrics.collect(session.state.event_log,session.player_id,ArenaCombatSession.ENEMY_ID)
	_check(session.state.round_number>0,archetype+"_rounds")
	_check(int(metrics.get("total_damage",0))>0,archetype+"_damage")
	_check(int(Dictionary(metrics.get("mh",{})).get("attempts",0))>0,archetype+"_mh")
	var missing: Array[String] = []
	for raw_id in abilities:
		var id := String(raw_id)
		if int(casts.get(id,0))==0:
			missing.append(id)
	# Missing ABI are diagnostic, not silently marked successful.
	print("PHYSICAL_DAMAGE_BENCHMARK_ARCHETYPE=",archetype,
		" rounds=",session.state.round_number,
		" casts=",JSON.stringify(casts),
		" missing_abi=",JSON.stringify(missing),
		" total_damage=",metrics.get("total_damage",0))
	return true
