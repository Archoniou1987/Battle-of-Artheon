extends SceneTree

## Deterministic physical-stage matrix using the production CombatEngine.
## Explicit rolls isolate defence ordering, crit and PAR penetration; no UI
## mocks and no second damage implementation.
var failures: Array[String] = []

func _check(condition: bool, id: String) -> void:
	if not condition:
		failures.append(id)
		print("PHYSICAL_STAGE_MATRIX_CASE=FAIL ", id)

func _init() -> void:
	_defence_priority()
	_critical_before_armour()
	_v12_chance_diminishing()
	_v12_active_effects_affect_combat()
	_typed_and_flat_penetration()
	_v12_armour_diminishing()
	_event_lineage_and_read_only_projection()
	print("PHYSICAL_STAGE_MATRIX_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _scenario(settings: Dictionary = {}) -> Dictionary:
	var state := CombatState.new()
	var test_level := int(settings.get("level",10))
	var actor := TestFixtureLoader.new_combatant("matrix_actor", "Attacker", test_level, 1000)
	var victim := TestFixtureLoader.new_combatant("matrix_victim", "Defender", test_level, 1000)
	actor.combat_stats["crit_chance_rating_percent"] = float(settings.get("crit", 0.0))
	actor.combat_stats["anti_dodge_rating_percent"] = float(settings.get("anti_dodge", 0.0))
	actor.combat_stats["block_crush"] = float(settings.get("crush", 0.0))
	actor.combat_stats["armour_penetration_percent"] = float(settings.get("general_pen", 0.0))
	actor.combat_stats["armour_penetration_flat"] = float(settings.get("flat_pen", 0.0))
	if float(settings.get("typed_pen", 0.0)) > 0.0:
		var totals: Dictionary = actor.combat_stats.get("par_totals", {})
		totals["PAR132"] = float(settings["typed_pen"])
		actor.combat_stats["par_totals"] = totals
	victim.combat_stats["dodge_rating_percent"] = float(settings.get("dodge", 0.0))
	victim.combat_stats["anti_crit_rating_percent"] = float(settings.get("anti_crit", 0.0))
	victim.combat_stats["shield_auto_block_rating_percent"] = float(settings.get("auto", 0.0))
	victim.combat_stats["manual_block_zones"] = ["chest"] if bool(settings.get("manual", false)) else []
	if settings.has("actor_effect"):
		actor.active_effects.append({
			"effect_id":"EFF_ACTIVE_ATTACKER","definition":Dictionary(settings["actor_effect"]),
			"start_round":int(settings.get("effect_start_round",1)),
			"remaining_rounds":2,"revealed":true
		})
	if settings.has("victim_effect"):
		victim.active_effects.append({
			"effect_id":"EFF_ACTIVE_DEFENDER","definition":Dictionary(settings["victim_effect"]),
			"start_round":int(settings.get("effect_start_round",1)),
			"remaining_rounds":2,"revealed":true
		})
	var physical_type := String(settings.get("damage_type", "slashing"))
	var zone_armour: Dictionary = {}
	zone_armour[physical_type] = float(settings.get("armour", 0.0))
	victim.armour["chest"] = zone_armour
	state.add_combatant(actor)
	state.add_combatant(victim)
	state.begin_round()
	var rolls: Dictionary = {
		"hit": int(settings.get("hit_roll", 1)),
		"reaction": 100, "dodge": int(settings.get("dodge_roll",1)), "auto_block": int(settings.get("auto_roll",1)),
		"block_crush": 1, "crit": int(settings.get("crit_roll",1)),
		"on_hit_effect": 100, "manual_block_effect": 100,
		"damage": 0.5
	}
	var attack := state.create_event(CombatEvent.Kind.ATTACK, "matrix_actor", "matrix_victim", {
		"raw_damage": 100.0, "damage_type": physical_type,
		"zone": "chest", "rolls": rolls, "is_weapon_attack": false
	})
	state.queue_event(attack)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	engine.resolve_pending_events()
	return {"state": state, "attack": attack, "actor": actor, "victim": victim}

func _defence_priority() -> void:
	var miss := _scenario({"hit_roll": 100, "dodge": 100.0, "manual": true, "auto": 100.0})
	_check(String((miss["attack"] as CombatEvent).result.get("outcome", "")) == "miss", "hit_precedes_defences")
	var dodge := _scenario({"dodge": 100.0, "manual": true, "auto": 100.0})
	_check(String((dodge["attack"] as CombatEvent).result.get("outcome", "")) == "dodge", "dodge_precedes_blocks")
	var manual := _scenario({"manual": true, "auto": 100.0})
	_check(String((manual["attack"] as CombatEvent).result.get("outcome", "")) == "manual_block", "manual_precedes_auto")
	var auto_block := _scenario({"auto": 100.0})
	_check(String((auto_block["attack"] as CombatEvent).result.get("outcome", "")) == "auto_block", "shield_auto_block")
	var crushed := _scenario({"manual": true, "auto": 100.0, "crush": 100.0})
	var crushed_event: CombatEvent = crushed["attack"]
	_check(String(crushed_event.result.get("outcome", "")) == "connected", "crush_passes_both_blocks")
	_check(bool(crushed_event.result.get("manual_block_crushed", false)) and bool(crushed_event.result.get("auto_block_crushed", false)), "crush_reports_both_defences")
	for entry in [miss, dodge, manual, auto_block]:
		var victim: CombatantState = entry["victim"]
		_check(victim.hp == 1000, "blocked_or_avoided_undamaged_" + String((entry["attack"] as CombatEvent).result.get("outcome", "")))

func _critical_before_armour() -> void:
	var plain := _scenario({"armour": 35.0})
	var critical := _scenario({"armour": 35.0, "crit": 100.0})
	var normal_event: CombatEvent = plain["attack"]
	var crit_event: CombatEvent = critical["attack"]
	_check(String(normal_event.result.get("outcome", "")) == "connected", "normal_hit_connected")
	_check(String(crit_event.result.get("outcome", "")) == "connected", "critical_hit_connected")
	_check(not bool(normal_event.result.get("critical", true)) and bool(crit_event.result.get("critical", false)), "critical_roll_control")
	_check(is_equal_approx(float(crit_event.result.get("raw_damage", 0.0)), 1.5 * float(normal_event.result.get("raw_damage", 0.0))), "critical_before_mitigation")
	_check(float(crit_event.result.get("after_armour_damage", 0.0)) > float(normal_event.result.get("after_armour_damage", 0.0)), "crit_survives_armour")

func _v12_chance_diminishing() -> void:
	# Independent approved v1.2 numerical anchors, before probability rolls.
	_check(absf(CombatMath.effective_dodge(50.0,20.0)-28.984671)<0.001,"dodge_anti_before_dr")
	_check(absf(CombatMath.effective_crit(50.0,10.0)-38.489634)<0.001,"crit_anti_before_dr")
	_check(absf(CombatRatingCurves.diminishing(50.0,"block")-43.939486)<0.001,"block_v12_dr")
	_check(is_equal_approx(CombatMath.effective_dodge(15.0,0.0),15.0),"dodge_no_dr_below_threshold")
	_check(is_equal_approx(CombatMath.effective_crit(20.0,0.0),20.0),"crit_no_dr_at_threshold")
	_check(is_equal_approx(CombatRatingCurves.diminishing(20.0,"block"),20.0),"block_no_dr_at_threshold")
	_check(CombatMath.effective_dodge(10000.0,0.0)<80.0,"dodge_asymptotic_cap")
	_check(CombatMath.effective_crit(10000.0,0.0)<100.0,"crit_asymptotic_cap")
	_check(CombatRatingCurves.diminishing(10000.0,"block")<75.0,"block_asymptotic_cap")
	# Defences must use the post-counter, post-DR chance in real CombatEngine.
	var dodge_28 := _scenario({"dodge":50.0,"anti_dodge":20.0,"dodge_roll":28})
	var dodge_29 := _scenario({"dodge":50.0,"anti_dodge":20.0,"dodge_roll":29})
	_check(String((dodge_28["attack"] as CombatEvent).result.get("outcome",""))=="dodge","dodge_roll_below_post_dr")
	_check(String((dodge_29["attack"] as CombatEvent).result.get("outcome",""))=="connected","dodge_roll_above_post_dr")
	_check(absf(float((dodge_29["attack"] as CombatEvent).result.get("dodge_chance",-1.0))-28.984671)<0.001,"dodge_event_final_chance")
	var crit_38 := _scenario({"crit":50.0,"anti_crit":10.0,"crit_roll":38})
	var crit_39 := _scenario({"crit":50.0,"anti_crit":10.0,"crit_roll":39})
	_check(bool((crit_38["attack"] as CombatEvent).result.get("critical",false)),"crit_roll_below_post_dr")
	_check(not bool((crit_39["attack"] as CombatEvent).result.get("critical",true)),"crit_roll_above_post_dr")
	_check(absf(float((crit_39["attack"] as CombatEvent).result.get("crit_chance",-1.0))-38.489634)<0.001,"crit_event_final_chance")
	var block_43 := _scenario({"auto":50.0,"auto_roll":43})
	var block_44 := _scenario({"auto":50.0,"auto_roll":44})
	_check(String((block_43["attack"] as CombatEvent).result.get("outcome",""))=="auto_block","auto_block_roll_below_post_dr")
	_check(String((block_44["attack"] as CombatEvent).result.get("outcome",""))=="connected","auto_block_roll_above_post_dr")
	_check(absf(float((block_44["attack"] as CombatEvent).result.get("auto_block_chance",-1.0))-43.939486)<0.001,"auto_block_event_final_chance")
	# After negative anti-rating EFF, subtraction still occurs before DR.
	_check(absf(CombatMath.effective_dodge(20.0,-5.0)-CombatRatingCurves.diminishing(25.0,"dodge"))<0.001,"negative_anti_dodge_effect")

func _v12_active_effects_affect_combat() -> void:
	# A real EFF with temporary dodge affects CombatEngine and the readout
	# equally. A pending EFF is excluded from BOTH until its start round.
	var with_dodge := _scenario({
		"dodge":20.0,"dodge_roll":40,
		"victim_effect":{"dodge_direct_pct":40.0},"effect_start_round":1
	})
	var pending_dodge := _scenario({
		"dodge":20.0,"dodge_roll":40,
		"victim_effect":{"dodge_direct_pct":40.0},"effect_start_round":2
	})
	var dodge_event: CombatEvent = with_dodge["attack"]
	var pending_event: CombatEvent = pending_dodge["attack"]
	var defender: CombatantState = with_dodge["victim"]
	var display := CombatModifierService.combat_readout(defender,1)
	_check(String(dodge_event.result.get("outcome",""))=="dodge","active_eff_changes_actual_dodge_outcome")
	_check(String(pending_event.result.get("outcome",""))=="connected","pending_eff_not_applied_early")
	_check(is_equal_approx(float(dodge_event.result.get("dodge_chance",-1.0)),float(display.get("dodge_after_dr_pct",-2.0))),"dodge_ui_matches_actual_roll_chance")
	var with_crit := _scenario({
		"crit":20.0,"crit_roll":40,
		"actor_effect":{"crit_chance_direct_pct":40.0},"effect_start_round":1
	})
	var pending_crit := _scenario({
		"crit":20.0,"crit_roll":40,
		"actor_effect":{"crit_chance_direct_pct":40.0},"effect_start_round":2
	})
	var crit_event: CombatEvent = with_crit["attack"]
	var pending_crit_event: CombatEvent = pending_crit["attack"]
	var attacker: CombatantState = with_crit["actor"]
	var crit_display := CombatModifierService.combat_readout(attacker,1)
	_check(bool(crit_event.result.get("critical",false)),"active_eff_changes_actual_crit_outcome")
	_check(not bool(pending_crit_event.result.get("critical",true)),"pending_crit_eff_not_applied_early")
	_check(is_equal_approx(float(crit_event.result.get("crit_chance",-1.0)),float(crit_display.get("crit_after_dr_pct",-2.0))),"crit_ui_matches_actual_roll_chance")

func _typed_and_flat_penetration() -> void:
	var baseline := _scenario({"armour": 35.0})
	var penetrated := _scenario({"armour": 35.0, "general_pen": 20.0, "typed_pen": 50.0, "flat_pen": 10.0})
	var base: CombatEvent = baseline["attack"]
	var hit: CombatEvent = penetrated["attack"]
	_check(String(hit.result.get("outcome", "")) == "connected", "penetration_hit_connected")
	_check(is_equal_approx(float(hit.result.get("base_armour", -1.0)), 35.0), "canonical_zone_armour")
	_check(is_equal_approx(float(hit.result.get("armour_penetration_percent", -1.0)), 0.2), "par126_percentage_points")
	_check(is_equal_approx(float(hit.result.get("typed_armour_penetration_percent", -1.0)), 0.5), "par132_only_slashing")
	_check(is_equal_approx(float(hit.result.get("effective_armour", -1.0)), 10.0), "flat_pen_before_general_and_typed")
	_check(is_equal_approx(float(hit.result.get("armour_penetration_flat", -1.0)), 10.0), "flat_penetration_rating")
	_check(float(hit.result.get("armour_reduction", 1.0)) < float(base.result.get("armour_reduction", 0.0)), "penetration_reduces_mitigation")
	_check(float(hit.result.get("after_armour_damage", 0.0)) > float(base.result.get("after_armour_damage", 0.0)), "penetration_increases_resolved_damage")
	# PAR132 is slashing-only: the same item rating must not penetrate piercing.
	var other_type := _scenario({"armour": 35.0, "typed_pen": 50.0, "damage_type": "piercing"})
	var piercing_hit: CombatEvent = other_type["attack"]
	_check(String(piercing_hit.result.get("outcome", "")) == "connected", "other_physical_type_connected")
	_check(is_zero_approx(float(piercing_hit.result.get("typed_armour_penetration_percent", -1.0))), "par132_does_not_affect_piercing")
	_check(is_equal_approx(float(piercing_hit.result.get("effective_armour", -1.0)), 35.0), "wrong_type_keeps_armour")

func _v12_armour_diminishing() -> void:
	# End-to-end engine test at both generator v1.2 armour anchor levels.
	var lv1 := _scenario({"level":1,"armour":80.0})
	var lv100 := _scenario({"level":100,"armour":320.0})
	for scenario in [lv1,lv100]:
		var hit: CombatEvent = scenario["attack"]
		_check(String(hit.result.get("outcome",""))=="connected","v12_armour_hit_connected")
		_check(is_equal_approx(float(hit.result.get("armour_raw_percent",-1.0)),40.0),"v12_armour_raw40")
		_check(absf(float(hit.result.get("armour_reduction",-1.0))*100.0-39.515635)<0.01,"v12_armour_diminishing40")
		_check((scenario["victim"] as CombatantState).hp == 940,"v12_armour_damage60")
	var heavy := _scenario({"level":1,"armour":200.0})
	var reduced: float = float((heavy["attack"] as CombatEvent).result.get("armour_reduction",-1.0))
	_check(absf(reduced*100.0-68.707771)<0.01,"v12_armour_diminishing100")
	_check((heavy["victim"] as CombatantState).hp == 969,"v12_armour_no_full_immunity")
	_check(CombatRatingCurves.diminishing(10000.0,"armour") < 85.1,"v12_extreme_armour_stays_below_cap")

func _event_lineage_and_read_only_projection() -> void:
	var scenario := _scenario({"armour": 35.0, "general_pen": 20.0})
	var state: CombatState = scenario["state"]
	var attack: CombatEvent = scenario["attack"]
	var trace: Dictionary = CombatDiagnostics.round_trace(state, 1)
	_check(bool(trace.get("valid_event_lineage", false)), "diagnostic_lineage_valid")
	_check(int(trace.get("event_count", -1)) == state.event_log.size(), "diagnostic_event_count")
	_check(state.pending_events.is_empty(), "engine_queue_drained")
	var children := 0
	for logged in state.event_log:
		if logged.kind == CombatEvent.Kind.DAMAGE and logged.parent_event_id == attack.event_id:
			children += 1
			_check(int(logged.result.get("final_damage", -1)) == 1000 - (scenario["victim"] as CombatantState).hp, "damage_matches_hp_delta")
	_check(children == 1, "one_damage_child_per_connected_attack")
	var snapshot: Array = trace.get("events", [])
	if not snapshot.is_empty():
		var copied: Dictionary = snapshot[0]
		var copied_result: Dictionary = copied.get("result", {})
		copied_result["outcome"] = "tampered_test_projection"
		_check(String(attack.result.get("outcome", "")) == "connected", "diagnostics_does_not_alias_engine_result")
