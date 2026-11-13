extends SceneTree

## v1.2: absolute PAR150 SP with optional K, direct % EFF on its own
## timing; zero K leaves existing ABI damage unchanged.
func _initialize() -> void:
	var state := CombatState.new()
	var caster := TestFixtureLoader.new_combatant("caster","Caster",1,100,100)
	caster.combat_stats["par_totals"]["PAR150"] = 100.0
	caster.combat_stats["magic_damage_rating"] = 100.0
	var target := TestFixtureLoader.new_combatant("target","Target",1,200,0)
	state.add_combatant(caster)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	var parent := state.create_event(CombatEvent.Kind.ACTION,"caster","target",{"ability_id":"SP_TEST","delivery_type":"DIRECT"})
	var plain := {"kind":"damage","amount":25.0,"damage_type":"frost"}
	var boosted := {"kind":"damage","amount":25.0,"damage_type":"frost","spell_power_scale":0.25}
	var first := engine._make_action_component_event(parent,plain,"target",1.0)
	var scaled := engine._make_action_component_event(parent,boosted,"target",1.0)
	var valid := is_equal_approx(float(first.payload.get("amount",-1.0)),25.0)
	valid = valid and is_equal_approx(float(scaled.payload.get("amount",-1.0)),50.0)
	var initial_heal := engine._make_action_component_event(parent,{"kind":"heal","amount":30.0,"spell_power_scale":0.5},"caster",1.0)
	valid = valid and int(initial_heal.payload.get("inline_heal",-1))==80
	var half_aoe := engine._make_action_component_event(parent,boosted,"target",0.5)
	valid = valid and is_equal_approx(float(half_aoe.payload.get("amount",-1.0)),25.0)
	var spell_zero := engine._make_action_component_event(parent,{"kind":"damage","amount":0.0,"damage_type":"fire","spell_power_scale":0.25},"target",1.0)
	valid = valid and is_equal_approx(float(spell_zero.payload.get("amount",-1)),25.0)
	caster.active_effects.append({
		"effect_id":"EFF_MAGIC_TEST",
		"definition":{"magic_damage_direct_pct":50.0},
		"start_round":state.round_number+1,"remaining_rounds":2
	})
	var before := engine._make_action_component_event(parent,boosted,"target",1.0)
	valid = valid and is_equal_approx(float(before.payload.get("amount",-1.0)),50.0)
	state.begin_round()
	var after := engine._make_action_component_event(parent,boosted,"target",1.0)
	valid = valid and is_equal_approx(float(after.payload.get("amount",-1.0)),75.0)
	var unscaled_after := engine._make_action_component_event(parent,plain,"target",1.0)
	valid = valid and is_equal_approx(float(unscaled_after.payload.get("amount",-1.0)),37.5)
	var physical := engine._make_action_component_event(parent,{"kind":"damage","amount":25.0,"damage_type":"physical"},"target",1.0)
	valid = valid and is_equal_approx(float(physical.payload.get("amount",-1.0)),25.0)
	# A live absolute SP effect changes both combat and the avatar readout.
	caster.active_effects.append({
		"effect_id":"EFF_SP_FLAT",
		"definition":{"spell_power_flat":100.0},
		"start_round":state.round_number+1,"remaining_rounds":2
	})
	var before_sp := engine._make_action_component_event(parent,boosted,"target",1.0)
	valid = valid and is_equal_approx(float(before_sp.payload.get("amount",-1.0)),75.0)
	state.begin_round()
	var with_sp := engine._make_action_component_event(parent,boosted,"target",1.0)
	valid = valid and is_equal_approx(float(with_sp.payload.get("amount",-1.0)),112.5)
	var with_sp_heal := engine._make_action_component_event(parent,{"kind":"heal","amount":30.0,"spell_power_scale":0.5},"caster",1.0)
	valid = valid and int(with_sp_heal.payload.get("inline_heal",-1))==130
	var avatar := CombatModifierService.combat_readout(caster,state.round_number)
	valid = valid and is_equal_approx(float(avatar.get("spell_power",-1.0)),200.0)
	valid = valid and is_equal_approx(float(caster.combat_stats["par_totals"]["PAR150"]),100.0)
	var described := AbilityCardText.describe("SP_TEST",{"name":"Scale","components":[boosted],"mana_cost":0,"cooldown_rounds":0})
	valid = valid and described.contains("0.250 × SP")
	var wrong_physical := {"components":[{"kind":"damage","amount":25,"damage_type":"physical","spell_power_scale":1.0}]}
	valid = valid and AbilityRuntime.validate_definition("SP_BAD_PHY",wrong_physical).has("spell_power_scale_requires_magic_damage_or_heal")
	var wrong_scale := {"components":[{"kind":"damage","amount":25,"damage_type":"fire","spell_power_scale":-1.0}]}
	valid = valid and AbilityRuntime.validate_definition("SP_BAD_K",wrong_scale).has("invalid_spell_power_scale")
	# The current production catalog contains ONLY the 30 approved physical
	# weapon abilities; none currently has a magic scaling coefficient K.
	var active_defs := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	valid = valid and active_defs.size()==38
	for ability_id in active_defs:
		for component in Array(Dictionary(active_defs[ability_id]).get("components",[])):
			valid = valid and not Dictionary(component).has("spell_power_scale")

	print("MAGIC_ABI_SCALING_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
