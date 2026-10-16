extends SceneTree

## ABI003 Fireball: 100 FIRE, 10 mana, one-round cooldown.
## EFF003: 10 FIRE damage per stack, 3 stacks max, ONE shared timer.
func _initialize() -> void:
	var definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	var abi: Dictionary = AbilityCatalog.definition(definitions, "ABI003")
	var eff: Dictionary = EffectCatalog.definition(effects, "EFF003")
	var ok := true
	ok = ok and String(abi.get("name", "")) == "Fireball"
	ok = ok and String(abi.get("delivery_type", "")) == "PROJECTILE"
	ok = ok and bool(abi.get("uses_magic_hit", false))
	ok = ok and int(abi.get("mana_cost", -1)) == 10
	ok = ok and int(abi.get("cooldown_rounds", -1)) == 1
	ok = ok and AbilityRuntime.validate_definition("ABI003", abi).is_empty()
	var components: Array = abi.get("components", [])
	ok = ok and components.size() == 2
	if components.size() == 2:
		ok = ok and String(Dictionary(components[0]).get("kind", "")) == "damage"
		ok = ok and float(Dictionary(components[0]).get("amount", -1.0)) == 100.0
		ok = ok and String(Dictionary(components[0]).get("damage_type", "")) == "fire"
		ok = ok and String(Dictionary(components[1]).get("kind", "")) == "effect"
		ok = ok and String(Dictionary(components[1]).get("effect_id", "")) == "EFF003"
	ok = ok and String(eff.get("kind", "")) == "dot"
	ok = ok and float(eff.get("damage", -1.0)) == 10.0
	ok = ok and String(eff.get("damage_type", "")) == "fire"
	ok = ok and int(eff.get("duration_rounds", 0)) == 3
	ok = ok and String(eff.get("stacking", "")) == "shared_duration"
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
	# Test-only predictable hit/crit values; canonical ABI has no hardcoded roll.
	var deterministic: Dictionary = abi.duplicate(true)
	deterministic["magic_hit_roll"] = 1
	deterministic["rolls"] = {"hit": 1, "crit": 100, "dodge": 100, "auto_block": 100}
	var scheduler := AbilityScheduler.new({"ABI003": deterministic}, {"caster": ["ABI003"]})

	# Casts on 1/3/5/7; attempts on 2/4/6/8 must fail due to cooldown.
	# Round 7 applies at the 3-stack cap and still REFRESHES the shared timer.
	var cast_rounds := [1, 3, 5, 7]
	var expected_hp := [900, 890, 770, 750, 620, 590, 460, 430, 400]
	var expected_mana := [90, 90, 80, 80, 70, 70, 60, 60, 60]
	var expected_stacks := [1, 1, 2, 2, 3, 3, 3, 3, 0]
	var expected_duration := [3, 2, 2, 1, 2, 1, 2, 1, 0]
	var expected_tick_damage := [0, 10, 20, 20, 30, 30, 30, 30, 30]
	for i in range(expected_hp.size()):
		var round_number := i + 1
		orchestrator.begin_round()
		var hp_before_cast := target.hp
		var mana_before_cast := caster.mana
		if round_number <= 8:
			var cast_event := scheduler.cast_event(state, "caster", "target", "ABI003")
			if cast_rounds.has(round_number):
				if cast_event == null:
					ok = false
					print("ABI003_CASE_FAIL=cast_rejected round=", round_number)
					break
				if int(cast_event.payload.get("magic_hit_roll", -1)) != 1:
					ok = false
				state.queue_event(cast_event)
				engine.resolve_pending_events()
				if target.hp != hp_before_cast - 100 or caster.mana != mana_before_cast - 10:
					ok = false
					print("ABI003_CASE_FAIL=base_or_mana round=", round_number, " hp=", target.hp, " mana=", caster.mana)
			else:
				if cast_event != null or caster.mana != mana_before_cast:
					ok = false
					print("ABI003_CASE_FAIL=cooldown round=", round_number)
			# One effect record per target, with ONE duration and stack counter.
			if target.active_effects.size() != 1:
				ok = false
				print("ABI003_CASE_FAIL=shared_record round=", round_number, " count=", target.active_effects.size())
		orchestrator.end_round()
		var actual_stacks := _burning_stacks(target)
		var actual_duration := _burning_duration(target)
		var tick_damage := _round_tick_damage(state, round_number)
		var round_ok := target.hp == expected_hp[i] and caster.mana == expected_mana[i] and actual_stacks == expected_stacks[i] and actual_duration == expected_duration[i] and tick_damage == expected_tick_damage[i]
		print("ABI003_ROUND=", round_number, " hp=", target.hp, " mana=", caster.mana, " stacks=", actual_stacks, " shared_duration=", actual_duration, " tick_damage=", tick_damage, " ok=", round_ok)
		ok = ok and round_ok

	# Insufficient mana never creates an event or starts the cooldown.
	orchestrator.begin_round()
	caster.mana = 9
	var rejected := scheduler.cast_event(state, "caster", "target", "ABI003")
	ok = ok and rejected == null and caster.mana == 9
	orchestrator.end_round()
	print("ABI003_FIREBALL_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

static func _burning_stacks(target: CombatantState) -> int:
	for record in target.active_effects:
		if String(record.get("effect_id", "")) == "EFF003":
			return int(record.get("stacks", 1))
	return 0

static func _burning_duration(target: CombatantState) -> int:
	for record in target.active_effects:
		if String(record.get("effect_id", "")) == "EFF003":
			return int(record.get("remaining_rounds", 0))
	return 0

static func _round_tick_damage(state: CombatState, round_number: int) -> int:
	var count := 0
	var total_damage := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and int(event.payload.get("round", -1)) == round_number and String(event.payload.get("effect_id", "")) == "EFF003":
			if String(event.payload.get("damage_type", "")) != "fire":
				return -1
			count += 1
			total_damage += int(event.result.get("final_damage", -1))
	# Only one DoT damage event each round, even with three stacks.
	if count > 1:
		return -1
	return total_damage
