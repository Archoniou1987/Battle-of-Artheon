class_name CharacterStatsService
extends RefCounted

## Authoritative character-stat snapshot for UI and gameplay consumers.
## Combat target-specific rolls and damage mitigation are not character stats.

static func snapshot(character: CharacterState, repository: ItemRepository = null, direct_effects: Dictionary = {}, par_snapshot: Dictionary = {}) -> Dictionary:
	if character == null:
		return {}
	var config := PrimaryStatEffects.load_config()
	if par_snapshot.is_empty():
		par_snapshot = ParCalculationService.calculate(character, repository)
	if par_snapshot.is_empty():
		return {}
	var primary: Dictionary = par_snapshot.get("totals", {})
	var result: Dictionary = par_snapshot.get("unmapped_derived", {}).duplicate(true)
	var definitions := ParCalculationService.registry()
	for par_id in primary:
		if ParCalculationService.PRIMARY_IDS.has(par_id):
			continue
		var definition: Dictionary = definitions.get(par_id, {})
		var source_key := String(definition.get("source_key", ""))
		if not source_key.is_empty():
			result[source_key] = primary[par_id]
	# These names have identical units/meaning; no rating-to-percentage conversion is guessed.
	result["armour_penetration_flat"] = primary["PAR125"]
	result["armour_penetration_percent"] = primary["PAR126"]
	for pair in [["shield_auto_block", "shield_auto_block_direct_pct"]]:
		result[pair[1]] = float(result.get(pair[1], 0)) + float(result.get(pair[0], 0))
	if repository != null:
		for id in character.active_equipment_ids(repository):
			var overlays: Variant = repository.get_item(String(id)).get("combat_stats", {})
			if not overlays is Dictionary:
				push_error("Invalid item direct-percent overlay")
				return {}
			for key in overlays:
				if String(key).ends_with("_direct_pct"):
					if not RatingMatrix._number(overlays[key]):
						push_error("Invalid item direct-percent value: " + String(key))
						return {}
					result[key] = float(result.get(key, 0)) + float(overlays[key])
	# Runtime effects are explicit semantic overlays; permanent item PAR was already added.
	for key in direct_effects:
		if not RatingMatrix._number(direct_effects[key]):
			push_error("Invalid direct effect overlay: " + String(key))
			return {}
		result[key] = float(result.get(key, 0.0)) + float(direct_effects[key])
	var ranges: Dictionary = par_snapshot["attack_ranges"]
	var bonus := float(result["physical_damage_flat"])
	for hand in ["main_hand", "off_hand"]:
		var range_id := "PAR050" if hand == "main_hand" else "PAR051"
		var damage: Dictionary = ranges[range_id]
		if damage.is_empty():
			result.erase(hand + "_damage")
			continue
		result[hand + "_min_damage"] = float(damage["min"]) + bonus
		result[hand + "_max_damage"] = float(damage["max"]) + bonus
		result[hand + "_damage_type"] = String(damage["type"])
		result[hand + "_damage"] = [result[hand + "_min_damage"], result[hand + "_max_damage"]]
	return convert_ratings(result, character.progression.level, config)

static func convert_ratings(values: Dictionary, level: int, config: Dictionary = {}) -> Dictionary:
	if config.is_empty():
		config = PrimaryStatEffects.load_config()
	if not config.get("rating_stats") is Array or config["rating_stats"].is_empty():
		push_error("Missing mandatory rating stat configuration")
		return {}
	for key in ParCombatContract.RATINGS.values():
		if not values.has(key) or not RatingMatrix._number(values[key]):
			push_error("Missing mandatory rating: " + String(key))
			return {}
	var result := values.duplicate(true)
	for key in config["rating_stats"]:
		var direct_key := String(key).trim_suffix("_rating") + "_direct_pct"
		if not result.has(key) and not result.has(direct_key):
			continue # Unimplemented rows remain absent; UI displays an em dash.
		var rating: Variant = result.get(key, 0.0) # Explicit direct-only overlays have no rating contribution.
		var direct: Variant = result.get(direct_key, 0.0)
		if not RatingMatrix._number(rating) or not RatingMatrix._number(direct):
			push_error("Invalid numeric rating or direct overlay: " + String(key))
			return {}
		var percent := RatingMatrix.to_percent(rating, level)
		if not is_finite(percent):
			return {}
		result[String(key) + "_percent"] = percent + float(direct)
	return result

static func rating_effect(snapshot_data: Dictionary, key: String) -> float:
	return float(snapshot_data.get(key + "_percent", 0.0))

## Explicit adapter: the combat runtime receives a detached snapshot, never UI labels.
## Existing combat code can keep its own target-specific hit and mitigation rolls.
static func combat_stats(character: CharacterState, repository: ItemRepository = null, direct_effects: Dictionary = {}, par_snapshot: Dictionary = {}) -> Dictionary:
	var totals := snapshot(character, repository, direct_effects, par_snapshot)
	if totals.is_empty():
		return {}
	var combat := totals.duplicate(true)
	var profiles: Array[Dictionary] = []
	var active := character.active_equipment_ids(repository) if repository != null else {}
	for hand in ["main_hand", "off_hand"]:
		if not totals.has(hand + "_damage"):
			continue
		var damage_range: Array = totals[hand + "_damage"]
		var id: Variant = character.equipment.get_equipped_instance_id(hand)
		var unarmed := id == null or not active.has(str(id))
		profiles.append({"slot":hand, "is_unarmed":unarmed, "instance_id":"unarmed_main_hand" if unarmed else str(id), "damage_min":float(damage_range[0]), "damage_max":float(damage_range[1]), "damage_type":String(totals[hand + "_damage_type"])})
	combat["weapon_profiles"] = profiles
	combat.erase("main_hand_damage")
	combat.erase("main_hand_min_damage")
	combat.erase("main_hand_max_damage")
	combat.erase("main_hand_damage_type")
	return combat
