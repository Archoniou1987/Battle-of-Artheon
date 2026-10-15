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
	var validated_overlay := {}
	if not _accumulate(validated_overlay, talent_par, definitions) or not _accumulate(validated_overlay, effect_par, definitions):
		return {}
	var base := {"PAR073": 2.0, "PAR014": 5.0}
	for index in range(PRIMARY_IDS.size()):
		var primary_id: String = PRIMARY_IDS[index]
		if not character.progression.base_stats.has(primary_id) or not (character.progression.base_stats[primary_id] is int or character.progression.base_stats[primary_id] is float) or not is_finite(float(character.progression.base_stats[primary_id])):
			push_error("Missing mandatory primary parameter: " + primary_id)
			return {}
		base[primary_id] = float(character.progression.base_stats[primary_id])
	for key in character.progression.base_stats:
		if not PRIMARY_IDS.has(key):
			push_error("Unexpected primary identifier: " + String(key))
			return {}
	var equipment := {}
	var active_weapon_count := 0
	var attack_ranges := {"PAR050": {}, "PAR051": {}}
	if repository == null:
		for id in character.equipment.slots.values():
			if id != null:
				push_error("Equipped item requires a repository for canonical PAR calculation")
				return {}
	else:
		for id in character.equipment.slots.values():
			if id != null and repository.get_item(String(id)).is_empty():
				push_error("Equipped item cannot be resolved: " + String(id))
				return {}
		var active := character.active_equipment_ids(repository)
		for instance_id in active:
			var item := repository.get_item(String(instance_id))
			if item.is_empty():
				push_error("PAR calculation: active item unavailable: " + String(instance_id))
				return {}
			var damage: Variant = item.get("damage", {})
			var declared_weapon := String(item.get("type", "")) == "weapon" or String(item.get("item_type", "")) == "weapon" or not String(item.get("weapon_class", "")).is_empty()
			if declared_weapon and (not damage is Dictionary or damage.is_empty()):
				push_error("Declared weapon missing mandatory damage range: " + String(instance_id))
				return {}
			if damage is Dictionary and not damage.is_empty():
				active_weapon_count += 1
				# Equipment owns placement; a template's preferred slot is not authoritative.
				var in_main := str(character.equipment.get_equipped_instance_id("main_hand")) == String(instance_id)
				var in_off := str(character.equipment.get_equipped_instance_id("off_hand")) == String(instance_id)
				if not in_main and not in_off:
					push_error("Weapon equipped outside a hand: " + String(instance_id))
					return {}
				var target_par := "PAR050" if in_main else "PAR051"
				if not valid_damage_range(damage):
					push_error("Invalid mandatory weapon range: " + target_par)
					return {}
				attack_ranges[target_par] = damage.duplicate(true)
				if float(Dictionary(item.get("par_stats", {})).get("PAR057", 0)) != 1.0 or Dictionary(item.get("par_bonuses", {})).has("PAR057"):
					push_error("Each equipped weapon must contribute exactly PAR057 = 1: " + String(instance_id))
					return {}
			elif Dictionary(item.get("par_stats", {})).has("PAR057") or Dictionary(item.get("par_bonuses", {})).has("PAR057"):
				push_error("Non-weapon cannot contribute PAR057: " + String(instance_id))
				return {}
			if not _accumulate(equipment, item.get("par_stats", {}), definitions) or not _accumulate(equipment, item.get("par_bonuses", {}), definitions):
				return {}
			# Explicit structural armour data remains supported, accumulated once here.
			for zone_index in range(EquipmentBuilder.HIT_ZONES.size()):
				var zone: String = EquipmentBuilder.HIT_ZONES[zone_index]
				var zone_ids := {"head":"PAR100", "chest":"PAR101", "arms":"PAR102", "waist":"PAR103", "legs":"PAR104"}
				var armour := float(Dictionary(item.get("armour_by_zone", {})).get(zone, 0)) + float(item.get("armour_all_zones_all_physical", 0))
				var armour_id: String = zone_ids[zone]
				equipment[armour_id] = float(equipment.get(armour_id, 0)) + armour
	var main_unarmed: bool = Dictionary(attack_ranges["PAR050"]).is_empty()
	if main_unarmed:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/unarmed_attack.json"))
		if not parsed is Dictionary or not parsed.get("unarmed") is Dictionary:
			push_error("Missing mandatory unarmed attack configuration")
			return {}
		var unarmed: Dictionary = parsed["unarmed"]
		if not unarmed.has("min_damage") or not unarmed.has("max_damage") or not unarmed.has("damage_type"):
			push_error("Incomplete mandatory unarmed attack configuration")
			return {}
		var fist_range := {"min": unarmed["min_damage"], "max": unarmed["max_damage"], "type": unarmed["damage_type"]}
		if not valid_damage_range(fist_range):
			push_error("Invalid mandatory unarmed damage range")
			return {}
		attack_ranges["PAR050"] = fist_range
	if talent_par.has("PAR057") or effect_par.has("PAR057"):
		push_error("PAR057 is owned exclusively by equipped weapons/unarmed configuration")
		return {}
	base["PAR057"] = 1.0 if main_unarmed else 0.0
	# Primary-derived formulas live here; source_key resolves only exact PAR equivalents.
	var derived := {}
	var unmapped := {}
	if not FileAccess.file_exists(DERIVED_CONFIG_PATH):
		push_error("Missing mandatory PAR derivation config")
		return {}
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(DERIVED_CONFIG_PATH))
	if not config is Dictionary or not config.get("effects") is Dictionary:
		push_error("Invalid mandatory PAR derivation config")
		return {}
	var formulas: Dictionary = config["effects"]
	if formulas.size() != PRIMARY_IDS.size():
		push_error("Incomplete primary PAR derivation config")
		return {}
	var primary_inputs := {}
	for primary_id in PRIMARY_IDS:
		primary_inputs[primary_id] = float(base[primary_id]) + float(equipment.get(primary_id, 0.0)) + float(talent_par.get(primary_id, 0.0)) + float(effect_par.get(primary_id, 0.0))
	derived = PrimaryStatEffects.calculate(primary_inputs, config)
	if derived.is_empty():
		return {}
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
			push_error("Derived stat has no canonical PAR: " + String(source_key))
			return {}
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

static func _accumulate(target: Dictionary, incoming: Variant, definitions: Dictionary) -> bool:
	if not incoming is Dictionary:
		push_error("PAR contribution must be a dictionary")
		return false
	for raw_id in incoming:
		var par_id := String(raw_id)
		if not definitions.has(par_id):
			push_error("Unknown locked PAR: " + par_id)
			return false
		if not (incoming[raw_id] is int or incoming[raw_id] is float) or not is_finite(float(incoming[raw_id])):
			push_error("Invalid numeric PAR contribution: " + par_id)
			return false
		target[par_id] = float(target.get(par_id, 0)) + float(incoming[raw_id])
	return true

static func valid_damage_range(value: Variant) -> bool:
	if not value is Dictionary or not value.has("min") or not value.has("max") or not value.has("type"):
		return false
	if not (value.min is int or value.min is float) or not (value.max is int or value.max is float):
		return false
	return is_finite(float(value.min)) and is_finite(float(value.max)) and float(value.min) >= 0 and float(value.max) >= float(value.min) and (EquipmentBuilder.PHYSICAL_TYPES.has(String(value.type)) or CombatDamagePayload.is_magic_damage_type(String(value.type)))
