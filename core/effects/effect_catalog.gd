class_name EffectCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/effects/catalog.json"

static func load_json(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing canonical EFF catalog: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Invalid canonical EFF catalog: " + path)
		return {}
	return parsed

static func definition(effects: Dictionary, effect_id: String) -> Dictionary:
	var value: Variant = effects.get(effect_id, {})
	return value if value is Dictionary else {}

## EFF owns duration rules; ABI only provides application context.
static func application_duration_rounds(definition: Dictionary, context: Dictionary = {}) -> int:
	var policy: Variant = definition.get("duration_from_charges", null)
	if not policy is Dictionary:
		return int(definition.get("duration_rounds", 1))
	var rule: Dictionary = policy
	var field := String(rule.get("charge_field", ""))
	var charges := maxi(0, int(context.get(field, 0)))
	var divisor := maxi(1, int(rule.get("charges_per_round", 1)))
	var low := int(rule.get("minimum_rounds", 0))
	var high := maxi(low, int(rule.get("maximum_rounds", 10)))
	return clampi(roundi(float(charges) / float(divisor)), low, high)
