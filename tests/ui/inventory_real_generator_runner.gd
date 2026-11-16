extends SceneTree

## Inventory's REAL v1.2 item generator, not the separate menu lab.
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		print("INVENTORY_REAL_GENERATOR=FAIL missing main scene")
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	var screen := game.get_node_or_null("InventoryScreen") as InventoryScreen
	if screen == null:
		print("INVENTORY_REAL_GENERATOR=FAIL missing inventory")
		quit(1)
		return
	if screen.v12_keypad_layer.get_parent() != screen.generator_dialog:
		failures.append("numeric keypad layer must belong to generator Window")
	if screen.v12_keypad.get_parent() != screen.v12_keypad_layer or screen.v12_keypad_layer.layer <= 0:
		failures.append("keypad not on upper dialog canvas layer")
	var found_spear := -1
	for i in range(screen.v12_archetype.item_count):
		if String(screen.v12_archetype.get_item_metadata(i)) == "2H_SPEAR":
			found_spear = i
	if found_spear < 0:
		failures.append("real inventory generator does not offer spear")
	else:
		screen.v12_archetype.select(found_spear)
		screen.v12_archetype.item_selected.emit(found_spear)
		if String(screen.v12_hand.get_selected_metadata()) != "2H":
			failures.append("spear must auto-select both hands")
	var random_button := screen.find_child("InventoryRandomSeedButton",true,false) as Button
	if random_button == null:
		failures.append("random seed button missing from inventory")
	else:
		var old_seed := int(screen.v12_seed.value)
		random_button.pressed.emit()
		var new_seed := int(screen.v12_seed.value)
		if new_seed == old_seed or new_seed < 1 or new_seed > 999999999:
			failures.append("random seed not updated within allowed range")
	screen.generator_dialog.popup_centered()
	await process_frame
	screen.v12_keypad.open_for(screen.v12_seed,"Seed")
	if not screen.v12_keypad.visible:
		failures.append("numeric keypad did not appear inside generator window")
	screen.v12_keypad.cancel()
	if screen.v12_keypad.visible:
		failures.append("numeric keypad did not close")
	print("INVENTORY_REAL_GENERATOR=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
