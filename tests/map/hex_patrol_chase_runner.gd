extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(12,12)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(5,4))
	var npc:=NpcInstance.new("GUARD",repo.get_npc("NPC003"))
	npc.aggression=100.0
	valid=valid and bridge.register_npc(map,npc,Vector2i(2,4))
	var route:Array[Vector2i]=[Vector2i(2,4),Vector2i(3,4),Vector2i(4,4)]
	var patrol:=HexPatrolState.new("GUARD",route)
	var chase:=HexNpcChaseState.new("GUARD",Vector2i(2,4),3,4)
	var controller:=HexPatrolChaseController.new(patrol,chase)
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	var first:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(first.get("ok",false)) and chase.mode=="chasing"
	valid=valid and patrol.path_index==0
	valid=valid and map.entity_positions["GUARD"]==Vector2i(3,4)
	valid=valid and bool(map.move_entity("PLAYER",Vector2i(6,4)).get("ok",false))
	valid=valid and bool(map.move_entity("PLAYER",Vector2i(7,4)).get("ok",false))
	var retreat:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(retreat.get("ok",false)) and chase.mode=="idle"
	valid=valid and map.entity_positions["GUARD"]==Vector2i(2,4)
	valid=valid and patrol.path_index==0
	var resume:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(resume.get("ok",false))
	valid=valid and patrol.path_index==1 and map.entity_positions["GUARD"]==Vector2i(3,4)
	print("HEX_PATROL_CHASE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
