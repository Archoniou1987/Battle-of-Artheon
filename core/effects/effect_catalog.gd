class_name EffectCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/effects/catalog.json"

static func load_json(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing canonical EFF catalog: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Invalid canonical EFF catalog: " + path)
		return {}
	return parsed

static func definition(effects: Dictionary, effect_id: String) -> Dictionary:
	var value: Variant = effects.get(effect_id, {})
	return value if value is Dictionary else {}
