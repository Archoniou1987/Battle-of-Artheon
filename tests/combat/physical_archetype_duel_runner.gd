extends SceneTree

## 15 physical v1.2 archetypes, unique 1v1 pairs (105), 50 duels per pair.
## Test only: canonical CombatEngine, actual ABI/EFF/AP/CD and real item rolls.
## No artificial charge priming, previous-round trigger markers, or damage buffs.
const LEVEL := 40
const DEF_HP := 2000
const ATTACK_HP := 1000
const DEF_ARMOUR_PCT := 45.0
const ATTACK_ARMOUR_PCT := 20.0
const BASE_DODGE_PCT := 5.0
const DEF_BLOCK_PCT := 10.0
const ATTACK_BLOCK_PCT := 0.0
const DEF_ARCHETYPES := ["SWORD_DEF","DAGGER_DEF","AXE_DEF","HAMMER_DEF"]
const DEFAULT_BATTLES := 50
const MAX_ROUNDS := 300
const BASE_SEED := 202611180
const REPORT_PATH := "res://test-results/physical-archetype-duels"
const SHIELD_ARCHETYPES := ["SWORD_DEF","AXE_DEF","HAMMER_DEF"]
const DEFENCE_ZONES := ["head","chest","arms","waist","legs"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _armour_rating(target_percent: float) -> float:
	var low := 0.0
	var high := 10000.0
	for _step in range(35):
		var mid := (low+high)*0.5
		if CombatRatingCurves.diminishing(CombatRatingCurves.armour_raw_pct(mid,LEVEL),"armour") < target_percent:
			low=mid
		else:
			high=mid
	return (low+high)*0.5

func _prepare(character_id: String, archetype: String, index: int) -> Dictionary:
	var character := CharacterState.new(character_id,archetype,LEVEL)
	character.progression.level=LEVEL
	character.level=LEVEL
	var repository := ItemRepository.new()
	var weapon := PhysicalDamageBenchmarkFixture.create_weapon(character,repository,archetype,LEVEL,BASE_SEED+index)
	if weapon.is_empty():
		return {}
	if WeaponHandPolicy.DUAL_ARCHETYPES.has(archetype):
		var offhand := PhysicalDamageBenchmarkFixture.create_offhand_weapon(character,repository,archetype,LEVEL,BASE_SEED+index)
		if offhand.is_empty():
			return {}
	if SHIELD_ARCHETYPES.has(archetype):
		# Real canonical shield, not a synthetic free block. Same item on all
		# three defensive 1H archetypes; no shield for 2H or dual wield.
		var shield_id := character_id+"_audit_shield"
		var shield := ItemTemplateService.resolve({"template_id":"shield","instance_id":shield_id})
		if shield.is_empty():
			return {}
		ItemDurabilityService.initialize_item(shield,100)
		if not repository.add_item(shield) or not character.receive_item(shield_id,repository):
			return {}
		if not character.equip("off_hand",shield_id,repository):
			return {}
	return {"character":character,"repository":repository,"weapon":weapon,
		"abilities":Array(weapon.get("abilities",[])).duplicate()}

func _runtime(prepared: Dictionary, archetype: String, defence_armour: float, attack_armour: float) -> CombatantState:
	var is_def := DEF_ARCHETYPES.has(archetype)
	var actor := CharacterCombatBuilder.build(prepared["character"],prepared["repository"],{"health":DEF_HP if is_def else ATTACK_HP})
	if actor==null:
		return null
	PhysicalDamageBenchmarkFixture.prepare_actor(actor,archetype,prepared["weapon"])
	# Explicit PvP role baselines. Offensive CRIT/PEN bonuses and all ABI
	# definitions remain unchanged; only HP, armour, dodge, block are specified.
	var armour := defence_armour if is_def else attack_armour
	for zone in DEFENCE_ZONES:
		actor.armour[zone]={"slashing":armour,"piercing":armour,"chopping":armour,"blunt":armour}
	actor.combat_stats["dodge_rating_percent"]=BASE_DODGE_PCT
	actor.combat_stats["shield_auto_block_rating_percent"]=DEF_BLOCK_PCT if is_def else ATTACK_BLOCK_PCT
	actor.combat_loadout["can_auto_block"]=is_def
	# Respect the existing PAR073 manual-block capacity and actual shield
	# availability. A dual-wield dagger does not acquire a virtual shield.
	actor.combat_loadout["can_manual_block"]=SHIELD_ARCHETYPES.has(archetype)
	return actor

func _duel(left: Dictionary, right: Dictionary, left_name: String, right_name: String,
		pair_index: int, battle_index: int, defence_armour: float, attack_armour: float) -> Dictionary:
	var a := _runtime(left,left_name,defence_armour,attack_armour)
	var b := _runtime(right,right_name,defence_armour,attack_armour)
	if a==null or b==null:
		return {"outcome":"setup_failed"}
	var state := CombatState.new()
	# Alternate insertion and action locking to cancel any stable first-side bias.
	var reverse := (battle_index % 2)==1
	if reverse:
		state.add_combatant(b)
		state.add_combatant(a)
	else:
		state.add_combatant(a)
		state.add_combatant(b)
	var group := GroupCombatState.new(state)
	group.add_member("A",a.combatant_id)
	group.add_member("B",b.combatant_id)
	group.set_active_opponent(a.combatant_id,b.combatant_id)
	group.set_active_opponent(b.combatant_id,a.combatant_id)
	var zones := CombatZoneState.new(group)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone(a.combatant_id,CombatZoneState.ZONE_2)
	zones.set_zone(b.combatant_id,CombatZoneState.ZONE_2)
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine,group,zones)
	var loadouts := {a.combatant_id:left["abilities"],b.combatant_id:right["abilities"]}
	var scheduler := AbilityScheduler.new(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),loadouts)
	var seed := BASE_SEED + pair_index*100003 + battle_index
	engine.combat_rng.seed=seed
	var pipeline := CombatAttackPipeline.new(state,seed,engine)
	var cursor := {a.combatant_id:0,b.combatant_id:0}
	var casts := {a.combatant_id:0,b.combatant_id:0}
	var outcome := "timeout"
	for turn in range(MAX_ROUNDS):
		var round := orchestrator.begin_round()
		var order: Array = [b,a] if reverse else [a,b]
		for actor in order:
			var fighter: CombatantState = actor
			var target: CombatantState = b if fighter==a else a
			# Existing PAR073, not this benchmark, determines the number of
			# manual block zones. Vary only the selected zones across rounds.
			if fighter.can_manual_block():
				var zones_to_block: Array[String] = []
				var block_count := mini(DEFENCE_ZONES.size(),CombatModifierService.manual_block_zone_capacity(fighter))
				for block_index in range(block_count):
					zones_to_block.append(DEFENCE_ZONES[(turn+pair_index+battle_index+block_index)%DEFENCE_ZONES.size()])
				fighter.combat_stats["manual_block_zones"]=zones_to_block
			var actor_id := fighter.combatant_id
			var decision := PhysicalDamageBenchmarkPolicy.choose(
				loadouts[actor_id],scheduler.definitions,
				scheduler.cooldowns_by_combatant.get(actor_id,{}),state.round_number,
				fighter.action_points,fighter.max_action_points,int(cursor[actor_id]))
			var ability_id := String(decision.get("id",""))
			if not ability_id.is_empty():
				var definition: Dictionary = scheduler.definitions.get(ability_id,{})
				var target_id := actor_id if String(definition.get("target_team","")).to_upper()=="ALLY" else target.combatant_id
				var action := scheduler.cast_event(state,actor_id,target_id,ability_id)
				if action!=null:
					round.lock_action(action)
					cursor[actor_id]=int(decision.get("cursor",cursor[actor_id]))
					casts[actor_id]=int(casts[actor_id])+1
			pipeline.lock_basic_attack(round,fighter,target)
		orchestrator.resolve_locked_actions(round)
		var result := orchestrator.end_round()
		outcome=String(result.get("battle_outcome","ongoing"))
		if outcome!="ongoing":
			break
	if outcome=="winner:A":
		outcome="A"
	elif outcome=="winner:B":
		outcome="B"
	elif outcome!="draw":
		outcome="timeout"
	return {"outcome":outcome,"rounds":state.round_number,
		"hp_a":a.visible_hp(),"hp_b":b.visible_hp(),
		"casts_a":int(casts[a.combatant_id]),"casts_b":int(casts[b.combatant_id])}

func _run() -> void:
	var battles := DEFAULT_BATTLES
	var start_pair := 0
	var end_pair := 105
	for raw in OS.get_cmdline_user_args():
		var argument := String(raw)
		if argument.begins_with("--battles="):
			battles=int(argument.trim_prefix("--battles="))
		elif argument.begins_with("--pair-start="):
			start_pair=int(argument.trim_prefix("--pair-start="))
		elif argument.begins_with("--pair-end="):
			end_pair=int(argument.trim_prefix("--pair-end="))
	var archetypes: Array = ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.duplicate()
	var expected := archetypes.size()*(archetypes.size()-1)/2
	if archetypes.size()!=15 or expected!=105 or battles<1 or battles>50 or start_pair<0 or end_pair>105 or start_pair>=end_pair:
		push_error("Invalid physical duel benchmark arguments")
		quit(1)
		return
	var defence_armour := _armour_rating(DEF_ARMOUR_PCT)
	var attack_armour := _armour_rating(ATTACK_ARMOUR_PCT)
	var pair_index := 0
	var finished_pairs := 0
	var completed_duels := 0
	var csv := "pair_index,archetype_a,archetype_b,battles,wins_a,wins_b,draws,timeouts,avg_rounds,avg_survivor_hp_a,avg_survivor_hp_b,abi_casts_a,abi_casts_b\n"
	for i in range(archetypes.size()):
		for j in range(i+1,archetypes.size()):
			if pair_index<start_pair or pair_index>=end_pair:
				pair_index+=1
				continue
			var name_a := String(archetypes[i])
			var name_b := String(archetypes[j])
			var left := _prepare("DUEL_A",name_a,i)
			var right := _prepare("DUEL_B",name_b,j)
			if left.is_empty() or right.is_empty():
				failures.append("setup_"+name_a+"_"+name_b)
				pair_index+=1
				continue
			var wins_a := 0
			var wins_b := 0
			var draws := 0
			var timeouts := 0
			var rounds_sum := 0
			var hp_a_sum := 0
			var hp_b_sum := 0
			var casts_a := 0
			var casts_b := 0
			for k in range(battles):
				var result := _duel(left,right,name_a,name_b,pair_index,k,defence_armour,attack_armour)
				var outcome := String(result.get("outcome","setup_failed"))
				if outcome=="setup_failed":
					failures.append("combat_setup_"+name_a+"_"+name_b)
					break
				match outcome:
					"A": wins_a+=1
					"B": wins_b+=1
					"draw": draws+=1
					"timeout": timeouts+=1
				rounds_sum+=int(result["rounds"])
				hp_a_sum+=int(result["hp_a"])
				hp_b_sum+=int(result["hp_b"])
				casts_a+=int(result["casts_a"])
				casts_b+=int(result["casts_b"])
			if wins_a+wins_b+draws+timeouts!=battles:
				failures.append("incomplete_"+name_a+"_"+name_b)
			else:
				completed_duels+=battles
				finished_pairs+=1
			var avg_rounds := float(rounds_sum)/float(battles)
			var row := "%d,%s,%s,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%d,%d" % [
				pair_index,name_a,name_b,battles,wins_a,wins_b,draws,timeouts,
				avg_rounds,float(hp_a_sum)/float(battles),float(hp_b_sum)/float(battles),casts_a,casts_b]
			csv+=row+"\n"
			print("PHYSICAL_DUEL_PAIR=",row)
			pair_index+=1
	print("PHYSICAL_DUEL_RULES=DEF 45pct armour 10pct auto-block 5pct dodge 2000HP; ATTACK 20pct armour 0pct auto-block 5pct dodge 1000HP; canonical attack/block counts")
	var output := REPORT_PATH+"/duels_%03d_%03d.csv" % [start_pair,end_pair]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH))
	var file := FileAccess.open(ProjectSettings.globalize_path(output),FileAccess.WRITE)
	if file==null:
		failures.append("csv_write")
	else:
		file.store_string(csv)
		file.close()
	print("PHYSICAL_DUEL_AUDIT=", "PASS" if failures.is_empty() else "FAIL",
		" pairs=",finished_pairs," battles=",completed_duels,
		" range=",start_pair,"-",end_pair," failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
