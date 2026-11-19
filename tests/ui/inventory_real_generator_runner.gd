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
	# The real InventoryScreen is instantiated lazily when the town panel opens.
	# Loading main.tscn alone does not create this node.
	game.call("_open_panel","Инвентарь")
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
	# Both approved 2H archetypes are playable ITEM v1.2 instances, not
	# preview-only templates. Selection must reserve both hands.
	for entry in [
		["2H_SWORD",["ABI313","ABI314","ABI315","ABI316"]],
		["2H_AXE",["ABI513","ABI514","ABI515","ABI516"]]
	]:
		var archetype_id := String(entry[0])
		var found := -1
		for i in range(screen.v12_archetype.item_count):
			if String(screen.v12_archetype.get_item_metadata(i)) == archetype_id:
				found = i
				break
		if found < 0:
			failures.append("real inventory generator does not offer "+archetype_id)
			continue
		screen.v12_archetype.select(found)
		screen.v12_archetype.item_selected.emit(found)
		if String(screen.v12_hand.get_selected_metadata()) != "2H":
			failures.append(archetype_id+" must auto-select 2H")
		var item := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",202611175+found,"2H")
		if item.is_empty():
			failures.append(archetype_id+" failed to generate actual v1.2 item")
		else:
			if Array(item.get("abilities",[])) != Array(entry[1]):
				failures.append(archetype_id+" generated wrong ABI")
			if Array(item.get("slot_usage",[])) != ["main_hand","off_hand"]:
				failures.append(archetype_id+" did not reserve both hands")
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
