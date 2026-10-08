extends SceneTree

func _initialize()->void:
	var valid:=true
	var repository:=ItemRepository.new()
	var player:=CharacterState.new("PERSIST_PLAYER","Persistence Hero",5)
	var pool:=EncounterLootPool.new()
	for i in range(2):
		var item_id:="PERSIST_ITEM_%d"%i
		valid=valid and repository.add_item({"instance_id":item_id,"template_id":"TEST","quality":"common"})
		valid=valid and pool.add_drop(item_id,"PERSIST_NPC")
	pool.assign_all(player.character_id)
	valid=valid and pool.claim("PERSIST_ITEM_0",player,repository)
	var expedition:=ExpeditionState.new("PERSIST_EXPEDITION")
	valid=valid and expedition.save_loot_pool("PERSIST_ENCOUNTER",pool)
	var checkpoint:Dictionary={
		"repository":repository.to_dict(),
		"inventory":player.inventory.to_dict(),
		"expedition":expedition.to_dict()
	}
	var restored_repository:=ItemRepository.from_dict(checkpoint["repository"])
	var restored_inventory:=InventoryState.from_dict(checkpoint["inventory"],restored_repository)
	var restored_expedition:=ExpeditionState.from_dict(checkpoint["expedition"])
	var restored_pool:=restored_expedition.restore_loot_pool("PERSIST_ENCOUNTER")
	var restored_player:=CharacterState.new("PERSIST_PLAYER","Persistence Hero",5)
	restored_player.inventory=restored_inventory
	valid=valid and restored_repository.size()==2
	valid=valid and restored_inventory.size()==1 and restored_inventory.owns("PERSIST_ITEM_0")
	valid=valid and restored_pool!=null and restored_pool.item_ids().size()==1
	valid=valid and restored_pool.available_for(restored_player.character_id).has("PERSIST_ITEM_1")
	valid=valid and not restored_pool.claim("PERSIST_ITEM_0",restored_player,restored_repository)
	valid=valid and restored_pool.claim("PERSIST_ITEM_1",restored_player,restored_repository)
	valid=valid and not restored_pool.claim("PERSIST_ITEM_1",restored_player,restored_repository)
	valid=valid and restored_inventory.size()==2 and restored_pool.item_ids().is_empty()
	# Exercise the expedition-level claim API and persist the resulting state.
	var second_pool:=EncounterLootPool.new()
	valid=valid and restored_repository.add_item({"instance_id":"RESTART_CLAIM","template_id":"TEST"})
	valid=valid and second_pool.add_drop("RESTART_CLAIM","NPC")
	second_pool.assign_all(restored_player.character_id)
	second_pool.place_on_hex(Vector2i(2,3),1000)
	valid=valid and restored_expedition.save_loot_pool("RESTART_ENCOUNTER",second_pool)
	valid=valid and restored_expedition.claim_loot_at_hex(restored_player,Vector2i(2,3),"RESTART_CLAIM",restored_repository,1100)
	var saved_after_claim:Dictionary={"repository":restored_repository.to_dict(),"inventory":restored_player.inventory.to_dict(),"expedition":restored_expedition.to_dict()}
	var after_repo:=ItemRepository.from_dict(saved_after_claim["repository"])
	var after_inventory:=InventoryState.from_dict(saved_after_claim["inventory"],after_repo)
	var after_expedition:=ExpeditionState.from_dict(saved_after_claim["expedition"])
	valid=valid and after_inventory.owns("RESTART_CLAIM")
	valid=valid and after_expedition.restore_loot_pool("RESTART_ENCOUNTER")==null
	valid=valid and not after_expedition.claim_loot_at_hex(restored_player,Vector2i(2,3),"RESTART_CLAIM",after_repo,1100)
	var malformed_inventory:Dictionary={"owner_id":"PERSIST_PLAYER","instance_ids":["PERSIST_ITEM_0","MISSING_ITEM"]}
	var checked_inventory:=InventoryState.from_dict(malformed_inventory,restored_repository)
	valid=valid and checked_inventory.size()==1 and not checked_inventory.owns("MISSING_ITEM")
	print("LOOT_PERSISTENCE_RESTART_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
