extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view = load("res://scenes/debug/debug_combat_viewer.tscn").instantiate()
	root.add_child(view)
	await process_frame
	for combatant in view.state.combatants.values():
		assert(ParAttackContract.validate(combatant).ok)
	assert(view.commands.queue_default_weapon_attacks("enemy").ok)
	view.engine.resolve_pending_events()
	view._end_round()
	view.queue_free()
	await process_frame
	print("DEBUG_CANONICAL_COMBAT=PASS")
	quit(0)
