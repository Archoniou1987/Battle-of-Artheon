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

static func _valid_par_ids() -> Dictionary:
	var ids := {}
	if not FileAccess.file_exists(PAR_PATH):
		return ids
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAR_PATH))
	if not raw is Dictionary or not bool(raw.get("locked", false)):
		return ids
	for entry in raw.get("parameters", []):
		if entry is Dictionary:
			ids[String(entry.get("id", ""))] = true
	return ids

static func resolve(instance: Dictionary) -> Dictionary:
	var template_id := String(instance.get("template_id", ""))
	if template_id.is_empty():
		return instance.duplicate(true) if validate_parameters(instance) else {}
	var templates := load_templates()
	if not templates.has(template_id):
		push_error("Item template not found: " + template_id)
		return {}
	var template: Dictionary = templates[template_id]
	var valid_ids := _valid_par_ids()
	var par_stats: Dictionary = template.get("par_stats", {})
	for par_id in par_stats:
		if not valid_ids.has(par_id):
			push_error("Unknown locked PAR: " + String(par_id))
			return {}
	var resolved := template.duplicate(true)
	resolved["id"] = template_id
	resolved["template_id"] = template_id
	resolved["par_stats"] = par_stats.duplicate(true)
	resolved["requirements"] = template.get("requirements", {}).duplicate(true)
	resolved["combat_stats"] = template.get("combat_stats", {}).duplicate(true)
	resolved["par_bonuses"] = instance.get("par_bonuses", {}).duplicate(true)
	# Keep only instance-owned data. Template-owned fields cannot be overridden.
	for field in ["instance_id", "rarity", "quality", "quality_multiplier", "rolled_mods", "origin", "durability_max", "durability_current", "_durability_repair_progress", "owner_id"]:
		if instance.has(field):
			resolved[field] = instance[field]
	# Charges are per item-instance, not template balance. Never copy item
	# components/max charges from the mutable instance over authored templates.
	if String(template.get("type","")) == "consumable" and instance.has("charges"):
		resolved["charges"] = int(instance["charges"])
	return resolved if validate_parameters(resolved) else {}

static func validate_parameters(item: Dictionary) -> bool:
	var definitions := _valid_par_ids()
	for field in ["guaranteed_stats", "bonuses", "base_stats", "final_stats"]:
		if not item.get(field, {}).is_empty():
			push_error("Obsolete item parameter field: " + field)
			return false
	for field in ["par_stats", "par_bonuses", "requirements"]:
		var values: Variant = item.get(field, {})
		if not values is Dictionary:
			push_error("Invalid item parameter dictionary: " + field)
			return false
		for key in values:
			if not definitions.has(key) or not (values[key] is int or values[key] is float) or not is_finite(float(values[key])):
				push_error("Invalid item parameter: " + field + "." + String(key))
				return false
			if field == "requirements" and not ParCalculationService.PRIMARY_IDS.has(key):
				push_error("Equipment requirement must reference a primary PAR: " + String(key))
				return false
	return true
