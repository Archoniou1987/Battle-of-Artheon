extends SceneTree

func _initialize()->void:
	var passed:=true
	var checks:=0
	var map:=TacticalMapState.new(30,30)
	var pf:=HexPathfinder.new()

	# Geometry: every interior cell has six unique neighbors at distance one.
	for r in range(1,29):
		for q in range(1,29):
			var origin:=Vector2i(q,r)
			var ns:=map.neighbors(origin)
			passed=passed and ns.size()==6
			for n in ns:
				passed=passed and HexGrid.distance(origin,n)==1
			checks+=1

	# Boundaries never expose cells outside the map.
	for pos in [Vector2i(0,0),Vector2i(29,0),Vector2i(0,29),Vector2i(29,29)]:
		for n in map.neighbors(pos):
			passed=passed and map.in_bounds(n)
		checks+=1

	# Build a wall with one gate. Every tested route must use the gate.
	for r in range(30):
		if r!=15: map.set_obstacle(Vector2i(14,r),"WALL",true)
	var gate:=Vector2i(14,15)
	for r in range(2,28,5):
		var start:=Vector2i(2,r)
		var goal:=Vector2i(27,r)
		var route:=pf.find_path(map,start,goal)
		var path:Array=route.get("path",[])
		passed=passed and bool(route.get("ok",false)) and path.has(gate)
		checks+=1

	# Seal the gate: opposite side becomes unreachable.
	map.set_obstacle(gate,"WALL",true)
	var sealed:=pf.find_path(map,Vector2i(2,15),Vector2i(27,15))
	passed=passed and not bool(sealed.get("ok",true)) and String(sealed.get("reason",""))=="unreachable"
	checks+=1

	# Invalid and blocked destinations are rejected.
	var outside:=pf.find_path(map,Vector2i(2,2),Vector2i(30,2))
	passed=passed and String(outside.get("reason",""))=="out_of_bounds"
	var blocked:=pf.find_path(map,Vector2i(2,2),Vector2i(14,2))
	passed=passed and String(blocked.get("reason",""))=="blocked"
	checks+=2

	# Weighted terrain: longer cheap road beats shorter expensive swamp.
	var weighted:=TacticalMapState.new(20,20)
	for q in range(3,16): weighted.set_terrain(Vector2i(q,10),"swamp",4.0)
	for q in range(2,17): weighted.set_terrain(Vector2i(q,9),"road",0.5)
	var weighted_route:=pf.find_path(weighted,Vector2i(2,10),Vector2i(16,10))
	var weighted_path:Array=weighted_route.get("path",[])
	var road_steps:=0
	for pos in weighted_path:
		if weighted.cell(pos).terrain_id=="road": road_steps+=1
	passed=passed and bool(weighted_route.get("ok",false)) and road_steps>=10
	checks+=1

	# Deterministic route queries across many start/goal pairs.
	var open_map:=TacticalMapState.new(25,25)
	for i in range(100):
		var start:=Vector2i((i*7)%25,(i*11)%25)
		var goal:=Vector2i((i*13+3)%25,(i*17+5)%25)
		var route:=pf.find_path(open_map,start,goal)
		var path:Array=route.get("path",[])
		passed=passed and bool(route.get("ok",false))
		if bool(route.get("ok",false)):
			passed=passed and path.front()==start and path.back()==goal
			for j in range(1,path.size()):
				passed=passed and HexGrid.distance(path[j-1],path[j])==1
		checks+=1

	print("HEX_STRESS checks=%d weighted_road_steps=%d"%[checks,road_steps])
	print("HEX_PATHFINDING_STRESS_TEST="+("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
