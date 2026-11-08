extends SceneTree

var failures: Array[String] = []

func check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)

func _initialize() -> void:
	check_unified_defaults()
	check_rates_and_fractional_carry()
	check_legacy_mana_combination()
	check_exclusions_and_clamping()
	check_offline_equivalence()
	for failure in failures:
		push_error("OUT_OF_COMBAT_REGEN: " + failure)
	print("OUT_OF_COMBAT_REGEN_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func fixture(hp_percent: float, mana_flat: float, hp_flat: float) -> Dictionary:
	var hero := CharacterState.new("regen_hero", "Regen Hero")
	var repository := ItemRepository.new()
	var ring := {
		"instance_id": "regen_ring",
		"equip_slots": ["ring1"], "slot_usage": ["ring1"],
		"par_stats": {"PAR012": hp_percent, "PAR013": mana_flat, "PAR017": hp_flat}
	}
	ItemDurabilityService.initialize_item(ring, 100)
	check(repository.add_item(ring) and hero.receive_item("regen_ring", repository) and hero.equip("ring1", "regen_ring", repository), "equip PAR012/PAR013/PAR017")
	return {"hero":hero,"repository":repository}

func check_unified_defaults() -> void:
	var setup := fixture(0.0, 0.0, 0.0)
	var hero: CharacterState = setup["hero"]
	var repo: ItemRepository = setup["repository"]
	var max_hp := int(hero.resource_snapshot(repo)["max_hp"])
	hero.current_hp = 50
	hero.current_mana = 0
	OutOfCombatRegenerationService.advance(hero, repo, 10.0)
	check(hero.current_hp == 50 + int(floor(float(max_hp) * 0.10 / 6.0)), "base HP = 10 percent of max per minute")
	check(hero.current_mana == 5, "base mana = 5 per ten seconds, with no item bonus")
	var snapshot := ParCalculationService.calculate(hero, repo)
	check(is_equal_approx(float(snapshot["totals"].get("PAR015", -1)), 0.0), "legacy PAR013 zero value does not add to PAR015")

func check_rates_and_fractional_carry() -> void:
	var setup := fixture(2.0, 3.0, 1.0)
	var hero: CharacterState = setup["hero"]
	var repository: ItemRepository = setup["repository"]
	var resources := hero.resource_snapshot(repository)
	var maximum := int(resources["max_hp"])
	hero.current_hp = 50
	hero.current_mana = 0
	var hp_per_ten := float(maximum) * 0.12 / 6.0 + 1.0
	var changed := OutOfCombatRegenerationService.advance(hero, repository, 1.0)
	check(changed, "one-second sub-point progress is kept")
	check(hero.current_hp == 50 + int(floor(hp_per_ten / 10.0)), "one-second HP calculation")
	check(hero.current_mana == 0, "one-second mana does not round prematurely")
	for i in range(9):
		OutOfCombatRegenerationService.advance(hero, repository, 1.0)
	check(hero.current_hp == 50 + int(floor(hp_per_ten)), "ten one-second ticks match /10sec HP")
	check(hero.current_mana == 8, "ten seconds: base 5 + legacy PAR013 3")
	check(is_equal_approx(hero.out_combat_hp_fraction, hp_per_ten - floor(hp_per_ten)), "HP fractional carry preserved")
	var saved := hero.resources_to_dict()
	var restored := CharacterState.new("regen_hero", "Restored")
	check(restored.restore_resources(saved), "restore fractional resource state")
	check(is_equal_approx(restored.out_combat_hp_fraction, hero.out_combat_hp_fraction), "HP fractional carry survived save")
	check(is_equal_approx(restored.out_combat_mana_fraction, hero.out_combat_mana_fraction), "mana fractional carry survived save")

func check_legacy_mana_combination() -> void:
	var setup := fixture(0.0,2.0,0.0)
	var hero: CharacterState = setup["hero"]
	var repo: ItemRepository = setup["repository"]
	var second := {"instance_id":"mana_regen_second_ring","equip_slots":["ring2"],"slot_usage":["ring2"],"par_stats":{"PAR015":3.0}}
	ItemDurabilityService.initialize_item(second,100)
	check(repo.add_item(second) and hero.receive_item("mana_regen_second_ring",repo) and hero.equip("ring2","mana_regen_second_ring",repo), "equip canonical mana ring")
	var par := ParCalculationService.calculate(hero,repo)
	check(is_equal_approx(float(par["totals"]["PAR015"]),5.0), "legacy PAR013=2 and PAR015=3 summed exactly once")
	check(is_zero_approx(float(par["totals"]["PAR013"])), "legacy PAR013 not retained as another live mana source")
	check(is_equal_approx(float(Dictionary(repo.get_item("regen_ring")["par_stats"])["PAR013"]),2.0), "legacy saved item left unchanged")
	hero.current_hp = 50
	hero.current_mana = 0
	OutOfCombatRegenerationService.advance(hero,repo,10.0)
	check(hero.current_mana == 10, "out of combat: base 5 + PAR015 total 5")
	var fighter := CharacterCombatBuilder.build(hero,repo)
	check(fighter != null, "unified combat mana snapshot exists")
	if fighter != null:
		check(is_equal_approx(float(fighter.combat_stats["mana_regen_round"]),5.0), "combat snapshot receives same PAR015 bonus")

func check_exclusions_and_clamping() -> void:
	var setup := fixture(10.0, 20.0, 8.0)
	var hero: CharacterState = setup["hero"]
	var repository: ItemRepository = setup["repository"]
	var snapshot := hero.resource_snapshot(repository)
	hero.current_hp = 0
	hero.current_mana = 0
	check(not OutOfCombatRegenerationService.advance(hero, repository, 1000000.0), "zero HP has no passive recovery")
	check(hero.current_hp == 0 and hero.current_mana == 0, "zero HP blocks both resources")
	hero.current_hp = 1
	hero.in_combat = true
	check(not OutOfCombatRegenerationService.advance(hero, repository, 1000.0), "combat suspends out-of-combat regeneration")
	check(hero.current_hp == 1, "combat HP unchanged")
	hero.in_combat = false
	check(not OutOfCombatRegenerationService.advance(hero, repository, -10.0), "negative elapsed time rejected")
	check(not OutOfCombatRegenerationService.advance(hero, repository, 0.0), "zero elapsed time rejected")
	OutOfCombatRegenerationService.advance(hero, repository, 1000000.0)
	check(hero.current_hp == int(snapshot["max_hp"]), "unlimited elapsed HP clamps to max")
	check(hero.current_mana == int(snapshot["max_mana"]), "unlimited elapsed mana clamps to max")
	check(is_zero_approx(hero.out_combat_hp_fraction) and is_zero_approx(hero.out_combat_mana_fraction), "fractions clear on maximum")

func check_offline_equivalence() -> void:
	var a := fixture(1.5, 0.7, 2.0)
	var hero_a: CharacterState = a["hero"]
	var repo_a: ItemRepository = a["repository"]
	hero_a.current_hp = 5
	hero_a.current_mana = 0
	var b := fixture(1.5, 0.7, 2.0)
	var hero_b: CharacterState = b["hero"]
	var repo_b: ItemRepository = b["repository"]
	hero_b.current_hp = 5
	hero_b.current_mana = 0
	for i in range(137):
		OutOfCombatRegenerationService.advance(hero_a, repo_a, 1.0)
	OutOfCombatRegenerationService.advance(hero_b, repo_b, 137.0)
	check(hero_a.current_hp == hero_b.current_hp and hero_a.current_mana == hero_b.current_mana, "137 live seconds equal 137 offline seconds")
	check(is_equal_approx(hero_a.out_combat_hp_fraction, hero_b.out_combat_hp_fraction), "HP carry independent of tick length")
	check(is_equal_approx(hero_a.out_combat_mana_fraction, hero_b.out_combat_mana_fraction), "mana carry independent of tick length")
