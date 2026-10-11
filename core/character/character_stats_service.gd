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
		result[key] = float(result.get(key, 0.0)) + float(direct_effects[key])
	var weapon_id: Variant = character.equipment.get_equipped_instance_id("main_hand")
	if weapon_id == null:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(UNARMED_PATH)) if FileAccess.file_exists(UNARMED_PATH) else {}
		if raw is Dictionary:
			var unarmed: Dictionary = raw.get("unarmed", {})
			var bonus := float(result.get("physical_damage_flat", 0.0))
			var low := float(unarmed.get("min_damage", 2)) + bonus
			var high := float(unarmed.get("max_damage", 4)) + bonus
			result["main_hand_min_damage"] = low
			result["main_hand_max_damage"] = high
			result["main_hand_damage_type"] = String(unarmed.get("damage_type", "blunt"))
	elif repository != null and active.has(String(weapon_id)):
		var weapon: Dictionary = repository.get_item(String(weapon_id))
		if weapon.has("min_damage") and weapon.has("max_damage"):
			var bonus := float(result.get("physical_damage_flat", 0.0))
			result["main_hand_min_damage"] = float(weapon["min_damage"]) + bonus
			result["main_hand_max_damage"] = float(weapon["max_damage"]) + bonus
			result["main_hand_damage_type"] = String(weapon.get("damage_type", ""))
	if result.has("main_hand_min_damage") and result.has("main_hand_max_damage"):
		result["main_hand_damage"] = [result["main_hand_min_damage"], result["main_hand_max_damage"]]
	for key in config.get("rating_stats", []):
		result[String(key) + "_percent"] = PrimaryStatEffects.rating_to_percent(float(result.get(key, 0.0)), character.progression.level, config)
	return result

static func rating_effect(snapshot_data: Dictionary, key: String) -> float:
	return float(snapshot_data.get(key + "_percent", 0.0))
