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
	var malformed_inventory:Dictionary={"owner_id":"PERSIST_PLAYER","instance_ids":["PERSIST_ITEM_0","MISSING_ITEM"]}
	var checked_inventory:=InventoryState.from_dict(malformed_inventory,restored_repository)
	valid=valid and checked_inventory.size()==1 and not checked_inventory.owns("MISSING_ITEM")
	print("LOOT_PERSISTENCE_RESTART_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
