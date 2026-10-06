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
	print("HEX_PATH steps=%d cost=%.2f used_road=%s"%[path.size()-1,float(route.get("cost",0.0)),used_road])
	print("HEX_PATHFINDING_TEST="+("PASS" if valid else "FAIL")); quit(0 if valid else 1)
