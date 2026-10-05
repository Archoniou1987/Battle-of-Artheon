class_name CombatSimulator
extends RefCounted

const HIT_ZONES := ["head", "chest", "arms", "waist", "legs"]

## Minimal duel runner for deterministic and later Monte Carlo simulations.

var state: CombatState
var engine: CombatEngine
var rng := RandomNumberGenerator.new()
var max_rounds: int = 100


func _init(combat_state: CombatState, balance: Dictionary = {}, seed_value: int = 1) -> void:
	state = combat_state
	engine = CombatEngine.new(state, balance)
	rng.seed = seed_value


func run_duel(first_id: String, second_id: String) -> Dictionary:
	while _both_alive(first_id, second_id) and state.round_number < max_rounds:
		_run_round(first_id, second_id)

	var first := state.get_combatant(first_id)
	var second := state.get_combatant(second_id)
	var outcome := "timeout"
	if not first.is_alive() and not second.is_alive():
		outcome = "draw"
	elif first.is_alive() and not second.is_alive():
		outcome = first_id
	elif second.is_alive() and not first.is_alive():
		outcome = second_id

	return {
		"outcome": outcome,
		"rounds": state.round_number,
		"first_hp": first.hp,
		"second_hp": second.hp,
		"events": state.event_log.size()
	}


func _run_round(first_id: String, second_id: String) -> void:
	state.begin_round()
	var round := CombatRound.new(state.round_number)
	var first := state.get_combatant(first_id)
	var second := state.get_combatant(second_id)

	_lock_basic_attack(round, first, second)
	_lock_basic_attack(round, second, first)
	round.resolve(engine)


func _lock_basic_attack(round: CombatRound, attacker: CombatantState, defender: CombatantState) -> void:
	if not attacker.is_alive():
		return
	if not _tempo_allows_attack(attacker.tempo):
		return

	round.lock_action(_make_basic_attack(attacker, defender, false))
	if attacker.tempo > 0.0 and CombatMath.roll_success(minf(attacker.tempo, 100.0), _roll()):
		round.lock_action(_make_basic_attack(attacker, defender, true))


func _make_basic_attack(attacker: CombatantState, defender: CombatantState, extra: bool) -> CombatEvent:
	return state.create_event(
		CombatEvent.Kind.ATTACK,
		attacker.combatant_id,
		defender.combatant_id,
		{
			"raw_damage": _weapon_damage(attacker),
			"zone": HIT_ZONES[rng.randi_range(0, HIT_ZONES.size() - 1)],
			"damage_type": String(attacker.combat_stats.get("main_hand_damage_type", "slashing")),
			"rolls": _attack_rolls(),
			"is_extra_attack": extra,
			"generates_ap": not extra
		}
	)


func _weapon_damage(attacker: CombatantState) -> float:
	var minimum := float(attacker.combat_stats.get("main_hand_damage_min", attacker.combat_stats.get("main_hand_damage", 1.0)))
	var maximum := float(attacker.combat_stats.get("main_hand_damage_max", attacker.combat_stats.get("main_hand_damage", minimum)))
	if maximum < minimum:
		var swap := minimum
		minimum = maximum
		maximum = swap
	return rng.randf_range(minimum, maximum)


func _tempo_allows_attack(tempo: float) -> bool:
	if tempo <= -100.0:
		return false
	if tempo >= 0.0:
		return true
	return CombatMath.roll_success(100.0 + tempo, _roll())


func _attack_rolls() -> Dictionary:
	return {
		"hit": _roll(),
		"reaction": _roll(),
		"dodge": _roll(),
		"auto_block": _roll(),
		"block_crush": _roll(),
		"crit": _roll(),
		"counterattack": _roll(),
		"counterattack_rolls": {
			"hit": _roll(), "reaction": _roll(), "dodge": _roll(),
			"auto_block": _roll(), "block_crush": _roll(), "crit": _roll()
		}
	}


func _roll() -> int:
	return rng.randi_range(1, 100)


func _both_alive(first_id: String, second_id: String) -> bool:
	return state.get_combatant(first_id).is_alive() and state.get_combatant(second_id).is_alive()
