class_name GroundLootSettlementAdapter
extends RefCounted

## Migration boundary from one durable, committed encounter reward pool
## to ordinary Solo GroundLoot. Only called AFTER settlement marker exists
## and BEFORE the world bundle is committed. Does not re-roll items.
## The marker is retained, therefore receipt replay cannot resurrect pool.
const MIGRATED_KEY := "ground_loot_settled_encounters"

static func migrate(expedition: ExpeditionState, repository: ItemRepository, encounter_key: String, player: CharacterState, receipt_hash: String) -> Dictionary:
	if expedition == null or not expedition.is_active() or repository == null or player == null or encounter_key.is_empty() or receipt_hash.is_empty():
		return {"ok":false,"reason":"invalid_ground_migration_context"}
	var hashes: Variant = expedition.world_state.get(MapCombatSettlementService.MARKER_KEY,{})
	if not hashes is Dictionary or String(hashes.get(encounter_key,"")) != receipt_hash:
		return {"ok":false,"reason":"uncommitted_ground_outcome"}
	var migrations: Dictionary = Dictionary(expedition.world_state.get(MIGRATED_KEY,{})).duplicate(true)
	if migrations.has(encounter_key):
		if String(migrations[encounter_key]) == receipt_hash and expedition.restore_loot_pool(encounter_key) == null:
			return {"ok":true,"already_migrated":true,"count":0}
		return {"ok":false,"reason":"ground_migration_conflict"}
	var pool := expedition.restore_loot_pool(encounter_key)
	if pool == null:
		return {"ok":false,"reason":"missing_ground_source_pool"}
	var ground := GroundLootService._registry(expedition)
	var seen: Dictionary = {}
	for item_id in pool.item_ids():
		if item_id.is_empty() or seen.has(item_id):
			return {"ok":false,"reason":"ground_duplicate_reward"}
		seen[item_id] = true
		if not repository.has_item(item_id) or ground.has(item_id) or player.inventory.owns(item_id):
			return {"ok":false,"reason":"ground_item_not_transferable","item_id":item_id}
		if String(pool.assigned_player_by_item.get(item_id,"")) != player.character_id:
			return {"ok":false,"reason":"ground_reward_owner_mismatch","item_id":item_id}
		for raw_slot in player.equipment.slots.values():
			if raw_slot == item_id:
				return {"ok":false,"reason":"ground_reward_equipped","item_id":item_id}
	# Mutate the authoritative expedition in one in-memory transition;
	# callers persist the resulting world and repository with world commit.
	for item_id in pool.item_ids():
		ground[item_id] = {
			"instance_id":item_id,
			"cell":[pool.hex_cell.x,pool.hex_cell.y],
			"source_id":encounter_key,
			"owner_id":player.character_id,
			"policy":GroundLootService.POLICY_EXPEDITION,
			"expires_at_unix":0
		}
	var pools: Dictionary = Dictionary(expedition.world_state.get("encounter_loot_pools",{})).duplicate(true)
	pools.erase(encounter_key)
	migrations[encounter_key] = receipt_hash
	expedition.world_state[GroundLootService.WORLD_KEY] = ground
	expedition.world_state["encounter_loot_pools"] = pools
	expedition.world_state[MIGRATED_KEY] = migrations
	return {"ok":true,"already_migrated":false,"count":seen.size(),"cell":pool.hex_cell}
