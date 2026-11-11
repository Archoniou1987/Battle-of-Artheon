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

## Stack caps belong to EFF; applied snapshots take precedence.
static var _canonical_stack_definitions: Dictionary = {}

static func stack_cap(effect_id: String, applied_definition: Dictionary = {}) -> int:
	var source: Dictionary = applied_definition
	if not source.has("max_stacks"):
		if _canonical_stack_definitions.is_empty():
			_canonical_stack_definitions = load_json()
		source = definition(_canonical_stack_definitions,effect_id)
	return maxi(1,int(source.get("max_stacks",1)))

## EFF-defined contextual magnitudes and level/snapshot scaling.
## COMBAT supplies the application context and target's active records;
## it never owns the magnitude formulas for any individual EFF.
static func application_modifiers(definition: Dictionary, context: Dictionary = {}) -> Dictionary:
	var resolved := definition
	var raw: Variant = definition.get("contextual_modifier",null)
	if raw is Dictionary:
		var rule: Dictionary = raw
		var input_field := String(rule.get("input_field",""))
		var legacy_field := String(rule.get("legacy_value_field",""))
		var value := 0.0
		if context.has(input_field):
			value = float(context[input_field]) * float(rule.get("per_unit",1.0))
		elif context.has(legacy_field):
			value = float(context[legacy_field])
		var lower := float(rule.get("minimum",0.0))
		var upper := maxf(lower,float(rule.get("maximum",100.0)))
		value = clampf(value,lower,upper)
		resolved = resolved.duplicate(true)
		for field in Array(rule.get("fields",[])):
			resolved[String(field)] = value
	var scaling: Variant = definition.get("application_scaling",null)
	if scaling is Dictionary:
		var rule: Dictionary = scaling
		var factor := 1.0
		if bool(rule.get("use_level",false)):
			var level_field := String(rule.get("level_field","effect_level"))
			var ceiling := maxi(1,int(definition.get("max_effect_level",1)))
			factor *= float(clampi(int(context.get(level_field,1)),1,ceiling))
		if bool(rule.get("use_snapshot_stacks",false)):
			factor *= float(maxi(0,int(context.get("effect_snapshot_stacks",0))))
		resolved = resolved.duplicate(true)
		for field in Array(rule.get("fields",[])):
			var key := String(field)
			resolved[key] = float(definition.get(key,0.0))*factor
	return resolved

## The named source is EFF-owned (snapshot_from), never embedded in COMBAT.
## Match the first still-present active record, preserving historical casts.
static func application_snapshot_stacks(definition: Dictionary, active_effects: Array) -> int:
	var source_id := String(definition.get("snapshot_from",""))
	if source_id.is_empty():
		return 0
	for raw in active_effects:
		if not raw is Dictionary:
			continue
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == source_id and int(record.get("remaining_rounds",0))>0:
			return int(record.get("stacks",0))
	return 0

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
