class_name CombatModifierServiceCases
extends RefCounted

static func run() -> bool:
	return (
		_case_canonical_percent_avoids_direct_pct_double_count()
		and _case_runtime_direct_pct_overlay_applies_once()
		and _case_magic_resist_prefers_canonical_stats()
		and _case_mana_regen_uses_runtime_overlay()
		and _case_damage_reduction_uses_runtime_overlay()
		and _case_manual_block_accessors_normalize_capacity()
	)

static func _combatant() -> CombatantState:
	var combatant := CombatantState.new("subject", "Subject", 10, 100, 50)
	return combatant

static func _case_canonical_percent_avoids_direct_pct_double_count() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["crit_chance_rating_percent"] = 12.0
	combatant.combat_stats["crit_chance_direct_pct"] = 5.0
	var actual := CombatModifierService.effective_percent(combatant, "crit_chance_rating", 1)
	return is_equal_approx(actual, 12.0)

static func _case_runtime_direct_pct_overlay_applies_once() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["crit_chance_rating_percent"] = 12.0
	combatant.active_effects.append({
		"effect_id": "EFF_TEST_CRIT",
		"definition": {"crit_chance_direct_pct": 3.0},
		"start_round": 1,
		"remaining_rounds": 1
	})
	var actual := CombatModifierService.effective_percent(combatant, "crit_chance_rating", 1)
	return is_equal_approx(actual, 15.0)

static func _case_magic_resist_prefers_canonical_stats() -> bool:
	var combatant := _combatant()
	combatant.magic_resists["fire"] = 0.25
	combatant.combat_stats["fire_resistance"] = 40.0
	combatant.active_effects.append({
		"effect_id": "EFF_TEST_RESIST",
		"definition": {"fire_resistance": 10.0},
		"start_round": 1,
		"remaining_rounds": 1
	})
	var actual := CombatModifierService.magic_resist(combatant, "fire", 1)
	return is_equal_approx(actual, 0.5)

static func _case_mana_regen_uses_runtime_overlay() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["mana_regen"] = 4.0
	combatant.active_effects.append({
		"effect_id": "EFF_TEST_REGEN",
		"definition": {"mana_regen": 6.0},
		"start_round": 1,
		"remaining_rounds": 1
	})
	return is_equal_approx(CombatModifierService.value(combatant, "mana_regen", 1), 10.0)

static func _case_damage_reduction_uses_runtime_overlay() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["damage_reduction"] = 0.35
	combatant.active_effects.append({
		"effect_id": "EFF_TEST_REDUCTION",
		"definition": {"damage_reduction": 0.80},
		"start_round": 1,
		"remaining_rounds": 1
	})
	return is_equal_approx(CombatModifierService.damage_reduction(combatant, 1), 1.0)

static func _case_manual_block_accessors_normalize_capacity() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["manual_block_zone_count"] = 4
	combatant.combat_stats["manual_block_zones"] = ["head", "chest"]
	return CombatModifierService.manual_block_zone_capacity(combatant) == 3 and CombatModifierService.manual_block_zones(combatant) == ["head", "chest"]
