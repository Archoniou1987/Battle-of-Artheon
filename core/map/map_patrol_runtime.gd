class_name MapPatrolRuntime
extends RefCounted

var map:TacticalMapState
var patrols:Array[Dictionary]=[]
var states:Dictionary={}
const STEP_SECONDS:=4.0
const RETRY_SECONDS:=1.0

func configure(world:TacticalMapState,definitions:Array)->void:
	map=world
	patrols.clear()
	states.clear()
	for raw_patrol in definitions:
		var patrol:Dictionary=raw_patrol
		var route:Array=patrol.get("path",[])
		if route.size()<2: continue
		var patrol_id:String=str(patrol.get("patrol_id",""))
		if patrol_id.is_empty() or not map.entity_positions.has(patrol_id): continue
		patrols.append(patrol)
		states[patrol_id]={"index":0,"direction":1,"remaining":_pause_at(patrol,0)}

func advance(delta:float)->bool:
	if map==null: return false
	var changed:=false
	for patrol in patrols:
		var patrol_id:String=str(patrol.get("patrol_id",""))
		var state:Dictionary=states.get(patrol_id,{})
		if state.is_empty(): continue
		var remaining:float=float(state.get("remaining",0.0))-delta
		if remaining>0.0:
			state["remaining"]=remaining
			continue
		var route:Array=patrol.get("path",[])
		var index:int=int(state["index"])
		var direction:int=int(state["direction"])
		var next_index:int=index+direction
		if next_index<0 or next_index>=route.size():
			direction=-direction
			next_index=index+direction
		if next_index<0 or next_index>=route.size(): continue
		var next:Vector2i=route[next_index]
		# Occupied cells are never overwritten. The patrol waits, then retries.
		if not map.entities_at(next).is_empty():
			state["remaining"]=RETRY_SECONDS
			continue
		var moved:Dictionary=map.move_entity(patrol_id,next)
		if not bool(moved.get("ok",false)):
			state["remaining"]=RETRY_SECONDS
			continue
		changed=true
		state["index"]=next_index
		state["direction"]=direction
		state["remaining"]=STEP_SECONDS+_pause_at(patrol,next_index)
	return changed

func _pause_at(patrol:Dictionary,index:int)->float:
	for pause in patrol.get("pause_points",[]):
		if int(pause.get("path_index",-1))==index:
			return maxf(0.0,float(pause.get("pause_seconds",0.0)))
	return 0.0
