extends SceneTree

func _init() -> void:
	var file := FileAccess.open("res://data/test/item_generator_eff001_template.json", FileAccess.READ)
	var template: Dictionary = JSON.parse_string(file.get_as_text())
	var generator := ItemGenerator.new(1001)
	var item: Dictionary = generator.generate(template, "purple")
	var repository := ItemRepository.new()
	var hero := CharacterState.new("EFF_HERO", "EFF Hero", 50)
	var stored: bool = repository.add_item(item)
	var received: bool = hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand", String(item.instance_id), repository)
	var resolved: Dictionary = ItemResolver.resolve_equipped("main_hand", hero.equipment, repository)
	var fighter := CombatantState.new("EFF_HERO", "EFF Hero", 50, 100, 0)
	EquipmentBuilder.equip(fighter, resolved)
	var effects: Array = fighter.combat_stats.get("weapon_on_hit_effects", [])
	var eff_ok: bool = effects.size() == 1 and String((effects[0] as Dictionary).get("effect_id", "")) == "EFF001" and float((effects[0] as Dictionary).get("chance", 0.0)) == 100.0
	var ok: bool = stored and received and equipped and not resolved.is_empty() and eff_ok
	print("GENERATED_EFF001_ITEM instance=", item.get("instance_id", ""), " effect=", item.get("on_hit_effect", {}), " runtime_effects=", effects)
	print("GENERATED_EFF001_ITEM_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
