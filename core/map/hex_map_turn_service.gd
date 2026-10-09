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
		var encounter:=coordinator.try_start_patrol_contact(map,bridge,player_id,patrol.patrol_id,rng)
		if bool(encounter.get("ok",false)):
			return {"ok":true,"patrol_contact":result,"encounter":encounter}
	return result

func step_chase(map:TacticalMapState,bridge:MapNpcBridge,chase:HexNpcChaseState,player_id:String,rng:RandomNumberGenerator)->Dictionary:
	if chase==null:
		return {"ok":false,"reason":"invalid_chase"}
	var result:=chase.step(map,bridge,player_id,rng,coordinator.combat_active)
	if bool(result.get("contact",false)):
		var encounter:=coordinator.try_start_patrol_contact(map,bridge,player_id,chase.npc_id,rng)
		if bool(encounter.get("ok",false)):
			return {"ok":true,"chase":result,"encounter":encounter}
	return result

func resolve_group_victory(result:Dictionary,map:TacticalMapState,bridge:MapNpcBridge,encounter:Dictionary,player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if not coordinator.combat_active:
		return {"ok":false,"reason":"no_active_combat"}
	if not bool(encounter.get("ok",false)):
		return {"ok":false,"reason":"invalid_encounter"}
	var npcs:Array[NpcInstance]=[]
	for raw_npc in encounter.get("npcs",[]):
		var npc:=raw_npc as NpcInstance
		if npc!=null:
			npcs.append(npc)
	var outcome:=MapCombatOutcomeService.resolve_group_victory(result,map,bridge,npcs,player,repository,loot_service,quality_chances)
	if bool(outcome.get("ok",false)):
		coordinator.finish_combat()
	return outcome

func finish_combat()->void:
	coordinator.finish_combat()
