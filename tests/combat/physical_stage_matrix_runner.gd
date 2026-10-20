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
	_typed_and_flat_penetration()
	_event_lineage_and_read_only_projection()
	print("PHYSICAL_STAGE_MATRIX_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _scenario(settings: Dictionary = {}) -> Dictionary:
	var state := CombatState.new()
	var actor := TestFixtureLoader.new_combatant("matrix_actor", "Attacker", 10, 1000)
	var victim := TestFixtureLoader.new_combatant("matrix_victim", "Defender", 10, 1000)
	actor.combat_stats["crit_chance_rating_percent"] = float(settings.get("crit", 0.0))
	actor.combat_stats["block_crush"] = float(settings.get("crush", 0.0))
	actor.combat_stats["armour_penetration_percent"] = float(settings.get("general_pen", 0.0))
	actor.combat_stats["armour_penetration_flat"] = float(settings.get("flat_pen", 0.0))
	if float(settings.get("typed_pen", 0.0)) > 0.0:
		var totals: Dictionary = actor.combat_stats.get("par_totals", {})
		totals["PAR132"] = float(settings["typed_pen"])
		actor.combat_stats["par_totals"] = totals
	victim.combat_stats["dodge_rating_percent"] = float(settings.get("dodge", 0.0))
	victim.combat_stats["shield_auto_block_rating_percent"] = float(settings.get("auto", 0.0))
	victim.combat_stats["manual_block_zones"] = ["chest"] if bool(settings.get("manual", false)) else []
	var physical_type := String(settings.get("damage_type", "slashing"))
	victim.armour["chest"] = {physical_type: float(settings.get("armour", 0.0))}
	state.add_combatant(actor)
	state.add_combatant(victim)
	state.begin_round()
	var rolls: Dictionary = {
		"hit": int(settings.get("hit_roll", 1)),
		"reaction": 100, "dodge": 1, "auto_block": 1,
		"block_crush": 1, "crit": 1, "counterattack": 100,
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

func _typed_and_flat_penetration() -> void:
	var baseline := _scenario({"armour": 35.0})
	var penetrated := _scenario({"armour": 35.0, "general_pen": 20.0, "typed_pen": 50.0, "flat_pen": 10.0})
	var base: CombatEvent = baseline["attack"]
	var hit: CombatEvent = penetrated["attack"]
	_check(String(hit.result.get("outcome", "")) == "connected", "penetration_hit_connected")
	_check(is_equal_approx(float(hit.result.get("base_armour", -1.0)), 35.0), "canonical_zone_armour")
	_check(is_equal_approx(float(hit.result.get("armour_penetration_percent", -1.0)), 0.2), "par126_percentage_points")
	_check(is_equal_approx(float(hit.result.get("typed_armour_penetration_percent", -1.0)), 0.5), "par132_only_slashing")
	_check(is_equal_approx(float(hit.result.get("effective_armour", -1.0)), 14.0), "sequential_general_typed_armour")
	_check(is_equal_approx(float(hit.result.get("armour_penetration_flat", -1.0)), 10.0), "flat_penetration_rating")
	_check(float(hit.result.get("armour_reduction", 1.0)) < float(base.result.get("armour_reduction", 0.0)), "penetration_reduces_mitigation")
	_check(float(hit.result.get("after_armour_damage", 0.0)) > float(base.result.get("after_armour_damage", 0.0)), "penetration_increases_resolved_damage")
	# PAR132 is slashing-only: the same item rating must not penetrate piercing.
	var other_type := _scenario({"armour": 35.0, "typed_pen": 50.0, "damage_type": "piercing"})
	var piercing_hit: CombatEvent = other_type["attack"]
	_check(String(piercing_hit.result.get("outcome", "")) == "connected", "other_physical_type_connected")
	_check(is_zero_approx(float(piercing_hit.result.get("typed_armour_penetration_percent", -1.0))), "par132_does_not_affect_piercing")
	_check(is_equal_approx(float(piercing_hit.result.get("effective_armour", -1.0)), 35.0), "wrong_type_keeps_armour")

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
