extends SceneTree

func _init() -> void:
	var file := FileAccess.open("res://data/test/item_generator_eff001_template.json", FileAccess.READ)
	var template: Dictionary = JSON.parse_string(file.get_as_text())
	var generator := ItemGenerator.new(1001)
	var item: Dictionary = generator.generate(template, "purple")
	var repository := ItemRepository.new()
	var hero := CharacterState.new("EFF_HERO", "EFF Hero", 50)
	repository.add_item(item)
	hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand", String(item.instance_id), repository)
	var resolved: Dictionary = ItemResolver.resolve_equipped("main_hand", hero.equipment, repository)

	var state := CombatState.new()
	var fighter := CombatantState.new("EFF_HERO", "EFF Hero", 50, 100, 0)
	var enemy := CombatantState.new("EFF_ENEMY", "EFF Enemy", 50, 200, 0)
	EquipmentBuilder.equip(fighter, resolved)
	enemy.combat_stats = {"main_hand_damage_min":1.0,"main_hand_damage_max":1.0,"main_hand_damage_type":"slashing"}
	state.add_combatant(fighter)
	state.add_combatant(enemy)
	var balance: Dictionary = AbilityCatalog.load_json("res://data/test/effects.json")
	var simulator := CombatSimulator.new(state, balance, 1001)
	simulator.max_rounds = 6
	var result: Dictionary = simulator.run_duel("EFF_HERO", "EFF_ENEMY")

	var effect_events := 0
	var bleed_ticks := 0
	var bleed_damage := 0
	var source_ok := true
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id", "")) == "EFF001":
			effect_events += 1
		if event.kind == CombatEvent.Kind.DAMAGE and String(event.payload.get("effect_id", "")) == "EFF001":
			bleed_ticks += 1
			bleed_damage += int(event.result.get("hp_removed", 0))
			source_ok = source_ok and event.source_id == "EFF_HERO"
	var ok: bool = equipped and effect_events > 0 and bleed_ticks > 0 and bleed_damage > 0 and source_ok
	print("GENERATED_EFF001_COMBAT effects=", effect_events, " bleed_ticks=", bleed_ticks, " bleed_damage=", bleed_damage, " source_ok=", source_ok, " rounds=", result.get("rounds", 0))
	print("GENERATED_EFF001_COMBAT_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
