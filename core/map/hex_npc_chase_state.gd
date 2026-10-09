class_name HexNpcChaseState
extends RefCounted

var npc_id:String
var mode:String="idle"
var home_position:Vector2i
var detection_radius:int=2
var chase_radius:int=4
var decided:bool=false
var rejected:bool=false

func _init(id:String,home:Vector2i,detect:int=2,chase:int=4)->void:
	npc_id=id
	home_position=home
	detection_radius=maxi(0,detect)
	chase_radius=maxi(0,chase)

func step(map:TacticalMapState,bridge:MapNpcBridge,player_id:String,rng:RandomNumberGenerator,combat_active:bool=false)->Dictionary:
	if combat_active:
		return {"ok":false,"reason":"combat_paused","mode":mode}
	if map==null or bridge==null or rng==null or not bridge.instances.has(npc_id) or not map.entity_positions.has(npc_id) or not map.entity_positions.has(player_id):
		return {"ok":false,"reason":"invalid_context"}
	var npc:NpcInstance=bridge.instances[npc_id]
	if not npc.is_alive():
		return {"ok":false,"reason":"npc_dead"}
	var position:Vector2i=map.entity_positions[npc_id]
	var player_pos:Vector2i=map.entity_positions[player_id]
	if mode=="idle":
		if HexGrid.distance(position,player_pos)>detection_radius:
			decided=false
			rejected=false
			return {"ok":false,"reason":"not_detected","mode":mode}
		if decided and rejected:
			return {"ok":false,"reason":"not_aggressive","mode":mode}
		var chance:=clampf(npc.aggression,0.0,100.0)
		decided=true
		rejected=chance<=0.0 or (chance<100.0 and rng.randf()*100.0>=chance)
		if rejected:
			return {"ok":false,"reason":"not_aggressive","mode":mode}
		mode="chasing"
	if mode=="chasing":
		if HexGrid.distance(home_position,player_pos)>chase_radius:
			mode="returning"
		elif HexGrid.distance(position,player_pos)<=1:
			return {"ok":true,"contact":true,"mode":mode,"npc_instance_id":npc_id}
		else:
			var next:=_next_step(map,position,player_pos,true)
			if next==position or HexGrid.distance(home_position,next)>chase_radius:
				mode="returning"
			else:
				var moved:=map.move_entity(npc_id,next)
				if bool(moved.get("ok",false)):
					return {"ok":true,"mode":mode,"movement":moved}
				return moved
	if mode=="returning":
		if position==home_position:
			mode="idle"
			decided=false
			rejected=false
			return {"ok":true,"mode":mode,"returned":true}
		var next_home:=_next_step(map,position,home_position,false)
		if next_home==position:
			return {"ok":false,"reason":"home_unreachable","mode":mode}
		var back:=map.move_entity(npc_id,next_home)
		if bool(back.get("ok",false)):
			if next_home==home_position:
				mode="idle"
				decided=false
				rejected=false
			return {"ok":true,"mode":mode,"movement":back}
		return back
	return {"ok":false,"reason":"invalid_mode"}

func _next_step(map:TacticalMapState,from:Vector2i,goal:Vector2i,stop_adjacent:bool)->Vector2i:
	var targets:Array[Vector2i]=[]
	if stop_adjacent:
		for candidate in map.neighbors(goal,true):
			if HexGrid.distance(home_position,candidate)<=chase_radius:
				targets.append(candidate)
	else:
		targets.append(goal)
	var finder:=HexPathfinder.new()
	var best:=from
	var best_cost:=INF
	for target in targets:
		var result:=finder.find_path(map,from,target)
		if not bool(result.get("ok",false)):
			continue
		var path:Array=result.get("path",[])
		if path.size()<2:
			continue
		var within_bounds:=true
		for cell in path:
			if stop_adjacent and HexGrid.distance(home_position,cell)>chase_radius:
				within_bounds=false
				break
		if within_bounds and float(result.get("cost",INF))<best_cost:
			best_cost=float(result.get("cost",INF))
			best=path[1]
	return best
