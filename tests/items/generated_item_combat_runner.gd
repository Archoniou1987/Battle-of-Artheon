extends SceneTree

func _numeric_dictionary_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key in expected.keys():
		if not actual.has(key) or not is_equal_approx(float(actual[key]), float(expected[key])):
			return false
	return true

func _init() -> void:
	var file := FileAccess.open("res://data/test/item_generator_template.json", FileAccess.READ)
	var template: Dictionary = JSON.parse_string(file.get_as_text())
	template["damage_type"] = "slashing"
	template["manual_block_zones_added"] = 1

	var generator := ItemGenerator.new(5050)
	var item: Dictionary = generator.generate(template, "purple")
	var repository := ItemRepository.new()
	var equipment := EquipmentState.new()
	var stored_ok: bool = repository.add_item(item)
	var wrong_slot_rejected: bool = not equipment.equip_item("feet", item)
	var slot_ok: bool = equipment.equip_item("main_hand", item)
	var instance_ok: bool = String(equipment.get_equipped_instance_id("main_hand")) == String(item.get("instance_id"))
	var resolved: Dictionary = ItemResolver.resolve_equipped("main_hand", equipment, repository)
	var resolved_ok: bool = not resolved.is_empty() and String(resolved.get("instance_id")) == String(item.get("instance_id"))

	var character := CharacterState.new("GEN_HERO", "Generated Sword Hero", 20)
	character.receive_item(String(item.instance_id), repository)
	character.equip("main_hand", String(item.instance_id), repository)
	var hero := CharacterCombatBuilder.build(character, repository, {"health":100,"mana":25})
	var enemy := TestFixtureLoader.new_combatant("GEN_ENEMY", "Training Enemy", 50, 100, 25)
	var dummy: Dictionary = {"damage":{"min":1,"max":1,"type":"slashing"}, "manual_block_zones_added":1}
	EquipmentBuilder.equip(enemy, dummy)

	var state := CombatState.new()
	state.add_combatant(hero)
	state.add_combatant(enemy)
	var simulator := CombatSimulator.new(TestFixtureLoader.canonicalize_state(state), {}, 5050)
	simulator.max_rounds = 100
	var result: Dictionary = simulator.run_duel(hero.combatant_id, enemy.combatant_id)

	var hero_profiles:Array = hero.combat_stats.get("weapon_profiles", [])
	var expected := ParCalculationService.calculate(character, repository)
	var bonus := float(expected.totals.PAR052)
	var equipped_ok: bool = hero_profiles.size() == 1 and is_equal_approx(float(hero_profiles[0].damage_min), float(item.damage_min) + bonus) and is_equal_approx(float(hero_profiles[0].damage_max), float(item.damage_max) + bonus)
	var stats_ok := _numeric_dictionary_equal(hero.stats, expected.totals)
	var damage_events: int = 0
	var rounds_ok: bool = true

	print("=== INSTANCE CHAIN ===")
	print("Stored: ", stored_ok, " | wrong_slot_rejected: ", wrong_slot_rejected, " | main_hand: ", equipment.get_equipped_instance_id("main_hand"), " | resolved: ", resolved_ok)
	print("=== GENERATED ITEM ===")
	print(JSON.stringify(item))
	print("=== EQUIPPED CHARACTER ===")
	var profile_min:Variant = "?"
	var profile_max:Variant = "?"
	if not hero_profiles.is_empty():
		profile_min = hero_profiles[0].get("damage_min", "?")
		profile_max = hero_profiles[0].get("damage_max", "?")
	print("Weapon profile damage: ", profile_min, "-", profile_max)
	print("Stats: ", JSON.stringify(hero.stats))
	print("=== COMBAT LOG ===")
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE:
			if event.source_id == hero.combatant_id:
				damage_events += 1
			var event_round: int = int(event.payload.get("round", 0))
			if event_round <= 0:
				rounds_ok = false
			print("Round ", event_round, " | ", event.source_id, " -> ", event.target_id, " | raw=", event.payload.get("raw_damage", event.payload.get("amount", "?")), " | result=", JSON.stringify(event.result))

	var ok: bool = stored_ok and wrong_slot_rejected and slot_ok and instance_ok and resolved_ok and equipped_ok and stats_ok and rounds_ok and damage_events > 0 and int(result.get("second_hp", 100)) < 100
	print("CHECKS repository=", stored_ok, " slot_guard=", wrong_slot_rejected, " instance=", instance_ok, " resolver=", resolved_ok, " equipped=", equipped_ok, " stats=", stats_ok, " rounds=", rounds_ok, " hero_damage_events=", damage_events)
	print("=== RESULT ===")
	print(JSON.stringify(result))
	print("INSTANCE_EQUIPMENT_COMBAT_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
