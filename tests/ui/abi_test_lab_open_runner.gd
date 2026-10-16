extends SceneTree

## Smoke: ABI Lab opens from Arena and does not mutate persistent resources.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		print("ABI_LAB_UI_TEST=FAIL missing scene")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_open_panel", "Арена")
	await process_frame
	var arena := main.get_node_or_null("ArenaScreen") as ArenaScreen
	if arena == null or arena.combat_session == null or arena.abi_lab_dialog == null:
		print("ABI_LAB_UI_TEST=FAIL lab dialog not attached")
		quit(1)
		return
	var character := main.get("player_character") as CharacterState
	if character == null:
		print("ABI_LAB_UI_TEST=FAIL missing player")
		quit(1)
		return
	var current_hp := character.current_hp
	var current_mana := character.current_mana
	var fighter := arena.combat_session.fighter(true)
	var arena_hp := fighter.hp
	var arena_mana := fighter.mana
	arena._open_abi_test_lab()
	await process_frame
	var dialog: AbiTestLabDialog = arena.abi_lab_dialog
	var ok := dialog.visible and dialog.session != null
	dialog._next_round(true)
	ok = ok and dialog.session != null and dialog.session.state.round_number == 1
	ok = ok and dialog.output.text.contains("Раунд 1")
	ok = ok and character.current_hp == current_hp and character.current_mana == current_mana
	ok = ok and fighter.hp == arena_hp and fighter.mana == arena_mana
	ok = ok and arena.combat_session.state.round_number == 0
	print("ABI_LAB_UI_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
