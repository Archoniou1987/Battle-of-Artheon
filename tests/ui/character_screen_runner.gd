extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main/main.tscn") as PackedScene
	assert(scene != null)
	var instance := scene.instantiate()
	root.add_child(instance)
	await process_frame
	instance.call("_open_panel", "Персонаж")
	await process_frame
	var screen := instance.get_node_or_null("CharacterScreen") as CharacterScreen
	assert(screen != null and screen.visible)
	assert(screen.character != null)
	assert(screen.combat_section != null)
	assert(screen.resistance_section != null)
	assert(screen.combat_section.get_child_count() >= 4)
	assert(screen.resistance_section.get_child_count() >= 3)
	assert(screen.character.progression.level == 1)
	assert(screen.xp_label.text.contains("900"))
	assert(screen.character.award_xp(900) == 1)
	screen.refresh()
	assert(screen.xp_label.text.contains("Уровень 2"))
	var before := int(screen.character.progression.base_stats["STR"])
	screen.call("_allocate", "STR")
	assert(int(screen.character.progression.base_stats["STR"]) == before + 1)
	assert(screen.character.progression.unspent_stat_points == 0)
	screen.back_button.pressed.emit()
	assert(not screen.visible)
	instance.call("_open_panel", "Инвентарь")
	await process_frame
	var inventory := instance.get_node_or_null("InventoryScreen") as InventoryScreen
	assert(inventory != null and inventory.visible)
	assert(inventory.slot_buttons.size() == 14)
	for slot in inventory.slot_buttons:
		var equipment_icon := inventory.slot_buttons[slot] as ItemIcon
		assert(equipment_icon != null)
		assert(equipment_icon.custom_minimum_size == Vector2(ItemIcon.CELL_SIZE, ItemIcon.CELL_SIZE))
	assert(inventory.bag_grid.get_child_count() == 0)
	assert(inventory.character_portrait != null)
	assert(inventory.character_portrait.get_parent().name == "EquipmentMiddle")
	assert(inventory.bag_title.text == "Сумка (0)")
	assert(inventory.bag_scroll != null)
	inventory.size = Vector2(360, 740)
	inventory.call("_apply_layout")
	assert(inventory.layout_row.vertical)
	assert(inventory.bag_grid.columns == 4)
	inventory.size = Vector2(900, 500)
	inventory.call("_apply_layout")
	assert(not inventory.layout_row.vertical)
	assert(inventory.bag_grid.columns == 6)
	assert(inventory.slot_buttons.size() == 14)
	assert(inventory.detail_dialog.actions != null)
	assert(inventory.detail_dialog.scroll != null)
	var sample := {"instance_id": "icon_smoke", "name": "Клинок", "rarity": "blue", "equip_slots": ["main_hand"]}
	ItemDurabilityService.initialize_item(sample, 100)
	assert(inventory.repository.add_item(sample))
	assert(inventory.character.inventory.add_instance("icon_smoke", inventory.repository))
	inventory.refresh()
	assert(inventory.bag_grid.get_child_count() == 1)
	var bag_icon := inventory.bag_grid.get_child(0) as ItemIcon
	assert(bag_icon != null)
	assert(bag_icon.custom_minimum_size == (inventory.slot_buttons["main_hand"] as ItemIcon).custom_minimum_size)
	assert(bag_icon.instance_id == "icon_smoke")
	inventory.back_button.pressed.emit()
	assert(not inventory.visible)
	print("Character and inventory screen UI smoke: PASS")
	quit(0)
