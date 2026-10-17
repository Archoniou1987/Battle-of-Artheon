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
	var ok: bool = dialog.visible and dialog.session != null
	# Regression: tabs own the scrolling; casting buttons stay outside scroll.
	ok = ok and dialog.pages != null and dialog.pages.get_tab_count() == 3
	ok = ok and dialog.pages.get_tab_title(0) == "Способность"
	ok = ok and dialog.pages.get_tab_title(1) == "PAR"
	ok = ok and dialog.pages.get_tab_title(2) == "Результаты"
	ok = ok and dialog.action_toolbar.get_parent() == dialog.pages.get_parent()
	ok = ok and dialog.reset_button.is_visible_in_tree()
	ok = ok and dialog.cast_button.is_visible_in_tree()
	ok = ok and dialog.skip_button.is_visible_in_tree()
	ok = ok and not dialog.custom_name_row.visible and not dialog.type_row.visible
	ok = ok and not dialog.mana_row.visible and not dialog.cooldown_row.visible
	ok = ok and dialog.ability_scroll != null and dialog.par_scroll != null
	# The dialog stays bounded even when the test is opened in a 720px viewport.
	var viewport_height := dialog.get_viewport().get_visible_rect().size.y
	ok = ok and float(dialog.size.y) <= viewport_height * 0.98
	# Switching presets exposes only the extra options that can be edited.
	dialog.preset_select.select(1)
	dialog._preset_changed(1)
	ok = ok and dialog.custom_name_row.visible and dialog.type_row.visible
	ok = ok and dialog.mana_row.visible and dialog.cooldown_row.visible
	ok = ok and dialog.type_select.item_count == 4
	dialog.preset_select.select(0)
	dialog._preset_changed(0)
	dialog._reset_session()
	ok = ok and dialog.pages.current_tab == 0
	dialog._next_round(true)
	ok = ok and dialog.session != null and dialog.session.state.round_number == 1
	ok = ok and dialog.pages.current_tab == 2
	ok = ok and dialog.output.text.contains("Раунд 1")
	ok = ok and dialog.status_label.text.contains("Раунд 1")
	ok = ok and dialog.action_toolbar.visible and dialog.cast_button.visible
	ok = ok and character.current_hp == current_hp and character.current_mana == current_mana
	ok = ok and fighter.hp == arena_hp and fighter.mana == arena_mana
	ok = ok and arena.combat_session.state.round_number == 0
	print("ABI_LAB_UI_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
