class_name SafeMapNavigation
extends RefCounted

static func terrain_seconds(terrain:String)->float:
	match terrain:
		"road": return 2.0
		"swamp": return 10.0
		"rough", "forest": return 6.0
		_: return 4.0

static func static_npc_at(map:TacticalMapState,roles:Dictionary,pos:Vector2i)->bool:
	for entity_id in map.entities_at(pos):
		if entity_id=="PLAYER" or roles.get(entity_id,"")=="P":
			continue
		return true
	return false

static func find_route(map:TacticalMapState,explored:Dictionary,origin:Vector2i,destination:Vector2i,visible:Dictionary,roles:Dictionary,allow_destination_npc:bool=false)->Array[Vector2i]:
	var empty:Array[Vector2i]=[]
	if not map.in_bounds(origin) or not map.in_bounds(destination): return empty
	if not explored.has(destination) or not map.cell(destination).is_passable(): return empty
	var frontier:Array[Vector2i]=[origin]
	var cost:Dictionary={origin:0.0}
	var previous:Dictionary={origin:origin}
	var settled:Dictionary={}
	while not frontier.is_empty():
		var best:=0
		for i in range(1,frontier.size()):
			if float(cost[frontier[i]])<float(cost[frontier[best]]): best=i
		var current:Vector2i=frontier[best]
		frontier.remove_at(best)
		if settled.has(current): continue
		settled[current]=true
		if current==destination: break
		for neighbor in map.neighbors(current,true):
			if not explored.has(neighbor) or settled.has(neighbor): continue
			if visible.has(neighbor) and static_npc_at(map,roles,neighbor) and not (allow_destination_npc and neighbor==destination): continue
			var next_cost:float=float(cost[current])+terrain_seconds(map.cell(neighbor).terrain_id)
			if not cost.has(neighbor) or next_cost<float(cost[neighbor]):
				cost[neighbor]=next_cost
				previous[neighbor]=current
				frontier.append(neighbor)
	if not previous.has(destination): return empty
	var route:Array[Vector2i]=[]
	var cursor:Vector2i=destination
	while cursor!=origin:
		route.push_front(cursor)
		cursor=previous[cursor]
	route.push_front(origin)
	return route
