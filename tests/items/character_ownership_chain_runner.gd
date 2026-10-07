extends SceneTree

func _init() -> void:
	var file := FileAccess.open("res://data/test/item_generator_template.json", FileAccess.READ)
	var template: Dictionary = JSON.parse_string(file.get_as_text())
	var generator := ItemGenerator.new(9090)
	var hero_item: Dictionary = generator.generate(template, "purple")
	var foreign_item: Dictionary = generator.generate(template, "purple")
	var repository := ItemRepository.new()
	var hero := CharacterState.new("HERO", "Hero", 50)
	var stranger := CharacterState.new("STRANGER", "Stranger", 50)

	var stored_hero := repository.add_item(hero_item)
	var stored_foreign := repository.add_item(foreign_item)
	var hero_received := hero.receive_item(String(hero_item.instance_id), repository)
	var stranger_received := stranger.receive_item(String(foreign_item.instance_id), repository)
	var foreign_rejected := not hero.equip("main_hand", String(foreign_item.instance_id), repository)
	var own_equipped := hero.equip("main_hand", String(hero_item.instance_id), repository)
	var slot_instance_ok := String(hero.equipment.get_equipped_instance_id("main_hand")) == String(hero_item.instance_id)
	var equipped_remove_rejected := not hero.remove_item(String(hero_item.instance_id))
	var unequip_ok := String(hero.unequip("main_hand")) == String(hero_item.instance_id)
	var remove_ok := hero.remove_item(String(hero_item.instance_id))
	var ownership_cleared := not hero.inventory.owns(String(hero_item.instance_id))
	var stranger_unchanged := stranger.inventory.owns(String(foreign_item.instance_id))

	var ok := stored_hero and stored_foreign and hero_received and stranger_received and foreign_rejected and own_equipped and slot_instance_ok and equipped_remove_rejected and unequip_ok and remove_ok and ownership_cleared and stranger_unchanged
	print("CHARACTER_CHAIN foreign_rejected=", foreign_rejected, " own_equipped=", own_equipped, " slot_instance=", slot_instance_ok, " equipped_remove=", equipped_remove_rejected)
	print("CHARACTER_CHAIN unequip=", unequip_ok, " remove=", remove_ok, " ownership_cleared=", ownership_cleared, " stranger_unchanged=", stranger_unchanged)
	print("CHARACTER_OWNERSHIP_CHAIN_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
