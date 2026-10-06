class_name CombatConsequenceService
extends RefCounted

## Applies persistent consequences after combat without coupling them to combat simulation.
static func apply_defeat_wear(result: Dictionary, character: CharacterState, repository: ItemRepository, durability_loss: int) -> Dictionary:
	if String(result.get("loser_id", "")) != character.character_id:
		return {}
	return ItemWearService.damage_equipped(character, repository, durability_loss)
