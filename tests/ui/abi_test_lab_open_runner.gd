extends SceneTree

## Smoke: ABI Lab opens from Arena and does not mutate persistent resources.
## Report each invariant separately: a single aggregate FAIL obscures regressions.
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("ABI_LAB_UI_CHECK_FAIL: ", label)

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
	check(dialog.visible, "popup becomes visible")
	check(dialog.session != null, "initial isolated session created")
	# Regression: tabs own the scrolling; action controls stay OUTSIDE scroll.
	check(dialog.pages != null, "tab container exists")
	if dialog.pages != null:
		check(dialog.pages.get_tab_count() == 3, "three tab pages")
		check(dialog.pages.get_tab_title(0) == "Способность", "ability tab title")
		check(dialog.pages.get_tab_title(1) == "PAR", "PAR tab title")
		check(dialog.pages.get_tab_title(2) == "Результаты", "results tab title")
		check(dialog.action_toolbar.get_parent() == dialog.pages.get_parent().get_parent(), "action toolbar in fixed frame outside tab viewport")
	check(dialog.pages.get_parent().clip_contents, "tab viewport clips overflowing tab contents")
	check(dialog.reset_button.is_visible_in_tree(), "reset button visible in tree")
	check(dialog.cast_button.is_visible_in_tree(), "cast button visible in tree")
	check(dialog.skip_button.is_visible_in_tree(), "skip button visible in tree")
	check(not dialog.custom_name_row.visible and not dialog.type_row.visible, "canonical name and type hidden")
	check(not dialog.mana_row.visible and not dialog.cooldown_row.visible, "canonical mana and cooldown hidden")
	check(dialog.ability_scroll != null and dialog.par_scroll != null, "dedicated tab scroll containers")
	# In headless Godot the native test window can resize to a popup's
	# minimum size. A 367px viewport and 367px popup are not an overflow.
	# Guard the actual regression: full form height (~1539px) instead of a
	# compact shell (roughly 367px), with tabs + action toolbar still visible.
	var viewport_height: float = dialog.get_viewport().get_visible_rect().size.y
	var popup_height: float = float(dialog.size.y)
	check(popup_height <= 700.0, "compact popup height=%s viewport=%s" % [str(popup_height), str(viewport_height)])
	check(float(dialog.pages.size.y) <= popup_height * 0.85, "tab pages fit inside popup: pages=%s popup=%s" % [str(dialog.pages.size.y), str(popup_height)])
	check(dialog.action_toolbar.get_global_rect().end.y <= float(dialog.position.y + dialog.size.y) + 2.0, "action toolbar remains within popup bounds")
	# Synthetic presets expose editable fields.
	var physical_index := _preset_index(dialog, "LAB_PHYSICAL")
	check(physical_index >= 0, "physical preset remains available")
	if physical_index >= 0:
		dialog.preset_select.select(physical_index)
		dialog._preset_changed(physical_index)
	check(dialog.custom_name_row.visible and dialog.type_row.visible, "synthetic name and damage type visible")
	check(dialog.mana_row.visible and dialog.cooldown_row.visible, "synthetic mana and cooldown visible")
	check(dialog.type_select.item_count == 4, "physical ABI has exactly four types, got %d" % dialog.type_select.item_count)
	var healing_index := _preset_index(dialog, "ABI004")
	check(healing_index >= 0, "ABI004 healing preset available")
	if healing_index >= 0:
		dialog.preset_select.select(healing_index)
		dialog._preset_changed(healing_index)
		check(dialog.target_row.visible and dialog.initial_hp_row.visible, "healing target and initial HP are visible")
		check(dialog.target_select.item_count == 2, "healing offers exactly ally and self")
		check(not dialog.custom_name_row.visible and not dialog.type_row.visible, "healing uses canonical locked fields")
	var fireball_index := _preset_index(dialog, "ABI003")
	dialog.preset_select.select(fireball_index)
	dialog._preset_changed(fireball_index)
	dialog._reset_session()
	check(dialog.pages.current_tab == 0, "new test starts on ability tab")
	dialog._next_round(true)
	check(dialog.session != null, "session remains after one cast")
	if dialog.session != null:
		check(dialog.session.state.round_number == 1, "one round completed, got %d" % dialog.session.state.round_number)
	check(dialog.pages.current_tab == 2, "cast switches to results tab")
	check(dialog.output.text.contains("Раунд 1"), "results include first round")
	check(dialog.status_label.text.contains("Раунд 1"), "status reports first round")
	check(dialog.action_toolbar.visible and dialog.cast_button.visible, "actions retained after cast")
	check(character.current_hp == current_hp and character.current_mana == current_mana, "persistent character HP and mana unchanged")
	check(fighter.hp == arena_hp and fighter.mana == arena_mana, "ArenaCombatSession HP and mana unchanged")
	check(arena.combat_session.state.round_number == 0, "live Arena round remains zero")
	# A finalized laboratory death must disable UI actions and preserve its log.
	if healing_index >= 0:
		dialog.preset_select.select(healing_index)
		dialog._preset_changed(healing_index)
		(dialog.fields["target_max_hp"] as SpinBox).value = 100
		(dialog.fields["initial_hp"] as SpinBox).value = 100
		(dialog.fields["damage"] as SpinBox).value = 20
		(dialog.fields["incoming_damage"] as SpinBox).value = 70
		(dialog.fields["incoming_hits"] as SpinBox).value = 2
		dialog.order_select.select(1) # heal_first
		dialog._reset_session()
		dialog._next_round(true)
		check(dialog.session.is_finished(), "lethal healing scenario finalizes lab death")
		check(dialog.cast_button.disabled and dialog.skip_button.disabled, "finalized lab death disables both round actions")
		check(dialog.status_label.text.contains("target_dead"), "lab status shows target death")
		check(dialog.output.text.contains("Тест завершён"), "lab output explains scenario completion")
		var completed_rounds := dialog.session.state.round_number
		var recorded := dialog.round_history.size()
		dialog._next_round(true) # programmatic bypass must still be harmless
		check(dialog.session.state.round_number == completed_rounds and dialog.round_history.size() == recorded, "finished lab cannot advance or append rounds")
		var export_snapshot: Variant = JSON.parse_string(dialog._log_json())
		check(export_snapshot is Dictionary and bool(export_snapshot.get("lab_finished", false)) and not bool(export_snapshot.get("active_session", true)), "export marks finished lab inactive")
	print("ABI_LAB_UI_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

static func _preset_index(dialog: AbiTestLabDialog, id: String) -> int:
	for i in range(dialog.preset_select.item_count):
		if String(dialog.preset_select.get_item_metadata(i)) == id:
			return i
	return -1
