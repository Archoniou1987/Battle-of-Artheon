class_name CombatRewardService
extends RefCounted

## A completed duel may create one shared loot pool, but never awards inventory.
## The caller retains the pool for manual claim and expedition persistence.
static func create_duel_loot_pool(result:Dictionary,defeated_source_id:String,winner:CharacterState,loot_table:Dictionary,templates_by_id:Dictionary,generator:ItemGenerator,repository:ItemRepository,loot_service:LootService)->EncounterLootPool:
	var pool:=EncounterLootPool.new()
	if winner==null or String(result.get("winner_id",""))!=winner.character_id:
		return pool
	if String(result.get("loser_id",""))!=defeated_source_id:
		return pool
	for drop in loot_service.roll_drops(defeated_source_id,loot_table,templates_by_id,generator,repository):
		pool.add_drop(String(drop.get("instance_id","")),defeated_source_id)
	pool.assign_all(winner.character_id)
	return pool
