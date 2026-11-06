extends SceneTree

const SAVE := "user://test_generated_town_roundtrip.json"
const MANIFEST := "user://test_generated_town_roundtrip_manifest.json"

func _cleanup() -> void:
	for path in [SAVE,MANIFEST]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var hero := CharacterState.new("player","World Tester",1)
	var items := ItemRepository.new()
	var created := SoloGameStateService.create(SAVE,hero,items,17)
	ok = ok and bool(created.get("ok",false))
	var departure := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
	ok = ok and bool(departure.get("ok",false))
	if not ok:
		print("GENERATED_TOWN_ROUNDTRIP_TEST=FAIL create/launch ",departure)
		_cleanup()
		quit(1)
		return
	var opened := SoloLiveMapSession.open(SAVE,MANIFEST,SoloTownExpeditionBridge.expedition_id_for_player("player"),"player")
	ok = ok and bool(opened.get("ok",false))
	if not bool(opened.get("ok",false)):
		print("GENERATED_TOWN_ROUNDTRIP_TEST=FAIL open ",opened)
		_cleanup()
		quit(1)
		return
	var session: SoloLiveMapSession = opened["session"]
	ok = ok and session.map.width==20 and session.map.height==20
	ok = ok and session.npc_bridge.instances.size()>3
	var instance: Dictionary = session.expedition.world_state[SoloLiveMapSession.MAP_INSTANCE_KEY]
	var instance_id := String(instance["instance_id"])
	var initial := session.expedition.player_position
	var destination := Vector2i(-1,-1)
	for next in session.map.neighbors(initial,true):
		if session.npc_bridge.npc_at(session.map,next).is_empty():
			destination=next
			break
	ok = ok and destination.x >= 0
	if destination.x>=0:
		var moved := session.move_one_step(destination)
		ok = ok and bool(moved.get("ok",false))
		var reopened := SoloLiveMapSession.open(SAVE,MANIFEST,SoloTownExpeditionBridge.expedition_id_for_player("player"),"player")
		ok = ok and bool(reopened.get("ok",false))
		if bool(reopened.get("ok",false)):
			var continued: SoloLiveMapSession = reopened["session"]
			ok = ok and continued.expedition.player_position==destination
			ok = ok and String(continued.expedition.world_state[SoloLiveMapSession.MAP_INSTANCE_KEY]["instance_id"])==instance_id
			ok = ok and continued.map.cell(initial).discovered
			ok = ok and continued.map.cell(destination).discovered
			ok = ok and continued.character.character_id=="player"
			var back := continued.return_to_town(SAVE)
			ok = ok and bool(back.get("ok",false))
			if bool(back.get("ok",false)):
				var reentry := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
				ok = ok and bool(reentry.get("ok",false))
				var latest := SoloGameStateService.read(SAVE,"player")
				ok = ok and bool(latest.get("ok",false))
				if bool(latest.get("ok",false)):
					ok = ok and String(latest["expedition"].world_state[SoloLiveMapSession.MAP_INSTANCE_KEY]["instance_id"])==instance_id
	_cleanup()
	print("GENERATED_TOWN_ROUNDTRIP_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
