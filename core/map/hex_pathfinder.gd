class_name HexPathfinder
extends RefCounted

func find_path(map:TacticalMapState, start:Vector2i, goal:Vector2i)->Dictionary:
	if not map.in_bounds(start) or not map.in_bounds(goal):
		return {"ok":false, "reason":"out_of_bounds", "path":[], "cost":0.0}
	if not map.cell(goal).is_passable():
		return {"ok":false, "reason":"blocked", "path":[], "cost":0.0}
	var frontier:Array[Vector2i] = [start]
	var came_from:Dictionary = {start:start}
	var cost_so_far:Dictionary = {start:0.0}
	while not frontier.is_empty():
		var current:=_lowest_score(frontier, cost_so_far, goal)
		frontier.erase(current)
		if current == goal:
			break
		for next in map.neighbors(current, true):
			var new_cost:float = float(cost_so_far[current]) + map.cell(next).movement_cost
			if not cost_so_far.has(next) or new_cost < float(cost_so_far[next]):
				cost_so_far[next] = new_cost
				came_from[next] = current
				if not frontier.has(next):
					frontier.append(next)
	if not came_from.has(goal):
		return {"ok":false, "reason":"unreachable", "path":[], "cost":0.0}
	var path:Array[Vector2i] = []
	var cursor:=goal
	while cursor != start:
		path.push_front(cursor)
		cursor = came_from[cursor]
	path.push_front(start)
	return {"ok":true, "path":path, "cost":float(cost_so_far[goal])}

func _lowest_score(frontier:Array[Vector2i], costs:Dictionary, goal:Vector2i)->Vector2i:
	var best:=frontier[0]
	var best_score:=float(costs[best]) + float(HexGrid.distance(best, goal))
	for candidate in frontier:
		var score:=float(costs[candidate]) + float(HexGrid.distance(candidate, goal))
		if score < best_score:
			best = candidate
			best_score = score
	return best
