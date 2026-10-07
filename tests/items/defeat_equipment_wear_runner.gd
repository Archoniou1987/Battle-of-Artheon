extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("HERO", "Hero", 20)
	var generator := ItemGenerator.new(700)
	var templates := [
		{"id":"WEAR_SWORD","name":"Sword","equip_slots":["main_hand"],"slot_usage":["main_hand"],"damage_min":2,"damage_max":3,"durability_max":50},
		{"id":"WEAR_HELM","name":"Helm","equip_slots":["head"],"slot_usage":["head"],"durability_max":40}
	]
	for template in templates:
		var item := generator.generate(template, "common")
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
		hero.equip(String((template.equip_slots as Array)[0]), String(item.instance_id), repository)

	var damaged := ItemWearService.damage_equipped(hero, repository, 2)
	var sword := repository.get_item(String(hero.equipment.get_equipped_instance_id("main_hand")))
	var helm := repository.get_item(String(hero.equipment.get_equipped_instance_id("head")))
	var ok := damaged.size() == 2
	ok = ok and int(sword.durability_current) == 48 and int(sword.durability_max) == 50
	ok = ok and int(helm.durability_current) == 38 and int(helm.durability_max) == 40

	print("DEFEAT_WEAR damaged=%d sword=%d/%d helm=%d/%d" % [damaged.size(), int(sword.durability_current), int(sword.durability_max), int(helm.durability_current), int(helm.durability_max)])
	print("DEFEAT_EQUIPMENT_WEAR_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
