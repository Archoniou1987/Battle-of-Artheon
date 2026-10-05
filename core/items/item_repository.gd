class_name ItemRepository
extends RefCounted

## Owns live item instances. Equipment stores only instance IDs.
var _items: Dictionary = {}

func add_item(item: Dictionary) -> bool:
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.is_empty() or _items.has(instance_id):
		return false
	_items[instance_id] = item.duplicate(true)
	return true

func has_item(instance_id: String) -> bool:
	return _items.has(instance_id)

func get_item(instance_id: String) -> Dictionary:
	if not _items.has(instance_id):
		return {}
	return (_items[instance_id] as Dictionary).duplicate(true)

func remove_item(instance_id: String) -> bool:
	return _items.erase(instance_id)

func size() -> int:
	return _items.size()
