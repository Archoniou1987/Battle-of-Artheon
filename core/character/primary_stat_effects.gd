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
	for stat in effects:
		var amount := float(stats.get(stat, 0))
		var modifiers: Dictionary = effects[stat]
		for key in modifiers:
			result[key] = float(result.get(key, 0.0)) + amount * float(modifiers[key])
	return result

## Rating effectiveness at a given level, interpolated between editable anchors.
## This is the raw chance contribution, before combat caps and opposition.
static func rating_to_percent(rating: float, level: int, config: Dictionary = {}) -> float:
	var source := config if not config.is_empty() else load_config()
	var curve: Dictionary = source.get("rating_curve", {})
	var reference := float(curve.get("reference_rating", 300))
	var anchors: Array = curve.get("anchors", [])
	if reference <= 0.0 or anchors.is_empty():
		return 0.0
	var current_level := clampi(level, int(anchors[0]["level"]), int(anchors[-1]["level"]))
	var efficiency := float(anchors[-1]["percent"])
	for i in range(anchors.size() - 1):
		var left: Dictionary = anchors[i]
		var right: Dictionary = anchors[i + 1]
		var first := int(left["level"])
		var last := int(right["level"])
		if current_level <= last:
			var t := float(current_level - first) / float(maxi(1, last - first))
			efficiency = lerpf(float(left["percent"]), float(right["percent"]), t)
			break
	return rating / reference * efficiency

## ABI/EFF direct percentage points are added separately, without level scaling.
static func effective_chance(rating: float, level: int, direct_percent: float = 0.0, config: Dictionary = {}) -> float:
	return rating_to_percent(rating, level, config) + direct_percent
