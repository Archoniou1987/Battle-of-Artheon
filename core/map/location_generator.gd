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
	return {"map":map,"entrance":entrance,"exit":exit,"seed":seed_value,"guaranteed_path":guaranteed_path,"resource_cells":resource_cells,"npc_cells":npc_cells,"object_cells":object_cells,"encounter_cells":encounter_cells,"encounter_service":encounter_service}
