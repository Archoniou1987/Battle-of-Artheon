class_name RatingMatrix
extends RefCounted

const CONFIG_PATH := "res://data/balance/rating_matrix.json"
## JSON is loaded once per runtime; the imported balance snapshot changes on restart.
static var _default_config: Dictionary = {}

static func to_percent(rating: Variant, level: Variant, config_path: String = CONFIG_PATH) -> float:
	if config_path == CONFIG_PATH and not _default_config.is_empty():
		return evaluate(rating, level, _default_config)
	if not FileAccess.file_exists(config_path):
		push_error("RatingMatrix: missing mandatory configuration: " + config_path)
		return NAN
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if config_path == CONFIG_PATH and config is Dictionary:
		_default_config = config.duplicate(true)
	return evaluate(rating, level, config)

## Single rating conversion owner. Numeric anchors come only from rating_matrix.json.
## evaluate() accepts explicit config for validation and deterministic tests.
static func evaluate(rating: Variant, level: Variant, config: Variant) -> float:
	if not _number(rating) or not _number(level) or float(level) != floor(float(level)):
		push_error("RatingMatrix: invalid rating or level")
		return NAN
	if not config is Dictionary:
		push_error("RatingMatrix: invalid configuration")
		return NAN
	var fields := ["version", "reference_rating", "minimum_level", "maximum_level", "percent_at_level_1", "percent_at_level_100"]
	for key in fields:
		if not config.has(key) or not _number(config[key]):
			push_error("RatingMatrix: missing or invalid config field: " + key)
			return NAN
	if int(config["version"]) != 2 or float(config["version"]) != 2.0:
		push_error("RatingMatrix: unsupported config version")
		return NAN
	var min_level := float(config["minimum_level"])
	var max_level := float(config["maximum_level"])
	var reference_rating := float(config["reference_rating"])
	var start_pct := float(config["percent_at_level_1"])
	var end_pct := float(config["percent_at_level_100"])
	if min_level < 1.0 or max_level <= min_level or reference_rating <= 0.0 or start_pct < 0.0 or end_pct < 0.0:
		push_error("RatingMatrix: invalid bounds")
		return NAN
	if float(level) < min_level or float(level) > max_level:
		push_error("RatingMatrix: level outside configured range")
		return NAN
	if config.get("interpolation") != "linear":
		push_error("RatingMatrix: unsupported interpolation")
		return NAN
	var progress := (float(level)-min_level)/(max_level-min_level)
	return float(rating)/reference_rating*lerpf(start_pct,end_pct,progress)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
