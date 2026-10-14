class_name RatingMatrix
extends RefCounted

const CONFIG_PATH := "res://data/balance/rating_matrix.json"

static func to_percent(rating: Variant, level: Variant, config_path: String = CONFIG_PATH) -> float:
	if not FileAccess.file_exists(config_path):
		push_error("RatingMatrix: missing mandatory configuration: " + config_path)
		return NAN
	return evaluate(rating, level, JSON.parse_string(FileAccess.get_file_as_string(config_path)))

## Pure v1 validation and interpolation. Invalid inputs never become a zero bonus.
static func evaluate(rating: Variant, level: Variant, config: Variant) -> float:
	if not _number(rating) or not _number(level) or float(level) != floor(float(level)) or float(level) < 1 or float(level) > 100:
		push_error("RatingMatrix: invalid rating or level")
		return NAN
	if not config is Dictionary:
		push_error("RatingMatrix: invalid configuration")
		return NAN
	var expected := {"version":1, "reference_rating":100, "minimum_level":1, "maximum_level":100, "percent_at_level_1":20, "percent_at_level_100":2.5}
	for key in expected:
		if not config.has(key) or not _number(config[key]) or float(config[key]) != float(expected[key]):
			push_error("RatingMatrix: invalid v1 configuration: " + key)
			return NAN
	if config.get("interpolation") != "linear":
		push_error("RatingMatrix: unsupported interpolation")
		return NAN
	var fraction := (float(level) - 1.0) / 99.0
	return float(rating) / 100.0 * lerpf(20.0, 2.5, fraction)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
