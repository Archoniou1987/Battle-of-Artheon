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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ItemBalanceWorkbench.PROFILE_PATH))
	print("ITEM_GENERATOR_LAB_UI=", "PASS" if failed.is_empty() else "FAIL")
	print(JSON.stringify({"tabs":screen.tab.get_tab_count(), "items":screen.result_rows.size(), "failures":failed}))
	quit(0 if failed.is_empty() else 1)
