extends SceneTree

func _initialize()->void:
	var valid:=true
	var repository:=ItemRepository.new()
	var expedition:=ExpeditionState.new("HEX_LOOT_EXPEDITION")
	var first:=EncounterLootPool.new()
	var second:=EncounterLootPool.new()
	valid=valid and repository.add_item({"instance_id":"HEX_LOOT_1"})
	valid=valid and repository.add_item({"instance_id":"HEX_LOOT_2"})
	valid=valid and first.add_drop("HEX_LOOT_1","NPC_1")
	valid=valid and second.add_drop("HEX_LOOT_2","NPC_2")
	first.place_on_hex(Vector2i(3,7),1000)
	second.place_on_hex(Vector2i(3,7),1400)
	first.assign_all("PLAYER")
	second.assign_all("PLAYER")
	valid=valid and expedition.save_loot_pool("FIGHT_1",first)
	valid=valid and expedition.save_loot_pool("FIGHT_2",second)
	var restored:=ExpeditionState.from_dict(expedition.to_dict())
	valid=valid and restored.loot_hexes(1800).size()==1
	valid=valid and restored.loot_hexes(1800).has(Vector2i(3,7))
	valid=valid and restored.cleanup_expired_loot(1899,repository)==0
	valid=valid and restored.cleanup_expired_loot(1900,repository)==1
	valid=valid and not repository.has_item("HEX_LOOT_1")
	valid=valid and repository.has_item("HEX_LOOT_2")
	valid=valid and restored.loot_hexes(1900).size()==1
	valid=valid and restored.cleanup_expired_loot(2300,repository)==1
	valid=valid and restored.loot_hexes(2300).is_empty()
	valid=valid and repository.size()==0
	valid=valid and restored.cleanup_expired_loot(2400,repository)==0
	print("HEX_LOOT_EXPIRY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
