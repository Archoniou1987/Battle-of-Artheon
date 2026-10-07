class_name AbilityCatalog
extends RefCounted

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func definition(abilities: Dictionary, ability_id: String) -> Dictionary:
	var value = abilities.get(ability_id, {})
	return value if value is Dictionary else {}

static func assigned_abilities(loadouts: Dictionary, combatant_id: String) -> Array:
	var value = loadouts.get(combatant_id, [])
	return value if value is Array else []
