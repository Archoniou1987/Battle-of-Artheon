class_name GroupCombatSimulator
extends RefCounted

var state:CombatState
var group:GroupCombatState
var controller:GroupCombatController
var engine:CombatEngine
var orchestrator:RoundOrchestrator
var max_rounds:int=999

func _init(combat_state:CombatState,group_state:GroupCombatState,balance:Dictionary={}) -> void:
	state=combat_state
	group=group_state
	controller=GroupCombatController.new(group)
	engine=CombatEngine.new(state,balance)
	orchestrator=RoundOrchestrator.new(state,engine,group)
	controller.initialize_active_opponents()

func run() -> Dictionary:
	while not controller.combat_finished() and state.round_number<max_rounds:
		run_round()
	var winner:=controller.winning_team()
	return {"outcome":"timeout" if not controller.combat_finished() else ("draw" if winner.is_empty() else "winner:"+winner),"winning_team":winner,"rounds":state.round_number,"dead_ids":_finalized_dead_ids()}

func run_round() -> Dictionary:
	if controller.combat_finished():
		return {"ok":false,"reason":"combat_finished","battle_outcome":"winner:"+controller.winning_team()}
	var round:=orchestrator.begin_round()
	var actors:Array[String]=[]
	for raw_id in group.combatant_team.keys():
		actors.append(String(raw_id))
	actors.sort()
	for actor_id in actors:
		var actor:=state.get_combatant(actor_id)
		if actor==null or actor.is_death_finalized() or not actor.is_alive():
			continue
		var target_id:=controller.ensure_active_opponent(actor_id)
		var target:=state.get_combatant(target_id)
		if target==null or target.is_death_finalized():
			continue
		round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,actor_id,target_id,{
			"amount":_basic_damage(actor),
			"raw_damage":_basic_damage(actor),
			"damage_type":"physical",
			"source":"group_basic_attack"
		}))
	orchestrator.resolve_locked_actions(round)
	var summary:=orchestrator.end_round()
	var sync:=controller.after_end_round(summary)
	return {"ok":true,"round":state.round_number,"summary":summary,"sync":sync,"battle_outcome":"winner:"+controller.winning_team() if controller.combat_finished() and not controller.winning_team().is_empty() else ("draw" if controller.combat_finished() else "ongoing")}

func _basic_damage(combatant:CombatantState)->float:
	var minimum:=float(combatant.combat_stats.get("main_hand_damage_min",1.0))
	var maximum:=float(combatant.combat_stats.get("main_hand_damage_max",minimum))
	return maxf(0.0,(minimum+maximum)*0.5)

func _finalized_dead_ids()->Array[String]:
	var result:Array[String]=[]
	for raw_id in state.combatants.keys():
		var combatant:=state.get_combatant(String(raw_id))
		if combatant!=null and combatant.is_death_finalized():
			result.append(String(raw_id))
	result.sort()
	return result
