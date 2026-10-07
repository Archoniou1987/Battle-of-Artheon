class_name RoundOrchestrator
extends RefCounted

## Combat v2 round lifecycle.
## Root actions are locked before resolution. Lethal damage does not cancel a
## locked action. Death and deferred consequences are finalized at end round.

var state:CombatState
var engine:CombatEngine
var deferred_events:Array[Dictionary]=[]
var persistent_actions:Array[Dictionary]=[]
var finalized_dead_ids:Array[String]=[]

func _init(combat_state:CombatState, combat_engine:CombatEngine) -> void:
	state=combat_state
	engine=combat_engine

func begin_round() -> CombatRound:
	state.begin_round()
	_queue_persistent_ticks()
	engine.resolve_pending_events()
	return CombatRound.new(state.round_number)

func resolve_locked_actions(round:CombatRound) -> void:
	round.resolve(engine)

func defer_event(event:CombatEvent, require_source_alive:bool=true, require_target_alive:bool=true) -> void:
	deferred_events.append({
		"event":event,
		"require_source_alive":require_source_alive,
		"require_target_alive":require_target_alive
	})

func register_from_action(event:CombatEvent) -> void:
	var duration_rounds:=int(event.payload.get("duration_rounds",0))
	if duration_rounds<=1:
		return
	var targets:Array[String]=[]
	for raw_id in event.payload.get("target_ids",[event.target_id]):
		var target_id:=String(raw_id)
		if not target_id.is_empty() and not targets.has(target_id):
			targets.append(target_id)
	register_persistent_action(event.source_id,targets,event.payload,duration_rounds)

func register_persistent_action(source_id:String, target_ids:Array[String], payload:Dictionary, duration_rounds:int) -> void:
	if duration_rounds <= 1:
		return
	persistent_actions.append({
		"source_id":source_id,
		"target_ids":target_ids.duplicate(),
		"payload":payload.duplicate(true),
		"remaining_ticks":duration_rounds-1
	})

func end_round() -> Dictionary:
	finalized_dead_ids=[]
	for combatant in state.combatants.values():
		if not combatant.is_alive():
			combatant.death_finalized=true
			finalized_dead_ids.append(combatant.combatant_id)
	var resolved_deferred:Array[int]=[]
	var canceled_deferred:Array[int]=[]
	for record in deferred_events:
		var event:CombatEvent=record.get("event")
		if _deferred_valid(record):
			state.queue_event(event)
			resolved_deferred.append(event.event_id)
		else:
			canceled_deferred.append(event.event_id)
	deferred_events.clear()
	engine.resolve_pending_events()
	_tick_effect_durations()
	return {
		"dead_ids":finalized_dead_ids.duplicate(),
		"resolved_deferred_event_ids":resolved_deferred,
		"canceled_deferred_event_ids":canceled_deferred
	}

func _deferred_valid(record:Dictionary) -> bool:
	var event:CombatEvent=record.get("event")
	if event == null:
		return false
	var source:=state.get_combatant(event.source_id)
	var target:=state.get_combatant(event.target_id)
	if bool(record.get("require_source_alive",true)) and (source==null or not source.is_alive()):
		return false
	if bool(record.get("require_target_alive",true)) and (target==null or not target.is_alive()):
		return false
	return true

func _queue_persistent_ticks() -> void:
	var kept:Array[Dictionary]=[]
	for record in persistent_actions:
		if int(record.get("remaining_ticks",0)) <= 0:
			continue
		var payload:Dictionary=record.get("payload",{}).duplicate(true)
		payload["target_ids"]=record.get("target_ids",[]).duplicate()
		var target_ids:Array=payload.get("target_ids",[])
		if target_ids.is_empty():
			continue
		var event:=state.create_event(CombatEvent.Kind.ACTION,String(record.get("source_id","")),String(target_ids[0]),payload)
		state.queue_event(event)
		record["remaining_ticks"]=int(record.get("remaining_ticks",0))-1
		if int(record.get("remaining_ticks",0))>0:
			kept.append(record)
	persistent_actions=kept

func _tick_effect_durations() -> void:
	for combatant in state.combatants.values():
		for active in combatant.active_effects:
			if state.round_number>=int(active.get("start_round",999999)):
				active["remaining_rounds"]=int(active.get("remaining_rounds",0))-1
		var kept:Array[Dictionary]=[]
		for active in combatant.active_effects:
			if int(active.get("remaining_rounds",0))>0:
				kept.append(active)
		combatant.active_effects=kept
