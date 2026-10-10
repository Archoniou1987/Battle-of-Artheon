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
	game.call("_open_panel", "Инвентарь")
	await _settle()
	_save("inventory-portrait.png")

	root.size = Vector2i(844, 390)
	await _settle()
	_save("inventory-landscape.png")

	game.call("_open_panel", "Персонаж")
	root.size = Vector2i(390, 844)
	await _settle()
	_save("character-portrait.png")
	print("Visual preview capture: PASS")
	quit(0)

func _settle() -> void:
	for i in range(5):
		await process_frame

func _save(file_name: String) -> void:
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	var error := image.save_png("res://visual-preview/" + file_name)
	assert(error == OK)
