extends SceneTree

const SAVE := "user://test_generated_patrol_save.json"
const MANIFEST := "user://test_generated_patrol_manifest.json"

func _cleanup() -> void:
	for p in [SAVE,MANIFEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var hero := CharacterState.new("player","Patrol Tester",1)
	var items := ItemRepository.new()
	var created := SoloGameStateService.create(SAVE,hero,items,100)
	ok = ok and bool(created.get("ok",false))
	var enter := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
	ok = ok and bool(enter.get("ok",false))
	var id := SoloTownExpeditionBridge.expedition_id_for_player("player")
	var first := SoloLiveMapSession.open(SAVE,MANIFEST,id,"player")
	ok = ok and bool(first.get("ok",false))
	if not bool(first.get("ok",false)):
		print("GENERATED_PATROL_PERSISTENCE_TEST=FAIL mount ",first)
		_cleanup()
		quit(1)
		return
	var session: SoloLiveMapSession = first["session"]
	ok = ok and not session.generated_content.is_empty()
	var before := session.patrol_runtime.snapshot()
	var changed := false
	for attempt in range(6):
		var tick := session.advance_patrols(30.0)
		ok = ok and bool(tick.get("ok",false))
		changed = changed or bool(tick.get("changed",false))
		if changed or not ok:
			break
	if before.size()>0:
		ok = ok and changed
	var stored := SoloGameStateService.read(SAVE,"player")
	ok = ok and bool(stored.get("ok",false))
	if bool(stored.get("ok",false)):
		ok = ok and stored["expedition"].world_state.has(SoloLiveMapSession.PATROL_KEY) == changed
	var reopened := SoloLiveMapSession.open(SAVE,MANIFEST,id,"player")
	ok = ok and bool(reopened.get("ok",false))
	if bool(reopened.get("ok",false)):
		var resumed: SoloLiveMapSession = reopened["session"]
		ok = ok and resumed.patrol_runtime.snapshot().keys().size() == session.patrol_runtime.snapshot().keys().size()
		for patrol_id in resumed.patrol_runtime.snapshot().keys():
			var current: Dictionary = resumed.patrol_runtime.snapshot()[patrol_id]
			var expected: Dictionary = session.patrol_runtime.snapshot()[patrol_id]
			ok = ok and current["position"] == expected["position"]
		ok = ok and resumed.expedition.player_position == session.expedition.player_position
	_cleanup()
	print("GENERATED_PATROL_PERSISTENCE_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
