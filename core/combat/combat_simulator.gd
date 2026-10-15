class_name CombatSimulator
extends RefCounted

var state: CombatState
var engine: CombatEngine
var attack_pipeline:CombatAttackPipeline
var ability_scheduler:AbilityScheduler:
	get:
		return attack_pipeline.ability_scheduler
	set(value):
		attack_pipeline.ability_scheduler=value
var orchestrator: RoundOrchestrator
var max_rounds: int = 999

func _init(combat_state: CombatState, balance: Dictionary = {}, seed_value: int = 1) -> void:
	state = combat_state
	engine = CombatEngine.new(state, balance)
	orchestrator = RoundOrchestrator.new(state, engine)
	attack_pipeline=CombatAttackPipeline.new(state,seed_value,engine)

func run_duel(first_id: String, second_id: String) -> Dictionary:
	while _both_alive(first_id, second_id) and state.round_number < max_rounds: _run_round(first_id, second_id)
	var first := state.get_combatant(first_id); var second := state.get_combatant(second_id); var outcome := "timeout"
	if not first.is_alive() and not second.is_alive(): outcome = "draw"
	elif first.is_alive() and not second.is_alive(): outcome = first_id
	elif second.is_alive() and not first.is_alive(): outcome = second_id
	var winner_id := ""
	var loser_id := ""
	if outcome == first_id:
		winner_id = first_id
		loser_id = second_id
	elif outcome == second_id:
		winner_id = second_id
		loser_id = first_id
	return {"outcome":outcome,"winner_id":winner_id,"loser_id":loser_id,"rounds":state.round_number,"first_hp":first.hp,"second_hp":second.hp,"first_mana":first.mana,"second_mana":second.mana,"events":state.event_log.size()}

func _run_round(first_id:String,second_id:String)->void:
	# Keep the legacy duel smoke simulator independent from spatial movement.
	# Combat v2's orchestrator is used only when it has a complete spatial context.
	var round:CombatRound
	if orchestrator!=null:
		round=orchestrator.begin_round()
	else:
		state.begin_round()
		round=CombatRound.new(state.round_number)
	attack_pipeline.regenerate_mana()
	var first:=state.get_combatant(first_id)
	var second:=state.get_combatant(second_id)
	attack_pipeline.lock_basic_attack(round,first,second)
	attack_pipeline.lock_basic_attack(round,second,first)
	orchestrator.resolve_locked_actions(round)
	# ABI is the second immediate phase. Start-of-round participants may finish
	# their established actions even when Base Attack has driven HP below zero.
	if first!=null and second!=null and not first.is_death_finalized() and not second.is_death_finalized():
		attack_pipeline.queue_ready_abilities(first,second)
		attack_pipeline.queue_ready_abilities(second,first)
		engine.resolve_pending_events()
	orchestrator.end_round()


func _both_alive(first_id:String,second_id:String)->bool:
	return not state.get_combatant(first_id).is_death_finalized() and not state.get_combatant(second_id).is_death_finalized()
