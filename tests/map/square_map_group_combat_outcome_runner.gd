extends SceneTree

func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_repo:=NpcRepository.new()
	npc_repo.load_definitions(doc)
	var map:=SquareMapState.new(12,12,Vector2i(4,5))
	var bridge:=MapNpcBridge.new()
	var cell:=Vector2i(5,5)
	var npcs:Array[NpcInstance]=[]
	var item_repo:=ItemRepository.new()
	var valid:=true
	for i in range(3):
		var id:="GROUP_LOOT_%03d"%(i+1)
		var npc:=NpcInstance.new(id,npc_repo.get_npc("NPC003"))
		npcs.append(npc)
		valid=valid and bridge.register_npc(map,npc,cell)
		var item_id:="GROUP_ITEM_%03d"%(i+1)
		var item:Dictionary={"instance_id":item_id,"template_id":"TEST_DAGGER","quality":"common","durability":{"current":15,"max":20}}
		item_repo.add_item(item)
		valid=valid and npc.receive_item(item_id,item_repo)
	var player:=CharacterState.new("PLAYER","Artheon Hero",5)
	var result:Dictionary={"winning_team":"players","dead_ids":["GROUP_LOOT_001","GROUP_LOOT_002","GROUP_LOOT_003"]}
	var outcome:=MapCombatOutcomeService.resolve_group_victory(result,map,bridge,npcs,player,item_repo,NpcPossessionLootService.new(1),{"common":100.0})
	valid=valid and bool(outcome.get("ok",false))
	valid=valid and int(outcome.get("defeated_count",0))==3
	valid=valid and int(outcome.get("drop_count",0))==3
	var pool:EncounterLootPool=outcome.get("loot_pool")
	valid=valid and pool!=null and pool.entries.size()==3
	valid=valid and pool.available_for("PLAYER").size()==3
	valid=valid and not pool.add_drop("GROUP_ITEM_001","GROUP_LOOT_001")
	valid=valid and pool.entries.size()==3
	var restored_pool:=EncounterLootPool.from_dict(pool.to_dict())
	valid=valid and restored_pool.entries.size()==3
	valid=valid and restored_pool.available_for("PLAYER").size()==3
	valid=valid and String(restored_pool.entries[2].get("source_npc_instance_id",""))=="GROUP_LOOT_003"
	valid=valid and bridge.npc_at(map,cell).is_empty()
	for i in range(3):
		var id:="GROUP_LOOT_%03d"%(i+1)
		var item_id:="GROUP_ITEM_%03d"%(i+1)
		valid=valid and npcs[i].life_state=="dead"
		valid=valid and not map.entity_positions.has(id)
		valid=valid and not player.inventory.owns(item_id)
		valid=valid and String(pool.entries[i].get("source_npc_instance_id",""))==id
	valid=valid and pool.claim("GROUP_ITEM_002",player,item_repo)
	valid=valid and player.inventory.owns("GROUP_ITEM_002")
	valid=valid and not player.inventory.owns("GROUP_ITEM_001")
	valid=valid and not player.inventory.owns("GROUP_ITEM_003")
	valid=valid and pool.entries.size()==2
	valid=valid and not pool.claim("GROUP_ITEM_002",player,item_repo)
	print("SQUARE_MAP_GROUP_OUTCOME_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
