extends SceneTree

const SAVE := "user://test_legacy_generated_upgrade.json"
const MANIFEST := "user://test_legacy_generated_upgrade_manifest.json"

func _cleanup() -> void:
	for path in [SAVE,MANIFEST]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var hero := CharacterState.new("player","Legacy Hero",1)
	var items := ItemRepository.new()
	ok = ok and items.add_item({"instance_id":"UNCLAIMED_LEGACY_ITEM","weight":1.0})
	var created := SoloGameStateService.create(SAVE,hero,items,9)
	ok = ok and bool(created.get("ok",false))
	var entered := SoloGameStateService.set_location(SAVE,"player",SoloGameStateService.LOCATION_MAP,MANIFEST)
	ok = ok and bool(entered.get("ok",false))
	var raw := SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(raw.get("ok",false))
	if not ok:
		print("LEGACY_GENERATED_UPGRADE_TEST=FAIL setup")
		_cleanup()
		quit(1)
		return
	var exp: ExpeditionState = raw["expedition"]
	var item_repo: ItemRepository = raw["repository"]
	var char: CharacterState = raw["character"]
	var dropped := GroundLootService.place_unowned(exp,item_repo,"UNCLAIMED_LEGACY_ITEM",Vector2i(5,5),"TEST")
	ok = ok and bool(dropped.get("ok",false))
	ok = ok and bool(ExpeditionSaveService.save(SAVE,exp,char,item_repo).get("ok",false))
	var refused := SoloGameStateService.upgrade_legacy_map(SAVE,"player",MANIFEST)
	ok = ok and String(refused.get("reason",""))=="legacy_loot_must_be_collected"
	var saved := SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(saved.get("ok",false))
	if bool(saved.get("ok",false)):
		exp = saved["expedition"]
		ok = ok and not exp.world_state.has(SoloLiveMapSession.MAP_INSTANCE_KEY)
		exp.world_state.erase(GroundLootService.WORLD_KEY)
		ok = ok and bool(ExpeditionSaveService.save(SAVE,exp,saved["character"],saved["repository"]).get("ok",false))
	var upgraded := SoloGameStateService.upgrade_legacy_map(SAVE,"player",MANIFEST)
	ok = ok and bool(upgraded.get("ok",false))
	var id := SoloTownExpeditionBridge.expedition_id_for_player("player")
	var opened := SoloLiveMapSession.open(SAVE,MANIFEST,id,"player")
	ok = ok and bool(opened.get("ok",false))
	if bool(opened.get("ok",false)):
		var live: SoloLiveMapSession = opened["session"]
		ok = ok and live.map.width==20 and live.map.height==20
		ok = ok and live.generated_content.has("regions")
		ok = ok and live.expedition.world_state.has("legacy_map_origin_v1")
		ok = ok and live.repository.has_item("UNCLAIMED_LEGACY_ITEM")
		ok = ok and live.character.character_id=="player"
		ok = ok and live.npc_bridge.instances.size()>3
	var second := SoloGameStateService.upgrade_legacy_map(SAVE,"player",MANIFEST)
	ok = ok and String(second.get("reason",""))=="already_generated_map"
	_cleanup()
	print("LEGACY_GENERATED_UPGRADE_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
