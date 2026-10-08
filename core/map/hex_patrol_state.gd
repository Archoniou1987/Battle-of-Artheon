class_name HexPatrolState
extends RefCounted

var patrol_id:String
var path:Array[Vector2i]=[]
var path_index:int=0
var direction:int=1
var paused:bool=false

func _init(id:String,route:Array[Vector2i])->void:
	patrol_id=id
	path=route.duplicate()

func step(map:TacticalMapState,combat_active:bool=false)->Dictionary:
	if combat_active:
		return {"ok":false,"reason":"combat_paused"}
	if map==null or patrol_id.is_empty() or path.size()<2 or not map.entity_positions.has(patrol_id):
		return {"ok":false,"reason":"invalid_patrol"}
	if map.entity_positions[patrol_id]!=path[path_index]:
		return {"ok":false,"reason":"position_mismatch"}
	var next_index:=path_index+direction
	if next_index<0 or next_index>=path.size():
		direction=-direction
		next_index=path_index+direction
	if HexGrid.distance(path[path_index],path[next_index])!=1:
		return {"ok":false,"reason":"invalid_route"}
	var result:=map.move_entity(patrol_id,path[next_index])
	if bool(result.get("ok",false)):
		path_index=next_index
		result["patrol_id"]=patrol_id
	return result
