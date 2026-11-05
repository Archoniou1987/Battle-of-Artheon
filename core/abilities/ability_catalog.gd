class_name AbilityCatalog
extends RefCounted

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## Only the approved numbered sword/dagger/axe/hammer ABI can surface
## in production loadouts. Older save IDs are left intact in persistence but
## cannot become executable or occupy an ability slot. TEST_* is isolated
## developer fixture naming, not a numbered game ABI.
static func is_retired_numbered_abi(ability_id: String) -> bool:
	if not ability_id.begins_with("ABI"):
		return false
	var suffix := ability_id.substr(3)
	if not suffix.is_valid_int():
		return false
	var index := int(suffix)
	return not (
		(index>=301 and index<=308)
		or (index>=401 and index<=408)
		or (index>=501 and index<=508)
		or (index>=601 and index<=606)
	)

static func definition(abilities: Dictionary, ability_id: String) -> Dictionary:
	var value = abilities.get(ability_id, {})
	return value if value is Dictionary else {}

static func assigned_abilities(loadouts: Dictionary, combatant_id: String) -> Array:
	var value = loadouts.get(combatant_id, [])
	return value if value is Array else []
