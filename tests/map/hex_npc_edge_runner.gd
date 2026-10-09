extends SceneTree

func _initialize()->void:
	var repo:=NpcRepository.new()
	repo.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map:=TacticalMapState.new(9,9)
	var bridge:=MapNpcBridge.new()
	var valid:=map.place_entity("PLAYER",Vector2i(4,3))
	var npc:=NpcInstance.new("WATCH",repo.get_npc("NPC003"))
	npc.aggression=0.0
	valid=valid and bridge.register_npc(map,npc,Vector2i(2,3))
	var chase:=HexNpcChaseState.new("WATCH",Vector2i(2,3),3,4)
	var turns:=HexMapTurnService.new()
	var rng:=RandomNumberGenerator.new()
	for i in range(10):
		var attempt:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
		valid=valid and attempt.get("reason","")=="not_aggressive" and chase.decided and chase.rejected
	npc.aggression=100.0
	var latched:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and latched.get("reason","")=="not_aggressive"
	valid=valid and map.move_entity("PLAYER",Vector2i(5,3)).get("ok",false)
	valid=valid and map.move_entity("PLAYER",Vector2i(6,3)).get("ok",false)
	var escape:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and escape.get("reason","")=="not_detected" and not chase.decided
	valid=valid and map.move_entity("PLAYER",Vector2i(5,3)).get("ok",false)
	var reentry:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and bool(reentry.get("ok",false)) and chase.mode=="chasing"
	turns.coordinator.combat_active=true
	var before:Vector2i=map.entity_positions["WATCH"]
	var paused:=turns.step_chase(map,bridge,chase,"PLAYER",rng)
	valid=valid and paused.get("reason","")=="combat_paused" and map.entity_positions["WATCH"]==before
	turns.finish_combat()
	print("HEX_NPC_EDGE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
