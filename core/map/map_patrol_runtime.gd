class_name MapPatrolRuntime
extends RefCounted

var map:TacticalMapState
var patrols:Array[Dictionary]=[]
var states:Dictionary={}
var collision_entity_id:String=""
var player_entity_id:String="PLAYER"
const STEP_SECONDS:=4.0
const RETRY_SECONDS:=1.0

func configure(world:TacticalMapState,definitions:Array,player_id:String="PLAYER")->void:
	player_entity_id=player_id
	map=world
	patrols.clear()
	states.clear()
	collision_entity_id=""
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
		if state.is_empty() or not map.entity_positions.has(patrol_id): continue
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
		# NPCs may share a hex; only contact with PLAYER triggers combat.
		if map.entities_at(next).has(player_entity_id):
			collision_entity_id=patrol_id
			state["remaining"]=RETRY_SECONDS
			return changed
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

## Persist only path indices, direction, clocks and current positions;
## never serialize duplicated NPC/character objects.
func snapshot() -> Dictionary:
	var output: Dictionary = {}
	for id in states.keys():
		if map == null or not map.entity_positions.has(id):
			continue
		var pos: Vector2i = map.entity_positions[id]
		output[id] = {"index":int(states[id]["index"]),"direction":int(states[id]["direction"]),"remaining":float(states[id]["remaining"]),"position":[pos.x,pos.y]}
	return output

func restore(saved: Dictionary) -> bool:
	if map == null:
		return false
	var expected: Dictionary = {}
	for patrol in patrols:
		expected[String(patrol["patrol_id"])] = patrol
	for id in saved.keys():
		if not expected.has(id) or not saved[id] is Dictionary:
			return false
		var data: Dictionary = saved[id]
		var path: Array = expected[id]["path"]
		var idx := int(data.get("index",-1))
		var dir := int(data.get("direction",0))
		var pos: Variant = data.get("position",null)
		if idx<0 or idx>=path.size() or dir not in [-1,1] or not pos is Array or pos.size()!=2:
			return false
		var cell := Vector2i(int(pos[0]),int(pos[1]))
		if path[idx]!=cell or not map.in_bounds(cell) or not map.cell(cell).is_passable():
			return false
		if float(data.get("remaining",-1.0))<0.0:
			return false
	for id in saved.keys():
		var data: Dictionary = saved[id]
		map.entity_positions[id] = Vector2i(int(data["position"][0]),int(data["position"][1]))
		states[id] = {"index":int(data["index"]),"direction":int(data["direction"]),"remaining":float(data["remaining"])}
	return true
