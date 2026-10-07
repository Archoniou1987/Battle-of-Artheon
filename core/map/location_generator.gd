class_name LocationGenerator
extends RefCounted

static func generate(width:int, height:int, seed_value:int = 1)->Dictionary:
	var safe_width:=maxi(5,width)
	var safe_height:=maxi(5,height)
	var map:=TacticalMapState.new(safe_width,safe_height,"grass",1.0)
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var entrance:=Vector2i(0,rng.randi_range(0,safe_height-1))
	var exit:=Vector2i(safe_width-1,rng.randi_range(0,safe_height-1))
	var guaranteed_path:Array[Vector2i]=[]
	var cursor:=entrance
	guaranteed_path.append(cursor)
	while cursor.x<exit.x:
		var next:=Vector2i(cursor.x+1,cursor.y)
		if cursor.y<exit.y and rng.randf()<0.55:
			next.y+=1
		elif cursor.y>exit.y and rng.randf()<0.55:
			next.y-=1
		cursor=next
		guaranteed_path.append(cursor)
	while cursor.y!=exit.y:
		cursor=Vector2i(cursor.x,cursor.y+(1 if cursor.y<exit.y else -1))
		guaranteed_path.append(cursor)
	var protected:Dictionary={}
	for pos in guaranteed_path:
		protected[pos]=true
	for r in range(safe_height):
		for q in range(safe_width):
			var pos:=Vector2i(q,r)
			if protected.has(pos) or pos==entrance or pos==exit:
				continue
			var roll:=rng.randf()
			if roll<0.12:
				map.set_obstacle(pos,"rock",true)
			elif roll<0.27:
				map.set_terrain(pos,"swamp",2.0)
			elif roll<0.42:
				map.set_terrain(pos,"rough",1.5)
	map.mark_visited(entrance)
	var content_cells:Array[Vector2i]=[]
	for r in range(safe_height):
		for q in range(safe_width):
			var content_pos:=Vector2i(q,r)
			if content_pos!=entrance and content_pos!=exit and map.cell(content_pos).is_passable():
				content_cells.append(content_pos)
	for i in range(content_cells.size()-1,0,-1):
		var j:=rng.randi_range(0,i)
		var swap:=content_cells[i]
		content_cells[i]=content_cells[j]
		content_cells[j]=swap
	var resource_cells:Array[Vector2i]=[]
	var npc_cells:Array[Vector2i]=[]
	var object_cells:Array[Vector2i]=[]
	var encounter_cells:Array[Vector2i]=[]
	for i in range(mini(3,content_cells.size())):
		resource_cells.append(content_cells.pop_back())
	for i in range(mini(4,content_cells.size())):
		npc_cells.append(content_cells.pop_back())
	for i in range(mini(3,content_cells.size())):
		object_cells.append(content_cells.pop_back())
	for i in range(mini(3,content_cells.size())):
		encounter_cells.append(content_cells.pop_back())
	for i in range(resource_cells.size()):
		var area:=MapArea.new("GEN_RESOURCE_%02d"%i,"resource",1,"common",1.0,60.0)
		map.add_area(area,[resource_cells[i]])
	for i in range(object_cells.size()):
		map.add_object("GEN_OBJECT_%02d"%i,object_cells[i])
	for i in range(npc_cells.size()):
		map.place_entity("GEN_NPC_%02d"%i,npc_cells[i])
	var encounter_service:=HexEncounterService.new()
	for i in range(encounter_cells.size()):
		var encounter:=HexEncounter.new("GEN_ENCOUNTER_%02d"%i,HexEncounter.TRIGGER_ENTER,"damage",{"amount":1},true)
		encounter_service.add_encounter(encounter,encounter_cells[i],map)
	var route_guards:Array[Dictionary]=[]
	var route_candidates:Array[Vector2i]=[]
	for route_pos in guaranteed_path:
		if route_pos!=entrance and route_pos!=exit and not npc_cells.has(route_pos):
			route_candidates.append(route_pos)
	if not route_candidates.is_empty():
		var guard_pos:=route_candidates[rng.randi_range(0,route_candidates.size()-1)]
		var guard_id:="GEN_ROUTE_GUARD_00"
		if map.place_entity(guard_id,guard_pos):
			route_guards.append({"guard_id":guard_id,"guard_pos":guard_pos})
	var patrols:Array[Dictionary]=[]
	var patrol_candidates:Array[Vector2i]=[]
	for patrol_pos in content_cells:
		if not npc_cells.has(patrol_pos):
			patrol_candidates.append(patrol_pos)
	if patrol_candidates.size()>=2:
		var patrol_start:Vector2i=patrol_candidates.pop_back()
		var patrol_goal:Vector2i=patrol_candidates[rng.randi_range(0,patrol_candidates.size()-1)]
		var patrol_result:Dictionary=HexPathfinder.new().find_path(map,patrol_start,patrol_goal)
		var patrol_path:Array=patrol_result.get("path",[])
		if bool(patrol_result.get("ok",false)) and patrol_path.size()>=2:
			var patrol_id:="GEN_PATROL_00"
			if map.place_entity(patrol_id,patrol_start):
				patrols.append({"patrol_id":patrol_id,"start":patrol_start,"goal":patrol_goal,"path":patrol_path})
	var boss_groups:Array[Dictionary]=[]
	var boss_candidates:Array[Vector2i]=[]
	for boss_candidate in content_cells:
		if map.entities_at(boss_candidate).is_empty():
			boss_candidates.append(boss_candidate)
	while not boss_candidates.is_empty() and boss_groups.is_empty():
		var boss_index:int=rng.randi_range(0,boss_candidates.size()-1)
		var boss_pos:Vector2i=boss_candidates[boss_index]
		boss_candidates.remove_at(boss_index)
		var boss_id:="GEN_BOSS_00"
		if not map.place_entity(boss_id,boss_pos):
			continue
		var guard_ids:Array[String]=[]
		var guard_positions:Array[Vector2i]=[]
		var boss_neighbors:Array[Vector2i]=map.neighbors(boss_pos,true)
		for i in range(boss_neighbors.size()-1,0,-1):
			var j:int=rng.randi_range(0,i)
			var swap:Vector2i=boss_neighbors[i]
			boss_neighbors[i]=boss_neighbors[j]
			boss_neighbors[j]=swap
		for guard_pos in boss_neighbors:
			if guard_ids.size()>=2:
				break
			if guard_pos==entrance or guard_pos==exit or not map.entities_at(guard_pos).is_empty():
				continue
			var guard_id:="GEN_BOSS_GUARD_%02d"%guard_ids.size()
			if map.place_entity(guard_id,guard_pos):
				guard_ids.append(guard_id)
				guard_positions.append(guard_pos)
		var member_ids:Array[String]=[boss_id]
		member_ids.append_array(guard_ids)
		var encounter_id:="GEN_BOSS_ENCOUNTER_00"
		var boss_encounter:=HexEncounter.new(encounter_id,HexEncounter.TRIGGER_ENTER,"combat",{"group_id":"GEN_BOSS_GROUP_00","boss_id":boss_id,"member_ids":member_ids},true)
		if encounter_service.add_encounter(boss_encounter,boss_pos,map):
			boss_groups.append({"group_id":"GEN_BOSS_GROUP_00","encounter_id":encounter_id,"boss_id":boss_id,"boss_pos":boss_pos,"guard_ids":guard_ids,"guard_positions":guard_positions,"member_ids":member_ids})
	var guarded_objects:Array[Dictionary]=[]
	var reserved_guard_cells:Dictionary={}
	for object_pos in object_cells:
		var candidates:Array[Vector2i]=[]
		for neighbor in map.neighbors(object_pos,true):
			if neighbor!=entrance and neighbor!=exit and not reserved_guard_cells.has(neighbor) and map.entities_at(neighbor).is_empty():
				candidates.append(neighbor)
		if candidates.is_empty():
			continue
		var guard_pos:=candidates[rng.randi_range(0,candidates.size()-1)]
		var guard_id:="GEN_GUARD_%02d"%guarded_objects.size()
		if map.place_entity(guard_id,guard_pos):
			reserved_guard_cells[guard_pos]=true
			guarded_objects.append({"object_pos":object_pos,"guard_pos":guard_pos,"guard_id":guard_id})
	return {"map":map,"entrance":entrance,"exit":exit,"seed":seed_value,"guaranteed_path":guaranteed_path,"resource_cells":resource_cells,"npc_cells":npc_cells,"object_cells":object_cells,"encounter_cells":encounter_cells,"encounter_service":encounter_service,"guarded_objects":guarded_objects,"route_guards":route_guards,"patrols":patrols,"boss_groups":boss_groups}
