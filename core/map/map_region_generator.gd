class_name MapRegionGenerator
extends RefCounted

const REGION_TYPES := [
	{"id":"bandit_camp","chance":0.20,"priority":10},
	{"id":"graveyard","chance":0.05,"priority":10},
	{"id":"beast_den","chance":0.25,"priority":10},
	{"id":"ruins","chance":0.15,"priority":10}
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
	for definition in REGION_TYPES:
		if rng.randf()<float(definition["chance"]):
			candidates.append(definition)
	candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return int(a["priority"])>int(b["priority"]))
	var cap:int=int(ceil(float(map.width*map.height)*3.0/400.0))
	var pocket_cap:int=int(ceil(float(map.width*map.height)*4.0/400.0))
	for pocket_index in range(pocket_cap):
		var pocket:Dictionary={}
		for attempt in range(ATTEMPTS):
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
		pockets.append({"pocket_id":pocket_id,"cells":cells,"gate":pocket["gate"]})
		if regions.size()<cap and not candidates.is_empty():
			var definition:Dictionary=candidates.pop_front()
			var region_id:="REGION_%02d"%regions.size()
			regions.append({"region_id":region_id,"region_type":definition["id"],"cells":cells.duplicate(),"entrances":[pocket["gate"]],"pocket_id":pocket_id})
	return {"pockets":pockets,"regions":regions}
