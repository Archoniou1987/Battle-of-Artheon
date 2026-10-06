class_name ItemDurabilityService
extends RefCounted

## Durability belongs to a unique item instance, never to the template.
## repair_progress is internal lifetime state and must not be exposed in public item summaries.

static func initialize_item(item: Dictionary, max_durability: int, current_durability: int = -1, repair_progress: int = 0) -> void:
	var maximum := maxi(1, max_durability)
	var current := maximum if current_durability < 0 else clampi(current_durability, 0, maximum)
	item["durability_max"] = maximum
	item["durability_current"] = current
	item["_durability_repair_progress"] = maxi(0, repair_progress)

static func is_usable(item: Dictionary) -> bool:
	return int(item.get("durability_current", 0)) > 0 and int(item.get("durability_max", 0)) > 0

static func damage(item: Dictionary, amount: int) -> int:
	if amount <= 0:
		return 0
	var before := int(item.get("durability_current", 0))
	var after := maxi(0, before - amount)
	item["durability_current"] = after
	return before - after

static func repair(item: Dictionary, amount: int) -> int:
	if amount <= 0:
		return 0
	var maximum := int(item.get("durability_max", 0))
	var current := int(item.get("durability_current", 0))
	if maximum <= 0 or current >= maximum:
		return 0
	var restored := mini(amount, maximum - current)
	item["durability_current"] = current + restored
	_consume_repair_lifetime(item, restored)
	return restored

static func public_summary(item: Dictionary) -> Dictionary:
	var summary := item.duplicate(true)
	summary.erase("_durability_repair_progress")
	return summary

static func _consume_repair_lifetime(item: Dictionary, restored: int) -> void:
	var progress := int(item.get("_durability_repair_progress", 0)) + restored
	var maximum := int(item.get("durability_max", 0))
	while maximum > 1:
		var threshold := maximum - 1
		if progress < threshold:
			break
		progress -= threshold
		maximum -= 1
		item["durability_max"] = maximum
		item["durability_current"] = mini(int(item.get("durability_current", maximum)), maximum)
	if maximum <= 1:
		progress = 0
	item["_durability_repair_progress"] = progress
