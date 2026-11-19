extends SceneTree

var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("BENCHMARK_CONDITIONS_FAIL=",label)

func _initialize() -> void:
	var state := CombatState.new()
	var hero := TestFixtureLoader.new_combatant("bench_hero","Hero",40,1000)
	var dummy := TestFixtureLoader.new_combatant("bench_dummy","Dummy",40,10000)
	state.add_combatant(hero)
	state.add_combatant(dummy)
	var effects := EffectCatalog.load_json()
	state.begin_round()
	_check(not PhysicalDamageBenchmarkConditions.prime_previous_round(state,hero.combatant_id,"dodge"),"no_previous_round_in_round_one")
	state.begin_round()
	_check(PhysicalDamageBenchmarkConditions.prime_previous_round(state,hero.combatant_id,"dodge"),"dodge_marker_created")
	_check(AbilityRuntime.previous_round_trigger_met(state,hero.combatant_id,"dodge"),"canonical_dodge_gate_passes")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI508",hero,dummy,effects,state.round_number),"axe_wounds_seeded")
	_check(AxeAbiCombatService._wounds(dummy,hero.combatant_id,state.round_number)==EffectCatalog.stack_cap("EFF501"),"axe_full_wounds")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI404",hero,dummy,effects,state.round_number),"dagger_accuracy_seeded")
	_check(WeaponComboAbiCombatService._stacks(hero,"EFF406",state.round_number)==EffectCatalog.stack_cap("EFF406"),"dagger_full_accuracy")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI304",hero,dummy,effects,state.round_number),"sword_mastery_seeded")
	_check(SwordAbiCombatService._active_stacks(hero,"EFF314",state.round_number)==EffectCatalog.stack_cap("EFF314"),"sword_full_mastery")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI608",hero,dummy,effects,state.round_number),"hammer_concussion_seeded")
	_check(HammerAbiCombatService._concussion(dummy,hero.combatant_id,state.round_number)==EffectCatalog.stack_cap("EFF601"),"hammer_full_concussion")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI407",hero,dummy,effects,state.round_number),"dagger_counter_seeded")
	_check(WeaponComboAbiCombatService._stacks(hero,"EFF408",state.round_number)==EffectCatalog.stack_cap("EFF408"),"dagger_full_counter")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI411",hero,dummy,effects,state.round_number),"dagger_breach_seeded")
	_check(WeaponComboAbiCombatService._stacks(dummy,"EFF401",state.round_number)==EffectCatalog.stack_cap("EFF401"),"dagger_full_breach")
	_check(PhysicalDamageBenchmarkConditions.prime_charges("ABI301",hero,dummy,effects,state.round_number),"nonspender_unmodified")
	_check(state.event_log.size()==1 and bool(state.event_log[0].payload.get("benchmark_trigger",false)),"no_fake_damage_recorded")
	print("PHYSICAL_DAMAGE_BENCHMARK_CONDITIONS=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)
