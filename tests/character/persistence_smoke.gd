extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var save_path := "user://character_inventory_v1.json"
	var progression_path := "user://character_progression_v1.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(progression_path))
	var scene := load("res://scenes/main/main.tscn") as PackedScene
	assert(scene != null)
	var first := scene.instantiate()
	root.add_child(first)
	await process_frame
	var character := first.get("player_character") as CharacterState
	var repository := first.get("item_repository") as ItemRepository
	var item := {"instance_id": "persist_test_ring", "name": "Persistence ring", "equip_slots": ["ring1"], "slot_usage": ["ring1"], "requirements": {}, "guaranteed_stats": {}}
	ItemDurabilityService.initialize_item(item, 100)
	assert(repository.add_item(item))
	assert(character.receive_item("persist_test_ring", repository))
	assert(character.equip("ring1", "persist_test_ring", repository))
	first.call("_save_inventory")
	assert(FileAccess.file_exists(save_path))
	assert(character.progression.allocate_stat("STR"))
	assert(character.progression.save_pending_stats())
	first.call("_save_progression")
	assert(FileAccess.file_exists(progression_path))
	first.queue_free()
	await process_frame
	var second := scene.instantiate()
	root.add_child(second)
	await process_frame
	assert((second.get("player_character") as CharacterState).inventory.owns("persist_test_ring"))
	assert((second.get("player_character") as CharacterState).equipment.get_equipped_instance_id("ring1") == "persist_test_ring")
	assert((second.get("item_repository") as ItemRepository).has_item("persist_test_ring"))
	assert((second.get("player_character") as CharacterState).progression.base_stats["STR"] == 2)
	second.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(progression_path))
	print("Character and inventory persistence smoke: PASS")
	quit(0)
