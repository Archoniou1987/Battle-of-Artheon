extends SceneTree
func _initialize()->void:
	var map:=TacticalMapState.new(15,15)
	var start:=Vector2i(1,5); var goal:=Vector2i(7,5)
	for q in range(2,7): map.set_terrain(Vector2i(q,5),"swamp",3.0)
	for q in range(2,7): map.set_terrain(Vector2i(q,4),"road",0.6)
	map.set_obstacle(Vector2i(4,5),"rock",true)
	var route:=HexPathfinder.new().find_path(map,start,goal)
	var path:Array=route.get("path",[])
	var valid:=HexGrid.neighbors(Vector2i(5,5)).size()==6 and HexGrid.distance(start,goal)==6
	valid=valid and bool(route.get("ok",false)) and path.size()>2 and not path.has(Vector2i(4,5))
	var used_road:=false
	for pos in path:
		if map.cell(pos).terrain_id=="road": used_road=true
	valid=valid and used_road and float(route.get("cost",999.0))<10.0
	var blocked_goal:=Vector2i(10,10); map.set_obstacle(blocked_goal,"wall",true)
	var rejected:=HexPathfinder.new().find_path(map,start,blocked_goal)
	valid=valid and not bool(rejected.get("ok",true)) and String(rejected.get("reason",""))=="blocked"
	# A cheap detour must beat the direct route, even when costs are below 1.
	var cheap_map:=TacticalMapState.new(5,3,"plain",1.0)
	for q in range(1,4):
		cheap_map.set_terrain(Vector2i(q,1),"expensive",5.0)
	for q in range(5):
		cheap_map.set_terrain(Vector2i(q,0),"cheap",0.1)
	var cheap_route:=HexPathfinder.new().find_path(cheap_map,Vector2i(0,1),Vector2i(4,1))
	valid=valid and bool(cheap_route.get("ok",false)) and float(cheap_route.get("cost",999.0))<6.0
	var blocked_start_map:=TacticalMapState.new(3,3)
	blocked_start_map.set_obstacle(Vector2i(0,0),"wall",true)
	var blocked_start:=HexPathfinder.new().find_path(blocked_start_map,Vector2i(0,0),Vector2i(2,2))
	valid=valid and not bool(blocked_start.get("ok",true)) and String(blocked_start.get("reason",""))=="blocked"
	print("HEX_PATH steps=%d cost=%.2f used_road=%s"%[path.size()-1,float(route.get("cost",0.0)),used_road])
	print("HEX_PATHFINDING_TEST="+("PASS" if valid else "FAIL")); quit(0 if valid else 1)
