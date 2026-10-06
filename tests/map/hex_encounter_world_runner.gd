extends SceneTree
func _initialize()->void:
	var map:=TacticalMapState.new(8,8)
	var service:=HexEncounterService.new()
	var valid:=map.place_entity("PLAYER",Vector2i(1,1))
	var trap:=HexEncounter.new("ENC_TRAP",HexEncounter.TRIGGER_ENTER,"damage",{"amount":12},false)
	var portal:=HexEncounter.new("ENC_PORTAL",HexEncounter.TRIGGER_INTERACT,"teleport",{"entity_id":"PLAYER","destination":Vector2i(6,6)},true)
	var secret:=HexEncounter.new("ENC_CHEST",HexEncounter.TRIGGER_DISCOVER,"reveal_object",{"object_id":"CHEST_SECRET","position":Vector2i(5,5)},true)
	valid=valid and service.add_encounter(trap,Vector2i(2,1),map)
	valid=valid and service.add_encounter(portal,Vector2i(3,1),map)
	valid=valid and service.add_encounter(secret,Vector2i(4,1),map)
	var move:=map.move_entity("PLAYER",Vector2i(2,1))
	var trap_events:=service.on_move(move)
	valid=valid and trap_events.size()==1
	var trap_result:=HexEncounterResolver.resolve(trap_events[0],map)
	valid=valid and bool(trap_result.get("ok",false)) and str(trap_result.get("consequence",""))=="damage"
	valid=valid and service.on_move({"ok":true,"to":Vector2i(2,1)}).size()==1
	var secret_events:=service.discover(Vector2i(4,1))
	var secret_result:=HexEncounterResolver.resolve(secret_events[0],map)
	valid=valid and bool(secret_result.get("ok",false)) and map.cell(Vector2i(5,5)).object_ids.has("CHEST_SECRET")
	var portal_events:=service.interact(Vector2i(3,1))
	var portal_result:=HexEncounterResolver.resolve(portal_events[0],map)
	valid=valid and bool(portal_result.get("ok",false)) and map.entity_positions["PLAYER"]==Vector2i(6,6)
	valid=valid and map.exploration_state(Vector2i(6,6))=="visited"
	valid=valid and service.interact(Vector2i(3,1)).is_empty()
	print("HEX_ENCOUNTER_WORLD_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
