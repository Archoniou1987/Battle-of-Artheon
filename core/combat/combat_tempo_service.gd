class_name CombatTempoService
extends RefCounted

## PAR019–021: finite positive pool, unlimited negative control debt.
## Threshold is evaluated only after the round's actions and death finalization.
const STUN_THRESHOLD := -100.0
const STUN_DEBT_PAYMENT := 100.0
const IMMUNITY_ROUNDS := 2

static func initialize(combatant: CombatantState, starting_tempo: float, maximum: float, regen: float) -> void:
	combatant.base_tempo = maxf(0.0, starting_tempo)
	combatant.max_tempo = maxf(0.0, maximum)
	combatant.tempo_regen = maxf(0.0, regen)
	combatant.tempo = clampf(combatant.base_tempo, 0.0, combatant.max_tempo)
	combatant.tempo_stun_round = -1
	combatant.tempo_immunity_until_round = 0

static func is_stunned(combatant: CombatantState, round_number: int) -> bool:
	return combatant != null and combatant.tempo_stun_round == round_number

static func is_immune(combatant: CombatantState, round_number: int) -> bool:
	return combatant != null and round_number > combatant.tempo_stun_round and round_number <= combatant.tempo_immunity_until_round

## All incoming negative Tempo applies even during stun immunity.
static func apply_control(combatant: CombatantState, amount: float) -> void:
	if combatant == null or not is_finite(amount):
		return
	combatant.tempo = minf(combatant.max_tempo, combatant.tempo - maxf(0.0, amount))

static func begin_round(state: CombatState) -> void:
	for combatant in state.combatants.values():
		if combatant == null or combatant.hp <= 0 or combatant.is_death_finalized():
			continue
		# PAR021 always works, including stun and immunity rounds.
		combatant.tempo = minf(combatant.max_tempo, combatant.tempo + maxf(0.0, combatant.tempo_regen))

static func end_round(state: CombatState) -> void:
	for combatant in state.combatants.values():
		if combatant == null or combatant.hp <= 0 or combatant.is_death_finalized():
			continue
		if is_stunned(combatant, state.round_number):
			# One-time rebound only after the actual stunned round has finished.
			combatant.tempo = minf(combatant.max_tempo, combatant.tempo + 0.5 * combatant.base_tempo)
			combatant.tempo_immunity_until_round = state.round_number + IMMUNITY_ROUNDS
			continue
		if is_immune(combatant, state.round_number):
			# Control debt remains untouched; no stun, payment, or rebound.
			continue
		if combatant.tempo <= STUN_THRESHOLD:
			combatant.tempo_stun_round = state.round_number + 1
			# Pay at most 100 negative points, with no positive overshoot.
			combatant.tempo = minf(0.0, combatant.tempo + STUN_DEBT_PAYMENT)
