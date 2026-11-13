extends SceneTree
func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var repo:=NpcRepository.new(); repo.load_definitions(doc)
	var npc:=NpcInstance.new("WORLD_BANDIT_001",repo.get_npc("NPC003"))
	var map:=TacticalMapState.new(12,12)
	var bridge:=MapNpcBridge.new()
	var valid:=bridge.register_npc(map,npc,Vector2i(5,5))
	valid=valid and map.place_entity("PLAYER",Vector2i(4,5))
	var step:=map.move_entity("PLAYER",Vector2i(5,5))
	var encounter:=bridge.encounter_at(map,map.entity_positions["PLAYER"])
	var player:=TestFixtureLoader.new_combatant("PLAYER","Artheon Hero",5,150,0)
	player.combat_stats.merge({"weapon_profiles":[{"damage_min":25.0,"damage_max":25.0,"damage_type":"slashing"}]}, true)
	var session:=MapEncounterCombatService.begin(encounter,repo,player)
	valid=valid and bool(step.get("ok",false)) and bool(session.get("ok",false))
	var enemy:CombatantState=session.get("enemy") as CombatantState
	valid=valid and enemy!=null and enemy.combatant_id=="WORLD_BANDIT_001"
	valid=valid and enemy.display_name==npc.display_name and enemy.level==npc.level
	valid=valid and session.get("npc")==npc
	var state:CombatState=session.get("state") as CombatState
	valid=valid and state.get_combatant("WORLD_BANDIT_001")==enemy and state.get_combatant("PLAYER")==player
	var simulator:=CombatSimulator.new(TestFixtureLoader.canonicalize_state(state),TestFixtureLoader.load_json("res://data/balance/physical_combat.json"),6711)
	simulator.max_rounds=20
	var result:=simulator.run_duel("PLAYER","WORLD_BANDIT_001")
	valid=valid and String(result.get("winner_id",""))=="PLAYER" and String(result.get("loser_id",""))=="WORLD_BANDIT_001"
	print("MAP_COMBAT npc_instance=%s template=%s rounds=%d outcome=%s"%[session.npc_instance_id,session.npc_template_id,int(result.rounds),String(result.outcome)])
	print("MAP_ENCOUNTER_COMBAT_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
