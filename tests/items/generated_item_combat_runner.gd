extends SceneTree

func _numeric_dictionary_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key in expected.keys():
		if not actual.has(key):
			return false
		if not is_equal_approx(float(actual[key]), float(expected[key])):
			return false
	return true

func _init() -> void:
	var file := FileAccess.open("res://data/test/item_generator_template.json", FileAccess.READ)
	var template: Dictionary = JSON.parse_string(file.get_as_text())
	template["damage_type"] = "slashing"
	template["manual_block_zones_added"] = 1

	var generator := ItemGenerator.new(5050)
	var item: Dictionary = generator.generate(template, "purple")
	var hero := CombatantState.new("GEN_HERO", "Generated Sword Hero", 50, 100, 25)
	var enemy := CombatantState.new("GEN_ENEMY", "Training Enemy", 50, 100, 25)
	EquipmentBuilder.equip(hero, item)
	var dummy: Dictionary = {"damage":{"min":1,"max":1,"type":"slashing"}, "manual_block_zones_added":1}
	EquipmentBuilder.equip(enemy, dummy)

	var state := CombatState.new()
	state.add_combatant(hero)
	state.add_combatant(enemy)
	var simulator := CombatSimulator.new(state, {}, 5050)
	simulator.max_rounds = 100
	var result: Dictionary = simulator.run_duel(hero.combatant_id, enemy.combatant_id)

	var equipped_ok: bool = int(hero.combat_stats.get("main_hand_damage_min", 0)) == int(item.get("damage_min", 0)) and int(hero.combat_stats.get("main_hand_damage_max", 0)) == int(item.get("damage_max", 0))
	var stats_ok: bool = _numeric_dictionary_equal(hero.stats, item.get("final_stats", {}))
	var damage_events: int = 0
	var rounds_ok: bool = true

	print("=== GENERATED ITEM ===")
	print(JSON.stringify(item))
	print("=== EQUIPPED CHARACTER ===")
	print("MainHand damage: ", hero.combat_stats.get("main_hand_damage_min"), "-", hero.combat_stats.get("main_hand_damage_max"))
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

	var ok: bool = equipped_ok and stats_ok and rounds_ok and damage_events > 0 and int(result.get("second_hp", 100)) < 100
	print("CHECKS equipped=", equipped_ok, " stats=", stats_ok, " rounds=", rounds_ok, " hero_damage_events=", damage_events)
	print("=== RESULT ===")
	print(JSON.stringify(result))
	print("GENERATED_ITEM_COMBAT_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
