class_name CharacterStatsService
extends RefCounted

## Authoritative character-stat snapshot for UI and gameplay consumers.
## Combat target-specific rolls and damage mitigation are not character stats.
const UNARMED_PATH := "res://data/combat/unarmed_attack.json"

static func snapshot(character: CharacterState, repository: ItemRepository = null, direct_effects: Dictionary = {}) -> Dictionary:
	if character == null:
		return {}
	var config := PrimaryStatEffects.load_config()
	var primary := character.progression.base_stats.duplicate(true)
	if repository != null:
		primary = character.effective_stats(repository)
	var result := PrimaryStatEffects.calculate(primary, config)
	var active: Dictionary = {}
	if repository != null:
		active = character.active_equipment_ids(repository)
		for instance_id in active:
			var item: Dictionary = repository.get_item(String(instance_id))
			for field in ["guaranteed_stats", "bonuses"]:
				var values: Variant = item.get(field, {})
				if not values is Dictionary:
					continue
				for key in values:
					if not primary.has(key):
						result[key] = float(result.get(key, 0.0)) + float(values[key])
	for key in direct_effects:
		if not String(key).ends_with("_direct_pct"):
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
		var direct_key := String(key) + "_direct_pct"
		result[String(key) + "_percent"] = PrimaryStatEffects.effective_chance(float(result.get(key, 0.0)), character.progression.level, float(direct_effects.get(direct_key, 0.0)), config)
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
		combat["main_hand_damage_min"] = float(damage_range[0])
		combat["main_hand_damage_max"] = float(damage_range[1])
		combat["main_hand_damage"] = (float(damage_range[0]) + float(damage_range[1])) / 2.0
	return combat
