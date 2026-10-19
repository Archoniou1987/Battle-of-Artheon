extends SceneTree

# Regression: opening the Arena from the village must construct a visible screen.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: main scene missing")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.call("_open_panel", "Арена")
	await process_frame
	var arena := main.get_node_or_null("ArenaScreen") as ArenaScreen
	if arena == null or not arena.visible or arena.square_content == null:
		push_error("ARENA_OPEN_SMOKE=FAIL: arena was not opened")
		quit(1)
		return
	if arena.player_slots.size() != 14 or arena.enemy_slots.size() != 14:
		push_error("ARENA_OPEN_SMOKE=FAIL: equipment slots missing")
		quit(1)
		return
	# Manual protection supports up to four arbitrarily selected body zones.
	arena.set_defense_capacity(4)
	if arena.selected_block_zones().size() != 4:
		push_error("ARENA_OPEN_SMOKE=FAIL: four-zone protection unavailable")
		quit(1)
		return
	arena._select_zone(true, "arms") # drop a currently protected zone
	arena._select_zone(true, "head") # replace it with a non-adjacent choice
	if arena.selected_block_zones().size() != 4 or not arena.selected_block_zones().has("head") or arena.selected_block_zones().has("arms"):
		push_error("ARENA_OPEN_SMOKE=FAIL: independent block zone selection")
		quit(1)
		return
	if arena.ability_buttons.size() != 5:
		push_error("ARENA_OPEN_SMOKE=FAIL: expected exactly five ABI controls")
		quit(1)
		return
	# Use a canonical definition for UI selection; no fake combat damage.
	arena.combat_session.ability_scheduler.loadouts[arena.combat_session.player_id] = ["ABI003"]
	arena.combat_session.player_ability_slots[0] = "ABI003"
	arena.combat_session.fighter(true).max_mana = 100
	arena.combat_session.fighter(true).mana = 100
	arena._refresh_ability_buttons()
	if arena.ability_buttons[0].disabled:
		push_error("ARENA_OPEN_SMOKE=FAIL: equipped ABI remains disabled")
		quit(1)
		return
	arena._select_ability(0)
	if arena.selected_ability != "ABI003":
		push_error("ARENA_OPEN_SMOKE=FAIL: ABI selection does not reach Arena")
		quit(1)
		return
	arena._select_ability(0)
	if not arena.selected_ability.is_empty():
		push_error("ARENA_OPEN_SMOKE=FAIL: second tap did not deselect ABI")
		quit(1)
		return
	print("ARENA_OPEN_SMOKE=PASS")
	quit(0)
