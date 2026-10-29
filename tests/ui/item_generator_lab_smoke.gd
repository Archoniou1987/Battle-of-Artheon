extends SceneTree

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var scene: PackedScene = load("res://scenes/debug/item_generator_lab.tscn")
	if scene == null:
		print("ITEM_GENERATOR_LAB_UI=FAIL: scene missing")
		quit(1)
		return
	var screen: ItemGeneratorLabScreen = scene.instantiate() as ItemGeneratorLabScreen
	root.add_child(screen)
	await process_frame
	await process_frame
	var failed: Array[String] = []
	if screen.tab.get_tab_count() != 4:
		failed.append("Expected four tabs")
	if screen.par_weights.has("GRP011"):
		failed.append("GRP should not be exposed as archetype weight")
	if not screen.par_weights.has("PAR033"):
		failed.append("Mobile archetype missing crit")
	if screen.result_rows.is_empty() or screen.result_box.get_child_count() < 2:
		failed.append("Unique template results absent")
	if screen.result_rows.size() > 100:
		failed.append("Unique templates exceeded request")
	for r in screen.result_rows:
		if not String(r["item_type"]).contains("Топор 2H"):
			failed.append("Type filter ignored")
		if (r["variants"] as Array).is_empty() or (r["variants"] as Array).size() > 4:
			failed.append("Invalid rarity line count")
	if screen.tab.current_tab != 3:
		failed.append("Results tab not shown")
	if screen.csv_button == null or screen.csv_button.disabled:
		failed.append("CSV export must be enabled after a successful generation")
	var saved_config: Dictionary = screen.last_generation_config.duplicate(true)
	screen.par_weights["PAR033"] = 999.0
	if screen.last_generation_config != saved_config:
		failed.append("CSV must capture the generation snapshot, not live edits")
	var csv := ItemLabCsvExporter.build(screen.last_generation_config, screen.last_generation_output, screen.engine)
	if not csv.contains("PAR_EFFECTIVE") or not csv.contains("ITEM"):
		failed.append("CSV export data missing settings or generated items")

	screen.mode_picker.select(1)
	screen._run_test()
	if screen.result_rows.size() != 100:
		failed.append("100 generated items not shown")
	screen.par_search.text = "PAR033"
	screen._filter_pars()
	if screen.par_list.item_count != 1:
		failed.append("PAR search failed")
	screen.tab.current_tab = 1
	# Real controls must save/load all edit states, not just render them.
	screen.par_weights["PAR033"] = 84.0
	screen.par_settings["PAR033"] = {"rating100_lv1":12.0,"max":5100.0}
	screen.preview_level_spin.value = 30.0
	screen.archetype_name.text = "Mobile test saved"
	screen._save_profile()
	screen.par_weights.clear()
	screen.par_settings.clear()
	screen.preview_level_spin.value = 5.0
	screen._load_profile()
	if not is_equal_approx(float(screen.par_weights.get("PAR033",0)),84.0):
		failed.append("Archetype weight did not persist")
	if not is_equal_approx(float((screen.par_settings.get("PAR033",{}) as Dictionary).get("max",0)),5100.0):
		failed.append("PAR max did not persist")
	if int(screen.preview_level_spin.value) != 30:
		failed.append("PAR comparison level did not persist")
	if screen.archetype_name.text != "Mobile test saved":
		failed.append("Archetype name did not persist")
	if not screen.engine.registry.has("PAR033"):
		failed.append("Local PAR registry missing")
	# Touch-safe number entry: field opens an in-game keypad on Web Preview.
	var value_button := screen.preview_level_spin.get_meta("lab_numeric_button", null) as Button
	if value_button == null:
		failed.append("Numeric field has no keypad touch target")
	else:
		value_button.pressed.emit()
		if not screen.numeric_keypad.visible:
			failed.append("Numeric keypad did not open")
		screen.numeric_keypad._key("4")
		screen.numeric_keypad._key("2")
		if not screen.numeric_keypad.apply_value() or int(screen.preview_level_spin.value) != 42:
			failed.append("Integer keypad did not update PAR preview level")
		if screen.numeric_keypad.visible:
			failed.append("Numeric keypad did not close after apply")
	var bonus_spin: SpinBox = screen.controls["bonus_scale"] as SpinBox
	screen.numeric_keypad.open_for(bonus_spin,"Bonus scale")
	screen.numeric_keypad._key("1")
	screen.numeric_keypad._key(".")
	screen.numeric_keypad._key("7")
	if not screen.numeric_keypad.apply_value() or not is_equal_approx(bonus_spin.value,1.7):
		failed.append("Decimal keypad did not apply to bonus scale")
	var weight_edit_found := false
	for child in screen.par_rows.get_children():
		for nested in child.get_children():
			if nested is SpinBox:
				var weight_spin := nested as SpinBox
				if weight_spin.has_meta("lab_numeric_button"):
					weight_edit_found = true
	if not weight_edit_found:
		failed.append("Archetype weights are not editable by keypad")
	var crit_preset: Button = null
	for candidate in screen.find_children("*", "Button", true, false):
		if candidate.text == "Крит":
			crit_preset = candidate as Button
			break
	if crit_preset == null:
		failed.append("Simple crit archetype button missing")
	else:
		crit_preset.pressed.emit()
		if screen.par_weights.size() != 1 or not is_equal_approx(float(screen.par_weights.get("PAR033",0)),100.0):
			failed.append("Simple single-PAR archetype not applied")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ItemBalanceWorkbench.PROFILE_PATH))
	print("ITEM_GENERATOR_LAB_UI=", "PASS" if failed.is_empty() else "FAIL")
	print(JSON.stringify({"tabs":screen.tab.get_tab_count(), "items":screen.result_rows.size(), "failures":failed}))
	quit(0 if failed.is_empty() else 1)
