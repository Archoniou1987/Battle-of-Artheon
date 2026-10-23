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
	return ItemTemplateService.resolve(_items[instance_id] as Dictionary)

func update_item(item: Dictionary) -> bool:
	var instance_id := String(item.get("instance_id", ""))
	if instance_id.is_empty() or not _items.has(instance_id):
		return false
	_items[instance_id] = item.duplicate(true)
	return true

func remove_item(instance_id: String) -> bool:
	return _items.erase(instance_id)

func size() -> int:
	return _items.size()

func to_dict()->Dictionary:
	return {"items":_items.duplicate(true)}

static func from_dict(data:Dictionary)->ItemRepository:
	var restored:=ItemRepository.new()
	var raw_items:Dictionary=data.get("items",{})
	for item_id in raw_items:
		var item=raw_items[item_id]
		if item is Dictionary and String(item.get("instance_id",""))==String(item_id):
			restored.add_item(item)
	return restored
