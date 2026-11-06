extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok := true
	var towns := {"starter":WorldInstanceContract.settlement("starter","forest",1)}
	var definition := WorldInstanceContract.instance("MAP-TEST-001","starter","forest",98765,1,20,20,1)
	var build := MapInstanceGenerationService.generate(definition,towns)
	ok = ok and bool(build.get("ok",false))
	if not ok:
		print("SOLO_GENERATED_LIVE_MOUNT_TEST=FAIL generation")
		quit(1)
		return
	var expedition := ExpeditionState.new("TEST_GENERATED_MOUNT")
	expedition.player_position = build["generated"]["entrance"]
	expedition.world_state[SoloLiveMapSession.MAP_INSTANCE_KEY] = definition
	var character := CharacterState.new("player","Tester",1)
	var repository := ItemRepository.new()
	var opened := SoloLiveMapSession._mount("user://test_generated_mount.json","user://test_generated_mount_manifest.json",expedition,character,repository)
	ok = ok and bool(opened.get("ok",false))
	if bool(opened.get("ok",false)):
		var session: SoloLiveMapSession = opened["session"]
		ok = ok and session.map.width == 20 and session.map.height == 20
		ok = ok and session.generated_content.has("regions") and session.generated_content.has("patrols")
		ok = ok and session.npc_bridge.instances.size() > 3
		ok = ok and session.map.entity_positions.has("player")
		ok = ok and session.map.entity_positions["player"] == expedition.player_position
		ok = ok and session.expedition.world_state[SoloLiveMapSession.MAP_INSTANCE_KEY]["instance_id"] == "MAP-TEST-001"
		print("SOLO_GENERATED_LIVE_NPCS=",session.npc_bridge.instances.size())
	else:
		print("SOLO_GENERATED_LIVE_REASON=",opened.get("reason","unknown"))
	print("SOLO_GENERATED_LIVE_MOUNT_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
