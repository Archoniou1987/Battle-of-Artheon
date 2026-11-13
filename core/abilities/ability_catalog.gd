class_name AbilityCatalog
extends RefCounted

const CANONICAL_PATH := "res://data/abilities/catalog.json"
static var _canonical_definitions: Dictionary = {}

## The ABI catalog owns its references to EFF. Existing effect components
## already provide primary links; effect_refs names supplementary roles.
static func effect_id(ability_id: String, role: String = "primary") -> String:
	if _canonical_definitions.is_empty():
		_canonical_definitions = load_json(CANONICAL_PATH)
	var ability := definition(_canonical_definitions, ability_id)
	if role == "primary":
		for raw in ability.get("components", []):
			if raw is Dictionary and String(raw.get("kind", "")) == "effect":
				return String(raw.get("effect_id", ""))
		return String(ability.get("sword_eff_id", ""))
	var refs: Variant = ability.get("effect_refs", {})
	return String(refs.get(role, "")) if refs is Dictionary else ""


## ABI owns ability-specific values. The committed action snapshot wins;
## old/test actions without a field fall back to the canonical ABI entry.
static func number(ability_id: String, field: String, snapshot: Dictionary = {}) -> float:
	if snapshot.has(field):
		return float(snapshot[field])
	if _canonical_definitions.is_empty():
		_canonical_definitions = load_json(CANONICAL_PATH)
	return float(definition(_canonical_definitions,ability_id).get(field,0.0))


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
		or (index>=401 and index<=412)
		or (index>=501 and index<=508)
		or (index>=601 and index<=606)
		or (index>=701 and index<=704)
	)

## A stale numbered ABI can remain in a save/checkpoint, but may never
## reach the battle scheduler. LAB_* and TEST_* are isolated developer IDs.
## Reject malformed ABI aliases (e.g. ABI0301) as well as retired numbers.
static func is_executable_id(ability_id: String) -> bool:
	if not ability_id.begins_with("ABI"):
		return true
	var suffix := ability_id.substr(3)
	if not suffix.is_valid_int():
		return false
	return ability_id == "ABI%d" % int(suffix) and not is_retired_numbered_abi(ability_id)

static func definition(abilities: Dictionary, ability_id: String) -> Dictionary:
	if not is_executable_id(ability_id):
		return {}
	var value = abilities.get(ability_id, {})
	return value if value is Dictionary else {}

static func assigned_abilities(loadouts: Dictionary, combatant_id: String) -> Array:
	var value = loadouts.get(combatant_id, [])
	if not value is Array:
		return []
	# Return a filtered view, never mutate stored saves or loadouts.
	var active: Array = []
	for raw_id in value:
		var ability_id := String(raw_id)
		if is_executable_id(ability_id):
			active.append(ability_id)
	return active
