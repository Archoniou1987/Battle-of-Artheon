class_name DuelSmokeCases
extends RefCounted

## Very small integration cases. These test engine behaviour, not balance.

static func run(balance: Dictionary) -> bool:
	return _equal_duel_finishes(balance) and _locked_actions_survive_death(balance) and _tempo_minus_100_cannot_attack(balance)


static func _equal_duel_finishes(balance: Dictionary) -> bool:
	var state := _make_state(30, 30, 10.0, 10.0)
	var result := CombatSimulator.new(state, balance, 42).run_duel("a", "b")
	return result.get("rounds", 0) > 0 and result.get("rounds", 0) <= 100 and result.get("outcome", "timeout") != "timeout"


static func _locked_actions_survive_death(balance: Dictionary) -> bool:
	var state := _make_state(10, 10, 50.0, 50.0)
	state.begin_round()
	var round := CombatRound.new(state.round_number)
	var a := state.create_event(CombatEvent.Kind.ATTACK, "a", "b", {"raw_damage": 50.0, "zone": "chest", "damage_type": "slashing", "rolls": {"hit": 1, "crit": 100}})
	var b := state.create_event(CombatEvent.Kind.ATTACK, "b", "a", {"raw_damage": 50.0, "zone": "chest", "damage_type": "slashing", "rolls": {"hit": 1, "crit": 100}})
	round.lock_action(a)
	round.lock_action(b)
	round.resolve(CombatEngine.new(state, balance))
	return not state.get_combatant("a").is_alive() and not state.get_combatant("b").is_alive()


static func _tempo_minus_100_cannot_attack(balance: Dictionary) -> bool:
	var state := _make_state(30, 30, 10.0, 10.0)
	state.get_combatant("a").tempo = -100.0
	var simulator := CombatSimulator.new(state, balance, 7)
	simulator.max_rounds = 1
	simulator.run_duel("a", "b")
	var attacks_from_a := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "a":
			attacks_from_a += 1
	return attacks_from_a == 0


static func _make_state(hp_a: int, hp_b: int, damage_a: float, damage_b: float) -> CombatState:
	var state := CombatState.new()
	var a := CombatantState.new("a", "A", 1, hp_a)
	var b := CombatantState.new("b", "B", 1, hp_b)
	a.combat_stats["main_hand_damage"] = damage_a
	b.combat_stats["main_hand_damage"] = damage_b
	state.add_combatant(a)
	state.add_combatant(b)
	return state
