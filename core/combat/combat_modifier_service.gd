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
	# One combined permanent+runtime percent, then v1.2 block diminishing.
	# Manual zone block is a separate deterministic defence, not this chance.
	var raw_chance := maxf(0.0,effective_percent(combatant,"shield_auto_block_rating",round_number))
	return clampf(CombatRatingCurves.diminishing(raw_chance,"block"),0.0,100.0)

static func block_crush_chance(combatant: CombatantState, round_number: int) -> float:
	# RAGE: each stack adds +2 percentage points vs ALL manual/auto blocks.
	# CRUSHER adds +20 via its ordinary EFF block_crush overlay.
	return value(combatant, "block_crush", round_number) + 2.0*float(AxeAbiCombatService.rage_stacks(combatant,round_number))

static func armour_penetration_flat(combatant: CombatantState, round_number: int) -> float:
	return value(combatant, "armour_penetration_flat", round_number)

static func armour_reduction_percent(combatant: CombatantState, round_number: int) -> float:
	# PAR126 is always percentage points: 1 = 1%, not 100%.
	var percentage_points := value(combatant, "armour_penetration_percent", round_number)
	return clampf(percentage_points / 100.0, 0.0, 1.0)

## PAR127–130 base/item values are already in PhysicalArmourService's 5x4
## matrix. Only live TRA/EFF overlays belong at the hit-resolution boundary.
static func global_physical_armour(combatant: CombatantState, damage_type: String, round_number: int) -> float:
	var normalized := damage_type.to_lower()
	if not EquipmentBuilder.PHYSICAL_TYPES.has(normalized):
		return 0.0
	return modifier(combatant, "physical_resist_" + normalized, round_number)

## PAR131–134: percentage penetration of only the matching physical armour type.
static func typed_armour_penetration_percent(combatant: CombatantState, damage_type: String, round_number: int) -> float:
	const TYPES := {"piercing": "PAR131", "slashing": "PAR132", "chopping": "PAR133", "blunt": "PAR134"}
	var key := String(TYPES.get(damage_type.to_lower(), ""))
	if key.is_empty():
		return 0.0
	var totals: Variant = combatant.combat_stats.get("par_totals", {})
	if not totals is Dictionary:
		return 0.0
	var percent := float(totals.get(key, 0.0)) + modifier(combatant, "armour_pen_" + damage_type.to_lower(), round_number)
	return clampf(percent / 100.0, 0.0, 1.0)

## PAR035 bonus is a rating. Item/direct percentages are summed before
## v1.2 critical-damage diminishing; the 1.5x base crit is unaffected.
static func crit_damage_bonus(combatant: CombatantState, round_number: int, ability_bonus_pct: float = 0.0) -> float:
	var raw_bonus := effective_percent(combatant,"crit_damage_rating",round_number)+ability_bonus_pct
	return maxf(0.0,CombatRatingCurves.diminishing(raw_bonus,"crit_damage"))

static func damage_reduction(combatant: CombatantState, round_number: int) -> float:
	# PAR135 is a RATING, not direct percentage points. Convert by owner
	# level then apply 5/35/1 DR. Legacy EFF/TRA 'damage_reduction' overlays
	# are explicit fractions and stay distinct from the item PAR budget.
	var par_rating := value(combatant,"damage_reduction_pct",round_number)
	var raw_par_percent := RatingMatrix.to_percent(par_rating,combatant.level)
	var par_after_dr := CombatRatingCurves.diminishing(maxf(0.0,raw_par_percent),"reduce")
	var direct_fraction := value(combatant,"damage_reduction",round_number)
	return clampf(par_after_dr/100.0+direct_fraction,0.0,1.0)

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

## Spell delivery names may differ from the canonical six magic schools.
static func magic_school(damage_type: String) -> String:
	match damage_type.to_lower():
		"frost": return "water"
		"lightning": return "air"
		"nature": return "earth"
		"holy": return "light"
		_: return damage_type.to_lower()

## PAR164 is universal; PAR165–170 apply only to their corresponding school.
## Both remain ratings until converted at ATTACKER level and are subtracted
## as percentage points before the target's magic resistance DR.
static func magic_penetration_percent(attacker: CombatantState, school: String, round_number: int) -> float:
	if attacker == null:
		return 0.0
	const PEN_PAR := {"fire":"PAR165","water":"PAR166","air":"PAR167","earth":"PAR168","dark":"PAR169","light":"PAR170"}
	var key := magic_school(school)
	if not PEN_PAR.has(key):
		return 0.0
	var totals: Variant = attacker.combat_stats.get("par_totals",{})
	if not totals is Dictionary:
		push_error("Magic penetration requires canonical attacker PAR totals")
		return 0.0
	var general_rating: Variant = totals.get("PAR164",0.0)
	var school_rating: Variant = totals.get(PEN_PAR[key],0.0)
	if not RatingMatrix._number(general_rating) or not RatingMatrix._number(school_rating):
		push_error("Invalid magic penetration PAR rating")
		return 0.0
	var raw_points := RatingMatrix.to_percent(float(general_rating)+float(school_rating),attacker.level)
	# Direct EFF/TRA/item overlays are explicitly percentage points, not ratings.
	var general_direct := "magic_pen_direct_pct"
	var school_direct := "magic_pen_"+key+"_direct_pct"
	raw_points += float(attacker.combat_stats.get(general_direct,0.0))
	raw_points += float(attacker.combat_stats.get(school_direct,0.0))
	raw_points += modifier(attacker,general_direct,round_number)
	raw_points += modifier(attacker,school_direct,round_number)
	return maxf(0.0,raw_points)

static func magic_resist(combatant: CombatantState, resist_type: String, round_number: int, attacker: CombatantState = null) -> float:
	var key := magic_school(resist_type)
	const ELEMENT_PAR := {"fire":"PAR191", "water":"PAR192", "air":"PAR193", "earth":"PAR194", "dark":"PAR195", "light":"PAR196"}
	if not ELEMENT_PAR.has(key):
		return 0.0
	var totals: Variant = combatant.combat_stats.get("par_totals", {})
	if not totals is Dictionary:
		push_error("Magic resistance requires canonical PAR totals")
		return 0.0
	# General PAR190 and school PAR191–196 combine sequentially in RAW %.
	# Attacker's converted PAR164 and matching PAR165–170 are subtracted
	# from the COMBINED raw defence before the single v1.2 magic DR.
	# A stat panel without an attacker still shows the unpenetrated defence.
	var general_raw := RatingMatrix.to_percent(float(totals.get("PAR190",0.0)),combatant.level)
	var school_raw := RatingMatrix.to_percent(float(totals.get(ELEMENT_PAR[key],0.0)),combatant.level)
	if not is_finite(general_raw) or not is_finite(school_raw):
		push_error("Invalid magic resistance rating")
		return 0.0
	# EFF is a percentage-point overlay for this school; hammer charges
	# contribute +0.25 p.p. per charge to the same raw school layer.
	var school_bonus := modifier(combatant,key+"_resist_direct_pct",round_number)
	var charge_bonus := 0.25*float(HammerAbiCombatService.charges(combatant,round_number))
	var general_fraction := clampf(general_raw/100.0,0.0,1.0)
	var school_fraction := clampf((school_raw+school_bonus+charge_bonus)/100.0,0.0,1.0)
	var sequential_raw_pct := 100.0*(1.0-(1.0-general_fraction)*(1.0-school_fraction))
	var penetration_pct := magic_penetration_percent(attacker,key,round_number)
	var remaining_raw_pct := maxf(0.0,sequential_raw_pct-penetration_pct)
	var after_dr_pct := CombatRatingCurves.diminishing(remaining_raw_pct,"magic_res")
	return clampf(after_dr_pct/100.0,0.0,1.0)

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
	return combatant.tempo

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
	for rating_key in ["hit_chance_rating", "dodge_rating", "anti_dodge_rating", "crit_chance_rating", "anti_crit_rating", "crit_damage_rating", "magic_damage_rating", "shield_auto_block_rating", "manual_block_rating", "block_crush_rating"]:
		if combatant.combat_stats.has(rating_key + "_percent"):
			result[rating_key + "_percent"] = effective_percent(combatant, rating_key, round_number)
	result["armour_penetration_flat"] = armour_penetration_flat(combatant, round_number)
	result["armour_penetration_percent"] = armour_reduction_percent(combatant, round_number) * 100.0
	# These are the SAME runtime calculations used by CombatEngine, not UI
	# approximations of flat/current EFF, ABI and TRA. Opponent counters,
	# body zone, distance and individual ABI packets are contextual.
	result["crit_after_dr_pct"] = CombatMath.effective_crit(effective_percent(combatant,"crit_chance_rating",round_number)+modifier(combatant,"crit_bonus",round_number),0.0)
	result["dodge_after_dr_pct"] = CombatMath.effective_dodge(effective_percent(combatant,"dodge_rating",round_number),0.0)
	result["auto_block_after_dr_pct"] = block_chance(combatant,round_number)
	result["crit_abi_bonus_pct"] = modifier(combatant,"crit_bonus",round_number)
	result["crit_damage_after_dr_pct"] = crit_damage_bonus(combatant,round_number)
	result["damage_reduction_par_after_dr_pct"] = CombatRatingCurves.diminishing(
		maxf(0.0,RatingMatrix.to_percent(value(combatant,"damage_reduction_pct",round_number),combatant.level)),"reduce")
	result["physical_outgoing_bonus_pct"] = modifier(combatant,"physical_damage_outgoing_direct_pct",round_number)
	var elemental_resists := {}
	for school in ["fire","water","air","earth","dark","light"]:
		elemental_resists[school] = magic_resist(combatant,school,round_number)*100.0
	result["elemental_resists_pct"] = elemental_resists
	# Offensive penetration shown separately; elemental_resists_pct remains
	# the character's own defence, not a fabricated value against an enemy.
	var penetration_by_school := {}
	for school in ["fire","water","air","earth","dark","light"]:
		penetration_by_school[school] = magic_penetration_percent(combatant,school,round_number)
	result["magic_penetration_by_school_pct"] = penetration_by_school
	return result

static func snapshot(combatant: CombatantState, round_number: int) -> Dictionary:
	var result: Dictionary = combatant.combat_stats.duplicate(true)
	for field in trait_modifiers(combatant):
		# Tempo control is already accumulated in the live pool when applied.
		if String(field) == "tempo_modifier":
			continue
		if not (String(field).ends_with("_flat") or String(field).ends_with("_direct_pct") or String(field).ends_with("_modifier") or String(field) == "damage_reduction"):
			continue
		result[field] = float(result.get(field, 0.0)) + float(trait_modifiers(combatant)[field])
	for record in active_effects(combatant, round_number):
		var definition: Dictionary = record.get("definition", {})
		for key in definition:
			var field := String(key)
			if field == "tempo_modifier":
				continue
			if not (field.ends_with("_flat") or field.ends_with("_direct_pct") or field.ends_with("_modifier") or field == "damage_reduction"):
				continue
			result[field] = float(result.get(field, 0.0)) + float(definition[key])
	return result
