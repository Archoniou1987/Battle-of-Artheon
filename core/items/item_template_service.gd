class_name ItemTemplateService
extends RefCounted

## Runtime template resolution. The template owns balance; the instance owns identity and wear.
const TEMPLATE_PATH := "res://data/items/arena_templates.json"
const PAR_PATH := "res://data/parameters/par_registry.json"

static func load_templates() -> Dictionary:
	var result := {}
	if not FileAccess.file_exists(TEMPLATE_PATH):
		return result
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE_PATH))
	if not raw is Dictionary:
		return result
	for entry in raw.get("templates", []):
		if entry is Dictionary:
			var id := String(entry.get("id", ""))
			if not id.is_empty() and not result.has(id):
				result[id] = entry
	return result

static func _par_keys() -> Dictionary:
	var keys := {}
	if not FileAccess.file_exists(PAR_PATH):
		return keys
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAR_PATH))
	if not raw is Dictionary or not bool(raw.get("locked", false)):
		return keys
	for entry in raw.get("parameters", []):
		if entry is Dictionary:
			var id := String(entry.get("id", ""))
			var key := String(entry.get("source_key", ""))
			if not id.is_empty() and not key.is_empty():
				keys[id] = key
	return keys

static func resolve(instance: Dictionary) -> Dictionary:
	var template_id := String(instance.get("template_id", ""))
	if template_id.is_empty():
		return instance.duplicate(true)
	var templates := load_templates()
	if not templates.has(template_id):
		push_error("Item template not found: " + template_id)
		return {}
	var template: Dictionary = templates[template_id]
	var keys := _par_keys()
	var stats := {}
	var par_stats: Dictionary = template.get("par_stats", {})
	for par_id in par_stats:
		if not keys.has(par_id):
			push_error("Unknown locked PAR: " + String(par_id))
			return {}
		stats[String(keys[par_id])] = par_stats[par_id]
	var resolved := template.duplicate(true)
	resolved["id"] = template_id
	resolved["template_id"] = template_id
	resolved["guaranteed_stats"] = stats
	resolved["requirements"] = template.get("requirements", {}).duplicate(true)
	resolved["combat_stats"] = template.get("combat_stats", {}).duplicate(true)
	resolved["bonuses"] = instance.get("bonuses", {}).duplicate(true)
	# Keep only instance-owned data. Template-owned fields cannot be overridden.
	for field in ["instance_id", "rarity", "quality", "quality_multiplier", "rolled_mods", "origin", "durability_max", "durability_current", "_durability_repair_progress", "owner_id"]:
		if instance.has(field):
			resolved[field] = instance[field]
	if instance.has("rolled_mods"):
		for mod in instance["rolled_mods"]:
			if mod is Dictionary:
				var key := String(mod.get("stat", ""))
				if keys.has(key):
					key = String(keys[key])
				if not key.is_empty():
					resolved["bonuses"][key] = float(resolved["bonuses"].get(key, 0)) + float(mod.get("value", 0))
	return resolved
