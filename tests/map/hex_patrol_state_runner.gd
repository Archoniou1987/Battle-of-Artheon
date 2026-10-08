extends SceneTree

func _initialize()->void:
	var map:=TacticalMapState.new(8,8)
	var route:Array[Vector2i]=[Vector2i(2,2),Vector2i(3,2),Vector2i(3,3)]
	var valid:=map.place_entity("PATROL_1",route[0])
	var patrol:=HexPatrolState.new("PATROL_1",route)
	var paused:=patrol.step(map,true)
	valid=valid and String(paused.get("reason",""))=="combat_paused"
	valid=valid and map.entity_positions["PATROL_1"]==route[0]
	for expected in [route[1],route[2],route[1],route[0]]:
		var result:=patrol.step(map)
		valid=valid and bool(result.get("ok",false))
		valid=valid and map.entity_positions["PATROL_1"]==expected
	var bad_route:Array[Vector2i]=[Vector2i(2,2),Vector2i(4,4)]
	var bad:=HexPatrolState.new("PATROL_2",bad_route)
	valid=valid and map.place_entity("PATROL_2",bad_route[0])
	valid=valid and String(bad.step(map).get("reason",""))=="invalid_route"
	valid=valid and map.entity_positions["PATROL_2"]==bad_route[0]
	var pause_map:=TacticalMapState.new(8,8)
	valid=valid and pause_map.place_entity("PATROL_WAIT",route[0])
	var waiting:=HexPatrolState.new("PATROL_WAIT",route)
	waiting.set_pause_points([{"path_index":1,"pause_seconds":3.0}])
	valid=valid and bool(waiting.step(pause_map).get("ok",false))
	valid=valid and String(waiting.step(pause_map,false,1.0).get("reason",""))=="patrol_waiting"
	valid=valid and String(waiting.step(pause_map,true,10.0).get("reason",""))=="combat_paused"
	valid=valid and is_equal_approx(waiting.remaining_pause_seconds,2.0)
	valid=valid and String(waiting.step(pause_map,false,2.0).get("reason",""))=="patrol_waiting"
	valid=valid and bool(waiting.step(pause_map).get("ok",false))
	valid=valid and pause_map.entity_positions["PATROL_WAIT"]==route[2]
	var contact_map:=TacticalMapState.new(8,8)
	valid=valid and contact_map.place_entity("PATROL_CONTACT",route[0])
	valid=valid and contact_map.place_entity("PLAYER",route[1])
	var contact_patrol:=HexPatrolState.new("PATROL_CONTACT",route)
	var contact:=contact_patrol.step(contact_map,false,1.0,"PLAYER")
	valid=valid and String(contact.get("reason",""))=="player_contact"
	valid=valid and contact.get("cell",Vector2i.ZERO)==route[1]
	valid=valid and contact_map.entity_positions["PATROL_CONTACT"]==route[0]
	valid=valid and contact_patrol.path_index==0
	print("HEX_PATROL_STATE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
