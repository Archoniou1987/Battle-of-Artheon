extends SceneTree

func _initialize()->void:
	var valid:=true
	var map:=SquareMapState.new(10,10,Vector2i(0,0))
	var shared:=Vector2i(3,2)
	valid=valid and map.place_entity("NPC_A",shared)
	valid=valid and map.place_entity("NPC_B",shared)
	valid=valid and map.place_entity("NPC_C",shared)
	valid=valid and map.entities_at(shared)==["NPC_A","NPC_B","NPC_C"]
	valid=valid and map.is_passable(shared)

	var route:=SquarePathfinder.find_path(map,Vector2i(0,2),Vector2i(6,2))
	valid=valid and bool(route.get("ok",false))
	valid=valid and route.get("path",[]).has(shared)

	map.set_blocked(shared,true)
	valid=valid and not map.is_passable(shared)
	var detour:=SquarePathfinder.find_path(map,Vector2i(0,2),Vector2i(6,2))
	valid=valid and bool(detour.get("ok",false))
	valid=valid and not detour.get("path",[]).has(shared)
	valid=valid and map.entities_at(shared).size()==3

	map.set_blocked(shared,false)
	map.player_position=Vector2i(2,2)
	var movement:=map.move_player(shared)
	valid=valid and bool(movement.get("ok",false))
	valid=valid and map.entities_at(map.player_position).size()==3

	var restored:=SquareMapState.from_dict(map.to_dict())
	valid=valid and restored.entities_at(shared)==["NPC_A","NPC_B","NPC_C"]
	valid=valid and restored.is_passable(shared)
	valid=valid and restored.remove_entity("NPC_B")
	valid=valid and restored.entities_at(shared)==["NPC_A","NPC_C"]

	print("SQUARE_MAP_ENTITY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
