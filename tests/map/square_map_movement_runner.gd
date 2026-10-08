extends SceneTree

func _initialize()->void:
	var valid:=true
	var map:=SquareMapState.new(10,10,Vector2i(0,0))
	valid=valid and map.width==10 and map.height==10
	valid=valid and map.passable_neighbors(Vector2i(0,0)).size()==2
	valid=valid and bool(map.move_player(Vector2i(1,0)).get("ok",false))
	valid=valid and not bool(map.move_player(Vector2i(2,1)).get("ok",false))
	map.set_blocked(Vector2i(2,0),true)
	valid=valid and not bool(map.move_player(Vector2i(2,0)).get("ok",false))

	var route_map:=SquareMapState.new(10,10,Vector2i(0,0))
	for y in range(9):
		route_map.set_blocked(Vector2i(4,y),true)
	var route:=SquarePathfinder.find_path(route_map,Vector2i(0,0),Vector2i(9,9))
	var path:Array=route.get("path",[])
	valid=valid and bool(route.get("ok",false)) and not path.is_empty()
	valid=valid and path[0]==Vector2i(0,0) and path[path.size()-1]==Vector2i(9,9)
	for i in range(1,path.size()):
		valid=valid and SquareGrid.distance(path[i-1],path[i])==1
		valid=valid and route_map.is_passable(path[i])

	var restored:=SquareMapState.from_dict(route_map.to_dict())
	valid=valid and restored.width==10 and restored.height==10
	valid=valid and not restored.is_passable(Vector2i(4,3))
	valid=valid and restored.player_position==route_map.player_position

	var large:=SquareMapState.new(50,30,Vector2i(0,0))
	var large_route:=SquarePathfinder.find_path(large,Vector2i(0,0),Vector2i(49,29))
	valid=valid and bool(large_route.get("ok",false))
	valid=valid and large_route.get("path",[]).size()==79

	print("SQUARE_MAP_MOVEMENT_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
