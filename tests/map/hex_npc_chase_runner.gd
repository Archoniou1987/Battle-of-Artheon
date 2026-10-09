extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(10,10)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(5,3))
	var npc:=NpcInstance.new("HUNTER",repo.get_npc("NPC003"))
	npc.aggression=100.0
	valid=valid and bridge.register_npc(map,npc,Vector2i(2,3))
	var chase:=HexNpcChaseState.new("HUNTER",Vector2i(2,3),4,3)
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	var first:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and bool(first.get("ok",false)) and chase.mode=="chasing"
	valid=valid and HexGrid.distance(map.entity_positions["HUNTER"],Vector2i(2,3))==1
	valid=valid and map.move_entity("PLAYER",Vector2i(6,3)).get("ok",false)
	var returning:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and bool(returning.get("ok",false)) and chase.mode=="idle"
	valid=valid and map.entity_positions["HUNTER"]==Vector2i(2,3)
	valid=valid and not turns.coordinator.combat_active
	var close_map:=TacticalMapState.new(8,8)
	var close_bridge:=MapNpcBridge.new()
	valid=valid and close_map.place_entity("PLAYER",Vector2i(4,3))
	var attacker:=NpcInstance.new("ATTACKER",repo.get_npc("NPC003"))
	attacker.aggression=100.0
	valid=valid and close_bridge.register_npc(close_map,attacker,Vector2i(2,3))
	var close_chase:=HexNpcChaseState.new("ATTACKER",Vector2i(2,3),2,4)
	var step1:=turns.step_chase(close_map,close_bridge,close_chase,"PLAYER",rng)
	valid=valid and bool(step1.get("ok",false))
	var step2:=turns.step_chase(close_map,close_bridge,close_chase,"PLAYER",rng)
	valid=valid and bool(step2.get("ok",false)) and step2.has("encounter")
	valid=valid and turns.coordinator.combat_active
	var paused:=turns.step_chase(close_map,close_bridge,close_chase,"PLAYER",rng)
	valid=valid and paused.get("reason","")=="combat_paused"
	print("HEX_NPC_CHASE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
