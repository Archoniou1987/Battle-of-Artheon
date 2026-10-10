class_name CharacterState
extends RefCounted

## Persistent gameplay ownership state. CombatantState remains combat-runtime only.
var character_id: String
var display_name: String
var level: int
var progression: CharacterProgression
var inventory: InventoryState
var equipment: EquipmentState

func _init(id: String, name: String, character_level: int = 1) -> void:
	character_id = id
	display_name = name
	progression = CharacterProgression.new(character_level)
	level = progression.level
	inventory = InventoryState.new(character_id)
	equipment = EquipmentState.new()

func receive_item(instance_id: String, repository: ItemRepository) -> bool:
	return inventory.add_instance(instance_id, repository)

func equip(slot: String, instance_id: String, repository: ItemRepository) -> bool:
	return EquipmentService.equip_instance(slot, instance_id, inventory, equipment, repository)

func unequip(slot: String) -> Variant:
	return equipment.unequip(slot)

func remove_item(instance_id: String) -> bool:
	return inventory.remove_instance(instance_id, equipment)

## Character-level progression is kept outside the combat runtime.
func award_xp(amount: int) -> int:
	var gained := progression.gain_xp(amount)
	level = progression.level
	return gained

func allocate_stat(stat: String) -> bool:
	return progression.allocate_stat(stat)

func progression_snapshot() -> Dictionary:
	return progression.to_dict()

func restore_progression(data: Dictionary) -> bool:
	if not progression.restore(data):
		return false
	level = progression.level
	return true
