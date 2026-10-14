extends SceneTree

## Deterministic regression: ABI elemental damage uses magic bonuses; EFF
## bonuses activate on the following round, not the application round.
func _initialize() -> void:
	var state := CombatState.new()
	var caster := TestFixtureLoader.new_combatant("caster", "Caster", 1, 100, 100)
	caster.combat_stats["magic_damage_flat"] = 5.0
	caster.combat_stats["magic_damage_rating_percent"] = 20.0
	var target := TestFixtureLoader.new_combatant("target", "Target", 1, 200, 0)
	state.add_combatant(caster)
	state.add_combatant(target)
	var engine := CombatEngine.new(state)
	var component := {"kind":"damage", "amount":25.0, "damage_type":"frost"}
	var parent := state.create_event(CombatEvent.Kind.ACTION, "caster", "target", {"ability_id":"ABI006", "delivery_type":"DIRECT"})
	var first := engine._make_action_component_event(parent, component, "target", 1.0)
	var valid := is_equal_approx(float(first.payload.get("amount", -1.0)), 36.0)
	caster.active_effects.append({
		"effect_id":"EFF_MAGIC_TEST",
		"definition":{"magic_damage_direct_pct":50.0},
		"start_round":state.round_number + 1,
		"remaining_rounds":2
	})
	var before := engine._make_action_component_event(parent, component, "target", 1.0)
	valid = valid and is_equal_approx(float(before.payload.get("amount", -1.0)), 36.0)
	state.begin_round()
	var after := engine._make_action_component_event(parent, component, "target", 1.0)
	valid = valid and is_equal_approx(float(after.payload.get("amount", -1.0)), 51.0)
	var physical := engine._make_action_component_event(parent, {"kind":"damage","amount":25.0,"damage_type":"physical"}, "target", 1.0)
	valid = valid and is_equal_approx(float(physical.payload.get("amount", -1.0)), 25.0)
	print("MAGIC_ABI_SCALING_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
