extends SceneTree

func _initialize()->void:
	var definitions:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_repo:=NpcRepository.new()
	npc_repo.load_definitions(definitions)
	var map:=TacticalMapState.new(9,9)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(4,4))
	var positions:Dictionary={
		"PRIMARY":Vector2i(4,4),
		"ALLY":Vector2i(5,4),
		"NEUTRAL":Vector2i(4,3),
		"FAR":Vector2i(6,4)
	}
	for npc_id in positions.keys():
		var npc:=NpcInstance.new(npc_id,npc_repo.get_npc("NPC003"))
		valid=valid and bridge.register_npc(map,npc,positions[npc_id])
	var ally:NpcInstance=bridge.instances["ALLY"]
	ally.detection_radius=1
	ally.aggression=100.0
	var neutral:NpcInstance=bridge.instances["NEUTRAL"]
	neutral.detection_radius=1
	neutral.aggression=0.0
	var far:NpcInstance=bridge.instances["FAR"]
	far.detection_radius=1
	far.aggression=100.0
	var from_instance:=NpcDetectionService.detect(map,bridge,"PLAYER")
	valid=valid and from_instance.size()==3
	var instance_join:=HexCombatJoinService.assemble(map,bridge,Vector2i(4,4),["PRIMARY"],{},RandomNumberGenerator.new())
	valid=valid and bool(instance_join.get("ok",false))
	valid=valid and instance_join.get("npc_instance_ids",[]).has("ALLY")
	valid=valid and not instance_join.get("npc_instance_ids",[]).has("NEUTRAL")
	valid=valid and not instance_join.get("npc_instance_ids",[]).has("FAR")
	var radii:Dictionary={"PRIMARY":0,"ALLY":1,"NEUTRAL":1,"FAR":1}
	var detected:=NpcDetectionService.detect(map,bridge,"PLAYER",radii)
	valid=valid and detected.size()==3
	var primary:Array[String]=["PRIMARY"]
	var rng:=RandomNumberGenerator.new()
	rng.seed=42
	var joined:=HexCombatJoinService.assemble(map,bridge,Vector2i(4,4),primary,{"ALLY":100,"NEUTRAL":0,"FAR":100},rng)
	valid=valid and bool(joined.get("ok",false))
	valid=valid and joined.get("npc_instance_ids",[]).size()==2
	valid=valid and joined.get("npc_instance_ids",[]).has("PRIMARY")
	valid=valid and joined.get("npc_instance_ids",[]).has("ALLY")
	valid=valid and not joined.get("npc_instance_ids",[]).has("FAR")
	valid=valid and map.entity_positions["ALLY"]==Vector2i(5,4)
	var invalid:=HexCombatJoinService.assemble(map,bridge,Vector2i(4,4),["FAR"],{},rng)
	valid=valid and not bool(invalid.get("ok",true))
	var encounter:=bridge.encounter_with_neighbors(map,Vector2i(4,4),RandomNumberGenerator.new())
	valid=valid and bool(encounter.get("ok",false))
	valid=valid and encounter.get("npc_instance_ids",[]).size()==2
	var player:=TestFixtureLoader.new_combatant("PLAYER","Test Hero",5,200)
	var session:=MapEncounterCombatService.begin(encounter,npc_repo,player)
	valid=valid and bool(session.get("ok",false))
	var combat_state:CombatState=session.get("state") as CombatState
	valid=valid and combat_state!=null and combat_state.combatants.size()==3
	valid=valid and map.entity_positions["ALLY"]==Vector2i(5,4)
	var coordinator:=HexEncounterCoordinator.new()
	var automatic:=coordinator.try_start(map,bridge,"PLAYER",RandomNumberGenerator.new())
	valid=valid and bool(automatic.get("ok",false))
	valid=valid and automatic.get("npc_instance_ids",[]).has("PRIMARY")
	valid=valid and automatic.get("npc_instance_ids",[]).has("ALLY")
	valid=valid and not automatic.get("npc_instance_ids",[]).has("NEUTRAL")
	valid=valid and not automatic.get("npc_instance_ids",[]).has("FAR")
	valid=valid and coordinator.try_start(map,bridge,"PLAYER",RandomNumberGenerator.new()).get("reason","")=="combat_active"
	coordinator.finish_combat()
	valid=valid and not coordinator.combat_active
	var turns:=HexMapTurnService.new()
	var empty_map:=TacticalMapState.new(9,9)
	var empty_bridge:=MapNpcBridge.new()
	valid=valid and empty_map.place_entity("PLAYER",Vector2i(1,1))
	var distant:=NpcInstance.new("DISTANT",npc_repo.get_npc("NPC003"))
	distant.detection_radius=4
	distant.aggression=100.0
	valid=valid and empty_bridge.register_npc(empty_map,distant,Vector2i(4,1))
	var walk:=turns.move_player(empty_map,empty_bridge,"PLAYER",Vector2i(2,1),RandomNumberGenerator.new())
	valid=valid and bool(walk.get("ok",false)) and not walk.has("encounter")
	valid=valid and not turns.coordinator.combat_active
	var patrol_npc:=NpcInstance.new("PATROL",npc_repo.get_npc("NPC003"))
	patrol_npc.aggression=100.0
	valid=valid and empty_bridge.register_npc(empty_map,patrol_npc,Vector2i(2,2))
	var route:Array[Vector2i]=[Vector2i(2,2),Vector2i(2,1)]
	var patrol:=HexPatrolState.new("PATROL",route)
	var patrol_result:=turns.step_patrol(empty_map,empty_bridge,patrol,"PLAYER",RandomNumberGenerator.new())
	valid=valid and bool(patrol_result.get("ok",false)) and patrol_result.has("encounter")
	valid=valid and turns.coordinator.combat_active
	valid=valid and empty_map.entity_positions["PATROL"]==Vector2i(2,2)
	var blocked:=turns.move_player(empty_map,empty_bridge,"PLAYER",Vector2i(3,1),RandomNumberGenerator.new())
	valid=valid and blocked.get("reason","")=="combat_active"
	turns.finish_combat()
	valid=valid and not turns.coordinator.combat_active
	print("HEX_NPC_DETECTION_JOIN_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
