extends SceneTree

## Runs with a display (xvfb-run), not --headless.
## Saves actual Godot-rendered UI frames for manual visual review.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://visual-preview"))
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	assert(packed != null)
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame

	root.size = Vector2i(390, 844)
	DisplayServer.window_set_size(Vector2i(390, 844))
	game.call("_open_panel", "Инвентарь")
	_seed_preview_items(game)
	await _settle()
	_save("inventory-portrait.png")
	var inventory := game.get_node("InventoryScreen") as InventoryScreen
	inventory.call("_select_item", "preview_0")
	await _settle()
	_save("inventory-item-details.png")
	inventory.detail_dialog.visible = false

	root.size = Vector2i(844, 390)
	DisplayServer.window_set_size(Vector2i(844, 390))
	await _settle()
	_save("inventory-landscape.png")

	game.call("_open_panel", "Персонаж")
	root.size = Vector2i(390, 844)
	DisplayServer.window_set_size(Vector2i(390, 844))
	await _settle()
	_save("character-portrait.png")
	assert((game.get_node("CharacterScreen") as CharacterScreen).combat_section != null)
	print("Visual preview capture: PASS")
	quit(0)

func _seed_preview_items(game: Node) -> void:
	var inventory := game.get_node_or_null("InventoryScreen") as InventoryScreen
	assert(inventory != null)
	var names := ["Клинок путника", "Кожаная броня", "Кольцо зоркости", "Посох ученика", "Сапоги", "Оберег", "Шлем", "Перчатки"]
	var rarities := ["grey", "green", "blue", "purple", "grey", "green", "blue", "orange"]
	for i in range(names.size()):
		var item := {
			"instance_id": "preview_%d" % i,
			"name": names[i],
			"rarity": rarities[i],
			"type": "preview",
			"item_level": 1,
			"equip_slots": ["main_hand"] if i == 0 else [],
			"guaranteed_stats": {"STR": 1} if i == 0 else {},
			"requirements": {},
			"description": "Тестовый предмет для проверки отображения интерфейса."
		}
		ItemDurabilityService.initialize_item(item, 100)
		assert(inventory.repository.add_item(item))
		assert(inventory.character.inventory.add_instance(item["instance_id"], inventory.repository))
	inventory.refresh()


func _settle() -> void:
	for i in range(5):
		await process_frame

func _save(file_name: String) -> void:
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.get_width() == root.size.x and image.get_height() == root.size.y)
	var error := image.save_png("res://visual-preview/" + file_name)
	assert(error == OK)
