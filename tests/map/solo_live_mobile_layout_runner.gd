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
	var hex := page.get("hex_canvas") as DebugMapCanvas
	var round_button := page.get("round_button") as Button
	var panel := page.get("combat_panel") as VBoxContainer
	var log_label := page.get("combat_log_label") as Label
	var attack_row := page.get("attack_zone_row") as VBoxContainer
	var block_row := page.get("block_zone_row") as GridContainer
	var ability := page.get("ability_selector") as OptionButton
	var elixir := page.get("elixir_selector") as OptionButton
	check(scroller != null and hex != null and hex.get_parent()==scroller,"map_has_horizontal_scroll_container")
	if scroller != null:
		check(scroller.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"horizontal_scroll_enabled")
		check(scroller.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,"map_viewport_scrolls_both_axes")
	check(round_button != null and panel != null and round_button.get_parent()==panel,"primary_button_in_combat_panel")
	if round_button != null and log_label != null:
		check(round_button.get_index() < log_label.get_index(),"primary_action_precedes_long_log")
		check(round_button.custom_minimum_size.y>=48,"primary_action_mobile_height")
	if ability != null and elixir != null:
		check(ability.custom_minimum_size.y>=44 and elixir.custom_minimum_size.y>=44,"ability_and_elixir_touch_targets")
	var hero_bar := page.get("hero_hp_bar") as ProgressBar
	var hero_effect_row := page.get("hero_effect_row") as HFlowContainer
	var enemy_rows := page.get("enemy_hp_rows") as VBoxContainer
	check(hero_bar != null and hero_effect_row != null and enemy_rows != null,"live_combat_vitals_widgets_exist")
	if hero_bar != null and hero_effect_row != null and enemy_rows != null:
		page.call("_update_combat_hp_bars",{
			"name":"Hero","hp":37,"max_hp":100,
			"effects":[{"id":"BUFF01","name":"Guard","polarity":"BUFF","stacks":2,"remaining_rounds":3}]
		},[
			{"name":"Bandit A","hp":18,"max_hp":80,"effects":[{"id":"EFF02","name":"Poison","polarity":"DEBUFF","stacks":1,"remaining_rounds":2}]},
			{"name":"Bandit B","hp":0,"max_hp":60,"effects":[]}
		])
		check(int(hero_bar.value)==37 and int(hero_bar.max_value)==100,"hero_bar_uses_canonical_values")
		check(hero_effect_row.get_child_count()==1 and "Guard" in String(hero_effect_row.get_child(0).text),"hero_buff_renders_under_hp")
		check(enemy_rows.get_child_count()==2,"each_npc_has_own_panel")
		if enemy_rows.get_child_count()==2:
			var one := enemy_rows.get_child(0) as VBoxContainer
			var two := enemy_rows.get_child(1) as VBoxContainer
			var first := one.get_child(1) as ProgressBar
			var second := two.get_child(1) as ProgressBar
			var enemy_effects := one.get_child(2) as HFlowContainer
			check(first != null and second != null and int(first.value)==18 and int(first.max_value)==80 and int(second.value)==0,"npc_hp_values_and_zero_visible")
			check(enemy_effects != null and enemy_effects.get_child_count()==1 and "Poison" in String(enemy_effects.get_child(0).text),"enemy_debuff_renders_under_hp")
		var many: Array = []
		for i in range(11):
			many.append({"id":"EFF"+str(i),"name":"Effect "+str(i),"polarity":"DEBUFF","stacks":1,"remaining_rounds":2})
		page.call("_set_effect_chips",hero_effect_row,many)
		check(hero_effect_row.get_child_count()==9 and hero_effect_row.get_child(8).text=="+3","effects_overflow_is_collapsed")
		page.call("_update_combat_hp_bars",{"name":"Hero","hp":150,"max_hp":100,"effects":[]},[])
		check(int(hero_bar.value)==100 and enemy_rows.get_child_count()==0 and hero_effect_row.get_child_count()==0,"refresh_clears_stale_effects_and_enemies")
	var gear := page.get("equipment_grid") as GridContainer
	check(gear != null and gear.columns==5,"ten_slot_equipment_grid_exists")
	if gear != null:
		var slots: Array = []
		for name in ["head","chest","hands","waist","legs","main_hand","off_hand","ring1","ring2","feet"]:
			slots.append({"slot":name,"instance_id":"","name":"","active":false})
		slots[0] = {"slot":"head","instance_id":"test_helmet","name":"Actual Helmet","active":true}
		slots[5] = {"slot":"main_hand","instance_id":"test_sword","name":"Actual Sword","active":false}
		page.call("_update_equipment_grid",slots)
		check(gear.get_child_count()==10,"all_ten_equipment_slots_render")
		if gear.get_child_count()==10:
			var helm := gear.get_child(0) as Button
			var sword := gear.get_child(5) as Button
			check(helm.disabled and "Actual Helmet" in helm.tooltip_text,"equipment_identity_from_snapshot")
			check(sword.disabled and "неактивно" in sword.tooltip_text,"inactive_equipment_not_shown_as_active")
		slots[0] = {"slot":"head","instance_id":"","name":"","active":false}
		page.call("_update_equipment_grid",slots)
		check(gear.get_child_count()==10 and "Пусто" in String(gear.get_child(0).tooltip_text),"unequipped_slot_clears_on_refresh")
	check(attack_row != null and block_row != null,"attack_and_defense_rows_preserved")
	check(hex != null and hex.HEX_SIZE >= 20.0,"canonical_hex_renderer_reused")
	var minimap := page.get("mini_map") as DebugMiniMap
	var stop := page.get("route_stop_button") as Button
	var route_info := page.get("route_label") as Label
	check(minimap != null and route_info != null and stop != null,"minimap_and_route_controls_present")
	var panel := page.get("map_panel") as Control
	check(panel != null and scroller != null and scroller.get_parent()==panel,"map_scroller_clipped_to_approved_viewport")
	check(panel != null and minimap != null and minimap.get_parent()==panel,"minimap_overlaid_on_hex_viewport")
	if minimap != null:
		check(minimap.offset_right-minimap.offset_left==155.0 and minimap.offset_bottom-minimap.offset_top==155.0,"minimap_square_155px")
	var upgrade := page.get("legacy_upgrade_button") as Button
	check(upgrade != null and upgrade.text.contains("20×20"),"explicit_legacy_upgrade_action")
	check(stop != null and stop.disabled,"stop_disabled_until_route_starts")
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
