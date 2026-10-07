class_name HexPathfinder
extends RefCounted

func find_path(map:TacticalMapState, start:Vector2i, goal:Vector2i)->Dictionary:
	if not map.in_bounds(start) or not map.in_bounds(goal):
		return {"ok":false, "reason":"out_of_bounds", "path":[], "cost":0.0}
	if not map.cell(goal).is_passable():
		return {"ok":false, "reason":"blocked", "path":[], "cost":0.0}
	var frontier:Array[Vector2i] = [start]
	var frontier_set:Dictionary = {start:true}
	var came_from:Dictionary = {start:start}
	var cost_so_far:Dictionary = {start:0.0}
	var closed:Dictionary = {}
	while not frontier.is_empty():
		var best_index:=_lowest_score_index(frontier, cost_so_far, goal)
		var current:Vector2i=frontier[best_index]
		frontier.remove_at(best_index)
		frontier_set.erase(current)
		if closed.has(current):
			continue
		closed[current] = true
		if current == goal:
			break
		for next in map.neighbors(current, true):
			if closed.has(next):
				continue
			var new_cost:float = float(cost_so_far[current]) + map.cell(next).movement_cost
			if not cost_so_far.has(next) or new_cost < float(cost_so_far[next]):
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not frontier_set.has(next):
					frontier.append(next)
					frontier_set[next] = true
	if not came_from.has(goal):
		return {"ok":false, "reason":"unreachable", "path":[], "cost":0.0}
	var path:Array[Vector2i] = []
	var cursor:=goal
	while cursor != start:
		path.push_back(cursor)
		cursor = came_from[cursor]
	path.push_back(start)
	path.reverse()
	return {"ok":true, "path":path, "cost":float(cost_so_far[goal])}

func _lowest_score_index(frontier:Array[Vector2i], costs:Dictionary, goal:Vector2i)->int:
	var best_index:=0
	var best_score:=float(costs[frontier[0]]) + float(HexGrid.distance(frontier[0], goal))
	for i in range(1,frontier.size()):
		var candidate:=frontier[i]
		var score:=float(costs[candidate]) + float(HexGrid.distance(candidate, goal))
		if score < best_score:
			best_index = i
			best_score = score
	return best_index
