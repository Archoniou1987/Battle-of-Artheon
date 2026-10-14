class_name ParCalculationService
extends RefCounted

## Single canonical PAR aggregation boundary.
## Phase 1: direct additive contributions only; derived PAR formulas are a separate phase.
## This service never converts PAR IDs into legacy stat names.
const REGISTRY_PATH := "res://data/parameters/par_registry.json"
const PRIMARY_IDS := ["PAR001", "PAR002", "PAR003", "PAR004", "PAR005", "PAR006"]

static func registry() -> Dictionary:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH))
	if not raw is Dictionary or not bool(raw.get("locked", false)):
		return {}
	var result := {}
	for entry in raw.get("parameters", []):
		if entry is Dictionary:
			result[String(entry.get("id", ""))] = entry.duplicate(true)
	return result

static func calculate(character: CharacterState, repository: ItemRepository, talent_par: Dictionary = {}, effect_par: Dictionary = {}) -> Dictionary:
	if character == null:
		return {}
	var definitions := registry()
	if definitions.is_empty():
		push_error("PAR registry unavailable")
		return {}
	var base := {}
	for index in range(PRIMARY_IDS.size()):
		base[PRIMARY_IDS[index]] = float(character.progression.base_stats.get(PRIMARY_IDS[index], 0))
	var equipment := {}
	if repository != null:
		var active := character.active_equipment_ids(repository)
		for instance_id in active:
			var item := repository.get_item(String(instance_id))
			if item.is_empty():
				continue
			_accumulate(equipment, item.get("par_stats", {}), definitions)
			_accumulate(equipment, item.get("par_bonuses", {}), definitions)
	var totals := {}
	var breakdown := {}
	for par_id in definitions:
		var parts := {
			"basic": float(base.get(par_id, 0)),
			"equipment": float(equipment.get(par_id, 0)),
			"talents": float(talent_par.get(par_id, 0)),
			"effects": float(effect_par.get(par_id, 0))
		}
		breakdown[par_id] = parts
		totals[par_id] = parts["basic"] + parts["equipment"] + parts["talents"] + parts["effects"]
	return {"totals": totals, "sources": breakdown}

static func _accumulate(target: Dictionary, incoming: Variant, definitions: Dictionary) -> void:
	if not incoming is Dictionary:
		return
	for raw_id in incoming:
		var par_id := String(raw_id)
		if not definitions.has(par_id):
			push_warning("Unknown PAR ignored: " + par_id)
			continue
		target[par_id] = float(target.get(par_id, 0)) + float(incoming[raw_id])
