class_name EquipmentState
extends RefCounted

const SLOTS := [
	"head", "shoulders", "neck", "back", "chest", "wrists",
	"ring1", "ring2", "waist", "legs", "feet", "main_hand", "off_hand", "tool"
]

var slots: Dictionary = {}

func _init() -> void:
	for slot in SLOTS:
		slots[slot] = null

func equip_item(slot: String, item: Dictionary) -> bool:
	if not slots.has(slot):
		return false
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.is_empty() or is_equipped(instance_id):
		return false
	var allowed_slots: Array = item.get("equip_slots", [])
	if not allowed_slots.has(slot):
		return false
	var occupied_slots: Array = item.get("slot_usage", [slot])
	if occupied_slots.is_empty():
		occupied_slots = [slot]
	if not occupied_slots.has(slot):
		occupied_slots = occupied_slots.duplicate()
		occupied_slots.append(slot)
	for occupied_slot in occupied_slots:
		if not slots.has(occupied_slot) or slots[occupied_slot] != null:
			return false
	for occupied_slot in occupied_slots:
		slots[occupied_slot] = instance_id
	return true

func unequip(slot: String) -> Variant:
	if not slots.has(slot):
		return null
	var previous: Variant = slots[slot]
	if previous == null:
		return null
	for equipment_slot in SLOTS:
		if slots[equipment_slot] == previous:
			slots[equipment_slot] = null
	return previous

func get_equipped_instance_id(slot: String) -> Variant:
	return slots.get(slot, null)

func is_equipped(instance_id: String) -> bool:
	return slots.values().has(instance_id)
