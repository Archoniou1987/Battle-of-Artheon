extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ABI_HERO", "ABI Hero", 50)
	var sword := {"instance_id":"ABI-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["TEST_ABI_FIREBALL","ABI002"]}
	var dagger := {"instance_id":"ABI-DAGGER-1","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["TEST_ABI_FIREBALL","TEST_ABI_LIGHTNING"]}
	var chest := {"instance_id":"ABI-CHEST-1","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["ABI004"]}
	for item in [sword, dagger, chest]:
		ItemDurabilityService.initialize_item(item, 50)
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand","ABI-SWORD-1",repository) and hero.equip("off_hand","ABI-DAGGER-1",repository) and hero.equip("chest","ABI-CHEST-1",repository)
	var slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var active: Array[String] = EquipmentAbilityLoadout.active_abilities(hero, repository)
	var weapon_ok: bool = slots.get("weapon", []) == ["TEST_ABI_FIREBALL","ABI002",null]
	var chest_ok: bool = slots.get("chest", []) == ["ABI004"]
	var head_empty: bool = slots.get("head", []) == [null]
	var duplicate_deduped: bool = active.count("TEST_ABI_FIREBALL") == 1
	var oh_excluded: bool = not active.has("TEST_ABI_LIGHTNING")
	var ok: bool = equipped and weapon_ok and chest_ok and head_empty and duplicate_deduped and oh_excluded and active.size() == 3
	print("ITEM_ABI_CHAIN weapon=", slots.get("weapon", []), " chest=", slots.get("chest", []), " head=", slots.get("head", []))
	print("ITEM_ABI_CHAIN duplicate_deduped=", duplicate_deduped, " active=", active, " oh_excluded=", oh_excluded)
	print("ITEM_ABI_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
