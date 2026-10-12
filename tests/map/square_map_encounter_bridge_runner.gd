extends SceneTree

func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var repo:=NpcRepository.new()
	repo.load_definitions(doc)
	var map:=SquareMapState.new(12,12,Vector2i(4,5))
	var bridge:=MapNpcBridge.new()
	var first:=NpcInstance.new("SQUARE_BANDIT_001",repo.get_npc("NPC003"))
	var second:=NpcInstance.new("SQUARE_BANDIT_002",repo.get_npc("NPC003"))
	var cell:=Vector2i(5,5)
	var valid:=bridge.register_npc(map,first,cell)
	valid=valid and bridge.register_npc(map,second,cell)
	valid=valid and map.is_passable(cell)

	var step:=map.move_player(cell)
	var encounter:=bridge.encounter_at(map,map.player_position)
	valid=valid and bool(step.get("ok",false)) and bool(encounter.get("ok",false))
	valid=valid and encounter.get("npc_instance_ids",[])==["SQUARE_BANDIT_001","SQUARE_BANDIT_002"]
	valid=valid and encounter.get("npcs",[]).size()==2

	var player:=CombatantState.new("PLAYER","Artheon Hero",5,150,0)
	player.combat_stats={"weapon_profiles":[{"damage_min":25.0,"damage_max":25.0,"damage_type":"slashing"}]}
	var session:=MapEncounterCombatService.begin(encounter,repo,player)
	valid=valid and bool(session.get("ok",false))
	valid=valid and session.get("npc")==first
	var state:CombatState=session.get("state") as CombatState
	valid=valid and state!=null and state.get_combatant("SQUARE_BANDIT_001")!=null
	valid=valid and map.entities_at(cell).size()==2
	valid=valid and map.is_passable(cell)

	print("SQUARE_MAP_ENCOUNTER_BRIDGE_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
