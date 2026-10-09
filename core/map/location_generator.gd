class_name LocationGenerator
extends RefCounted

const SAFE_ENTRANCE_RADIUS:=3
const BASE_RESOURCES:=8
const BASE_NPCS:=12
const BASE_OBJECTS:=5
const BASE_ENCOUNTERS:=6
const BASE_PATROLS:=5
const MIN_PATROL_PATH_CELLS:=8

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
	# Walk the rectangular offset grid using real hex neighbors.
	# First move horizontally, then finish with a shortest hex path.
	while cursor != exit:
		var candidates:Array[Vector2i]=[]
		var best_distance:=HexGrid.distance(cursor,exit)
		for neighbor in HexGrid.neighbors(cursor):
			if map.in_bounds(neighbor) and HexGrid.distance(neighbor,exit)<best_distance:
				candidates.append(neighbor)
		if candidates.is_empty():
			break
		cursor=candidates[rng.randi_range(0,candidates.size()-1)]
		guaranteed_path.append(cursor)
	var protected:Dictionary={}
	for pos in guaranteed_path:
		protected[pos]=true
	var region_result:Dictionary=MapRegionGenerator.generate(map,entrance,exit,guaranteed_path,rng)
	var thematic_reserved:Dictionary={}
	for region in region_result["regions"]:
		for pos in region["cells"]:
			thematic_reserved[pos]=true
	for pocket in region_result["pockets"]:
		for pos in pocket["cells"]:
			thematic_reserved[pos]=true
		for pos in pocket["border"]:
			thematic_reserved[pos]=true
		thematic_reserved[pocket["gate"]]=true
	# Standard terrain is generated only after the thematic regions are fixed.
	for r in range(safe_height):
		for q in range(safe_width):
			var pos:=Vector2i(q,r)
			if protected.has(pos) or pos==entrance or pos==exit or thematic_reserved.has(pos):
				continue
			var roll:=rng.randf()
			if roll<0.12:
				map.set_obstacle(pos,"rock",true)
			elif roll<0.27:
				map.set_terrain(pos,"swamp",2.0)
			elif roll<0.42:
				map.set_terrain(pos,"rough",1.5)
	map.mark_visited(entrance)

	# Guarded objects are deliberately built as one-cell dead-end pockets.
	# The guard occupies the pocket's only passable entrance, so the object
	# cannot be bypassed geometrically.
	var object_cells:Array[Vector2i]=[]
	var guarded_objects:Array[Dictionary]=[]
	var reserved_guard_cells:Dictionary={}
	var pocket_candidates:Array[Vector2i]=[]
	for r in range(safe_height):
		for q in range(safe_width):
			var candidate:=Vector2i(q,r)
			if candidate==entrance or candidate==exit or protected.has(candidate) or thematic_reserved.has(candidate):
				continue
			if HexGrid.distance(entrance,candidate)<=SAFE_ENTRANCE_RADIUS+1:
				continue
			if map.cell(candidate).is_passable():
				pocket_candidates.append(candidate)
	_shuffle_cells(pocket_candidates,rng)
	for object_pos in pocket_candidates:
		if object_cells.size()>=BASE_OBJECTS:
			break
		# Earlier pockets may have changed this candidate after the candidate list was built.
		# Never reuse an existing object/guard cell and never shape an already blocked cell.
		if object_cells.has(object_pos) or reserved_guard_cells.has(object_pos) or thematic_reserved.has(object_pos) or not map.cell(object_pos).is_passable():
			continue
		var passable_neighbors:Array[Vector2i]=map.neighbors(object_pos,true)
		if passable_neighbors.is_empty():
			continue
		var protected_neighbors:Array[Vector2i]=[]
		for neighbor in passable_neighbors:
			if protected.has(neighbor):
				protected_neighbors.append(neighbor)
		if protected_neighbors.size()>1:
			continue
		var guard_pos:Vector2i=protected_neighbors[0] if protected_neighbors.size()==1 else passable_neighbors[rng.randi_range(0,passable_neighbors.size()-1)]
		if reserved_guard_cells.has(guard_pos) or HexGrid.distance(entrance,guard_pos)<=SAFE_ENTRANCE_RADIUS:
			continue
		var can_shape:=true
		# A new pocket must not block the access guard of any pocket already committed.
		# This can happen even when the new object cell itself is still free.
		for neighbor in passable_neighbors:
			if neighbor==guard_pos:
				continue
			if protected.has(neighbor) or thematic_reserved.has(neighbor) or neighbor==entrance or neighbor==exit or reserved_guard_cells.has(neighbor):
				can_shape=false
				break
		if not can_shape:
			continue
		var before_reachable:Dictionary=_reachable_cells(map,entrance)
		var changed_neighbors:Array[Vector2i]=[]
		for neighbor in passable_neighbors:
			if neighbor!=guard_pos:
				map.set_obstacle(neighbor,"object_pocket_wall",true)
				changed_neighbors.append(neighbor)
		var after_reachable:Dictionary=_reachable_cells(map,entrance)
		var valid_access:=after_reachable.has(guard_pos) and after_reachable.has(object_pos)
		for previous_cell in before_reachable.keys():
			if not after_reachable.has(previous_cell):
				valid_access=false
				break
		if not valid_access:
			for neighbor in changed_neighbors:
				map.set_obstacle(neighbor,"",false)
			continue
		var object_id:="GEN_OBJECT_%02d"%object_cells.size()
		var guard_id:="GEN_GUARD_%02d"%guarded_objects.size()
		map.add_object(object_id,object_pos)
		map.place_entity(guard_id,guard_pos)
		object_cells.append(object_pos)
		reserved_guard_cells[guard_pos]=true
		guarded_objects.append({"object_pos":object_pos,"guard_pos":guard_pos,"guard_id":guard_id})

	var accessible:Dictionary=_reachable_cells(map,entrance)
	var content_cells:Array[Vector2i]=[]
	for r in range(safe_height):
		for q in range(safe_width):
			var content_pos:=Vector2i(q,r)
			if content_pos==entrance or content_pos==exit or thematic_reserved.has(content_pos) or object_cells.has(content_pos) or reserved_guard_cells.has(content_pos):
				continue
			if map.cell(content_pos).is_passable() and accessible.has(content_pos):
				content_cells.append(content_pos)
	_shuffle_cells(content_cells,rng)

	var resource_cells:Array[Vector2i]=[]
	var npc_cells:Array[Vector2i]=[]
	var encounter_cells:Array[Vector2i]=[]
	_take_safe_cells(resource_cells,content_cells,BASE_RESOURCES,entrance,0)
	_take_safe_cells(npc_cells,content_cells,BASE_NPCS,entrance,SAFE_ENTRANCE_RADIUS)
	_take_safe_cells(encounter_cells,content_cells,BASE_ENCOUNTERS,entrance,SAFE_ENTRANCE_RADIUS)
	for i in range(resource_cells.size()):
		var area:=MapArea.new("GEN_RESOURCE_%02d"%i,"resource",1,"common",1.0,60.0)
		map.add_area(area,[resource_cells[i]])
	for i in range(npc_cells.size()):
		map.place_entity("GEN_NPC_%02d"%i,npc_cells[i])
	# Populate thematic pockets independently of ordinary map content.
	var region_npcs:Array[Dictionary]=[]
	for region in region_result["regions"]:
		var available:Array[Vector2i]=[]
		for pos in region["cells"]:
			if accessible.has(pos) and map.cell(pos).is_passable() and map.entities_at(pos).is_empty():
				available.append(pos)
		_shuffle_cells(available,rng)
		var count:int=mini(3,available.size())
		for j in range(count):
			var entity_id:="GEN_REGION_NPC_%02d_%02d"%[region_npcs.size(),j]
			var npc_pos:Vector2i=available[j]
			if map.place_entity(entity_id,npc_pos):
				region_npcs.append({"entity_id":entity_id,"region_id":region["region_id"],"region_type":region["region_type"],"pos":npc_pos})
	var region_objects:Array[Dictionary]=[]
	var kinds:Dictionary={"bandit_camp":"tent","graveyard":"grave","beast_den":"bones","ruins":"relic"}
	for region in region_result["regions"]:
		var choices:Array[Vector2i]=[]
		for pos in region["cells"]:
			if accessible.has(pos) and map.cell(pos).is_passable() and map.entities_at(pos).is_empty() and map.cell(pos).object_ids.is_empty():
				choices.append(pos)
		_shuffle_cells(choices,rng)
		for j in range(mini(3,choices.size())):
			var object_id:="GEN_REGION_PROP_%s_%02d"%[str(region["region_id"]),j]
			var prop_pos:Vector2i=choices[j]
			if map.add_object(object_id,prop_pos):
				region_objects.append({"object_id":object_id,"region_id":region["region_id"],"region_type":region["region_type"],"kind":kinds.get(region["region_type"],"relic"),"pos":prop_pos})
	var encounter_service:=HexEncounterService.new()
	for i in range(encounter_cells.size()):
		var encounter:=HexEncounter.new("GEN_ENCOUNTER_%02d"%i,HexEncounter.TRIGGER_ENTER,"damage",{"amount":1},true)
		encounter_service.add_encounter(encounter,encounter_cells[i],map)

	var route_guards:Array[Dictionary]=[]
	var route_candidates:Array[Vector2i]=[]
	for route_pos in guaranteed_path:
		if route_pos!=entrance and route_pos!=exit and HexGrid.distance(entrance,route_pos)>SAFE_ENTRANCE_RADIUS and map.entities_at(route_pos).is_empty():
			route_candidates.append(route_pos)
	if not route_candidates.is_empty():
		var guard_pos:=route_candidates[rng.randi_range(0,route_candidates.size()-1)]
		var guard_id:="GEN_ROUTE_GUARD_00"
		if map.place_entity(guard_id,guard_pos):
			route_guards.append({"guard_id":guard_id,"guard_pos":guard_pos})

	var patrols:Array[Dictionary]=[]
	var patrol_starts:=content_cells.duplicate()
	_shuffle_cells(patrol_starts,rng)
	var patrol_attempts:=0
	while patrols.size()<BASE_PATROLS and not patrol_starts.is_empty() and patrol_attempts<200:
		patrol_attempts+=1
		var patrol_start:Vector2i=patrol_starts.pop_back()
		if thematic_reserved.has(patrol_start) or HexGrid.distance(entrance,patrol_start)<=SAFE_ENTRANCE_RADIUS or not map.entities_at(patrol_start).is_empty():
			continue
		var goals:=content_cells.duplicate()
		_shuffle_cells(goals,rng)
		var chosen_path:Array=[]
		var chosen_goal:=patrol_start
		for patrol_goal in goals:
			if patrol_goal==patrol_start or thematic_reserved.has(patrol_goal) or HexGrid.distance(entrance,patrol_goal)<=SAFE_ENTRANCE_RADIUS:
				continue
			var patrol_result:Dictionary=HexPathfinder.new().find_path(map,patrol_start,patrol_goal)
			var candidate_path:Array=patrol_result.get("path",[])
			if not bool(patrol_result.get("ok",false)) or candidate_path.size()<MIN_PATROL_PATH_CELLS:
				continue
			var safe_path:=true
			for step in candidate_path:
				if thematic_reserved.has(step) or HexGrid.distance(entrance,step)<=SAFE_ENTRANCE_RADIUS:
					safe_path=false
					break
			if not safe_path:
				continue
			chosen_path=candidate_path
			chosen_goal=patrol_goal
			break
		if chosen_path.is_empty():
			continue
		var patrol_id:="GEN_PATROL_%02d"%patrols.size()
		if not map.place_entity(patrol_id,patrol_start):
			continue
		var pause_points:Array[Dictionary]=[]
		pause_points.append({"path_index":0,"pause_seconds":rng.randf_range(2.0,5.0)})
		if chosen_path.size()>=6:
			var middle_index:=rng.randi_range(2,chosen_path.size()-3)
			pause_points.append({"path_index":middle_index,"pause_seconds":rng.randf_range(1.5,4.0)})
		pause_points.append({"path_index":chosen_path.size()-1,"pause_seconds":rng.randf_range(2.0,5.0)})
		patrols.append({
			"patrol_id":patrol_id,
			"start":patrol_start,
			"goal":chosen_goal,
			"path":chosen_path,
			"movement_mode":"ping_pong",
			"pause_points":pause_points
		})

	# Optional thematic patrols: one short route inside each region.
	for region in region_result["regions"]:
		var allowed:Dictionary={}
		var starts:Array[Vector2i]=[]
		for cell_pos in region["cells"]:
			allowed[cell_pos]=true
			if accessible.has(cell_pos) and map.cell(cell_pos).is_passable() and map.entities_at(cell_pos).is_empty():
				starts.append(cell_pos)
		if starts.size()<6:
			continue
		_shuffle_cells(starts,rng)
		var route:Array=[]
		for start_pos in starts:
			for goal_pos in starts:
				if HexGrid.distance(start_pos,goal_pos)<3:
					continue
				var found:Dictionary=HexPathfinder.new().find_path(map,start_pos,goal_pos)
				if not bool(found.get("ok",false)):
					continue
				var path_cells:Array=found.get("path",[])
				if path_cells.size()<4 or path_cells.size()>8:
					continue
				var contained:=true
				for path_pos in path_cells:
					if not allowed.has(path_pos):
						contained=false
						break
				if contained:
					route=path_cells
					break
			if not route.is_empty():
				break
		if route.is_empty():
			continue
		var id:="GEN_REGION_PATROL_%s"%str(region["region_id"])
		if map.place_entity(id,route[0]):
			patrols.append({"patrol_id":id,"region_id":region["region_id"],"region_type":region["region_type"],"start":route[0],"goal":route[route.size()-1],"path":route,"movement_mode":"ping_pong","pause_points":[{"path_index":0,"pause_seconds":3.0},{"path_index":route.size()-1,"pause_seconds":3.0}]})

	var boss_groups:Array[Dictionary]=[]
	var boss_candidates:Array[Vector2i]=[]
	for boss_candidate in content_cells:
		if HexGrid.distance(entrance,boss_candidate)>SAFE_ENTRANCE_RADIUS and map.entities_at(boss_candidate).is_empty():
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
		_shuffle_cells(boss_neighbors,rng)
		for guard_pos in boss_neighbors:
			if guard_ids.size()>=2:
				break
			if guard_pos==entrance or guard_pos==exit or HexGrid.distance(entrance,guard_pos)<=SAFE_ENTRANCE_RADIUS or not map.entities_at(guard_pos).is_empty():
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

	return {
		"map":map,"entrance":entrance,"exit":exit,"seed":seed_value,
		"guaranteed_path":guaranteed_path,"resource_cells":resource_cells,"npc_cells":npc_cells,
		"object_cells":object_cells,"encounter_cells":encounter_cells,"encounter_service":encounter_service,
		"guarded_objects":guarded_objects,"route_guards":route_guards,"patrols":patrols,"boss_groups":boss_groups,
		"pockets":region_result["pockets"],"regions":region_result["regions"],"region_npcs":region_npcs,"region_objects":region_objects,
		"region_candidates":region_result["region_candidates"],"pocket_attempts":region_result["pocket_attempts"],"geometry_rejections":region_result["geometry_rejections"],
		"safe_entrance_radius":SAFE_ENTRANCE_RADIUS
	}

static func _shuffle_cells(cells:Array, rng:RandomNumberGenerator)->void:
	for i in range(cells.size()-1,0,-1):
		var j:=rng.randi_range(0,i)
		var swap=cells[i]
		cells[i]=cells[j]
		cells[j]=swap

static func _take_safe_cells(target:Array[Vector2i], source:Array[Vector2i], count:int, entrance:Vector2i, danger_radius:int)->void:
	var i:=source.size()-1
	while i>=0 and target.size()<count:
		var pos:Vector2i=source[i]
		if HexGrid.distance(entrance,pos)>danger_radius:
			target.append(pos)
			source.remove_at(i)
		i-=1

static func _reachable_cells(map:TacticalMapState, start:Vector2i)->Dictionary:
	var reachable:Dictionary={}
	if not map.in_bounds(start) or not map.cell(start).is_passable():
		return reachable
	var frontier:Array[Vector2i]=[start]
	reachable[start]=true
	var index:=0
	while index<frontier.size():
		var current:Vector2i=frontier[index]
		index+=1
		for neighbor in map.neighbors(current,true):
			if reachable.has(neighbor):
				continue
			reachable[neighbor]=true
			frontier.append(neighbor)
	return reachable
