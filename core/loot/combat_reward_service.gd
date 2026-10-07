class_name CombatRewardService
extends RefCounted

## Bridges a completed combat result into persistent loot ownership.
## Combat itself stays independent from loot tables and inventories.
static func award_duel_loot(result: Dictionary, defeated_source_id: String, winner: CharacterState, loot_table: Dictionary, templates_by_id: Dictionary, generator: ItemGenerator, repository: ItemRepository, loot_service: LootService) -> Array[Dictionary]:
	if String(result.get("winner_id", "")) != winner.character_id:
		return []
	if String(result.get("loser_id", "")) != defeated_source_id:
		return []
	return loot_service.roll_loot(defeated_source_id, loot_table, templates_by_id, generator, repository, winner.inventory)
