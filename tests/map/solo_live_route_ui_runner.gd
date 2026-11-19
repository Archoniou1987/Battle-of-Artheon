extends SceneTree

const SAVE := "user://test_route_ui_canonical.json"
const MANIFEST := "user://test_route_ui_manifest.json"

func _cleanup() -> void:
	for path in [SAVE,MANIFEST]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_cleanup()
	var ok := true
	var hero := CharacterState.new("player","Route Hero",1)
	var items := ItemRepository.new()
	var created := SoloGameStateService.create(SAVE,hero,items,123)
	var launched := SoloGameStateService.enter_generated_map(SAVE,"player",MANIFEST)
	ok = ok and bool(created.get("ok",false)) and bool(launched.get("ok",false))
	var id := SoloTownExpeditionBridge.expedition_id_for_player("player")
	var opened := SoloLiveMapSession.open(SAVE,MANIFEST,id,"player")
	ok = ok and bool(opened.get("ok",false))
	if not ok:
		print("SOLO_LIVE_ROUTE_UI_TEST=FAIL setup ",opened)
		_cleanup()
		quit(1)
		return
	var session: SoloLiveMapSession = opened["session"]
	var from: Vector2i = session.expedition.player_position
	var target := Vector2i(-1,-1)
	for cell in session.map.neighbors(from,true):
		if session.npc_bridge.npc_at(session.map,cell).is_empty():
			target=cell
			break
	ok = ok and target.x>=0
	var packed := load("res://scenes/main/solo_live_map.tscn") as PackedScene
	ok = ok and packed!=null
	if packed!=null and target.x>=0:
		var page := packed.instantiate() as Control
		root.add_child(page)
		page.set("session",session)
		page.call("_refresh")
		var minimap := page.get("mini_map") as DebugMiniMap
		var canvas := page.get("hex_canvas") as DebugMapCanvas
		ok = ok and minimap!=null and canvas!=null
		page.call("_select_hex_destination",target)
		ok = ok and bool(page.get("_route_ready_for_confirmation"))
		ok = ok and not bool(page.get("route_running"))
		page.call("_select_hex_destination",target)
		ok = ok and bool(page.get("route_running"))
		var seconds := SafeMapNavigation.terrain_seconds(session.map.cell(target).terrain_id)
		page.call("_process",seconds+0.5)
		ok = ok and session.expedition.player_position==target
		var current := SoloGameStateService.read(SAVE,"player")
		ok = ok and bool(current.get("ok",false))
		if bool(current.get("ok",false)):
			ok = ok and current["expedition"].player_position==target
		ok = ok and minimap.player_cell==target
		page.call("_stop_route")
		ok = ok and not bool(page.get("route_running"))
		page.queue_free()
	_cleanup()
	print("SOLO_LIVE_ROUTE_UI_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
