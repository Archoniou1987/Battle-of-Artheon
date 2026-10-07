class_name ChestService
extends RefCounted

static func open_chest(chest: ChestState, opener: CharacterState, loot_table: Dictionary, templates_by_id: Dictionary, generator: ItemGenerator, repository: ItemRepository, loot_service: LootService) -> Array[Dictionary]:
	if chest == null or chest.is_open:
		return []
	if chest.chest_id.is_empty() or chest.loot_table_id.is_empty():
		return []
	if String(loot_table.get("id", "")) != chest.loot_table_id:
		return []
	chest.is_open = true
	return loot_service.roll_loot(chest.chest_id, loot_table, templates_by_id, generator, repository, opener.inventory)
