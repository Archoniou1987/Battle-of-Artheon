extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(9,9)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(4,4))
	for i in range(3):
		var npc:=NpcInstance.new("GROUP"+str(i),repo.get_npc("NPC003"))
		npc.aggression=100.0
		valid=valid and bridge.register_npc(map,npc,[Vector2i(3,4),Vector2i(4,3),Vector2i(5,4)][i])
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	var encounter:=turns.coordinator.try_start_patrol_contact(map,bridge,"PLAYER","GROUP0",rng)
	valid=valid and bool(encounter.get("ok",false)) and encounter.get("npc_instance_ids",[]).size()==3
	var again:=turns.coordinator.try_start_patrol_contact(map,bridge,"PLAYER","GROUP1",rng)
	valid=valid and again.get("reason","")=="combat_active"
	var route:Array[Vector2i]=[Vector2i(3,4),Vector2i(2,4)]
	var patrol:=HexPatrolState.new("GROUP0",route)
	var frozen:=turns.step_patrol(map,bridge,patrol,"PLAYER",rng)
	valid=valid and frozen.get("reason","")=="combat_paused"
	turns.finish_combat()
	var resumed:=turns.step_patrol(map,bridge,patrol,"PLAYER",rng)
	valid=valid and bool(resumed.get("ok",false)) and patrol.path_index==1
	print("HEX_GROUP_PAUSE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
