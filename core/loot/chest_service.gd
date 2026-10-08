class_name ChestService
extends RefCounted

## Opening a chest generates drops once; ownership changes only through claim().
static func open_chest(chest:ChestState,opener:CharacterState,loot_table:Dictionary,templates_by_id:Dictionary,generator:ItemGenerator,repository:ItemRepository,loot_service:LootService)->EncounterLootPool:
	var pool:=EncounterLootPool.new()
	if chest==null or opener==null or chest.is_open:
		return pool
	if chest.chest_id.is_empty() or chest.loot_table_id.is_empty():
		return pool
	if String(loot_table.get("id",""))!=chest.loot_table_id:
		return pool
	chest.is_open=true
	for item in loot_service.roll_drops(chest.chest_id,loot_table,templates_by_id,generator,repository):
		pool.add_drop(String(item.get("instance_id","")),chest.chest_id)
	pool.assign_all(opener.character_id)
	return pool
