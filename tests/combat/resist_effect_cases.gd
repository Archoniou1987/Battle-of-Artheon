class_name ResistEffectCases
extends RefCounted

static func run(base_balance:Dictionary) -> bool:
	var balance := base_balance.duplicate(true)
	var effects:Dictionary = balance.get("effects", {}).duplicate(true)
	effects["EFF_FREEZE"] = {"id":"EFF_FREEZE","kind":"freeze","duration_rounds":1,"stacking":"unique","max_stacks":1}
	balance["effects"] = effects
	return (
		_case_magic_damage_resist(balance)
		and _case_penetration_reduces_actual_magic_damage(balance)
		and _case_penetration_affects_effect_chance(balance)
		and _case_penetration_school_aliases(balance)
		and _case_effect_chance_100_to_60(balance)
		and _case_effect_chance_80_to_48(balance)
		and _case_effect_immunity(balance)
	)

static func _state() -> CombatState:
	var state := CombatState.new()
	state.add_combatant(TestFixtureLoader.new_combatant("source","Source",10,100))
	state.add_combatant(TestFixtureLoader.new_combatant("target","Target",10,100))
	state.begin_round()
	return state

static func _set_resist_percent(target: CombatantState, par_id: String, percent: float) -> void:
	var per_100_rating := RatingMatrix.to_percent(100.0, target.level)
	target.combat_stats["par_totals"]["PAR190"] = 0.0
	target.combat_stats["par_totals"][par_id] = percent * 100.0 / per_100_rating

static func _case_magic_damage_resist(balance:Dictionary) -> bool:
	var state := _state()
	_set_resist_percent(state.get_combatant("target"), "PAR191", 40.0)
	var event := state.create_event(CombatEvent.Kind.DAMAGE,"source","target",{"amount":10.0,"damage_type":"fire"})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(event)
	var expected := CombatRatingCurves.diminishing(40.0,"magic_res")/100.0
	return state.get_combatant("target").hp == 94 and is_equal_approx(float(event.result.get("magic_resist",0.0)),expected)

static func _case_penetration_reduces_actual_magic_damage(balance:Dictionary) -> bool:
	var state := _state()
	var source: CombatantState = state.get_combatant("source")
	_set_resist_percent(state.get_combatant("target"),"PAR191",40.0)
	# Attacker's 100 general rating converts at Lv10 to ~18.545%,
	# removing that amount BEFORE DR. Other schools are unaffected.
	source.combat_stats["par_totals"]["PAR164"] = 100.0
	var attack_pen := RatingMatrix.to_percent(100.0,source.level)
	var remaining := maxf(0.0,40.0-attack_pen)
	var expected := CombatRatingCurves.diminishing(remaining,"magic_res")/100.0
	var hit := state.create_event(CombatEvent.Kind.DAMAGE,"source","target",{"amount":100.0,"damage_type":"fire"})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(hit)
	return (
		is_equal_approx(float(hit.result.get("magic_resist",-1.0)),expected)
		and int(hit.result.get("final_damage",-1))==CombatMath.final_damage_floor(100.0*(1.0-expected))
		and int(hit.result.get("final_damage",-1))==78
	)

static func _case_penetration_affects_effect_chance(balance:Dictionary) -> bool:
	var state := _state()
	var source: CombatantState = state.get_combatant("source")
	_set_resist_percent(state.get_combatant("target"),"PAR192",40.0)
	source.combat_stats["par_totals"]["PAR166"] = 100.0
	var effect := _effect_event(state,100.0,70)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(effect)
	var expected := 40.0-RatingMatrix.to_percent(100.0,source.level)
	return (
		bool(effect.result.get("resolved",false))
		and is_equal_approx(float(effect.result.get("resist",-1.0)),expected/100.0)
		and is_equal_approx(float(effect.result.get("effective_chance",-1.0)),100.0-expected)
	)

static func _case_penetration_school_aliases(balance:Dictionary) -> bool:
	var state := _state()
	var source: CombatantState = state.get_combatant("source")
	var target: CombatantState = state.get_combatant("target")
	_set_resist_percent(target,"PAR192",40.0)
	source.combat_stats["par_totals"]["PAR166"] = 100.0
	var pen := CombatModifierService.magic_resist(target,"frost",1,source)
	var ordinary := CombatModifierService.magic_resist(target,"water",1,source)
	# Fire never inherits the water penetration. No magic resist for physical.
	var fire := CombatModifierService.magic_resist(target,"fire",1,source)
	return (
		is_equal_approx(pen,ordinary)
		and pen<CombatModifierService.magic_resist(target,"water",1)
		and is_zero_approx(fire)
		and CombatDamagePayload.is_magic_damage_type("nature")
		and CombatDamagePayload.is_magic_damage_type("holy")
		and CombatModifierService.magic_school("lightning")=="air"
	)

static func _effect_event(state:CombatState, chance:float, roll:int) -> CombatEvent:
	return state.create_event(CombatEvent.Kind.EFFECT,"source","target",{
		"effect_id":"EFF_FREEZE","base_chance":chance,"resist_type":"water","effect_roll":roll,"source_type":"ability"
	})

static func _case_effect_chance_100_to_60(balance:Dictionary) -> bool:
	var state := _state()
	_set_resist_percent(state.get_combatant("target"), "PAR192", 40.0)
	var event := _effect_event(state,100.0,60)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(event)
	var expected := 100.0-CombatRatingCurves.diminishing(40.0,"magic_res")
	return bool(event.result.get("resolved",false)) and is_equal_approx(float(event.result.get("effective_chance",0.0)),expected)

static func _case_effect_chance_80_to_48(balance:Dictionary) -> bool:
	var state := _state()
	_set_resist_percent(state.get_combatant("target"), "PAR192", 40.0)
	var event := _effect_event(state,80.0,49)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(event)
	var expected := 80.0*(1.0-CombatRatingCurves.diminishing(40.0,"magic_res")/100.0)
	return not bool(event.result.get("resolved",true)) and String(event.result.get("outcome","")) == "resisted" and is_equal_approx(float(event.result.get("effective_chance",0.0)),expected)

static func _case_effect_immunity(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").effect_immunities.append("freeze")
	var event := _effect_event(state,100.0,1)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(event)
	return not bool(event.result.get("resolved",true)) and String(event.result.get("outcome","")) == "immune" and state.get_combatant("target").active_effects.is_empty()
