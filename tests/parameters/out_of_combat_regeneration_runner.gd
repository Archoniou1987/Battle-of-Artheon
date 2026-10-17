extends SceneTree

var failures: Array[String] = []

func check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)

func _initialize() -> void:
	check_rates_and_fractional_carry()
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

func check_rates_and_fractional_carry() -> void:
	var setup := fixture(2.0, 3.0, 1.0)
	var hero: CharacterState = setup["hero"]
	var repository: ItemRepository = setup["repository"]
	var resources := hero.resource_snapshot(repository)
	var maximum := int(resources["max_hp"])
	hero.current_hp = 50
	hero.current_mana = 0
	var hp_per_ten := float(maximum) * 0.02 + 1.0
	var changed := OutOfCombatRegenerationService.advance(hero, repository, 1.0)
	check(changed, "one-second sub-point progress is kept")
	check(hero.current_hp == 50 + int(floor(hp_per_ten / 10.0)), "one-second HP calculation")
	check(hero.current_mana == 0, "one-second mana does not round prematurely")
	for i in range(9):
		OutOfCombatRegenerationService.advance(hero, repository, 1.0)
	check(hero.current_hp == 50 + int(floor(hp_per_ten)), "ten one-second ticks match /10sec HP")
	check(hero.current_mana == 3, "ten one-second ticks match /10sec mana")
	check(is_equal_approx(hero.out_combat_hp_fraction, hp_per_ten - floor(hp_per_ten)), "HP fractional carry preserved")
	var saved := hero.resources_to_dict()
	var restored := CharacterState.new("regen_hero", "Restored")
	check(restored.restore_resources(saved), "restore fractional resource state")
	check(is_equal_approx(restored.out_combat_hp_fraction, hero.out_combat_hp_fraction), "HP fractional carry survived save")
	check(is_equal_approx(restored.out_combat_mana_fraction, hero.out_combat_mana_fraction), "mana fractional carry survived save")

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
