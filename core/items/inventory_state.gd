class_name InventoryState
extends RefCounted

var owner_id: String
var _instance_ids: Dictionary = {}

func _init(p_owner_id: String) -> void:
	owner_id = p_owner_id

func add_instance(instance_id: String, repository: ItemRepository) -> bool:
	if instance_id.is_empty() or not repository.has_item(instance_id) or _instance_ids.has(instance_id):
		return false
	_instance_ids[instance_id] = true
	return true

func owns(instance_id: String) -> bool:
	return _instance_ids.has(instance_id)

func remove_instance(instance_id: String, equipment: EquipmentState) -> bool:
	if not owns(instance_id) or equipment.is_equipped(instance_id):
		return false
	return _instance_ids.erase(instance_id)

func size() -> int:
	return _instance_ids.size()

func instance_ids() -> Array:
	return _instance_ids.keys().duplicate()

func to_dict()->Dictionary:
	return {"owner_id":owner_id,"instance_ids":instance_ids()}

static func from_dict(data:Dictionary,repository:ItemRepository)->InventoryState:
	var restored:=InventoryState.new(String(data.get("owner_id","")))
	for raw_id in data.get("instance_ids",[]):
		restored.add_instance(String(raw_id),repository)
	return restored
