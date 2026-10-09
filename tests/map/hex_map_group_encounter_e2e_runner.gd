extends SceneTree

func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_repo:=NpcRepository.new()
	npc_repo.load_definitions(doc)
	var map:=TacticalMapState.new(12,12)
	var start:=Vector2i(4,5)
	var player_placed:=map.place_entity("PLAYER",start)
	var bridge:=MapNpcBridge.new()
	var contact:=Vector2i(5,5)
	var npcs:Array[NpcInstance]=[]
	var item_repo:=ItemRepository.new()
	var valid:=player_placed and HexGrid.distance(start,contact)==1
	for i in range(3):
		var npc_id:="E2E_NPC_%03d"%(i+1)
		var npc:=NpcInstance.new(npc_id,npc_repo.get_npc("NPC003"))
		npcs.append(npc)
		valid=valid and bridge.register_npc(map,npc,contact)
		var item_id:="E2E_ITEM_%03d"%(i+1)
		var item:Dictionary={"instance_id":item_id,"template_id":"TEST_DAGGER","quality":"common","durability":{"current":15,"max":20}}
		item_repo.add_item(item)
		valid=valid and npc.receive_item(item_id,item_repo)

	var turns:=HexMapTurnService.new()
	var movement:=turns.move_player(map,bridge,"PLAYER",contact,RandomNumberGenerator.new())
	valid=valid and bool(movement.get("ok",false))
	var encounter:Dictionary=movement.get("encounter",{})
	valid=valid and bool(encounter.get("ok",false))
	valid=valid and encounter.get("npc_instance_ids",[]).size()==3

	var player_character:=CharacterState.new("PLAYER","Artheon Hero",5)
	var player:=CombatantState.new("PLAYER","Artheon Hero",5,200)
	player.combat_stats={"main_hand_damage_min":500.0,"main_hand_damage_max":500.0}
	var session:=MapEncounterCombatService.begin(encounter,npc_repo,player)
	valid=valid and bool(session.get("ok",false))
	var state:CombatState=session.get("state") as CombatState
	var group:GroupCombatState=session.get("group") as GroupCombatState
	valid=valid and state!=null and group!=null and state.combatants.size()==4

	var simulator:=GroupCombatSimulator.new(state,group)
	var combat_result:=simulator.run()
	valid=valid and String(combat_result.get("winning_team",""))=="players"
	valid=valid and combat_result.get("dead_ids",[]).size()==3

	var outcome:=turns.resolve_group_victory(combat_result,map,bridge,encounter,player_character,item_repo,NpcPossessionLootService.new(1),{"common":100.0})
	valid=valid and not turns.coordinator.combat_active
	valid=valid and bool(outcome.get("ok",false))
	valid=valid and int(outcome.get("defeated_count",0))==3
	valid=valid and bridge.npc_at(map,contact).is_empty()
	for npc in npcs:
		valid=valid and npc.life_state=="dead"
		valid=valid and not map.entity_positions.has(npc.instance_id)

	var pool:EncounterLootPool=outcome.get("loot_pool")
	valid=valid and pool!=null and pool.entries.size()==3
	valid=valid and pool.available_for("PLAYER").size()==3
	for i in range(3):
		valid=valid and not player_character.inventory.owns("E2E_ITEM_%03d"%(i+1))
	valid=valid and pool.claim("E2E_ITEM_002",player_character,item_repo)
	valid=valid and player_character.inventory.owns("E2E_ITEM_002")
	valid=valid and not player_character.inventory.owns("E2E_ITEM_001")
	valid=valid and not player_character.inventory.owns("E2E_ITEM_003")
	valid=valid and pool.entries.size()==2

	print("HEX_MAP_GROUP_E2E_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
