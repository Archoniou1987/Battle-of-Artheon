extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ABI_HERO", "ABI Hero", 50)
	var sword := {"instance_id":"ABI-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["ABI001","ABI002"]}
	var dagger := {"instance_id":"ABI-DAGGER-1","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["ABI001","ABI003"]}
	var chest := {"instance_id":"ABI-CHEST-1","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["ABI004"]}
	for item in [sword, dagger, chest]:
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
	var equipped := hero.equip("main_hand","ABI-SWORD-1",repository) and hero.equip("off_hand","ABI-DAGGER-1",repository) and hero.equip("chest","ABI-CHEST-1",repository)
	var slots := EquipmentAbilityLoadout.build(hero, repository)
	var active := EquipmentAbilityLoadout.active_abilities(hero, repository)
	var weapon_ok := slots.weapon == ["ABI001","ABI002","ABI003"]
	var chest_ok := slots.chest == ["ABI004"]
	var head_empty := slots.head == [null]
	var duplicate_deduped := active.count("ABI001") == 1
	var ok := equipped and weapon_ok and chest_ok and head_empty and duplicate_deduped and active.size() == 4
	print("ITEM_ABI_CHAIN weapon=", slots.weapon, " chest=", slots.chest, " head=", slots.head)
	print("ITEM_ABI_CHAIN duplicate_deduped=", duplicate_deduped, " active=", active)
	print("ITEM_ABI_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
