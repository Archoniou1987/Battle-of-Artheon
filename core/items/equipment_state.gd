class_name EquipmentState
extends RefCounted

const SLOTS := [
	"head", "shoulders", "neck", "back", "chest", "wrists",
	"ring1", "ring2", "waist", "legs", "feet", "main_hand", "off_hand"
]

var slots: Dictionary = {}

func _init() -> void:
	for slot in SLOTS:
		slots[slot] = null

func equip(slot: String, instance_id: String) -> bool:
	if not slots.has(slot) or instance_id.is_empty():
		return false
	if is_equipped(instance_id):
		return false
	slots[slot] = instance_id
	return true

func unequip(slot: String) -> Variant:
	if not slots.has(slot):
		return null
	var previous: Variant = slots[slot]
	slots[slot] = null
	return previous

func get_instance_id(slot: String) -> Variant:
	return slots.get(slot, null)

func is_equipped(instance_id: String) -> bool:
	return slots.values().has(instance_id)
