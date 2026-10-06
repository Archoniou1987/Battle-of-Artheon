class_name LootService
extends RefCounted

var rng := RandomNumberGenerator.new()

func _init(seed_value: int = 1) -> void:
	rng.seed = seed_value

func roll_loot(source_id: String, loot_table: Dictionary, templates_by_id: Dictionary, generator: ItemGenerator, repository: ItemRepository, inventory: InventoryState) -> Array[Dictionary]:
	var awarded: Array[Dictionary] = []
	for raw_entry in loot_table.get("entries", []):
		var entry := raw_entry as Dictionary
		if rng.randf() * 100.0 >= float(entry.get("chance", 0.0)):
			continue
		var template_id := String(entry.get("template_id", ""))
		if not templates_by_id.has(template_id):
			continue
		var quality := _roll_quality(entry.get("quality_weights", {}))
		if quality.is_empty():
			continue
		var item := generator.generate(templates_by_id[template_id] as Dictionary, quality)
		if item.is_empty():
			continue
		item["loot_source_id"] = source_id
		item["loot_table_id"] = String(loot_table.get("id", ""))
		if not repository.add_item(item):
			continue
		var instance_id := String(item.get("instance_id", ""))
		if not inventory.add_instance(instance_id, repository):
			repository.remove_item(instance_id)
			continue
		awarded.append(item)
	return awarded

func _roll_quality(weights: Dictionary) -> String:
	var total := 0.0
	for value in weights.values():
		total += maxf(0.0, float(value))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var cumulative := 0.0
	for quality in ["poor", "common", "green", "blue", "purple"]:
		cumulative += maxf(0.0, float(weights.get(quality, 0.0)))
		if roll < cumulative:
			return quality
	return "purple"
