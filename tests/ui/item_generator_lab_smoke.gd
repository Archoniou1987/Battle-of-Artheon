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
	print("ITEM_GENERATOR_LAB_UI=", "PASS" if failed.is_empty() else "FAIL")
	print(JSON.stringify({"tabs":screen.tab.get_tab_count(), "items":screen.result_rows.size(), "failures":failed}))
	quit(0 if failed.is_empty() else 1)
