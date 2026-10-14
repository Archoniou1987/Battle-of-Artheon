class_name CharacterStatsService
extends RefCounted

## Authoritative character-stat snapshot for UI and gameplay consumers.
## Combat target-specific rolls and damage mitigation are not character stats.
const UNARMED_PATH := "res://data/combat/unarmed_attack.json"

static func snapshot(character: CharacterState, repository: ItemRepository = null, direct_effects: Dictionary = {}) -> Dictionary:
	if character == null:
		return {}
	var config := PrimaryStatEffects.load_config()
	var par_snapshot := ParCalculationService.calculate(character, repository)
	var primary: Dictionary = par_snapshot.get("totals", {})
	var result := PrimaryStatEffects.calculate(primary, config)
	var active: Dictionary = character.active_equipment_ids(repository) if repository != null else {}
	# PAR totals are owned by ParCalculationService; never add item bonuses twice.
	for key in direct_effects:
		result[key] = float(result.get(key, 0.0)) + float(direct_effects[key])
	var weapon_id: Variant = character.equipment.get_equipped_instance_id("main_hand")
	var weapon: Dictionary = {}
	if weapon_id != null and repository != null and active.has(String(weapon_id)):
		weapon = repository.get_item(String(weapon_id))
	var damage: Dictionary = weapon.get("damage", {}) if weapon.get("damage", {}) is Dictionary else {}
	var bonus := float(result.get("physical_damage_flat", 0.0))
	if not damage.is_empty():
		result["main_hand_min_damage"] = float(damage.get("min", 0.0)) + bonus
		result["main_hand_max_damage"] = float(damage.get("max", 0.0)) + bonus
		result["main_hand_damage_type"] = String(damage.get("type", "slashing"))
	else:
		# Empty or inactive main-hand equipment grants no weapon damage.
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNARMED_PATH)) if FileAccess.file_exists(UNARMED_PATH) else {}
		if raw is Dictionary:
			var unarmed: Dictionary = raw.get("unarmed", {})
			result["main_hand_min_damage"] = float(unarmed.get("min_damage", 2)) + bonus
			result["main_hand_max_damage"] = float(unarmed.get("max_damage", 4)) + bonus
			result["main_hand_damage_type"] = String(unarmed.get("damage_type", "blunt"))
	if result.has("main_hand_min_damage") and result.has("main_hand_max_damage"):
		result["main_hand_damage"] = [result["main_hand_min_damage"], result["main_hand_max_damage"]]
	for key in config.get("rating_stats", []):
		var direct_key := String(key).trim_suffix("_rating") + "_direct_pct"
		var direct_percent := float(result.get(direct_key, 0.0))
		result[String(key) + "_percent"] = PrimaryStatEffects.effective_chance(float(result.get(key, 0.0)), character.progression.level, direct_percent, config)
	return result

static func rating_effect(snapshot_data: Dictionary, key: String) -> float:
	return float(snapshot_data.get(key + "_percent", 0.0))

## Explicit adapter: the combat runtime receives a detached snapshot, never UI labels.
## Existing combat code can keep its own target-specific hit and mitigation rolls.
static func combat_stats(character: CharacterState, repository: ItemRepository = null, direct_effects: Dictionary = {}) -> Dictionary:
	var totals := snapshot(character, repository, direct_effects)
	if totals.is_empty():
		return {}
	var combat := totals.duplicate(true)
	if totals.has("main_hand_damage"):
		var damage_range: Array = totals["main_hand_damage"]
		combat["weapon_profiles"] = [{
			"damage_min":float(damage_range[0]),
			"damage_max":float(damage_range[1]),
			"damage_type":String(totals.get("main_hand_damage_type", "blunt"))
		}]
	combat.erase("main_hand_damage")
	combat.erase("main_hand_min_damage")
	combat.erase("main_hand_max_damage")
	combat.erase("main_hand_damage_type")
	return combat
