extends SceneTree

const SAVE := "user://test_map_archive_expiry.json"
const MANIFEST := "user://test_map_archive_expiry_manifest.json"

func _cleanup() -> void:
	for path in [SAVE,MANIFEST]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var hero := CharacterState.new("player","Expiry Tester",1)
	var repo := ItemRepository.new()
	ok = ok and repo.add_item({"instance_id":"OWNED_ITEM","weight":1.0})
	ok = ok and hero.inventory.add_instance("OWNED_ITEM",repo)
	ok = ok and repo.add_item({"instance_id":"ABANDONED_LOOT","weight":1.0})
	ok = ok and bool(SoloGameStateService.create(SAVE,hero,repo,31).get("ok",false))
	var entry := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
	ok = ok and bool(entry.get("ok",false))
	if not ok:
		print("MAP_ARCHIVE_EXPIRY_TEST=FAIL initial")
		_cleanup()
		quit(1)
		return
	var current := SoloGameStateService.read(SAVE,"player")
	var exp: ExpeditionState = current["expedition"]
	var item_repo: ItemRepository = current["repository"]
	var player: CharacterState = current["character"]
	var dropped := GroundLootService.place_unowned(exp,item_repo,"ABANDONED_LOOT",exp.player_position,"TEST")
	ok = ok and bool(dropped.get("ok",false))
	ok = ok and bool(ExpeditionSaveService.save(SAVE,exp,player,item_repo).get("ok",false))
	ok = ok and bool(SoloGameStateService.set_location(SAVE,"player",SoloGameStateService.LOCATION_TOWN,MANIFEST).get("ok",false))
	var fresh := SoloGameStateService.start_new_expedition(SAVE,"player",MANIFEST)
	ok = ok and bool(fresh.get("ok",false))
	if not ok:
		print("MAP_ARCHIVE_EXPIRY_TEST=FAIL fresh ",fresh)
		_cleanup()
		quit(1)
		return
	current = SoloGameStateService.read(SAVE,"player")
	exp = current["expedition"]
	var archives: Dictionary = exp.world_state[SoloGameStateService.MAP_ARCHIVES_KEY]
	var original_id := String(fresh["previous_map_id"])
	ok = ok and archives.has(original_id)
	ok = ok and int(archives[original_id]["expires_at_unix"]) > int(Time.get_unix_time_from_system())
	ok = ok and archives[original_id]["world_state"][GroundLootService.WORLD_KEY].has("ABANDONED_LOOT")
	ok = ok and current["repository"].has_item("ABANDONED_LOOT")
	ok = ok and current["character"].inventory.owns("OWNED_ITEM")
	# Advance the archive's expiry only, not the system clock.
	archives[original_id]["expires_at_unix"] = int(Time.get_unix_time_from_system())-1
	exp.world_state[SoloGameStateService.MAP_ARCHIVES_KEY] = archives
	ok = ok and bool(ExpeditionSaveService.save(SAVE,exp,current["character"],current["repository"]).get("ok",false))
	ok = ok and bool(SoloGameStateService.set_location(SAVE,"player",SoloGameStateService.LOCATION_TOWN,MANIFEST).get("ok",false))
	current = SoloGameStateService.read(SAVE,"player")
	var saved := SoloGameStateService.save_town(SAVE,current["character"],current["repository"],String(current["sha256"]))
	ok = ok and bool(saved.get("ok",false))
	current = SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(current.get("ok",false))
	if bool(current.get("ok",false)):
		ok = ok and not current["expedition"].world_state[SoloGameStateService.MAP_ARCHIVES_KEY].has(original_id)
		ok = ok and not current["repository"].has_item("ABANDONED_LOOT")
		ok = ok and current["repository"].has_item("OWNED_ITEM")
		ok = ok and current["character"].inventory.owns("OWNED_ITEM")
		ok = ok and current["expedition"].world_state[SoloLiveMapSession.MAP_INSTANCE_KEY]["instance_id"]==fresh["instance_id"]
	_cleanup()
	print("MAP_ARCHIVE_EXPIRY_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
