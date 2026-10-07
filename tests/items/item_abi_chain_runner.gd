extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ABI_HERO", "ABI Hero", 50)
	var sword := {"instance_id":"ABI-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["ABI001","ABI002"]}
	var dagger := {"instance_id":"ABI-DAGGER-1","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["ABI001","ABI003"]}
	var chest := {"instance_id":"ABI-CHEST-1","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["ABI004"]}
	for item in [sword, dagger, chest]:
		ItemDurabilityService.initialize_item(item, 50)
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
	var equipped: bool = hero.equip("main_hand","ABI-SWORD-1",repository) and hero.equip("off_hand","ABI-DAGGER-1",repository) and hero.equip("chest","ABI-CHEST-1",repository)
	var slots: Dictionary = EquipmentAbilityLoadout.build(hero, repository)
	var active: Array[String] = EquipmentAbilityLoadout.active_abilities(hero, repository)
	var weapon_ok: bool = slots.get("weapon", []) == ["ABI001","ABI002","ABI003"]
	var chest_ok: bool = slots.get("chest", []) == ["ABI004"]
	var head_empty: bool = slots.get("head", []) == [null]
	var duplicate_deduped: bool = active.count("ABI001") == 1
	var ok: bool = equipped and weapon_ok and chest_ok and head_empty and duplicate_deduped and active.size() == 4
	print("ITEM_ABI_CHAIN weapon=", slots.get("weapon", []), " chest=", slots.get("chest", []), " head=", slots.get("head", []))
	print("ITEM_ABI_CHAIN duplicate_deduped=", duplicate_deduped, " active=", active)
	print("ITEM_ABI_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
