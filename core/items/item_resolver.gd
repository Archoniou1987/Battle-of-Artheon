class_name ItemResolver
extends RefCounted

## Resolves an equipped InstanceID into the materialized item consumed by EquipmentBuilder.
static func resolve_equipped(slot: String, equipment: EquipmentState, repository: ItemRepository) -> Dictionary:
	var instance_id: Variant = equipment.get_instance_id(slot)
	if instance_id == null:
		return {}
	return repository.get_item(String(instance_id))
