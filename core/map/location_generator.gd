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
	return {"map":map,"entrance":entrance,"exit":exit,"seed":seed_value,"guaranteed_path":guaranteed_path}
