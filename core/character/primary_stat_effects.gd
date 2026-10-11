class_name PrimaryStatEffects
extends RefCounted

const CONFIG_PATH := "res://data/character/primary_stat_effects.json"

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("Missing primary stat config: " + CONFIG_PATH)
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## Return only configured primary-stat contributions, without inventing
## equipment, combat-runtime or unimplemented values.
static func calculate(stats: Dictionary, config: Dictionary = {}) -> Dictionary:
	var source := config if not config.is_empty() else load_config()
	var effects: Dictionary = source.get("effects", {})
	var result: Dictionary = {}
	for stat in effects:
		var amount := float(stats.get(stat, 0))
		var modifiers: Dictionary = effects[stat]
		for key in modifiers:
			result[key] = float(result.get(key, 0.0)) + amount * float(modifiers[key])
	return result
