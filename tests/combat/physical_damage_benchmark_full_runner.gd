extends SceneTree

## Canonical physical balance measurement: real v1.2 items, Combat Engine,
## ABI, EFF, AP and CD. Run 1000 fresh combats for each of 15 archetypes.
## --battles=N permits CI smoke testing without pretending it is full data.
const LEVEL := 40
const DUMMY_HP := 10000
const DEFAULT_BATTLES := 1000
const MAX_ROUNDS := 400
const BASE_SEED := 202611170
const REPORT_PATH := "res://test-results/physical-damage-benchmark/report.txt"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

static func _armour_rating() -> float:
	var lower := 0.0
	var upper := 10000.0
	for _i in range(35):
		var middle := (lower+upper)*0.5
		if CombatRatingCurves.diminishing(CombatRatingCurves.armour_raw_pct(middle,LEVEL),"armour")<20.0:
			lower=middle
		else:
			upper=middle
	return (lower+upper)*0.5

static func _tally_damage(bucket: Dictionary, damage: int, attempts: int) -> void:
	bucket["damage"]=int(bucket.get("damage",0))+damage
	bucket["attempts"]=int(bucket.get("attempts",0))+attempts

func _run() -> void:
	var battles := DEFAULT_BATTLES
	for argument in OS.get_cmdline_user_args():
		if String(argument).begins_with("--battles="):
			battles = int(String(argument).trim_prefix("--battles="))
	if battles < 1 or battles > DEFAULT_BATTLES:
		push_error("Benchmark battle count must be between 1 and 1000")
		quit(1)
		return
	var armour := _armour_rating()
	var effect_catalog := EffectCatalog.load_json()
	var rows: Array[String] = []
	rows.append("Physical damage benchmark | level=40 battles=%d armour=20%% dummy_hp=%d" % [battles,DUMMY_HP])
	rows.append("One target; real post-mitigation damage; seeded independent combats")
	var completed := 0
	for raw_archetype in ItemV12InstanceFactory.PHYSICAL_ARCHETYPES:
		var archetype := String(raw_archetype)
		var result := _measure_archetype(archetype,completed,battles,armour,effect_catalog)
		if result.is_empty():
			failures.append(archetype)
		else:
			rows.append(String(result["report"]))
			completed += 1
			print("PHYSICAL_DAMAGE_BENCHMARK_COMPLETE=",archetype," battles=",result["battles"]," rounds=",result["rounds"])
	# A generated report is a human-readable artifact, not evidence that the
	# full 1000-battle protocol ran if --battles=1 was passed.
	var path := ProjectSettings.globalize_path(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		failures.append("report_write")
	else:
		file.store_string("\n\n".join(rows)+"\n")
		file.close()
	for row in rows:
		print(row)
	print("PHYSICAL_DAMAGE_BENCHMARK=","PASS" if failures.is_empty() else "FAIL",
		" battles_per_archetype=",battles," archetypes=",completed," failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func _measure_archetype(archetype: String, index: int, battles: int, armour: float, effects: Dictionary) -> Dictionary:
	var hero := CharacterState.new("BENCHMARK_"+archetype,archetype,LEVEL)
	# CharacterProgression currently clamps 40 to 20; benchmark-only override.
	hero.progression.level=LEVEL
	hero.level=LEVEL
	for primary in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[primary]=90
	var repo := ItemRepository.new()
	var hand := "2H" if ItemV12InstanceFactory.TWO_HAND_ARCHETYPES.has(archetype) else "MH"
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,LEVEL,"purple",BASE_SEED+index,hand)
	if item.is_empty() or not hero.equip("main_hand",String(item.get("instance_id","")),repo):
		return {}
	var abilities: Array = item.get("abilities",[])
	if abilities.size()!=4:
		return {}
	var previous_clear := ArenaCombatSession.training_dummy_clear_defaults
	var previous_items := ArenaCombatSession.training_dummy_items.duplicate(true)
	ArenaCombatSession.training_dummy_clear_defaults=true
	ArenaCombatSession.training_dummy_items={}
	var attack_tally := {"damage":0,"attempts":0}
	var ability_tally: Dictionary = {}
	var definitions: Dictionary = {}
	var effect_tally: Dictionary = {}
	var effect_ticks: Dictionary = {}
	var rounds_total := 0
	var completed := 0
	var total_damage := 0
	for raw_id in abilities:
		ability_tally[String(raw_id)]={"damage":0,"casts":0}
	for battle_index in range(battles):
		var session := ArenaCombatSession.new(hero,repo)
		var actor := session.fighter(true)
		var dummy := session.fighter(false)
		if actor==null or dummy==null:
			break
		PhysicalDamageBenchmarkParProfiles.apply(actor,archetype)
		dummy.level=LEVEL
		dummy.max_hp=DUMMY_HP
		dummy.hp=DUMMY_HP
		dummy.combat_stats["dodge_rating_percent"]=0.0
		dummy.combat_stats["shield_auto_block_rating_percent"]=0.0
		dummy.combat_stats["anti_crit_rating_percent"]=0.0
		dummy.combat_loadout["can_auto_block"]=false
		dummy.combat_stats.erase("manual_block_zones")
		for zone in ["head","chest","arms","waist","legs"]:
			dummy.armour[zone]={"slashing":armour,"piercing":armour,"chopping":armour,"blunt":armour}
		session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID]=[]
		definitions=session.ability_scheduler.definitions
		var seed := BASE_SEED+index*100000+battle_index
		session.engine.combat_rng.seed=seed
		var pipeline := CombatAttackPipeline.new(session.state,seed,session.engine)
		var cursor := 0
		var casts_this_battle: Dictionary = {}
		var ended := false
		for round_index in range(MAX_ROUNDS):
			if dummy.is_death_finalized():
				ended=true
				break
			var round: CombatRound = session.orchestrator.begin_round()
			var cooldowns: Dictionary = session.ability_scheduler.cooldowns_by_combatant.get(session.player_id,{})
			var decision := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,cooldowns,session.state.round_number,actor.action_points,actor.max_action_points,cursor)
			var chosen := String(decision.get("id",""))
			if not chosen.is_empty():
				var definition: Dictionary = definitions.get(chosen,{})
				var target_id := session.player_id if String(definition.get("target_team","")).to_upper()=="ALLY" else ArenaCombatSession.ENEMY_ID
				var eligible := PhysicalDamageBenchmarkConditions.prime_previous_round(session.state,session.player_id,String(definition.get("trigger_previous_round","")))
				if eligible:
					eligible = PhysicalDamageBenchmarkConditions.prime_charges(chosen,actor,dummy,effects,session.state.round_number)
				if eligible:
					var action: CombatEvent = session.ability_scheduler.cast_event(session.state,session.player_id,target_id,chosen)
					if action!=null:
						round.lock_action(action)
						cursor=int(decision.get("cursor",cursor))
						casts_this_battle[chosen]=int(casts_this_battle.get(chosen,0))+1
			pipeline.lock_basic_attack(round,actor,dummy,["chest","chest"])
			session.orchestrator.resolve_locked_actions(round)
			session.orchestrator.end_round()
			if dummy.is_death_finalized():
				ended=true
				break
		if not ended:
			# Do not include truncated fights as valid observations.
			print("PHYSICAL_DAMAGE_BENCHMARK_TIMEOUT=",archetype," battle=",battle_index," hp=",dummy.hp)
			break
		var metrics := PhysicalDamageBenchmarkMetrics.collect(session.state.event_log,session.player_id,ArenaCombatSession.ENEMY_ID)
		var mh: Dictionary = metrics.get("mh",{})
		var oh: Dictionary = metrics.get("oh",{})
		_tally_damage(attack_tally,int(mh.get("damage",0))+int(oh.get("damage",0)),
			int(mh.get("attempts",0))+int(oh.get("attempts",0)))
		total_damage += int(metrics.get("total_damage",0))
		rounds_total += session.state.round_number
		for id in abilities:
			var key := String(id)
			var record: Dictionary = ability_tally[key]
			record["casts"]=int(record["casts"])+int(casts_this_battle.get(key,0))
			record["damage"]=int(record["damage"])+int(Dictionary(metrics.get("abi_damage",{})).get(key,0))
		for raw_eff in Dictionary(metrics.get("dot_damage",{})).keys():
			var eff := String(raw_eff)
			effect_tally[eff]=int(effect_tally.get(eff,0))+int(metrics["dot_damage"][eff])
			effect_ticks[eff]=int(effect_ticks.get(eff,0))+int(Dictionary(metrics.get("dot_ticks",{})).get(eff,0))
		completed+=1
	ArenaCombatSession.training_dummy_clear_defaults=previous_clear
	ArenaCombatSession.training_dummy_items=previous_items
	if completed!=battles:
		return {}
	var formatted: Dictionary = {}
	for id in abilities:
		var key := String(id)
		var record: Dictionary = ability_tally[key]
		var def: Dictionary = definitions.get(key,{})
		var deals_damage := false
		for part in Array(def.get("components",[])):
			if String(Dictionary(part).get("kind",""))=="damage":
				deals_damage=true
		formatted[key]={"damage":int(record["damage"]),"casts":int(record["casts"]),"no_damage":not deals_damage}
	var summary := PhysicalDamageBenchmarkReport.format_archetype(archetype,battles,attack_tally,formatted,definitions)
	summary+="\nСредний урон/раунд — %d" % roundi(float(total_damage)/float(maxi(1,rounds_total)))
	summary+="\nСреднее число раундов — %.1f" % (float(rounds_total)/float(battles))
	var effect_ids: Array[String] = []
	for raw in effect_tally.keys():
		effect_ids.append(String(raw))
	effect_ids.sort()
	for eff in effect_ids:
		summary+="\n%s (EFF) — %d за тик · %d за бой" % [eff,roundi(float(effect_tally[eff])/float(maxi(1,int(effect_ticks.get(eff,0))))),roundi(float(effect_tally[eff])/float(battles))]
	return {"report":summary,"battles":completed,"rounds":rounds_total}
