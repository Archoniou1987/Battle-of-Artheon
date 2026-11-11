extends SceneTree

## Physical hammer v1.2: persistent charges, reflection, on-hit generation,
## conversion into healing/surge and armour fracture selected-zone mechanics.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("HAMMER_V12_FAIL=",label)

func _effect(fighter: CombatantState, effect_id: String) -> Dictionary:
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}

func _attacks(session: ArenaCombatSession, abi: String) -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("hammer_abi_id","")) == abi:
			result.append(event)
	return result

func _make_session(archetype: String, seed_value: int) -> ArenaCombatSession:
	var hero := CharacterState.new("HAMMER_"+archetype,"Hammer Test",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[par_id] = 90
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,40,"purple",seed_value)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	_check(hero.equip("main_hand",String(item.get("instance_id","")),repo),archetype+"_equipped")
	var expected: Array = ["ABI601","ABI602","ABI603","ABI604"] if archetype=="HAMMER_DEF" else ["ABI601","ABI602","ABI605","ABI606"]
	_check(item.get("abilities",[]) == expected,archetype+"_loadout")
	var restored := ItemRepository.from_dict(repo.to_dict())
	_check(restored.get_item(String(item.get("instance_id",""))).get("abilities",[])==expected,archetype+"_save_load")
	var session := ArenaCombatSession.new(hero,repo)
	var actor := session.fighter(true)
	var target := session.fighter(false)
	if actor==null or target==null:
		_check(false,archetype+"_fighters")
		return null
	actor.max_hp = 100000
	actor.hp = 100000
	target.max_hp = 100000
	target.hp = 100000
	actor.combat_stats["hit_chance_rating_percent"] = 100.0
	actor.combat_stats["dodge_rating_percent"] = 0.0
	actor.combat_stats["shield_auto_block_rating_percent"] = 0.0
	actor.combat_loadout["can_auto_block"] = false
	target.combat_stats["hit_chance_rating_percent"] = 100.0
	target.combat_stats["dodge_rating_percent"] = 0.0
	target.combat_stats["shield_auto_block_rating_percent"] = 0.0
	target.combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	var options := session.player_ability_options()
	for i in range(4):
		_check(i < options.size() and String(options[i].get("id",""))==String(expected[i]),archetype+"_slot_"+str(i))
	for id in expected:
		session.ability_scheduler.definitions[id]["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _cast(session: ArenaCombatSession, ability_id: String, zone: String = "chest") -> bool:
	session.fighter(true).action_points = 8
	var result := session.play_round([zone],["head","arms"],ability_id)
	_check(bool(result.get("ok",false)),ability_id+"_round")
	return bool(result.get("ok",false))

func _give_charges(session: ArenaCombatSession, n: int) -> void:
	var actor := session.fighter(true)
	var existing := _effect(actor,"EFF601")
	if not existing.is_empty():
		actor.active_effects.erase(existing)
	HammerAbiCombatService.gain_charges(session.engine,actor,n)

func _run() -> void:
	var catalog := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	for abi in HammerAbiCombatService.ABILITIES:
		_check(catalog.has(abi),"abi_catalog_"+abi)
		if catalog.has(abi):
			_check(AbilityRuntime.validate_definition(abi,catalog[abi]).is_empty(),"abi_valid_"+abi)
	for eff in ["EFF601","EFF602","EFF603","EFF604"]:
		_check(effects.has(eff),"eff_catalog_"+eff)
	_check(bool(effects.get("EFF601",{}).get("permanent",false)),"charge_never_expires")
	var fracture_definition: Dictionary = effects.get("EFF603",{})
	for boundary in [[0,0],[4,0],[5,1],[14,1],[15,2],[100,10],[120,10]]:
		var actual := EffectCatalog.application_duration_rounds(fracture_definition,{"hammer_fracture_charges":boundary[0]})
		_check(actual == boundary[1],"fracture_duration_%d" % boundary[0])
	_check(int(catalog.get("ABI606",{}).get("ap_cost",-1))==5,"crush_ap_five")

	var defence := _make_session("HAMMER_DEF",202611091)
	if defence != null:
		if _cast(defence,"ABI601"):
			_check(HammerAbiCombatService.charges(defence.fighter(true),defence.state.round_number)>=5,"passive_successful_mh_charges")
			_check(_attacks(defence,"ABI601").size()==1,"heavy_no_extra_mh")
		if _cast(defence,"ABI602"):
			# NPC's ordinary attack is random: if it misses, blocks, or deals
			# zero final damage, no reflection should be generated. Verify that
			# activation itself succeeded independently of that random outcome.
			var reflect_applied := false
			for event in defence.state.event_log:
				if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id","")) == "EFF602" and bool(event.result.get("resolved",false)):
					reflect_applied = true
			_check(reflect_applied,"reflect_activation")
			# This test targets reflection, not PAR135/trait damage reduction.
			# The high-stat Lv40 fixture may legitimately have 100% mitigation;
			# neutralize it ONLY inside this controlled fixture so an incoming
			# DAMAGE event removes HP and can produce a reflected event.
			var receiver := defence.fighter(true)
			receiver.combat_stats["damage_reduction_pct"] = 0.0
			receiver.combat_stats["damage_reduction"] = 0.0
			_check(CombatModifierService.damage_reduction(receiver,defence.state.round_number) < 1.0,"reflect_fixture_not_immune")
			# Deterministic damage during the SAME sealed round as the instant
			# ABI. Tests reflection without relying on NPC accuracy/defence RNG.
			var controlled_round: CombatRound = defence.orchestrator.begin_round()
			var reflect_action := AbilityRuntime.build_action_event(
				defence.state,defence.player_id,defence.player_id,"ABI602",catalog["ABI602"]
			)
			controlled_round.lock_action(reflect_action)
			var incoming := defence.state.create_event(
				CombatEvent.Kind.DAMAGE,ArenaCombatSession.ENEMY_ID,defence.player_id,
				{"amount":500.0,"damage_type":"physical","source":"reflection_test"}
			)
			controlled_round.lock_action(incoming)
			defence.orchestrator.resolve_locked_actions(controlled_round)
			defence.orchestrator.end_round()
			var reflected := false
			var reflection_count := 0
			for event in defence.state.event_log:
				if event.kind == CombatEvent.Kind.DAMAGE and String(event.payload.get("source","")) == "hammer_reflection" and int(event.payload.get("round",-1)) == defence.state.round_number:
					reflection_count += 1
					if event.source_id == defence.player_id and event.target_id == ArenaCombatSession.ENEMY_ID and float(event.payload.get("amount",0.0)) > 0.0:
						reflected = true
			_check(int(incoming.result.get("final_damage",0)) > 0,"reflect_test_positive_incoming")
			_check(reflected,"reflect_current_round")
			_check(reflection_count == 1,"reflect_no_recursive_chain")
			if not reflected:
				print("HAMMER_REFLECT_DIAGNOSTIC= incoming=",incoming.result,
					" active=",defence.fighter(true).active_effects,
					" reflect_action=",reflect_action.result)
		_give_charges(defence,80)
		defence.fighter(true).hp = 50000
		if _cast(defence,"ABI603"):
			_check(defence.fighter(true).hp>=65000,"heal_from_charges")
			_check(HammerAbiCombatService.charges(defence.fighter(true),defence.state.round_number)>=40,"half_charges_remain")
		_give_charges(defence,100)
		if _cast(defence,"ABI604","legs"):
			var fracture := _effect(defence.fighter(false),"EFF603")
			_check(not fracture.is_empty(),"fracture_applied_on_hit")
			if not fracture.is_empty():
				var definition: Dictionary = fracture.get("definition",{})
				_check(String(definition.get("armour_zone",""))=="legs","fracture_selected_zone")
				_check(int(definition.get("duration_rounds",0))==10,"fracture_ten_rounds")

	var attack := _make_session("HAMMER_ATTACK",202611092)
	if attack != null:
		_give_charges(attack,80)
		if _cast(attack,"ABI605"):
			var surge := _effect(attack.fighter(true),"EFF604")
			_check(not surge.is_empty(),"surge_buff")
			if not surge.is_empty():
				_check(float(Dictionary(surge.get("definition",{})).get("physical_damage_outgoing_direct_pct",0))==20.0,"surge_25pct_of_80")
		_give_charges(attack,100)
		if _cast(attack,"ABI606"):
			var crush_attacks := _attacks(attack,"ABI606")
			_check(crush_attacks.size()==1,"crush_one_hit")
			if not crush_attacks.is_empty():
				_check(float(crush_attacks[0].payload.get("raw_damage",0))>0,"crush_nonzero")
				_check(int(crush_attacks[0].payload.get("hammer_formal_tempo_delta",0))==-200,"tempo_delta_formal_only")
			_check(HammerAbiCombatService.charges(attack.fighter(true),attack.state.round_number)<=5,"crush_consumes_all")


	# The applied EFF601 snapshot controls both charge reads and new gains.
	if attack != null:
		_give_charges(attack,100)
		var charge_record := _effect(attack.fighter(true),"EFF601")
		var capped_charge_definition: Dictionary = Dictionary(charge_record.get("definition",{})).duplicate(true)
		capped_charge_definition["max_stacks"] = 7
		charge_record["definition"] = capped_charge_definition
		_check(HammerAbiCombatService.charges(attack.fighter(true),attack.state.round_number)==7,"charge_stack_cap_from_eff_snapshot")
		charge_record["stacks"] = 6
		HammerAbiCombatService.gain_charges(attack.engine,attack.fighter(true),10)
		_check(int(charge_record.get("stacks",0))==7,"charge_gain_respects_eff_snapshot_cap")

	print("HAMMER_V12_ABI_EFF=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
