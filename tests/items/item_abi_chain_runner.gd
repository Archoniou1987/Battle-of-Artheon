extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ABI_HERO", "ABI Hero", 50)
	var sword := {"instance_id":"ABI-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["TEST_ABI_FIREBALL","TEST_ABI_FROST"]}
	var dagger := {"instance_id":"ABI-DAGGER-1","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["TEST_ABI_FIREBALL","TEST_ABI_LIGHTNING"]}
	var chest := {"instance_id":"ABI-CHEST-1","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["TEST_ABI_SHIELD_BASH"]}
	var head := {"instance_id":"ABI-HELM-1","equip_slots":["head"],"slot_usage":["head"],"abilities":["TEST_ABI_HEAD"]}
	for item in [sword, dagger, chest, head]:
		ItemDurabilityService.initialize_item(item, 50)
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand","ABI-SWORD-1",repository) and hero.equip("off_hand","ABI-DAGGER-1",repository) and hero.equip("chest","ABI-CHEST-1",repository) and hero.equip("head","ABI-HELM-1",repository)
	var slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var active: Array[String] = EquipmentAbilityLoadout.active_abilities(hero, repository)
	var weapon_ok: bool = slots.get("weapon", []) == ["TEST_ABI_FIREBALL","TEST_ABI_FROST",null,null]
	var chest_ok: bool = slots.get("chest", []) == ["TEST_ABI_SHIELD_BASH"]
	var head_ok: bool = slots.get("head", []) == ["TEST_ABI_HEAD"]
	var slot_order_ok: bool = active == ["TEST_ABI_FIREBALL","TEST_ABI_FROST","TEST_ABI_SHIELD_BASH","TEST_ABI_HEAD"]
	var duplicate_deduped: bool = active.count("TEST_ABI_FIREBALL") == 1
	var oh_excluded: bool = not active.has("TEST_ABI_LIGHTNING")
	var ok: bool = equipped and weapon_ok and chest_ok and head_ok and slot_order_ok and duplicate_deduped and oh_excluded and active.size() == 4
	# A duplicate Chest/Head ABI belongs to the earlier reserved slot, Chest.
	var duplicate_head: Dictionary = repository.get_item("ABI-HELM-1")
	duplicate_head["abilities"] = ["TEST_ABI_SHIELD_BASH"]
	var updated: bool = repository.update_item(duplicate_head)
	var duplicate_slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var chest_priority: bool = updated and duplicate_slots.get("chest", []) == ["TEST_ABI_SHIELD_BASH"] and duplicate_slots.get("head", []) == [null]
	ok = ok and chest_priority
	# Production sanity: a generated, approved sword has exactly its four
	# current ABI; retired tutorial templates cannot be rolled or equipped.
	var real_abilities := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var real_effects: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/effects/catalog.json"))
	var preview_hero := CharacterState.new("ABI_TEMPLATE_HERO","Template Hero",40)
	var preview_repo := ItemRepository.new()
	for stat_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		preview_hero.progression.base_stats[stat_id] = 100
	var generated := ItemV12InstanceFactory.grant_weapon(preview_hero,preview_repo,"SWORD_DEF",40,"purple",154301)
	ok = ok and not generated.is_empty()
	if not generated.is_empty():
		ok = ok and preview_hero.equip("main_hand",String(generated["instance_id"]),preview_repo)
	var actual_abilities := EquipmentAbilityLoadout.active_abilities(preview_hero,preview_repo)
	ok = ok and actual_abilities == ["ABI301","ABI302","ABI303","ABI306"]
	for ability_id in actual_abilities:
		if not real_abilities.has(ability_id):
			ok = false
			continue
		var definition: Dictionary = real_abilities[ability_id]
		for component in Array(definition.get("components",[])):
			if String(Dictionary(component).get("kind","")) == "effect":
				ok = ok and real_effects is Dictionary and Dictionary(real_effects).has(String(Dictionary(component).get("effect_id","")))
	ok = ok and not ItemTemplateService.load_templates().has("training_fire_staff_abi003")
	ok = ok and not ItemTemplateService.load_templates().has("training_healer_chest_abi004")
	print("ITEM_ABI_PRODUCTION_TEMPLATES=",actual_abilities," effects_valid=",ok)
	print("ITEM_ABI_CHAIN weapon=", slots.get("weapon", []), " chest=", slots.get("chest", []), " head=", slots.get("head", []))
	print("ITEM_ABI_CHAIN duplicate_deduped=", duplicate_deduped, " active=", active, " oh_excluded=", oh_excluded)
	print("ITEM_ABI_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
