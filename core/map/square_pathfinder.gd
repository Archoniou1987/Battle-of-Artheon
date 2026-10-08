class_name SquarePathfinder
extends RefCounted

static func find_path(map:SquareMapState,start:Vector2i,goal:Vector2i)->Dictionary:
	if not map.is_passable(start) or not map.is_passable(goal):
		return {"ok":false,"path":[]}
	if start==goal:
		return {"ok":true,"path":[start]}
	var frontier:Array[Vector2i]=[start]
	var came_from:Dictionary={start:start}
	var index:=0
	while index<frontier.size():
		var current:Vector2i=frontier[index]
		index+=1
		for next_pos in map.passable_neighbors(current):
			if came_from.has(next_pos):
				continue
			came_from[next_pos]=current
			if next_pos==goal:
				var path:Array[Vector2i]=[goal]
				var cursor:=goal
				while cursor!=start:
					cursor=came_from[cursor]
					path.push_front(cursor)
				return {"ok":true,"path":path}
			frontier.append(next_pos)
	return {"ok":false,"path":[]}
