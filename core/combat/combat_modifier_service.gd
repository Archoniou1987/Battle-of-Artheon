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

## Rating conversion is owned by CharacterStatsService. Canonical *_percent
## already includes permanent *_direct_pct, so this layer adds runtime overlays only.
static func effective_percent(combatant: CombatantState, key: String, round_number: int) -> float:
	var field := key + "_percent"
	if not combatant.combat_stats.has(field) or not RatingMatrix._number(combatant.combat_stats[field]):
		push_error("Missing mandatory converted rating: " + field)
		return NAN
	var direct_key := key.trim_suffix("_rating") + "_direct_pct"
	var permanent: Variant = trait_modifiers(combatant).get(direct_key, 0.0)
	if not RatingMatrix._number(permanent):
		push_error("Invalid runtime direct-percent modifier: " + direct_key)
		return NAN
	var result := float(combatant.combat_stats[field]) + float(permanent)
	for record in active_effects(combatant, round_number):
		var value: Variant = Dictionary(record.get("definition", {})).get(direct_key, 0.0)
		if not RatingMatrix._number(value):
			push_error("Invalid effect direct-percent modifier: " + direct_key)
			return NAN
		result += float(value)
	if not is_finite(result):
		push_error("Non-finite converted rating: " + field)
		return NAN
	return result

static func block_chance(combatant: CombatantState, round_number: int) -> float:
	return effective_percent(combatant, "shield_auto_block_rating", round_number)

static func block_crush_chance(combatant: CombatantState, round_number: int) -> float:
	return value(combatant, "block_crush", round_number)

static func armour_penetration_flat(combatant: CombatantState, round_number: int) -> float:
	return value(combatant, "armour_penetration_flat", round_number)

static func armour_reduction_percent(combatant: CombatantState, round_number: int) -> float:
	var value_percent := value(combatant, "armour_penetration_percent", round_number)
	if value_percent > 1.0:
		value_percent /= 100.0
	return clampf(value_percent, 0.0, 1.0)

static func damage_reduction(combatant: CombatantState, round_number: int) -> float:
	return clampf(value(combatant, "damage_reduction", round_number), 0.0, 1.0)

static func manual_block_zone_capacity(combatant: CombatantState) -> int:
	var totals: Variant = combatant.combat_stats.get("par_totals")
	if not totals is Dictionary or not totals.has("PAR073") or not RatingMatrix._number(totals["PAR073"]):
		push_error("Missing or invalid mandatory PAR073")
		return 0 # Diagnostic failure; combat entry points reject the contract before resolving.
	return int(totals["PAR073"])

static func manual_block_zones(combatant: CombatantState) -> Array:
	return Array(combatant.combat_stats.get("manual_block_zones", [])).duplicate(true)

static func equipped_item_types(combatant: CombatantState) -> Array:
	return Array(combatant.combat_stats.get("equipped_item_types", [])).duplicate(true)

static func weapon_on_hit_effects(combatant: CombatantState) -> Array:
	return Array(combatant.combat_stats.get("weapon_on_hit_effects", [])).duplicate(true)

static func manual_block_effects(combatant: CombatantState) -> Array:
	return Array(combatant.combat_stats.get("on_manual_block_effects", [])).duplicate(true)

static func abilities(combatant: CombatantState) -> Array:
	return Array(combatant.combat_stats.get("abilities", [])).duplicate(true)

static func magic_resist(combatant: CombatantState, resist_type: String, round_number: int) -> float:
	var key := resist_type.to_lower()
	const ELEMENT_PAR := {"fire":"PAR191", "water":"PAR192", "air":"PAR193", "earth":"PAR194", "dark":"PAR195", "light":"PAR196"}
	if not ELEMENT_PAR.has(key):
		return 0.0
	var totals: Variant = combatant.combat_stats.get("par_totals", {})
	if not totals is Dictionary:
		push_error("Magic resistance requires canonical PAR totals")
		return 0.0
	var rating := float(totals.get("PAR190", 0.0)) + float(totals.get(ELEMENT_PAR[key], 0.0))
	var percent := RatingMatrix.to_percent(rating, combatant.level)
	if not is_finite(percent):
		push_error("Invalid magic resistance rating")
		return 0.0
	return clampf(percent / 100.0, 0.0, 1.0)

## The shared combat/UI read contract. A caller can request any derived stat
## without reimplementing the overlay. Raw ratings remain available separately.
static func value(combatant: CombatantState, key: String, round_number: int, default_value: float = 0.0) -> float:
	if key.ends_with("_percent"):
		var rating_key := key.trim_suffix("_percent")
		if combatant.combat_stats.has(key):
			return effective_percent(combatant, rating_key, round_number)
		return default_value + modifier(combatant, rating_key.trim_suffix("_rating") + "_direct_pct", round_number)
	return float(combatant.combat_stats.get(key, default_value)) + modifier(combatant, key, round_number)

static func effective_tempo(combatant: CombatantState, round_number: int) -> float:
	return combatant.tempo + value(combatant, "tempo", round_number) + modifier(combatant, "tempo_modifier", round_number)

## One traceable read model for a future duel card and combat diagnostics.
## Contextual rolls (opponent, hit zone, distance) belong to CombatEngine.
static func combat_readout(combatant: CombatantState, round_number: int) -> Dictionary:
	var result := snapshot(combatant, round_number)
	result["effective_tempo"] = effective_tempo(combatant, round_number)
	result["damage_reduction"] = damage_reduction(combatant, round_number)
	result["manual_block_zone_capacity"] = manual_block_zone_capacity(combatant)
	result["manual_block_zones"] = manual_block_zones(combatant)
	result["equipped_item_types"] = equipped_item_types(combatant)
	result["weapon_on_hit_effects"] = weapon_on_hit_effects(combatant)
	result["on_manual_block_effects"] = manual_block_effects(combatant)
	result["abilities"] = abilities(combatant)
	for rating_key in ["hit_chance_rating", "dodge_rating", "anti_dodge_rating", "crit_chance_rating", "anti_crit_rating", "counterattack_rating", "crit_damage_rating", "magic_damage_rating", "shield_auto_block_rating", "manual_block_rating", "block_crush_rating"]:
		if combatant.combat_stats.has(rating_key + "_percent"):
			result[rating_key + "_percent"] = effective_percent(combatant, rating_key, round_number)
	result["armour_penetration_flat"] = armour_penetration_flat(combatant, round_number)
	result["armour_penetration_percent"] = armour_reduction_percent(combatant, round_number) * 100.0
	return result

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
