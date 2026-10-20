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
	var head := inventory.slot_buttons.get("head", null) as ItemIcon
	check(head != null, "head_button_exists")
	if head != null:
		var hover := head.get_node_or_null(SquareSlotFeedback.HOVER_OVERLAY) as Control
		check(hover != null, "head_hover_overlay")
		check(hover != null and hover.mouse_filter==Control.MOUSE_FILTER_IGNORE, "overlay_not_clickable")
		check(head.tooltip_text.contains("пусто"), "empty_slot_hover_hint")
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
