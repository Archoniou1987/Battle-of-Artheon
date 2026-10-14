class_name ParCalculationService
extends RefCounted

## Single canonical PAR aggregation boundary.
## Phase 1: direct additive contributions only; derived PAR formulas are a separate phase.
## This service never converts PAR IDs into legacy stat names.
const REGISTRY_PATH := "res://data/parameters/par_registry.json"
const DERIVED_CONFIG_PATH := "res://data/character/primary_stat_effects.json"
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
	var base := {"PAR073": 2.0}
	for index in range(PRIMARY_IDS.size()):
		base[PRIMARY_IDS[index]] = float(character.progression.base_stats.get(PRIMARY_IDS[index], 0))
	var equipment := {}
	var active_weapon_count := 0
	var attack_ranges := {"PAR050": {}, "PAR051": {}}
	if repository != null:
		var active := character.active_equipment_ids(repository)
		for instance_id in active:
			var item := repository.get_item(String(instance_id))
			if item.is_empty():
				continue
			# Each active weapon contributes one attack; shields do not.
			# Deduplicated active IDs prevent two-handed items counting twice.
			var damage: Variant = item.get("damage", {})
			if damage is Dictionary and not damage.is_empty():
				active_weapon_count += 1
				var target_par := "PAR051" if String(item.get("slot", "")) == "off_hand" else "PAR050"
				attack_ranges[target_par] = {"min": float(damage.get("min", 0.0)), "max": float(damage.get("max", 0.0)), "type": String(damage.get("type", "blunt"))}
			_accumulate(equipment, item.get("par_stats", {}), definitions)
			_accumulate(equipment, item.get("par_bonuses", {}), definitions)
	# Unarmed fallback counts as the sole main-hand attack.
	# PAR057 is derived from active weapon count, not item bonuses.
	base["PAR057"] = 1.0 if active_weapon_count == 0 else 0.0
	# Primary-derived formulas live here; source_key resolves only exact PAR equivalents.
	var derived := {}
	var unmapped := {}
	if FileAccess.file_exists(DERIVED_CONFIG_PATH):
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(DERIVED_CONFIG_PATH))
		if config is Dictionary:
			var formulas: Dictionary = config.get("effects", {})
			for primary_id in formulas:
				var modifiers: Variant = formulas[primary_id]
				if not modifiers is Dictionary:
					continue
				var input_value := float(base.get(primary_id, 0.0)) + float(equipment.get(primary_id, 0.0)) + float(talent_par.get(primary_id, 0.0)) + float(effect_par.get(primary_id, 0.0))
				for output_key in modifiers:
					derived[output_key] = float(derived.get(output_key, 0.0)) + input_value * float(modifiers[output_key])
	var source_to_id := {}
	for par_id in definitions:
		var source_key := String(definitions[par_id].get("source_key", ""))
		if not source_key.is_empty():
			source_to_id[source_key] = par_id
	for source_key in derived:
		if source_to_id.has(source_key):
			var target_id: String = source_to_id[source_key]
			base[target_id] = float(base.get(target_id, 0.0)) + float(derived[source_key])
		else:
			unmapped[source_key] = derived[source_key]
	# Do not let arbitrary item bonuses duplicate the weapon-count rule.
	if active_weapon_count > 0 and int(equipment.get("PAR057", 0)) != active_weapon_count:
		push_error("Each equipped weapon must contribute PAR057 = 1")
	if active_weapon_count < 2:
		attack_ranges["PAR051"] = {}
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
	return {"totals": totals, "sources": breakdown, "attack_ranges": attack_ranges, "unmapped_derived": unmapped}

static func _accumulate(target: Dictionary, incoming: Variant, definitions: Dictionary) -> void:
	if not incoming is Dictionary:
		return
	for raw_id in incoming:
		var par_id := String(raw_id)
		if not definitions.has(par_id):
			push_warning("Unknown PAR ignored: " + par_id)
			continue
		target[par_id] = float(target.get(par_id, 0)) + float(incoming[raw_id])
