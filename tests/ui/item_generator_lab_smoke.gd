extends SceneTree

func _init() -> void:
	call_deferred("_test")

func _test() -> void:
	var scene: PackedScene = load("res://scenes/debug/item_generator_lab.tscn")
	if scene == null:
		print("ITEM_GENERATOR_LAB_UI=FAIL: scene missing")
		quit(1)
		return
	var screen := scene.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var grid: GridContainer = screen.card_grid
	var ok := screen.result_items.size() == 100 and grid != null and grid.get_child_count() == 100
	if ok:
		screen.mode_select.select(1)
		screen._generate()
		ok = screen.result_items.size() == 100 and grid.get_child_count() == 100
	print("ITEM_GENERATOR_LAB_UI=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
