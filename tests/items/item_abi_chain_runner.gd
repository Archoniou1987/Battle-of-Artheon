extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ABI_HERO", "ABI Hero", 50)
	var sword := {"instance_id":"ABI-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["TEST_ABI_FIREBALL","ABI002"]}
	var dagger := {"instance_id":"ABI-DAGGER-1","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["TEST_ABI_FIREBALL","TEST_ABI_LIGHTNING"]}
	var chest := {"instance_id":"ABI-CHEST-1","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["ABI004"]}
	var head := {"instance_id":"ABI-HELM-1","equip_slots":["head"],"slot_usage":["head"],"abilities":["ABI_HEAD_TEST"]}
	for item in [sword, dagger, chest, head]:
		ItemDurabilityService.initialize_item(item, 50)
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand","ABI-SWORD-1",repository) and hero.equip("off_hand","ABI-DAGGER-1",repository) and hero.equip("chest","ABI-CHEST-1",repository) and hero.equip("head","ABI-HELM-1",repository)
	var slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var active: Array[String] = EquipmentAbilityLoadout.active_abilities(hero, repository)
	var weapon_ok: bool = slots.get("weapon", []) == ["TEST_ABI_FIREBALL","ABI002",null]
	var chest_ok: bool = slots.get("chest", []) == ["ABI004"]
	var head_ok: bool = slots.get("head", []) == ["ABI_HEAD_TEST"]
	var slot_order_ok: bool = active == ["TEST_ABI_FIREBALL","ABI002","ABI004","ABI_HEAD_TEST"]
	var duplicate_deduped: bool = active.count("TEST_ABI_FIREBALL") == 1
	var oh_excluded: bool = not active.has("TEST_ABI_LIGHTNING")
	var ok: bool = equipped and weapon_ok and chest_ok and head_ok and slot_order_ok and duplicate_deduped and oh_excluded and active.size() == 4
	# A duplicate Chest/Head ABI belongs to the earlier reserved slot, Chest.
	var duplicate_head: Dictionary = repository.get_item("ABI-HELM-1")
	duplicate_head["abilities"] = ["ABI004"]
	var updated: bool = repository.update_item(duplicate_head)
	var duplicate_slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var chest_priority: bool = updated and duplicate_slots.get("chest", []) == ["ABI004"] and duplicate_slots.get("head", []) == [null]
	ok = ok and chest_priority
	# Production catalogs: real item template -> equipped ABI -> EFF references.
	# These opt-in templates are also selectable in the town item generator.
	var production_templates := ItemTemplateService.load_templates()
	var real_abilities := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var real_effects: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/effects/catalog.json"))
	var preview_hero := CharacterState.new("ABI_TEMPLATE_HERO","Template Hero",20)
	var preview_repo := ItemRepository.new()
	for pair in [
		["training_fire_staff_abi003","main_hand"],
		["training_healer_chest_abi004","chest"]
	]:
		var template_id: String = pair[0]
		var equip_slot: String = pair[1]
		if not production_templates.has(template_id):
			ok = false
			continue
		var instance_id := "TEMPLATE_" + template_id
		var generated := {"instance_id":instance_id,"template_id":template_id,"rarity":"green"}
		ItemDurabilityService.initialize_item(generated,100)
		if not preview_repo.add_item(generated) or not preview_hero.receive_item(instance_id,preview_repo) or not preview_hero.equip(equip_slot,instance_id,preview_repo):
			ok = false
	var actual_abilities := EquipmentAbilityLoadout.active_abilities(preview_hero,preview_repo)
	ok = ok and actual_abilities == ["ABI003","ABI004"]
	for ability_id in actual_abilities:
		if not real_abilities.has(ability_id):
			ok = false
			continue
		var definition: Dictionary = real_abilities[ability_id]
		for component in Array(definition.get("components",[])):
			if String(Dictionary(component).get("kind","")) == "effect":
				ok = ok and real_effects is Dictionary and Dictionary(real_effects).has(String(Dictionary(component).get("effect_id","")))
	print("ITEM_ABI_PRODUCTION_TEMPLATES=",actual_abilities," effects_valid=",ok)
	print("ITEM_ABI_CHAIN weapon=", slots.get("weapon", []), " chest=", slots.get("chest", []), " head=", slots.get("head", []))
	print("ITEM_ABI_CHAIN duplicate_deduped=", duplicate_deduped, " active=", active, " oh_excluded=", oh_excluded)
	print("ITEM_ABI_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
