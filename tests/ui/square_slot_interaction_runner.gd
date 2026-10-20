extends SceneTree

## Visual/interaction contract, separate from combat correctness:
## fixed square scaling, system ABI strip, hover/press feedback and empty slots.
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("SQUARE_SLOT_UI: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Control.new()
	var canvas := Control.new()
	root.add_child(host)
	host.add_child(canvas)
	for edge in [320.0, 480.0, 600.0]:
		SquareUiGeometry.fit(host, canvas, edge)
		check(is_equal_approx(host.size.x, host.size.y), "square_edge_" + str(edge))
		check(canvas.size == Vector2(480.0,480.0), "logical_480_" + str(edge))
		check(is_equal_approx(canvas.scale.x, canvas.scale.y), "uniform_scale_" + str(edge))
		check(is_equal_approx(canvas.size.x * canvas.scale.x, edge), "fitted_extent_" + str(edge))
	host.queue_free()
	var hero := CharacterState.new("SQUARE_UI_HERO", "UI Hero", 5)
	var repository := ItemRepository.new()
	var inventory := InventoryScreen.new(hero, repository)
	root.add_child(inventory)
	await process_frame
	check(inventory.slot_buttons.size()==14, "inventory_equipment_slots")
	check(inventory.visual_lab_dialog != null and inventory.visual_lab_theme.item_count == 3, "visual_lab_three_themes")
	check(inventory.visual_lab_frames.button_pressed and not inventory.visual_lab_ghosts.button_pressed, "visual_lab_default_frame_only")
	inventory._visual_lab_theme_changed(1)
	check(inventory.visual_lab_theme_index == 1 and inventory.equipment_background.modulate == Color("#e8c99d"), "visual_lab_bronze_theme")
	inventory._visual_lab_frames_changed(false)
	check((inventory.slot_buttons["head"] as ItemIcon).get_theme_stylebox("normal").border_width_left == 0, "visual_lab_hide_empty_frame")
	inventory._visual_lab_ghosts_changed(true)
	check((inventory.slot_buttons["head"] as ItemIcon).show_empty_placeholder_icon, "visual_lab_toggle_ghosts")
	inventory._visual_lab_background_changed(0.5)
	check(is_equal_approx(inventory.equipment_background.modulate.a, 0.5), "visual_lab_backdrop_strength")
	inventory._visual_lab_scenario_changed(2)
	check(inventory.visual_lab_scenario_index == 2, "visual_lab_full_equipment_scenario")
	check((inventory.slot_buttons["head"] as ItemIcon).has_node(VisualLabPreview.OVERLAY), "visual_lab_mock_overlay_isolated")
	inventory._visual_lab_scale_changed(0.85)
	inventory._visual_lab_shift_changed(12.0)
	var inventory_middle := inventory.equipment_content.get_node("EquipmentMiddle") as Control
	check(is_equal_approx(inventory_middle.scale.x, 0.9025 * 0.85), "visual_lab_equipment_scale")
	check(is_equal_approx(inventory_middle.position.x, 35.0), "visual_lab_equipment_shift")
	inventory._reset_visual_lab()
	check(inventory.visual_lab_theme_index == 0 and not (inventory.slot_buttons["head"] as ItemIcon).show_empty_placeholder_icon, "visual_lab_reset_without_save")

	var head := inventory.slot_buttons.get("head", null) as ItemIcon
	check(head != null, "head_button_exists")
	if head != null:
		var hover := head.get_node_or_null(SquareSlotFeedback.HOVER_OVERLAY) as Control
		check(hover != null, "head_hover_overlay")
		check(hover != null and hover.mouse_filter==Control.MOUSE_FILTER_IGNORE, "overlay_not_clickable")
		check(head.tooltip_text.contains("пусто"), "empty_slot_hover_hint")
		check(not head.show_empty_placeholder_icon and not head._empty_background.visible and not head._slot_background.visible, "inventory_ghost_icons_hidden")
		var empty_frame := head.get_theme_stylebox("normal") as StyleBoxFlat
		check(empty_frame != null and empty_frame.border_width_left == 2, "empty_inventory_frame_visible")
		check(not inventory.elixir_buttons[0].show_empty_placeholder_icon and not inventory.elixir_buttons[0]._empty_background.visible, "empty_inventory_elixir_icon_hidden")
		# The final artwork can take over the entire empty-slot baseline
		# without removing the input target or the independent item border.
		head.set_empty_art_in_background(true)
		check(not head._empty_background.visible and not head._slot_background.visible, "baked_empty_art_hides_individual_sprites")
		check(head.tooltip_text.contains("пусто"), "baked_slot_keeps_semantics")
		head.set_item({"instance_id":"TEST_ICON","name":"Test Helmet","rarity":"purple"}, "Голова")
		var rarity_box := head.get_theme_stylebox("normal") as StyleBoxFlat
		check(rarity_box != null and rarity_box.border_width_left > 0 and rarity_box.border_color == Color(ItemIcon.RARITY_COLORS["purple"]), "rarity_border_only_on_item")
		head.set_item({}, "Голова")
		head.set_empty_art_in_background(false)
		if hover != null:
			head.button_down.emit()
			check(hover.modulate.a >= 0.85, "press_feedback_is_immediate")
			await create_timer(0.08).timeout
			check(hover.modulate.a > 0.2, "press_has_visible_feedback")
			head.button_up.emit()
		inventory._select_slot("head")
		check(inventory.empty_slot_info != null and inventory.empty_slot_info.visible, "empty_slot_tap_opens_info")
		check(inventory.empty_slot_info.dialog_text.contains("Шлем") and inventory.empty_slot_info.dialog_text.contains("пусто"), "empty_slot_info_content")
		inventory.empty_slot_info.hide()
	inventory.queue_free()
	await process_frame

	var arena := ArenaScreen.new(hero,repository)
	root.add_child(arena)
	await process_frame
	check(arena.ability_buttons.size()==5,"five_permanent_abi_buttons")
	check(arena.visual_lab_dialog != null and arena.visual_lab_theme.item_count == 3, "arena_visual_lab_available")
	arena.visual_lab_theme_index = 2
	arena.visual_lab_scenario_index = 1
	arena._apply_visual_lab()
	check(arena.arena_background.modulate == Color("#b7c3d4"), "arena_visual_lab_steel_theme")
	var arena_head := arena.player_slots["head"] as ItemIcon
	var arena_empty_style := arena_head.get_theme_stylebox("normal") as StyleBoxFlat
	check(arena_empty_style.border_color == Color("#9aabb8"), "arena_visual_lab_empty_slot_border")
	var abi_style := arena.ability_buttons[0].get_theme_stylebox("normal") as StyleBoxFlat
	check(abi_style.border_color == Color("#9aabb8"), "arena_visual_lab_abi_border")
	var elixir_style := arena.player_elixir_slots[0].get_theme_stylebox("normal") as StyleBoxFlat
	check(elixir_style.border_color == Color("#9aabb8"), "arena_visual_lab_elixir_border")
	var selection := arena.defense_buttons[0].get_node("SelectionOutline") as Panel
	var selection_style := selection.get_theme_stylebox("panel") as StyleBoxFlat
	check(selection_style.border_color == Color("#9aabb8"), "arena_visual_lab_zone_outline")
	check(arena.defense_buttons[0].get_theme_stylebox("normal") is StyleBoxTexture, "arena_visual_lab_zone_icon_preserved")
	arena._reset_visual_lab()
	check(arena.visual_lab_theme_index == 0 and arena.visual_lab_scenario_index == 0, "arena_visual_lab_reset")
	check((arena.ability_buttons[0].get_theme_stylebox("normal") as StyleBoxFlat).border_color == Color("#83b8d9"), "arena_visual_lab_abi_reset_border")

	var empty_arena_head := arena.player_slots.get("head", null) as ItemIcon
	check(empty_arena_head != null and not empty_arena_head.show_empty_placeholder_icon and not empty_arena_head._empty_background.visible, "empty_arena_equipment_icon_hidden")
	check(arena.player_elixir_slots[0].get_theme_stylebox("normal") is StyleBoxFlat, "arena_elixir_frame_without_icon_atlas")
	for index in range(arena.ability_buttons.size()):
		var button := arena.ability_buttons[index]
		check(button.get_theme_stylebox("normal") is StyleBoxFlat, "system_square_abi_" + str(index))
		check(button.get_node_or_null(SquareSlotFeedback.HOVER_OVERLAY) != null, "tactile_abi_" + str(index))
		check(button.tooltip_text.contains(SquareUiGeometry.abi_source(index)), "abi_source_" + str(index))
	check(arena.ability_buttons[3].tooltip_text.contains("Нагрудная броня"), "abi4_chest")
	check(arena.ability_buttons[4].tooltip_text.contains("Шлем"), "abi5_helmet")
	var row := arena.square_content.get_node_or_null("AbilitySlots") as HBoxContainer
	check(row != null and row.get_theme_constant("separation")==0, "abi_strip_no_gaps")
	SquareSlotFeedback.set_selected(arena.ability_buttons[0],true)
	var selected := arena.ability_buttons[0].get_node_or_null(SquareSlotFeedback.SELECTION_OVERLAY) as Control
	check(selected != null and selected.visible, "selected_overlay")
	SquareSlotFeedback.set_selected(arena.ability_buttons[0],false)
	check(selected != null and not selected.visible, "selection_can_clear")
	check(arena.player_elixir_slots.size()==4 and arena.player_elixir_slots[0].has_node(SquareSlotFeedback.HOVER_OVERLAY), "elixir_feedback")
	check(arena.round_button_art != null and arena.round_button_art.texture != null, "end_turn_art_preserved")
	arena.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("SQUARE_SLOT_UI_TEST=","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
