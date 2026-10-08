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
	print("HEX_PATROL_STATE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
