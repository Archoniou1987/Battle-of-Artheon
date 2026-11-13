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
		print("MAP_CLOSURE_DISCARD_TEST=FAIL initial")
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
		print("MAP_CLOSURE_DISCARD_TEST=FAIL fresh ",fresh)
		_cleanup()
		quit(1)
		return
	current = SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(current.get("ok",false))
	if bool(current.get("ok",false)):
		var world: Dictionary = current["expedition"].world_state
		ok = ok and not world.has(SoloGameStateService.MAP_ARCHIVES_KEY)
		ok = ok and not world.has(GroundLootService.WORLD_KEY)
		ok = ok and not current["repository"].has_item("ABANDONED_LOOT")
		ok = ok and current["repository"].has_item("OWNED_ITEM")
		ok = ok and current["character"].inventory.owns("OWNED_ITEM")
		ok = ok and String(world[SoloLiveMapSession.MAP_INSTANCE_KEY]["instance_id"])==String(fresh["instance_id"])
	_cleanup()
	print("MAP_CLOSURE_DISCARD_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
