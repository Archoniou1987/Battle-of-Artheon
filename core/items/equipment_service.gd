class_name EquipmentService
extends RefCounted

## Ownership gate for all normal equipment operations.
static func equip_instance(slot: String, instance_id: String, inventory: InventoryState, equipment: EquipmentState, repository: ItemRepository) -> bool:
	if instance_id.is_empty() or not inventory.owns(instance_id):
		return false
	if not repository.has_item(instance_id):
		return false
	if equipment.is_equipped(instance_id):
		return false
	var item := repository.get_item(instance_id)
	if item.is_empty() or not ItemDurabilityService.is_usable(item):
		return false
	return equipment.equip_item(slot, item)
