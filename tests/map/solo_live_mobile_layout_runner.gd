extends SceneTree

## Mobile layout smoke test for the LIVE Solo map script. This deliberately
## avoids a fake combat engine or changes to gameplay state.
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("SOLO_MOBILE_LAYOUT_CASE=FAIL ",label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main/solo_live_map.tscn") as PackedScene
	check(scene != null,"solo_scene_loads")
	if scene == null:
		quit(1)
		return
	var page := scene.instantiate() as Control
	check(page != null,"solo_scene_instantiates")
	if page == null:
		quit(1)
		return
	root.add_child(page)
	var scroller := page.get("map_scroller") as ScrollContainer
	var grid := page.get("tile_container") as GridContainer
	var round_button := page.get("round_button") as Button
	var panel := page.get("combat_panel") as VBoxContainer
	var log_label := page.get("combat_log_label") as Label
	var attack_row := page.get("attack_zone_row") as VBoxContainer
	var block_row := page.get("block_zone_row") as GridContainer
	var ability := page.get("ability_selector") as OptionButton
	var elixir := page.get("elixir_selector") as OptionButton
	check(scroller != null and grid != null and grid.get_parent()==scroller,"map_has_horizontal_scroll_container")
	if scroller != null:
		check(scroller.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"horizontal_scroll_enabled")
		check(scroller.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"map_keeps_parent_vertical_scroll")
	check(round_button != null and panel != null and round_button.get_parent()==panel,"primary_button_in_combat_panel")
	if round_button != null and log_label != null:
		check(round_button.get_index() < log_label.get_index(),"primary_action_precedes_long_log")
		check(round_button.custom_minimum_size.y>=48,"primary_action_mobile_height")
	if ability != null and elixir != null:
		check(ability.custom_minimum_size.y>=44 and elixir.custom_minimum_size.y>=44,"ability_and_elixir_touch_targets")
	check(attack_row != null and block_row != null,"attack_and_defense_rows_preserved")
	check(grid != null and grid.columns==SoloLiveMapSession.WIDTH,"canonical_map_width_preserved")
	# Exercise the real scene's selection handler without a fabricated
	# combat engine. Capacity is exactly two zones for this UI fixture.
	if block_row != null:
		page.set("active_block_capacity",2)
		var checks: Array[CheckBox] = []
		for i in range(5):
			var cb := CheckBox.new()
			cb.button_pressed = i < 2
			block_row.add_child(cb)
			checks.append(cb)
		page.set("block_controls",checks)
		checks[2].button_pressed = true
		page.call("_on_block_zone_toggled",true,2)
		var count := 0
		for cb in checks:
			if cb.button_pressed:
				count += 1
		check(count==2 and checks[2].button_pressed,"new_block_zone_replaces_old_at_capacity")
		checks[2].button_pressed = false
		page.call("_on_block_zone_toggled",false,2)
		check(checks[2].button_pressed,"cannot_submit_fewer_than_block_capacity")
		checks[3].button_pressed = true
		page.call("_on_block_zone_toggled",true,3)
		count = 0
		for cb in checks:
			if cb.button_pressed:
				count += 1
		check(count==2 and checks[3].button_pressed,"repeated_block_changes_keep_exact_capacity")
	page.queue_free()
	print("SOLO_MOBILE_LAYOUT_TEST=", "PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)
