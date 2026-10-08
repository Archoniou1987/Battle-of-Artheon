extends SceneTree

func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var repo:=NpcRepository.new()
	repo.load_definitions(doc)
	var map:=SquareMapState.new(12,12,Vector2i(4,5))
	var bridge:=MapNpcBridge.new()
	var cell:=Vector2i(5,5)
	var ids:=["GROUP_NPC_001","GROUP_NPC_002","GROUP_NPC_003"]
	var valid:=true
	for npc_id in ids:
		valid=valid and bridge.register_npc(map,NpcInstance.new(npc_id,repo.get_npc("NPC003")),cell)
	valid=valid and bool(map.move_player(cell).get("ok",false))
	var encounter:=bridge.encounter_at(map,cell)
	var player:=CombatantState.new("PLAYER","Artheon Hero",5,150,0)
	var session:=MapEncounterCombatService.begin(encounter,repo,player)
	valid=valid and bool(session.get("ok",false))
	var state:CombatState=session.get("state") as CombatState
	var enemies:Array=session.get("enemies",[])
	valid=valid and enemies.size()==3
	valid=valid and session.get("npc_instance_ids",[])==ids
	valid=valid and state.combatants.size()==4
	valid=valid and state.get_combatant("PLAYER")==player
	for npc_id in ids:
		var enemy:=state.get_combatant(npc_id)
		valid=valid and enemy!=null and enemy.combatant_id==npc_id
	valid=valid and session.get("enemy")==state.get_combatant("GROUP_NPC_001")
	valid=valid and session.get("npc_instance_id","")=="GROUP_NPC_001"

	print("SQUARE_MAP_GROUP_COMBAT_STATE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
