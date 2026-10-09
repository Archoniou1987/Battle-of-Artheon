extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(9,9)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(4,3))
	var npc:=NpcInstance.new("STUCK",repo.get_npc("NPC003"))
	npc.aggression=100.0
	valid=valid and bridge.register_npc(map,npc,Vector2i(2,3))
	var chase:=HexNpcChaseState.new("STUCK",Vector2i(2,3),3,4)
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	chase.mode="returning"
	chase.wait_for_detection_exit=true
	var home:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and bool(home.get("returned",false)) and chase.mode=="idle"
	for i in range(5):
		var repeated:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
		valid=valid and repeated.get("reason","")=="not_aggressive" and chase.mode=="idle"
	valid=valid and map.move_entity("PLAYER",Vector2i(5,3)).get("ok",false)
	valid=valid and map.move_entity("PLAYER",Vector2i(6,3)).get("ok",false)
	var reset:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and reset.get("reason","")=="not_detected" and not chase.wait_for_detection_exit
	print("HEX_NPC_RETRY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
