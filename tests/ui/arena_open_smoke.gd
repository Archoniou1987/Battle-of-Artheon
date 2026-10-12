extends SceneTree

# Regression: opening the Arena from the village must construct a visible screen.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: main scene missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_open_panel", "Арена")
	await process_frame
	var arena := main.get_node_or_null("ArenaScreen") as ArenaScreen
	if arena == null or not arena.visible or arena.square_content == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: arena was not opened")
		quit(1)
		return
	if arena.player_slots.size() != 14 or arena.enemy_slots.size() != 14:
		push_error("ARENA_OPEN_SMOKE=FAIL: equipment slots missing")
		quit(1)
		return
	print("ARENA_OPEN_SMOKE=PASS")
	quit(0)
