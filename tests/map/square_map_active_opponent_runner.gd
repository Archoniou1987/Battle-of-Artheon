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
	var player:=CombatantState.new("PLAYER","Artheon Hero",5,150,0)
	var session:=MapEncounterCombatService.begin(bridge.encounter_at(map,cell),repo,player)
	var state:CombatState=session.get("state") as CombatState
	var group:GroupCombatState=session.get("group") as GroupCombatState
	var controller:GroupCombatController=session.get("group_controller") as GroupCombatController
	valid=valid and state!=null and group!=null and controller!=null
	valid=valid and group.team_of("PLAYER")=="players"
	for npc_id in ids:
		valid=valid and group.team_of(npc_id)=="enemies"
	valid=valid and group.active_opponent("PLAYER")=="GROUP_NPC_001"
	valid=valid and group.active_opponent("GROUP_NPC_001")=="PLAYER"
	valid=valid and group.active_opponent("GROUP_NPC_002")=="PLAYER"
	valid=valid and group.active_opponent("GROUP_NPC_003")=="PLAYER"

	state.get_combatant("GROUP_NPC_001").death_finalized=true
	var sync:=controller.after_end_round({"dead_ids":["GROUP_NPC_001"]})
	valid=valid and group.active_opponent("PLAYER")=="GROUP_NPC_002"
	valid=valid and String(sync.get("active_replacements",{}).get("PLAYER",{}).get("to",""))=="GROUP_NPC_002"
	valid=valid and not controller.combat_finished()

	state.get_combatant("GROUP_NPC_002").death_finalized=true
	controller.after_end_round({"dead_ids":["GROUP_NPC_002"]})
	valid=valid and group.active_opponent("PLAYER")=="GROUP_NPC_003"
	valid=valid and not controller.combat_finished()

	state.get_combatant("GROUP_NPC_003").death_finalized=true
	controller.after_end_round({"dead_ids":["GROUP_NPC_003"]})
	valid=valid and controller.combat_finished()
	valid=valid and controller.winning_team()=="players"

	print("SQUARE_MAP_ACTIVE_OPPONENT_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
