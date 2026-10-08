extends SceneTree
func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_repo:=NpcRepository.new(); npc_repo.load_definitions(doc)
	var npc:=NpcInstance.new("WORLD_BANDIT_001",npc_repo.get_npc("NPC003"))
	var item_repo:=ItemRepository.new()
	var item:Dictionary={"instance_id":"BANDIT_DAGGER_001","template_id":"TEST_DAGGER","quality":"common","durability":{"current":15,"max":20}}
	item_repo.add_item(item)
	var valid:=npc.receive_item("BANDIT_DAGGER_001",item_repo)
	var map:=TacticalMapState.new(10,10); var bridge:=MapNpcBridge.new()
	valid=valid and bridge.register_npc(map,npc,Vector2i(5,5))
	var player:=CharacterState.new("PLAYER","Artheon Hero",5)
	var result:Dictionary={"winner_id":"PLAYER","loser_id":"WORLD_BANDIT_001"}
	var outcome:=MapCombatOutcomeService.resolve_victory(result,map,bridge,npc,player,item_repo,NpcPossessionLootService.new(1),{"common":100.0})
	valid=valid and bool(outcome.get("ok",false)) and npc.life_state=="dead"
	valid=valid and not map.entity_positions.has("WORLD_BANDIT_001")
	valid=valid and bridge.instances.has("WORLD_BANDIT_001")
	valid=valid and bridge.npc_at(map,Vector2i(5,5)).is_empty()
	valid=valid and not player.inventory.owns("BANDIT_DAGGER_001") and int(outcome.get("drop_count",0))==1
	var pool:EncounterLootPool=outcome.get("loot_pool")
	valid=valid and pool!=null and pool.available_for("PLAYER")==["BANDIT_DAGGER_001"]
	var saved_pool:=pool.to_dict()
	var restored:=EncounterLootPool.from_dict(saved_pool)
	valid=valid and restored.available_for("PLAYER")==["BANDIT_DAGGER_001"]
	valid=valid and String(restored.entries[0].get("source_npc_instance_id",""))=="WORLD_BANDIT_001"
	valid=valid and restored.claim("BANDIT_DAGGER_001",player,item_repo)
	valid=valid and player.inventory.owns("BANDIT_DAGGER_001") and restored.entries.is_empty()
	print("MAP_COMBAT_OUTCOME npc=%s state=%s drops=%d inventory=%d"%[npc.instance_id,npc.life_state,int(outcome.drop_count),player.inventory.size()])
	print("MAP_COMBAT_OUTCOME_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
