class_name CombatModifierServiceCases
extends RefCounted

static func run() -> bool:
	return (
		_case_canonical_percent_avoids_direct_pct_double_count()
		and _case_runtime_direct_pct_overlay_applies_once()
		and _case_auto_block_runtime_overlay_dr_once()
		and _case_combat_readout_matches_runtime_effects()
		and _case_magic_resist_prefers_canonical_stats()
		and _case_magic_resist_sequential_dr_and_overlay()
		and _case_v12_magic_penetration_before_resistance_dr()
		and _case_mana_regen_uses_runtime_overlay()
		and _case_damage_reduction_uses_runtime_overlay()
		and _case_v12_par135_rating_age_and_dr()
		and _case_v12_crit_damage_bonus_dr()
		and _case_manual_block_accessors_use_par073()
		and _case_equipped_item_types_accessor_copies_values()
		and _case_effect_trigger_accessors_copy_values()
		and _case_abilities_accessor_copies_values()
	)

static func _combatant() -> CombatantState:
	var combatant := TestFixtureLoader.new_combatant("subject", "Subject", 10, 100, 50)
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

static func _case_auto_block_runtime_overlay_dr_once() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["shield_auto_block_rating_percent"] = 30.0
	combatant.active_effects.append({
		"effect_id":"EFF_TEST_AUTO_BLOCK",
		"definition":{"shield_auto_block_direct_pct":20.0},
		"start_round":1,
		"remaining_rounds":1
	})
	var actual := CombatModifierService.block_chance(combatant,1)
	return absf(actual-43.939486)<0.001

static func _case_combat_readout_matches_runtime_effects() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["crit_chance_rating_percent"] = 40.0
	combatant.combat_stats["dodge_rating_percent"] = 25.0
	combatant.combat_stats["shield_auto_block_rating_percent"] = 30.0
	combatant.active_effects.append({
		"effect_id":"EFF_READOUT_TEST",
		"definition":{
			"crit_chance_direct_pct":15.0,"dodge_direct_pct":10.0,
			"shield_auto_block_direct_pct":20.0,
			"physical_damage_outgoing_direct_pct":25.0,
			"damage_reduction":0.15
		},
		"start_round":2,"remaining_rounds":2
	})
	var before := CombatModifierService.combat_readout(combatant,1)
	var active := CombatModifierService.combat_readout(combatant,2)
	var after := CombatModifierService.combat_readout(combatant,1)
	return (
		is_equal_approx(float(before.get("crit_after_dr_pct",-1.0)),CombatMath.effective_crit(40.0,0.0))
		and is_equal_approx(float(active.get("crit_after_dr_pct",-1.0)),CombatMath.effective_crit(55.0,0.0))
		and is_equal_approx(float(active.get("dodge_after_dr_pct",-1.0)),CombatMath.effective_dodge(35.0,0.0))
		and is_equal_approx(float(active.get("auto_block_after_dr_pct",-1.0)),CombatRatingCurves.diminishing(50.0,"block"))
		and is_equal_approx(float(active.get("physical_outgoing_bonus_pct",-1.0)),25.0)
		and is_equal_approx(float(active.get("damage_reduction",-1.0)),0.15)
		and is_equal_approx(float(after.get("physical_outgoing_bonus_pct",-1.0)),0.0)
		and is_equal_approx(float(combatant.combat_stats.get("crit_chance_rating_percent",0.0)),40.0)
	)

static func _case_magic_resist_prefers_canonical_stats() -> bool:
	var combatant := _combatant()
	combatant.magic_resists["fire"] = 0.25
	combatant.combat_stats["fire_resistance"] = 40.0
	combatant.combat_stats["par_totals"]["PAR190"] = 100.0
	combatant.combat_stats["par_totals"]["PAR191"] = 100.0
	var per_layer := RatingMatrix.to_percent(100.0,combatant.level)/100.0
	var raw_combined_pct := 100.0*(1.0-(1.0-per_layer)*(1.0-per_layer))
	var expected := CombatRatingCurves.diminishing(raw_combined_pct,"magic_res")/100.0
	return is_equal_approx(CombatModifierService.magic_resist(combatant,"fire",1),expected)

static func _case_magic_resist_sequential_dr_and_overlay() -> bool:
	var fighter := TestFixtureLoader.new_combatant("resist_lv1","Magic Resist",1,100)
	fighter.combat_stats["par_totals"]["PAR190"] = 200.0
	fighter.combat_stats["par_totals"]["PAR191"] = 200.0
	var base := CombatModifierService.magic_resist(fighter,"fire",1)
	# 200 rating = 40% per layer; sequentially combining yields 64% raw,
	# then one DR keeps the final output strictly below the 85.1% cap.
	var expected := CombatRatingCurves.diminishing(64.0,"magic_res")/100.0
	fighter.active_effects.append({
		"effect_id":"EFF_MAGIC_RESIST_BONUS",
		"definition":{"fire_resist_direct_pct":20.0},
		"start_round":2,"remaining_rounds":2
	})
	var active := CombatModifierService.magic_resist(fighter,"fire",2)
	var pending := CombatModifierService.magic_resist(fighter,"fire",1)
	# Fire bonus cannot add to the unaffected water resistance.
	var water := CombatModifierService.magic_resist(fighter,"water",2)
	return (
		is_equal_approx(base,expected)
		and is_equal_approx(pending,base)
		and active>base
		and is_equal_approx(water,CombatRatingCurves.diminishing(40.0,"magic_res")/100.0)
		and CombatModifierService.magic_resist(fighter,"fire",2)<0.851
		and is_equal_approx(float(CombatModifierService.combat_readout(fighter,2).get("elemental_resists_pct",{}).get("fire",-1.0)),active*100.0)
	)

static func _case_v12_magic_penetration_before_resistance_dr() -> bool:
	var attacker := TestFixtureLoader.new_combatant("penetrator","Penetrator",1,100)
	var defender := TestFixtureLoader.new_combatant("resist_target","Target",1,100)
	attacker.combat_stats["par_totals"]["PAR164"] = 100.0
	attacker.combat_stats["par_totals"]["PAR165"] = 100.0
	defender.combat_stats["par_totals"]["PAR190"] = 200.0
	defender.combat_stats["par_totals"]["PAR191"] = 200.0
	defender.combat_stats["par_totals"]["PAR192"] = 200.0
	# 40% common and 40% school -> 64% raw. 20% common pen + 20%
	# fire pen -> 24% before DR. Water only receives common pen -> 44%.
	var unpenetrated := CombatModifierService.magic_resist(defender,"fire",1)
	var fire := CombatModifierService.magic_resist(defender,"fire",1,attacker)
	var water := CombatModifierService.magic_resist(defender,"water",1,attacker)
	attacker.active_effects.append({
		"effect_id":"EFF_PENETRATION",
		"definition":{"magic_pen_fire_direct_pct":10.0},
		"start_round":2,"remaining_rounds":2
	})
	var pending := CombatModifierService.magic_resist(defender,"fire",1,attacker)
	var active := CombatModifierService.magic_resist(defender,"fire",2,attacker)
	var readout := CombatModifierService.combat_readout(attacker,2)
	return (
		is_equal_approx(fire,0.24)
		and is_equal_approx(water,CombatRatingCurves.diminishing(44.0,"magic_res")/100.0)
		and unpenetrated>water and water>fire and active<fire
		and is_equal_approx(pending,fire)
		and is_equal_approx(active,0.14)
		and is_equal_approx(float(Dictionary(readout.get("magic_penetration_by_school_pct",{})).get("fire",0.0)),50.0)
		and is_equal_approx(float(Dictionary(readout.get("elemental_resists_pct",{})).get("fire",0.0)),0.0)
	)

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

static func _case_v12_par135_rating_age_and_dr() -> bool:
	var lv1 := TestFixtureLoader.new_combatant("par135_lv1","Damage Reduction 1",1,100)
	var lv100 := TestFixtureLoader.new_combatant("par135_lv100","Damage Reduction 100",100,100)
	for target in [lv1,lv100]:
		target.combat_stats["damage_reduction_pct"] = 100.0
	var first := CombatModifierService.damage_reduction(lv1,1)
	var last := CombatModifierService.damage_reduction(lv100,1)
	# Rating 100 -> 20% at L1; DR 5/35/1 maps 20 -> 15.
	return is_equal_approx(first,0.15) and is_equal_approx(last,0.04) and first>last

static func _case_v12_crit_damage_bonus_dr() -> bool:
	var fighter := TestFixtureLoader.new_combatant("crit_dr","Crit Damage",1,100)
	fighter.combat_stats["crit_damage_rating_percent"] = 100.0
	return (
		is_equal_approx(CombatModifierService.crit_damage_bonus(fighter,1),90.0)
		and is_equal_approx(CombatModifierService.crit_damage_bonus(fighter,1,25.0),CombatRatingCurves.diminishing(125.0,"crit_damage"))
		and CombatModifierService.crit_damage_bonus(fighter,1,10000.0)<250.0
		and is_equal_approx(float(CombatModifierService.combat_readout(fighter,1).get("crit_damage_after_dr_pct",-1)),90.0)
	)

static func _case_manual_block_accessors_use_par073() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["par_totals"]["PAR073"] = 2
	combatant.combat_stats["manual_block_zones"] = ["head", "chest"]
	return CombatModifierService.manual_block_zone_capacity(combatant) == 2 and CombatModifierService.manual_block_zones(combatant) == ["head", "chest"]

static func _case_equipped_item_types_accessor_copies_values() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["equipped_item_types"] = ["dagger", "shield"]
	var equipped := CombatModifierService.equipped_item_types(combatant)
	equipped.append("mutated")
	return CombatModifierService.equipped_item_types(combatant) == ["dagger", "shield"]

static func _case_effect_trigger_accessors_copy_values() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["weapon_on_hit_effects"] = [{"effect_id": "EFF001"}]
	combatant.combat_stats["on_manual_block_effects"] = [{"effect_id": "EFF002"}]
	var on_hit := CombatModifierService.weapon_on_hit_effects(combatant)
	var on_block := CombatModifierService.manual_block_effects(combatant)
	on_hit.clear()
	on_block.clear()
	return CombatModifierService.weapon_on_hit_effects(combatant).size() == 1 and CombatModifierService.manual_block_effects(combatant).size() == 1

static func _case_abilities_accessor_copies_values() -> bool:
	var combatant := _combatant()
	combatant.combat_stats["abilities"] = ["ABI001"]
	var abilities := CombatModifierService.abilities(combatant)
	abilities.append("ABI999")
	return CombatModifierService.abilities(combatant) == ["ABI001"]
