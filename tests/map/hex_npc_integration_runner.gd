extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(12,12)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(5,4))
	var guard:=NpcInstance.new("GUARD",repo.get_npc("NPC003"))
	var ally:=NpcInstance.new("ALLY",repo.get_npc("NPC003"))
	guard.aggression=100.0
	ally.aggression=100.0
	valid=valid and bridge.register_npc(map,guard,Vector2i(2,4))
	valid=valid and bridge.register_npc(map,ally,Vector2i(5,5))
	var route:Array[Vector2i]=[Vector2i(2,4),Vector2i(3,4),Vector2i(4,4)]
	var patrol:=HexPatrolState.new("GUARD",route)
	var chase:=HexNpcChaseState.new("GUARD",Vector2i(2,4),3,4)
	var controller:=HexPatrolChaseController.new(patrol,chase)
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	var pursuit:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(pursuit.get("ok",false)) and chase.mode=="chasing"
	var contact:=controller.step(map,bridge,turns,"PLAYER",rng)
	if not contact.has("encounter"):
		contact=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(contact.get("ok",false)) and contact.has("encounter")
	var encounter:Dictionary=contact.get("encounter",{})
	valid=valid and encounter.get("npc_instance_ids",[]).size()==2
	valid=valid and turns.coordinator.combat_active
	var frozen_position:Vector2i=map.entity_positions["GUARD"]
	var frozen:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and frozen.get("reason","")=="combat_paused"
	valid=valid and map.entity_positions["GUARD"]==frozen_position
	turns.finish_combat()
	valid=valid and map.move_entity("PLAYER",Vector2i(6,4)).get("ok",false)
	valid=valid and map.move_entity("PLAYER",Vector2i(7,4)).get("ok",false)
	var retreat:=controller.step(map,bridge,turns,"PLAYER",rng)
	print("NPC_INTEGRATION_DIAG pursuit=",pursuit," contact=",contact," retreat=",retreat," chase_mode=",chase.mode," guard_pos=",map.entity_positions["GUARD"])
	valid=valid and bool(retreat.get("ok",false))
	for i in range(5):
		if chase.mode=="idle":
			break
		retreat=controller.step(map,bridge,turns,"PLAYER",rng)
		valid=valid and bool(retreat.get("ok",false))
	valid=valid and chase.mode=="idle"
	valid=valid and map.entity_positions["GUARD"]==Vector2i(2,4)
	var resume:=controller.step(map,bridge,turns,"PLAYER",rng)
	valid=valid and bool(resume.get("ok",false)) and patrol.path_index==1
	print("HEX_NPC_INTEGRATION_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
