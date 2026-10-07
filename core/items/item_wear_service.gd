class_name ItemWearService
extends RefCounted

## Applies defeat wear to every unique equipped item instance.
static func damage_equipped(character: CharacterState, repository: ItemRepository, amount: int) -> Dictionary:
	var damaged: Dictionary = {}
	if amount <= 0:
		return damaged
	for slot in EquipmentState.SLOTS:
		var raw_instance_id: Variant = character.equipment.get_equipped_instance_id(slot)
		if raw_instance_id == null:
			continue
		var instance_id := String(raw_instance_id)
		if damaged.has(instance_id) or not repository.has_item(instance_id):
			continue
		var item := repository.get_item(instance_id)
		var lost := ItemDurabilityService.damage(item, amount)
		if lost > 0 and repository.update_item(item):
			damaged[instance_id] = lost
	return damaged
