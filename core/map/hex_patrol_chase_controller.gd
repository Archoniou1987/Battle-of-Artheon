class_name HexPatrolChaseController
extends RefCounted

var patrol:HexPatrolState
var chase:HexNpcChaseState
var returning_to_route:bool=false

func _init(p_patrol:HexPatrolState,p_chase:HexNpcChaseState)->void:
	patrol=p_patrol
	chase=p_chase

func step(map:TacticalMapState,bridge:MapNpcBridge,turns:HexMapTurnService,player_id:String,rng:RandomNumberGenerator,elapsed_seconds:float=1.0)->Dictionary:
	if patrol==null or chase==null or turns==null or patrol.patrol_id!=chase.npc_id:
		return {"ok":false,"reason":"invalid_controller"}
	if turns.coordinator.combat_active:
		return {"ok":false,"reason":"combat_paused"}
	if not map.entity_positions.has(chase.npc_id):
		return {"ok":false,"reason":"missing_npc"}
	if returning_to_route:
		return _return_to_route(map)
	if chase.mode=="idle":
		chase.home_position=map.entity_positions[chase.npc_id]
	var action:=turns.step_chase(map,bridge,chase,player_id,rng)
	if chase.mode=="chasing":
		return action
	if chase.mode=="returning":
		return action
	if bool(action.get("returned",false)):
		return {"ok":true,"mode":"patrolling","returned":true}
	if action.get("reason","")=="not_aggressive" or action.get("reason","")=="not_detected":
		return turns.step_patrol(map,bridge,patrol,player_id,rng,elapsed_seconds)
	if chase.mode=="idle" and bool(action.get("ok",false)) and action.has("movement"):
		return action
	return action

func _return_to_route(map:TacticalMapState)->Dictionary:
	if not map.entity_positions.has(chase.npc_id):
		return {"ok":false,"reason":"missing_npc"}
	var position:Vector2i=map.entity_positions[chase.npc_id]
	var target:Vector2i=patrol.path[patrol.path_index]
	if position==target:
		returning_to_route=false
		return {"ok":true,"mode":"patrolling","returned":true}
	var path_result:=HexPathfinder.new().find_path(map,position,target)
	if not bool(path_result.get("ok",false)):
		return {"ok":false,"reason":"route_unreachable"}
	var path:Array=path_result.get("path",[])
	if path.size()<2:
		return {"ok":false,"reason":"route_unreachable"}
	var moved:=map.move_entity(chase.npc_id,path[1])
	if bool(moved.get("ok",false)) and path[1]==target:
		returning_to_route=false
	return {"ok":bool(moved.get("ok",false)),"mode":"returning_to_route","movement":moved}
