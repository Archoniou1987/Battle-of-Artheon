extends SceneTree

## Canonical ABI003 Fireball + EFF003 Burning integration.
## All 100-damage values are test baselines, NOT the final balance.
## EFF003 is 10 FIRE damage per active stack per round for 3 rounds.
func _initialize() -> void:
	var definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	var abi: Dictionary = AbilityCatalog.definition(definitions, "ABI003")
	var eff: Dictionary = EffectCatalog.definition(effects, "EFF003")
	var ok := true
	ok = ok and abi.get("name", "") == "Fireball"
	ok = ok and String(abi.get("delivery_type", "")) == "PROJECTILE"
	ok = ok and bool(abi.get("uses_magic_hit", false))
	ok = ok and AbilityRuntime.validate_definition("ABI003", abi).is_empty()
	ok = ok and Array(abi.get("components", [])).size() == 2
	ok = ok and float(Dictionary(abi["components"][0]).get("amount", -1.0)) == 100.0
	ok = ok and String(Dictionary(abi["components"][0]).get("damage_type", "")) == "fire"
	ok = ok and String(Dictionary(abi["components"][1]).get("effect_id", "")) == "EFF003"
	ok = ok and String(eff.get("kind", "")) == "dot"
	ok = ok and float(eff.get("damage", -1.0)) == 10.0
	ok = ok and String(eff.get("damage_type", "")) == "fire"
	ok = ok and int(eff.get("duration_rounds", 0)) == 3
	ok = ok and String(eff.get("stacking", "")) == "stack"
	ok = ok and int(eff.get("max_stacks", 0)) == 3
	if not ok:
		print("ABI003_FIREBALL_TEST=FAIL invalid_catalog")
		quit(1)
		return

	var state := CombatState.new()
	var caster := TestFixtureLoader.new_combatant("caster", "Caster", 1, 1000, 100)
	var target := TestFixtureLoader.new_combatant("target", "Target", 1, 1000, 0)
	caster.combat_stats["magic_damage_rating_percent"] = 0.0
	caster.combat_stats["crit_chance_rating_percent"] = 0.0
	caster.combat_stats["hit_chance_rating_percent"] = 100.0
	state.add_combatant(caster)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	engine.combat_rng.seed = 303
	var orchestrator := RoundOrchestrator.new(state, engine)
	# Explicit deterministic rolls here; production ABI003 has NO hardcoded roll.
	var deterministic: Dictionary = abi.duplicate(true)
	deterministic["magic_hit_roll"] = 1
	deterministic["rolls"] = {"hit": 1, "crit": 100, "dodge": 100, "auto_block": 100}
	var scheduler := AbilityScheduler.new({"ABI003": deterministic}, {"caster": ["ABI003"]})

	# Round 1: 100; round 2: 100 + 10; round 3: 100 + 20;
	# round 4: fourth application is capped, 100 + 30;
	# rounds 5/6: the independently expiring stacks tick 20, then 10.
	var expected_hp := [900, 790, 670, 540, 520, 510]
	var expected_stacks := [1, 2, 3, 2, 1, 0]
	var expected_tick_counts := [0, 1, 2, 3, 2, 1]
	for round_index in range(6):
		var current_round := round_index + 1
		orchestrator.begin_round()
		var before_cast_hp := target.hp
		if current_round <= 4:
			var event := scheduler.cast_event(state, "caster", "target", "ABI003")
			if event == null:
				ok = false
				print("ABI003_CASE_FAIL=cast round=", current_round)
				break
			if int(event.payload.get("magic_hit_roll", -1)) != 1:
				ok = false
			state.queue_event(event)
			engine.resolve_pending_events()
			if target.hp != before_cast_hp - 100:
				ok = false
				print("ABI003_CASE_FAIL=base_damage round=", current_round, " hp=", target.hp)
			var pre_tick_stacks := _burning_stacks(target)
			if pre_tick_stacks != mini(3, current_round):
				ok = false
				print("ABI003_CASE_FAIL=stack_cap round=", current_round, " stacks=", pre_tick_stacks)
		else:
			if target.hp != before_cast_hp:
				ok = false
		orchestrator.end_round()
		var actual_stacks := _burning_stacks(target)
		var tick_count := _round_ticks(state, current_round)
		var this_round_ok := target.hp == expected_hp[round_index] and actual_stacks == expected_stacks[round_index] and tick_count == expected_tick_counts[round_index]
		print("ABI003_ROUND=", current_round, " hp=", target.hp, " expected_hp=", expected_hp[round_index], " stacks=", actual_stacks, " ticks=", tick_count, " ok=", this_round_ok)
		ok = ok and this_round_ok
	ok = ok and caster.mana == 100 # Mana cost is pending PAR018/balance approval.
	print("ABI003_FIREBALL_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

static func _burning_stacks(target: CombatantState) -> int:
	var count := 0
	for record in target.active_effects:
		if String(record.get("effect_id", "")) == "EFF003":
			count += 1
	return count

static func _round_ticks(state: CombatState, round_number: int) -> int:
	var count := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and int(event.payload.get("round", -1)) == round_number and String(event.payload.get("effect_id", "")) == "EFF003":
			if String(event.payload.get("damage_type", "")) != "fire" or int(event.result.get("final_damage", -1)) != 10:
				return -1
			count += 1
	return count
