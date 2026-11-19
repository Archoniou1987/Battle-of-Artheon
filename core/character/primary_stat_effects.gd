class_name PrimaryStatEffects
extends RefCounted

const CONFIG_PATH := "res://data/character/primary_stat_effects.json"

static func load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("Missing primary stat config: " + CONFIG_PATH)
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

## Return only configured primary-stat contributions, without inventing
## equipment, combat-runtime or unimplemented values.
static func calculate(stats: Dictionary, config: Dictionary = {}) -> Dictionary:
	var source := config if not config.is_empty() else load_config()
	var effects: Dictionary = source.get("effects", {})
	var result: Dictionary = {}
	if effects.size() != ParCalculationService.PRIMARY_IDS.size():
		push_error("Incomplete primary effect configuration")
		return {}
	for stat in effects:
		if not ParCalculationService.PRIMARY_IDS.has(stat) or not stats.has(stat) or not RatingMatrix._number(stats[stat]) or not effects[stat] is Dictionary:
			push_error("Invalid primary effect input: " + String(stat))
			return {}
		var amount := float(stats[stat])
		for key in effects[stat]:
			if not RatingMatrix._number(effects[stat][key]):
				push_error("Invalid primary effect coefficient: " + String(key))
				return {}
			result[key] = float(result.get(key, 0.0)) + amount * float(effects[stat][key])
	return result

## RatingMatrix v1 is the sole rating conversion owner.
## This is the raw chance contribution, before combat caps and opposition.
static func rating_to_percent(rating: float, level: int) -> float:
	return RatingMatrix.to_percent(rating, level)

## ABI/EFF direct percentage points are added separately, without level scaling.
static func effective_chance(rating: float, level: int, direct_percent: float = 0.0) -> float:
	return rating_to_percent(rating, level) + direct_percent
