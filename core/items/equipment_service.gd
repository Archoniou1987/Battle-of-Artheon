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
	var allowed: Array = item.get("equip_slots", [])
	if (slot == "ring1" or slot == "ring2") and not allowed.has(slot) and (allowed.has("ring1") or allowed.has("ring2")):
		var usage: Array = item.get("slot_usage", [allowed[0]])
		if usage.size() != 1 or (usage[0] != "ring1" and usage[0] != "ring2"):
			return false
		item = item.duplicate(true)
		var slots: Array = allowed.duplicate()
		slots.append(slot)
		item["equip_slots"] = slots
		item["slot_usage"] = [slot]
	return equipment.equip_item(slot, item)
