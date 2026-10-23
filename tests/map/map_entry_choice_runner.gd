extends SceneTree

const SAVE := "user://test_map_entry_choice.json"
const MANIFEST := "user://test_map_entry_choice_manifest.json"

func _cleanup() -> void:
	for path in [SAVE,MANIFEST]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var character := CharacterState.new("player","Entry Choice",1)
	var repository := ItemRepository.new()
	ok = ok and repository.add_item({"instance_id":"KEPT_ITEM","weight":1.0})
	ok = ok and character.inventory.add_instance("KEPT_ITEM",repository)
	ok = ok and bool(SoloGameStateService.create(SAVE,character,repository,71).get("ok",false))
	var choices := SoloGameStateService.map_entry_options(SAVE,"player",MANIFEST)
	ok = ok and bool(choices.get("ok",false)) and bool(choices.get("can_start_new",false))
	var first := SoloGameStateService.start_new_expedition(SAVE,"player",MANIFEST)
	ok = ok and bool(first.get("ok",false))
	if not bool(first.get("ok",false)):
		print("MAP_ENTRY_CHOICE_TEST=FAIL first ",first)
		_cleanup()
		quit(1)
		return
	var first_id := String(first["instance_id"])
	var active := SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(active.get("ok",false))
	if bool(active.get("ok",false)):
		ok = ok and active["character"].inventory.owns("KEPT_ITEM")
		ok = ok and active["expedition"].world_state.has(SoloLiveMapSession.MAP_INSTANCE_KEY)
		ok = ok and not active["expedition"].world_state.has(SoloGameStateService.MAP_ARCHIVES_KEY)
	var returned := SoloGameStateService.set_location(SAVE,"player",SoloGameStateService.LOCATION_TOWN,MANIFEST)
	ok = ok and bool(returned.get("ok",false))
	var previous := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
	ok = ok and bool(previous.get("ok",false))
	if bool(previous.get("ok",false)):
		ok = ok and String(previous.get("instance_id",""))==first_id
		ok = ok and bool(SoloGameStateService.set_location(SAVE,"player",SoloGameStateService.LOCATION_TOWN,MANIFEST).get("ok",false))
	# A previous completed combat must not block new map creation or
	# falsely mark a same-named NPC on the next map as already defeated.
	var before_second := SoloGameStateService.read(SAVE,"player")
	var previous_world: ExpeditionState = before_second["expedition"]
	var receipt_id := "solo:live:" + previous_world.expedition_id + ":GEN_NPC_00"
	var hash := "a".repeat(64)
	previous_world.world_state[MapWorldCommitService.TOMBSTONES_KEY] = {
		receipt_id:{"receipt_sha256":hash,"npc_ids":["GEN_NPC_00"],"npc_positions":{}}
	}
	previous_world.world_state[MapCombatSettlementService.MARKER_KEY] = {receipt_id:hash}
	ok = ok and bool(ExpeditionSaveService.save(SAVE,previous_world,before_second["character"],before_second["repository"]).get("ok",false))
	var second := SoloGameStateService.start_new_expedition(SAVE,"player",MANIFEST)
	ok = ok and bool(second.get("ok",false))
	if bool(second.get("ok",false)):
		ok = ok and String(second["instance_id"])!=first_id
		var saved := SoloGameStateService.read(SAVE,"player")
		ok = ok and bool(saved.get("ok",false))
		if bool(saved.get("ok",false)):
			var world: Dictionary = saved["expedition"].world_state
			ok = ok and not world.has(SoloGameStateService.MAP_ARCHIVES_KEY)
			ok = ok and int(world[SoloGameStateService.MAP_SERIAL_KEY]) == 2
			ok = ok and bool(second.get("previous_map_closed",false))
			ok = ok and Dictionary(world.get(MapWorldCommitService.TOMBSTONES_KEY,{})).has(receipt_id)
			ok = ok and Dictionary(world.get(MapCombatSettlementService.MARKER_KEY,{})).has(receipt_id)
			ok = ok and not MapWorldCommitService.is_defeated_spawn(saved["expedition"],"GEN_NPC_00")
			ok = ok and saved["character"].inventory.owns("KEPT_ITEM")
			ok = ok and saved["repository"].has_item("KEPT_ITEM")
	var refused := SoloGameStateService.start_new_expedition(SAVE,"player",MANIFEST)
	ok = ok and String(refused.get("reason",""))=="game_state_not_in_town"
	_cleanup()
	print("MAP_ENTRY_CHOICE_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
