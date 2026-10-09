class_name MapRegionGenerator
extends RefCounted

const REGION_TYPES := [
	{"id":"bandit_camp","chance":0.40,"priority":10},
	{"id":"graveyard","chance":0.40,"priority":10},
	{"id":"beast_den","chance":0.40,"priority":10},
	{"id":"ruins","chance":0.40,"priority":10}
]
const ATTEMPTS := 60

static func generate(map:TacticalMapState, entrance:Vector2i, exit:Vector2i, main_path:Array[Vector2i], rng:RandomNumberGenerator)->Dictionary:
	var protected:Dictionary={}
	for pos in main_path:
		protected[pos]=true
	var reserved:Dictionary={}
	var pockets:Array[Dictionary]=[]
	var regions:Array[Dictionary]=[]
	var candidates:Array[Dictionary]=[]
	var attempts_total:=0
	var rejected_geometry:=0
	for definition in REGION_TYPES:
		if rng.randf()<float(definition["chance"]):
			candidates.append(definition)
	if candidates.is_empty():
		candidates.append(REGION_TYPES[rng.randi_range(0,REGION_TYPES.size()-1)])
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return int(a["priority"])>int(b["priority"]))
	var candidate_count:=candidates.size()
	var cap:int=int(ceil(float(map.width*map.height)*3.0/400.0))
	var pocket_cap:int=int(ceil(float(map.width*map.height)*4.0/400.0))
	for pocket_index in range(pocket_cap):
		var pocket:Dictionary={}
		for attempt in range(ATTEMPTS):
			attempts_total+=1
			var gate:Vector2i=main_path[rng.randi_range(0,main_path.size()-1)]
			if gate==entrance or gate==exit or HexGrid.distance(gate,entrance)<=4 or reserved.has(gate):
				continue
			var starts:Array[Vector2i]=[]
			for neighbor in map.neighbors(gate):
				if not protected.has(neighbor) and not reserved.has(neighbor):
					starts.append(neighbor)
			if starts.is_empty():
				continue
			var seed:Vector2i=starts[rng.randi_range(0,starts.size()-1)]
			var cells:Array[Vector2i]=[seed]
			var owned:Dictionary={seed:true}
			var target_size:int=rng.randi_range(8,20)
			while cells.size()<target_size:
				var options:Array[Vector2i]=[]
				for pos in cells:
					for neighbor in map.neighbors(pos):
						if owned.has(neighbor) or protected.has(neighbor) or reserved.has(neighbor):
							continue
						if HexGrid.distance(neighbor,entrance)<=3 or neighbor==exit:
							continue
						if not options.has(neighbor):
							options.append(neighbor)
				if options.is_empty():
					break
				var chosen:Vector2i=options[rng.randi_range(0,options.size()-1)]
				cells.append(chosen)
				owned[chosen]=true
			if cells.size()<8:
				continue
			var border:Dictionary={}
			for pos in cells:
				for neighbor in map.neighbors(pos):
					if not owned.has(neighbor):
						border[neighbor]=true
			var valid:=true
			for pos in border.keys():
				if (protected.has(pos) and pos!=gate) or reserved.has(pos):
					valid=false
					break
			if not valid:
				rejected_geometry+=1
				continue
			pocket={"cells":cells,"gate":gate,"border":border.keys()}
			break
		if pocket.is_empty():
			continue
		var cells:Array[Vector2i]=pocket["cells"]
		for pos in cells:
			map.set_obstacle(pos,"",false)
			map.set_terrain(pos,"grass",1.0)
			reserved[pos]=true
		for pos in pocket["border"]:
			if pos==pocket["gate"]:
				continue
			map.set_obstacle(pos,"region_pocket_wall",true)
			reserved[pos]=true
		map.set_obstacle(pocket["gate"],"",false)
		var pocket_id:="POCKET_%02d"%pockets.size()
		pockets.append({"pocket_id":pocket_id,"cells":cells,"gate":pocket["gate"],"border":pocket["border"]})
		if regions.size()<cap and not candidates.is_empty():
			var definition:Dictionary=candidates.pop_front()
			var region_id:="REGION_%02d"%regions.size()
			regions.append({"region_id":region_id,"region_type":definition["id"],"cells":cells.duplicate(),"entrances":[pocket["gate"]],"pocket_id":pocket_id})
	# Thematic regions are not required to be pockets. Place remaining
	# successful probability rolls as open regions if pocket shaping failed.
	# No walls are introduced here, so the guaranteed route stays intact.
	for definition in candidates:
		if regions.size()>=cap:
			break
		var selected:Array[Vector2i]=[]
		for attempt in range(ATTEMPTS*4):
			var seed:=Vector2i(rng.randi_range(1,map.width-2),rng.randi_range(0,map.height-1))
			if protected.has(seed) or reserved.has(seed) or HexGrid.distance(seed,entrance)<=3 or HexGrid.distance(seed,exit)<=2:
				continue
			var cells:Array[Vector2i]=[seed]
			var owned:Dictionary={seed:true}
			var target_size:=rng.randi_range(8,25)
			while cells.size()<target_size:
				var options:Array[Vector2i]=[]
				for pos in cells:
					for neighbor in map.neighbors(pos):
						if owned.has(neighbor) or reserved.has(neighbor) or protected.has(neighbor):
							continue
						if HexGrid.distance(neighbor,entrance)<=3 or HexGrid.distance(neighbor,exit)<=2:
							continue
						if not options.has(neighbor):
							options.append(neighbor)
				if options.is_empty():
					break
				var chosen:Vector2i=options[rng.randi_range(0,options.size()-1)]
				owned[chosen]=true
				cells.append(chosen)
			if cells.size()>=8:
				selected=cells
				break
		if selected.is_empty():
			continue
		for pos in selected:
			map.set_obstacle(pos,"",false)
			map.set_terrain(pos,"grass",1.0)
			reserved[pos]=true
		var region_id:="REGION_%02d"%regions.size()
		regions.append({"region_id":region_id,"region_type":definition["id"],"cells":selected,"entrances":[],"pocket_id":""})
	# A guaranteed thematic region for 20x20 maps, independent of pocket geometry.
	if regions.is_empty():
		var fallback:Array[Vector2i]=[]
		for y in range(map.height):
			for x in range(map.width):
				var pos:=Vector2i(x,y)
				if not protected.has(pos) and not reserved.has(pos) and HexGrid.distance(pos,entrance)>3 and HexGrid.distance(pos,exit)>2:
					fallback.append(pos)
		if not fallback.is_empty():
			var selected:Array[Vector2i]=[fallback[rng.randi_range(0,fallback.size()-1)]]
			var owned:Dictionary={selected[0]:true}
			while selected.size()<8:
				var options:Array[Vector2i]=[]
				for pos in selected:
					for neighbor in map.neighbors(pos):
						if fallback.has(neighbor) and not owned.has(neighbor) and not options.has(neighbor):
							options.append(neighbor)
				if options.is_empty():
					break
				var next:Vector2i=options[rng.randi_range(0,options.size()-1)]
				selected.append(next)
				owned[next]=true
			for pos in selected:
				map.set_obstacle(pos,"",false)
				map.set_terrain(pos,"grass",1.0)
			var definition:Dictionary=REGION_TYPES[rng.randi_range(0,REGION_TYPES.size()-1)]
			regions.append({"region_id":"REGION_00","region_type":definition["id"],"cells":selected,"entrances":[],"pocket_id":""})
	return {"pockets":pockets,"regions":regions,"region_candidates":candidate_count,"pocket_attempts":attempts_total,"geometry_rejections":rejected_geometry}
