extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(7,7)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(3,2))
	var npc:=NpcInstance.new("BOUND",repo.get_npc("NPC003"))
	npc.aggression=100.0
	valid=valid and bridge.register_npc(map,npc,Vector2i(0,2))
	var chase:=HexNpcChaseState.new("BOUND",Vector2i(0,2),4,3)
	var rng:=RandomNumberGenerator.new()
	var turns:=HexMapTurnService.new()
	for blocked in [Vector2i(1,2),Vector2i(0,3),Vector2i(1,1),Vector2i(2,2),Vector2i(3,1),Vector2i(4,1),Vector2i(4,2),Vector2i(3,3),Vector2i(2,3)]:
		valid=valid and map.set_obstacle(blocked,"wall",true)
	var attempt:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and bool(attempt.get("ok",false)) and chase.mode=="idle"
	valid=valid and chase.wait_for_detection_exit
	valid=valid and map.entity_positions["BOUND"]==Vector2i(0,2)
	var repeat_attempt:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and repeat_attempt.get("reason","")=="not_aggressive"
	valid=valid and not map.move_entity("BOUND",Vector2i(-1,2)).get("ok",false)
	valid=valid and not map.move_entity("BOUND",Vector2i(2,2)).get("ok",false)
	chase.mode="returning"
	chase.home_position=Vector2i(2,2)
	var stranded:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and stranded.get("reason","")=="home_unreachable"
	valid=valid and chase.mode=="returning"
	print("HEX_NPC_BOUNDARY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
