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
	for pair in [["shield_auto_block", "shield_auto_block_direct_pct"], ["counterattack", "counterattack_direct_pct"]]:
		result[pair[1]] = float(result.get(pair[1], 0)) + float(result.get(pair[0], 0))
	# Runtime effects are explicit semantic overlays; permanent item PAR was already added.
	for key in direct_effects:
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
	for key in config.get("rating_stats", []):
		var direct_key := String(key).trim_suffix("_rating") + "_direct_pct"
		var direct_percent := float(result.get(direct_key, 0.0))
		result[String(key) + "_percent"] = PrimaryStatEffects.effective_chance(float(result.get(key, 0.0)), character.progression.level, direct_percent, config)
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
	if totals.has("main_hand_damage"):
		var damage_range: Array = totals["main_hand_damage"]
		combat["weapon_profiles"] = [{
			"slot":"main_hand", "is_unarmed":true,
			"damage_min":float(damage_range[0]),
			"damage_max":float(damage_range[1]),
			"damage_type":String(totals.get("main_hand_damage_type", "blunt"))
		}]
	combat.erase("main_hand_damage")
	combat.erase("main_hand_min_damage")
	combat.erase("main_hand_max_damage")
	combat.erase("main_hand_damage_type")
	return combat
