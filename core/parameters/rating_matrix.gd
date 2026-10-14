class_name RatingMatrix
extends RefCounted

const CONFIG_PATH := "res://data/balance/rating_matrix.json"

static func to_percent(rating: float, level: int) -> float:
	if not is_finite(rating) or level < 1 or level > 100:
		push_error("RatingMatrix: invalid rating or level")
		return NAN
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("RatingMatrix: missing mandatory configuration")
		return NAN
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not raw is Dictionary:
		push_error("RatingMatrix: invalid configuration")
		return NAN
	for key in ["reference_rating", "minimum_level", "maximum_level", "percent_at_level_1", "percent_at_level_100"]:
		if not raw.has(key) or not (raw[key] is int or raw[key] is float):
			push_error("RatingMatrix: missing or invalid " + key)
			return NAN
	var reference := float(raw["reference_rating"])
	var min_level := int(raw["minimum_level"])
	var max_level := int(raw["maximum_level"])
	if reference <= 0 or min_level != 1 or max_level != 100 or String(raw.get("interpolation", "")) != "linear":
		push_error("RatingMatrix: unsupported scale configuration")
		return NAN
	var fraction := float(level - min_level) / float(max_level - min_level)
	return rating / reference * lerpf(float(raw["percent_at_level_1"]), float(raw["percent_at_level_100"]), fraction)
