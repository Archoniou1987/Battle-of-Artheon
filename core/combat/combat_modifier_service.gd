class_name CombatModifierService
extends RefCounted

## Runtime overlay shared by ABI, EFF and (later) TRA.
## It never mutates the persistent character or its base combat stats.
static func active_effects(combatant: CombatantState, round_number: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in combatant.active_effects:
		if not raw is Dictionary:
			continue
		var record: Dictionary = raw
		if round_number < int(record.get("start_round", 999999)) or int(record.get("remaining_rounds", 0)) <= 0:
			continue
		result.append(record)
	return result

## TRA is an optional runtime dictionary of direct modifiers on combat_stats.
## Persistent talent ownership and unlock rules are handled separately.
static func trait_modifiers(combatant: CombatantState) -> Dictionary:
	var raw: Variant = combatant.combat_stats.get("trait_modifiers", {})
	return raw if raw is Dictionary else {}

static func flat_bonus(combatant: CombatantState, key: String, round_number: int) -> float:
	var total := 0.0
	for record in active_effects(combatant, round_number):
		var definition: Dictionary = record.get("definition", {})
		total += float(definition.get(key, 0.0))
	return total

static func modifier(combatant: CombatantState, key: String, round_number: int) -> float:
	return float(trait_modifiers(combatant).get(key, 0.0)) + flat_bonus(combatant, key, round_number)

static func flag(combatant: CombatantState, key: String, round_number: int) -> bool:
	if bool(trait_modifiers(combatant).get(key, false)):
		return true
	for record in active_effects(combatant, round_number):
		var definition: Dictionary = record.get("definition", {})
		if bool(definition.get(key, false)):
			return true
	return false

static func effective_stat(combatant: CombatantState, key: String, round_number: int) -> float:
	return float(combatant.combat_stats.get(key, 0.0)) + modifier(combatant, key, round_number)

## Rating conversion is owned by the canonical character stats service.
## Direct percentage-point overlays are never level-scaled.
static func effective_percent(combatant: CombatantState, key: String, round_number: int) -> float:
	var direct_key := key.trim_suffix("_rating") + "_direct_pct"
	return float(combatant.combat_stats.get(key + "_percent", 0.0)) + float(combatant.combat_stats.get(direct_key, 0.0)) + modifier(combatant, direct_key, round_number)

static func snapshot(combatant: CombatantState, round_number: int) -> Dictionary:
	var result: Dictionary = combatant.combat_stats.duplicate(true)
	for field in trait_modifiers(combatant):
		if not (String(field).ends_with("_flat") or String(field).ends_with("_direct_pct") or String(field).ends_with("_modifier") or String(field) == "damage_reduction"):
			continue
		result[field] = float(result.get(field, 0.0)) + float(trait_modifiers(combatant)[field])
	for record in active_effects(combatant, round_number):
		var definition: Dictionary = record.get("definition", {})
		for key in definition:
			var field := String(key)
			if not (field.ends_with("_flat") or field.ends_with("_direct_pct") or field.ends_with("_modifier") or field == "damage_reduction"):
				continue
			result[field] = float(result.get(field, 0.0)) + float(definition[key])
	return result
