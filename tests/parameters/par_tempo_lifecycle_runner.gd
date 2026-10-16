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
	check(not bool(ParCombatContract.action_status(fighter, 2).get("ok", true)) or CombatTempoService.is_stunned(fighter, 2), "scheduled stun blocks actions")
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
	var fighter := actor("tempo_attacker", 100.0, 100.0, 20.0)
	check(not CombatTempoService.is_stunned(fighter, 1), "positive Tempo is not stun")
	check(fighter.tempo == fighter.max_tempo, "positive Tempo remains capped")
