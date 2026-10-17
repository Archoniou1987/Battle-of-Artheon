extends SceneTree

const PROGRESSION_SAVE := "user://character_progression_v1.json"
const INVENTORY_SAVE := "user://character_inventory_v1.json"
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func verify(ok: bool, reason: String) -> void:
	if not ok:
		errors.append(reason)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESSION_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INVENTORY_SAVE))
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		verify(false, "missing main scene")
		_finish()
		return
	var first := packed.instantiate()
	root.add_child(first)
	await process_frame
	var hero := first.get("player_character") as CharacterState
	var repo := first.get("item_repository") as ItemRepository
	var ring := {"instance_id":"offline_regen_ring","equip_slots":["ring1"],"slot_usage":["ring1"],"par_stats":{"PAR012":1.0,"PAR013":2.0,"PAR017":1.0}}
	ItemDurabilityService.initialize_item(ring, 100)
	verify(repo.add_item(ring) and hero.receive_item("offline_regen_ring", repo) and hero.equip("ring1", "offline_regen_ring", repo), "equip offline ring")
	hero.current_hp = 25
	hero.current_mana = 0
	first.call("_save_inventory")
	first.call("_save_progression")
	first.queue_free()
	await process_frame
	# Simulate 40 seconds of an unloaded, non-combat session by adjusting
	# only the persisted clock. This is deterministic and requires no wait.
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESSION_SAVE))
	if not payload is Dictionary:
		verify(false, "saved progression JSON missing")
		_finish()
		return
	payload["regen_saved_unix"] = Time.get_unix_time_from_system() - 40.0
	payload["regen_paused"] = false
	var file := FileAccess.open(PROGRESSION_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var second := packed.instantiate()
	root.add_child(second)
	await process_frame
	var loaded := second.get("player_character") as CharacterState
	var loaded_repo := second.get("item_repository") as ItemRepository
	var max_hp := int(loaded.resource_snapshot(loaded_repo)["max_hp"])
	var gain := 4.0 * (0.01 * float(max_hp) + 1.0)
	verify(loaded.current_hp == mini(max_hp, 25 + int(floor(gain))), "offline HP uses PAR012% plus PAR017 flat /10 sec")
	verify(loaded.current_mana == 8, "offline mana uses PAR013 /10 sec")
	verify(loaded.equipment.get_equipped_instance_id("ring1") == "offline_regen_ring", "equipment restored before catch-up")
	second.call("_open_panel", "Арена")
	await process_frame
	var arena := second.get_node_or_null("ArenaScreen") as ArenaScreen
	verify(arena != null and loaded.in_combat, "Arena pauses passive regeneration")
	var mana_before := loaded.current_mana
	OutOfCombatRegenerationService.advance(loaded, loaded_repo, 100.0)
	verify(loaded.current_mana == mana_before, "Arena rejects background regeneration")
	if arena != null:
		arena.back_requested.emit()
	verify(not loaded.in_combat, "leaving Arena resumes recovery")
	second.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESSION_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INVENTORY_SAVE))
	_finish()

func _finish() -> void:
	for failure in errors:
		push_error("OFFLINE_REGEN_INTEGRATION: " + failure)
	print("OFFLINE_REGEN_INTEGRATION_TEST=", "PASS" if errors.is_empty() else "FAIL", " failures=", errors.size())
	quit(0 if errors.is_empty() else 1)
