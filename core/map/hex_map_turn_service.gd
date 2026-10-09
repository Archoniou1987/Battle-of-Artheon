class_name HexMapTurnService
extends RefCounted

var coordinator:HexEncounterCoordinator=HexEncounterCoordinator.new()

func move_player(map:TacticalMapState,bridge:MapNpcBridge,player_id:String,to:Vector2i,rng:RandomNumberGenerator)->Dictionary:
	if coordinator.combat_active:
		return {"ok":false,"reason":"combat_active"}
	if map==null or bridge==null or rng==null:
		return {"ok":false,"reason":"invalid_context"}
	var moved:=map.move_entity(player_id,to)
	if not bool(moved.get("ok",false)):
		return moved
	var encounter:=coordinator.try_start(map,bridge,player_id,rng)
	if bool(encounter.get("ok",false)):
		return {"ok":true,"movement":moved,"encounter":encounter}
	return {"ok":true,"movement":moved}

func step_patrol(map:TacticalMapState,bridge:MapNpcBridge,patrol:HexPatrolState,player_id:String,rng:RandomNumberGenerator,elapsed_seconds:float=1.0)->Dictionary:
	if map==null or bridge==null or patrol==null or rng==null:
		return {"ok":false,"reason":"invalid_context"}
	var result:=patrol.step(map,coordinator.combat_active,elapsed_seconds,player_id)
	if result.get("reason","")=="player_contact":
		var encounter:=coordinator.try_start(map,bridge,player_id,rng)
		if bool(encounter.get("ok",false)):
			return {"ok":true,"patrol_contact":result,"encounter":encounter}
	return result

func finish_combat()->void:
	coordinator.finish_combat()
