class_name ResistEffectCases
extends RefCounted

static func run(base_balance:Dictionary) -> bool:
	var balance := base_balance.duplicate(true)
	var effects:Dictionary = balance.get("effects", {}).duplicate(true)
	effects["EFF_FREEZE"] = {"id":"EFF_FREEZE","kind":"freeze","duration_rounds":1,"stacking":"unique","max_stacks":1}
	balance["effects"] = effects
	return (
		_case_magic_damage_resist(balance)
		and _case_effect_chance_100_to_60(balance)
		and _case_effect_chance_80_to_48(balance)
		and _case_effect_immunity(balance)
	)

static func _state() -> CombatState:
	var state := CombatState.new()
	state.add_combatant(CombatantState.new("source","Source",10,100))
	state.add_combatant(CombatantState.new("target","Target",10,100))
	state.begin_round()
	return state

static func _case_magic_damage_resist(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").magic_resists["fire"] = 0.40
	var event := state.create_event(CombatEvent.Kind.DAMAGE,"source","target",{"amount":10.0,"damage_type":"fire"})
	CombatEngine.new(state,balance).resolve_event(event)
	return state.get_combatant("target").hp == 94 and is_equal_approx(float(event.result.get("magic_resist",0.0)),0.40)

static func _effect_event(state:CombatState, chance:float, roll:int) -> CombatEvent:
	return state.create_event(CombatEvent.Kind.EFFECT,"source","target",{
		"effect_id":"EFF_FREEZE","base_chance":chance,"resist_type":"water","effect_roll":roll,"source_type":"ability"
	})

static func _case_effect_chance_100_to_60(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").magic_resists["water"] = 40.0
	var event := _effect_event(state,100.0,60)
	CombatEngine.new(state,balance).resolve_event(event)
	return bool(event.result.get("resolved",false)) and is_equal_approx(float(event.result.get("effective_chance",0.0)),60.0)

static func _case_effect_chance_80_to_48(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").magic_resists["water"] = 0.40
	var event := _effect_event(state,80.0,49)
	CombatEngine.new(state,balance).resolve_event(event)
	return not bool(event.result.get("resolved",true)) and String(event.result.get("outcome","")) == "resisted" and is_equal_approx(float(event.result.get("effective_chance",0.0)),48.0)

static func _case_effect_immunity(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").effect_immunities.append("EFF_FREEZE")
	var event := _effect_event(state,100.0,1)
	CombatEngine.new(state,balance).resolve_event(event)
	return not bool(event.result.get("resolved",true)) and String(event.result.get("outcome","")) == "immune" and state.get_combatant("target").active_effects.is_empty()
