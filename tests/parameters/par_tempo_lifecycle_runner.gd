extends SceneTree

var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)

func actor(name: String, starting: float, cap: float, regen: float) -> CombatantState:
	var value := CombatantState.new(name, name, 1, 100, 30)
	CombatTempoService.initialize(value, starting, cap, regen)
	return value

func _initialize() -> void:
	stun_and_debt()
	immune_accumulation()
	positive_regeneration_cap()
	death_prevents_tempo()
	par_character_and_npc_adapters()
	no_extra_attack_from_positive_tempo()
	for failure in failures:
		push_error("PAR_TEMPO: " + failure)
	print("PAR_TEMPO_LIFECYCLE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func stun_and_debt() -> void:
	var fighter := actor("tempo_debt", 60.0, 100.0, 10.0)
	var state := CombatState.new()
	state.add_combatant(fighter)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(state))
	var round := orchestrator.begin_round()
	check(state.round_number == 1 and is_equal_approx(fighter.tempo, 70.0), "PAR021 at round opening")
	CombatTempoService.apply_control(fighter, 300.0)
	check(is_equal_approx(fighter.tempo, -230.0), "strong control debt accumulates")
	check(not CombatTempoService.is_stunned(fighter, 1), "control does not instantly stun in same round")
	orchestrator.resolve_locked_actions(round)
	orchestrator.end_round()
	check(fighter.tempo_stun_round == 2 and is_equal_approx(fighter.tempo, -130.0), "end round threshold schedules stun and repays exactly 100")
	orchestrator.begin_round()
	check(CombatTempoService.is_stunned(fighter, 2), "stun starts one full next round")
	check(is_equal_approx(fighter.tempo, -120.0), "PAR021 works even during stun")
	check(CombatTempoService.is_stunned(fighter, 2), "scheduled stun blocks the next round")
	orchestrator.end_round()
	check(is_equal_approx(fighter.tempo, -90.0), "50 percent base rebound only at stunned round end")
	check(fighter.tempo_immunity_until_round == 4, "two immune rounds after stun")
	orchestrator.begin_round()
	check(CombatTempoService.is_immune(fighter, 3) and not CombatTempoService.is_stunned(fighter, 3), "immune round one")
	CombatTempoService.apply_control(fighter, 500.0)
	check(is_equal_approx(fighter.tempo, -580.0), "control applies even when immune")
	orchestrator.end_round()
	check(fighter.tempo_stun_round == 2 and is_equal_approx(fighter.tempo, -580.0), "immunity blocks stun, payment and rebound")
	orchestrator.begin_round()
	check(CombatTempoService.is_immune(fighter, 4), "immune round two")
	orchestrator.end_round()
	check(fighter.tempo_stun_round == 2, "stun remains blocked through entire second immune round")
	orchestrator.begin_round()
	check(not CombatTempoService.is_immune(fighter, 5), "immunity expires before fifth round")
	orchestrator.end_round()
	check(fighter.tempo_stun_round == 6, "fresh stun scheduled only at end of nonimmune round")

func immune_accumulation() -> void:
	var fighter := actor("immunity", 0.0, 100.0, 0.0)
	var state := CombatState.new()
	state.add_combatant(fighter)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(state))
	orchestrator.begin_round()
	CombatTempoService.apply_control(fighter, 500.0)
	orchestrator.end_round()
	check(is_equal_approx(fighter.tempo, -400.0), "control below -100 is not discarded")
	orchestrator.begin_round()
	CombatTempoService.apply_control(fighter, 200.0)
	orchestrator.end_round()
	check(is_equal_approx(fighter.tempo, -600.0), "stunned round still accepts incoming control")
	check(CombatTempoService.is_immune(fighter, 3), "immunity begins after stunned round")

func positive_regeneration_cap() -> void:
	var fighter := actor("cap", 60.0, 100.0, 15.0)
	var state := CombatState.new()
	state.add_combatant(fighter)
	for round_id in range(10):
		state.begin_round()
		CombatTempoService.begin_round(state)
	check(is_equal_approx(fighter.tempo, 100.0), "PAR021 never exceeds PAR020")
	CombatTempoService.apply_control(fighter, 110.0)
	check(is_equal_approx(fighter.tempo, -10.0), "damage reduces positive Tempo")
	state.begin_round()
	CombatTempoService.begin_round(state)
	check(is_equal_approx(fighter.tempo, 5.0), "PAR021 can recover across zero")
	CombatTempoService.apply_control(fighter, 300.0)
	check(fighter.tempo < -100.0, "negative Tempo unbounded")

func death_prevents_tempo() -> void:
	var fighter := actor("dead", 60.0, 100.0, 20.0)
	fighter.hp = 0
	var state := CombatState.new()
	state.add_combatant(fighter)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(state))
	orchestrator.begin_round()
	check(is_equal_approx(fighter.tempo, 60.0), "no PAR021 on zero HP")
	CombatTempoService.apply_control(fighter, 500.0)
	orchestrator.end_round()
	check(fighter.is_death_finalized() and fighter.tempo_stun_round == -1, "death finalization precedes stun check")

func no_extra_attack_from_positive_tempo() -> void:
	var attacker := TestFixtureLoader.new_combatant("tempo_attacker", "Tempo attacker", 1, 1000)
	var defender := TestFixtureLoader.new_combatant("tempo_defender", "Tempo defender", 1, 1000)
	TestFixtureLoader.set_weapon_profiles(attacker, [{"damage_min":3.0,"damage_max":3.0,"damage_type":"slashing"}])
	CombatTempoService.initialize(attacker, 100.0, 100.0, 20.0)
	var state := CombatState.new()
	state.add_combatant(attacker)
	state.add_combatant(defender)
	var pipeline := CombatAttackPipeline.new(state, 42)
	var round := CombatRound.new(1)
	state.begin_round()
	pipeline.lock_basic_attack(round, attacker, defender)
	var extras := 0
	for event in round.locked_actions:
		if bool(event.payload.get("is_extra_attack", false)):
			extras += 1
	check(round.locked_actions.size() == 1 and extras == 0, "positive Tempo never generates extra base attacks")

func par_character_and_npc_adapters() -> void:
	var hero := CharacterState.new("tempo_par_hero", "Tempo hero")
	var repository := ItemRepository.new()
	var item := {"instance_id":"tempo_par_ring","equip_slots":["ring1"],"slot_usage":["ring1"],"par_stats":{"PAR019":60.0,"PAR020":20.0,"PAR021":10.0}}
	ItemDurabilityService.initialize_item(item, 100)
	check(repository.add_item(item) and hero.receive_item("tempo_par_ring", repository) and hero.equip("ring1", "tempo_par_ring", repository), "equip Tempo PAR ring")
	var par := ParCalculationService.calculate(hero, repository)
	check(is_equal_approx(float(Dictionary(par.get("totals", {})).get("PAR020", -1)), 120.0), "PAR020 baseline 100 plus equipment bonus")
	var fighter := CharacterCombatBuilder.build(hero, repository)
	check(fighter != null, "Tempo CharacterCombatBuilder")
	if fighter != null:
		check(is_equal_approx(fighter.base_tempo, 60.0), "PAR019 is initial Tempo")
		check(is_equal_approx(fighter.max_tempo, 120.0), "PAR020 is runtime positive cap")
		check(is_equal_approx(fighter.tempo_regen, 10.0), "PAR021 is fixed per-round recovery")
		check(is_equal_approx(fighter.tempo, 60.0), "starting current Tempo matches PAR019")
	var npc_totals := {"PAR052":0.0,"PAR057":1.0,"PAR073":1.0,"PAR019":35.0,"PAR020":140.0,"PAR021":7.0}
	for par_id in ParCombatContract.RATINGS:
		npc_totals[par_id] = 0.0
	var npc := NpcState.new({
		"id":"tempo_par_npc", "name":"Tempo NPC", "level":1,
		"base":{
			"health":100, "mana":40,
			"par_totals":npc_totals,
			"par_attack_ranges":{"PAR050":{"min":2.0,"max":4.0,"type":"blunt"}},
			"combat_stats":{"weapon_profiles":[{"slot":"main_hand","damage_min":2.0,"damage_max":4.0,"damage_type":"blunt"}]}
		}
	})
	var enemy := NpcCombatBuilder.build(npc)
	check(enemy != null, "Tempo NpcCombatBuilder")
	if enemy != null:
		check(is_equal_approx(enemy.base_tempo, 35.0) and is_equal_approx(enemy.tempo, 35.0), "NPC PAR019 initializes current/base Tempo")
		check(is_equal_approx(enemy.max_tempo, 140.0) and is_equal_approx(enemy.tempo_regen, 7.0), "NPC PAR020/PAR021 parity")
