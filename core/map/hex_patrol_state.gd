class_name HexPatrolState
extends RefCounted

var patrol_id:String
var path:Array[Vector2i]=[]
var path_index:int=0
var direction:int=1
var pause_points:Dictionary={}
var remaining_pause_seconds:float=0.0

func _init(id:String,route:Array[Vector2i])->void:
	patrol_id=id
	path=route.duplicate()

func set_pause_points(points:Array[Dictionary])->void:
	pause_points.clear()
	for point in points:
		var index:=int(point.get("path_index",-1))
		if index>=0 and index<path.size():
			pause_points[index]=maxf(0.0,float(point.get("pause_seconds",0.0)))

func step(map:TacticalMapState,combat_active:bool=false,elapsed_seconds:float=1.0,player_id:String="")->Dictionary:
	if combat_active:
		return {"ok":false,"reason":"combat_paused"}
	if map==null or patrol_id.is_empty() or path.size()<2 or not map.entity_positions.has(patrol_id):
		return {"ok":false,"reason":"invalid_patrol"}
	if map.entity_positions[patrol_id]!=path[path_index]:
		return {"ok":false,"reason":"position_mismatch"}
	if remaining_pause_seconds>0.0:
		remaining_pause_seconds=maxf(0.0,remaining_pause_seconds-maxf(0.0,elapsed_seconds))
		return {"ok":false,"reason":"patrol_waiting","remaining_seconds":remaining_pause_seconds}
	var next_index:=path_index+direction
	if next_index<0 or next_index>=path.size():
		direction=-direction
		next_index=path_index+direction
	if not player_id.is_empty() and map.entity_positions.has(player_id) and map.entity_positions[player_id]==path[next_index]:
		return {"ok":false,"reason":"player_contact","patrol_id":patrol_id,"cell":path[next_index],"player_id":player_id}
	if HexGrid.distance(path[path_index],path[next_index])!=1:
		return {"ok":false,"reason":"invalid_route"}
	var result:=map.move_entity(patrol_id,path[next_index])
	if bool(result.get("ok",false)):
		path_index=next_index
		remaining_pause_seconds=float(pause_points.get(path_index,0.0))
		result["patrol_id"]=patrol_id
	return result
