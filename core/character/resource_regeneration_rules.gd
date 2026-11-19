class_name ResourceRegenerationRules
extends RefCounted

## Single configured arithmetic: 1 round in combat = 1 ten-second mana interval.
const PATH := "res://data/balance/resource_regeneration.json"

static var _cache: Dictionary = {}

static func config() -> Dictionary:
	if _cache.is_empty():
		if not FileAccess.file_exists(PATH):
			push_error("Missing resource regeneration config")
			return {}
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not raw is Dictionary or int(raw.get("version", 0)) != 1 or float(raw.get("interval_seconds", 0)) <= 0.0:
			push_error("Invalid resource regeneration config")
			return {}
		_cache = raw
	return _cache

static func interval_seconds() -> float:
	var cfg := config()
	return float(cfg.get("interval_seconds", NAN)) if not cfg.is_empty() else NAN

static func hp_per_interval(max_hp: int, bonus_percent_per_minute: float) -> float:
	var cfg := config()
	if cfg.is_empty():
		return NAN
	var rate := float(cfg.get("base_hp_percent_per_minute", NAN)) + bonus_percent_per_minute
	if not is_finite(rate):
		return NAN
	return maxf(0.0, rate) * float(max_hp) / 100.0 * interval_seconds() / 60.0

static func mana_per_interval(bonus_mana: float) -> float:
	var cfg := config()
	if cfg.is_empty():
		return NAN
	var rate := float(cfg.get("base_mana_per_interval", NAN)) + bonus_mana
	return maxf(0.0, rate) if is_finite(rate) else NAN
