class_name AbilityCatalog
extends RefCounted

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## No active numbered ABI below 301 remain in the game. These legacy
## references can still occur in old saves; never expose them as castable.
## TEST_ names are isolated development fixtures, not production ABI IDs.
static func is_retired_numbered_abi(ability_id: String) -> bool:
	if not ability_id.begins_with("ABI"):
		return false
	var suffix := ability_id.substr(3)
	return suffix.is_valid_int() and int(suffix)<301

static func definition(abilities: Dictionary, ability_id: String) -> Dictionary:
	var value = abilities.get(ability_id, {})
	return value if value is Dictionary else {}

static func assigned_abilities(loadouts: Dictionary, combatant_id: String) -> Array:
	var value = loadouts.get(combatant_id, [])
	return value if value is Array else []
