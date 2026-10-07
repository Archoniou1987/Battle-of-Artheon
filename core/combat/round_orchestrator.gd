class_name RoundOrchestrator
extends RefCounted

## Combat v2 phase owner.
## Intent is locked from the start-of-round snapshot. Immediate actions resolve
## before movement; already-active persistent effects resolve after movement.
## Death is finalized only after the EFF phase.

var state:CombatState
var engine:CombatEngine
var group_state:GroupCombatState
var zone_state:CombatZoneState
var movement_resolver:CombatMovementResolver
var deferred_events:Array[Dictionary]=[]
var persistent_actions:Array[Dictionary]=[]
var finalized_dead_ids:Array[String]=[]
var start_snapshot:Dictionary={}
var movement_requests:Array[Dictionary]=[]

func _init(combat_state:CombatState, combat_engine:CombatEngine, combat_groups:GroupCombatState=null, combat_zones:CombatZoneState=null) -> void:
	state=combat_state
	engine=combat_engine
	group_state=combat_groups
	zone_state=combat_zones
	if group_state!=null and zone_state!=null:
		movement_resolver=CombatMovementResolver.new(zone_state)
		engine.configure_spatial_context(group_state,zone_state)

func begin_round() -> CombatRound:
	state.begin_round()
	start_snapshot=_capture_start_snapshot()
	movement_requests.clear()
	return CombatRound.new(state.round_number)

func resolve_locked_actions(round:CombatRound) -> void:
	round.resolve(engine)

func queue_movement_request(combatant_id:String, to_zone:int, tempo_roll:int=1, bypass_front:bool=false, movement_kind:String="navigation") -> bool:
	if movement_resolver==null or not start_snapshot.has(combatant_id):
		return false
	for existing in movement_requests:
		if String(existing.get("combatant_id",""))==combatant_id:
			return false
	var snap:Dictionary=start_snapshot[combatant_id]
	if bool(snap.get("movement_locked",false)):
		return false
	movement_requests.append({
		"combatant_id":combatant_id,
		"from_zone":int(snap.get("zone",-1)),
		"to_zone":to_zone,
		"tempo":float(snap.get("tempo",0.0)),
		"tempo_roll":tempo_roll,
		"bypass_front":bypass_front,
		"movement_kind":movement_kind
	})
	return true

func resolve_movement_phase() -> Array[Dictionary]:
	var results:Array[Dictionary]=[]
	if movement_resolver==null:
		movement_requests.clear()
		return results
	for request in movement_requests:
		var combatant_id:=String(request.get("combatant_id",""))
		var result:=movement_resolver.resolve_request(
			combatant_id,
			int(request.get("to_zone",-1)),
			float(request.get("tempo",0.0)),
			int(request.get("tempo_roll",1)),
			bool(request.get("bypass_front",false))
		)
		result["movement_kind"]=String(request.get("movement_kind","navigation"))
		results.append(result)
	movement_requests.clear()
	return results

func defer_event(event:CombatEvent, require_source_alive:bool=true, require_target_alive:bool=true) -> void:
	deferred_events.append({"event":event,"require_source_alive":require_source_alive,"require_target_alive":require_target_alive})

func register_from_action(event:CombatEvent) -> void:
	var duration_rounds:=int(event.payload.get("duration_rounds",0))
	if duration_rounds<=1:
		return
	var zone_id:=int(event.payload.get("zone_id",-1))
	if zone_id>=CombatZoneState.ZONE_1 and zone_id<=CombatZoneState.ZONE_3 and group_state!=null and zone_state!=null:
		register_zone_effect(event.source_id,zone_id,event.payload,duration_rounds)
		return
	# Compatibility path for non-zone persistent actions. New AREA effects must
	# bind to zone_id and never freeze a target list.
	var targets:Array[String]=[]
	for raw_id in event.payload.get("target_ids",[event.target_id]):
		var target_id:=String(raw_id)
		if not target_id.is_empty() and not targets.has(target_id):
			targets.append(target_id)
	register_persistent_action(event.source_id,targets,event.payload,duration_rounds)

func register_zone_effect(source_id:String, zone_id:int, payload:Dictionary, duration_rounds:int) -> void:
	if duration_rounds<=1 or zone_state==null or group_state==null:
		return
	persistent_actions.append({
		"source_id":source_id,
		"zone_id":zone_id,
		"payload":payload.duplicate(true),
		"start_round":state.round_number+1,
		"remaining_ticks":duration_rounds-1
	})

func register_persistent_action(source_id:String, target_ids:Array[String], payload:Dictionary, duration_rounds:int) -> void:
	if duration_rounds<=1:
		return
	persistent_actions.append({
		"source_id":source_id,
		"target_ids":target_ids.duplicate(),
		"payload":payload.duplicate(true),
		"start_round":state.round_number+1,
		"remaining_ticks":duration_rounds-1
	})

func resolve_effect_phase() -> Array[int]:
	var event_ids:Array[int]=[]
	var kept:Array[Dictionary]=[]
	for record in persistent_actions:
		if int(record.get("remaining_ticks",0))<=0:
			continue
		if state.round_number<int(record.get("start_round",999999)):
			kept.append(record)
			continue
		var targets:Array[String]=_persistent_targets(record)
		if targets.is_empty():
			record["remaining_ticks"]=int(record.get("remaining_ticks",0))-1
			if int(record.get("remaining_ticks",0))>0:
				kept.append(record)
			continue
		var payload:Dictionary=record.get("payload",{}).duplicate(true)
		payload["target_ids"]=targets
		payload["duration_rounds"]=1
		var event:=state.create_event(CombatEvent.Kind.ACTION,String(record.get("source_id","")),targets[0],payload)
		state.queue_event(event)
		event_ids.append(event.event_id)
		record["remaining_ticks"]=int(record.get("remaining_ticks",0))-1
		if int(record.get("remaining_ticks",0))>0:
			kept.append(record)
	persistent_actions=kept
	engine.resolve_pending_events()
	return event_ids

func end_round() -> Dictionary:
	finalized_dead_ids=[]
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
	var movement_results:=resolve_movement_phase()
	var effect_event_ids:=resolve_effect_phase()
	for combatant in state.combatants.values():
		if not combatant.is_alive():
			combatant.death_finalized=true
			finalized_dead_ids.append(combatant.combatant_id)
	_tick_effect_durations()
	return {
		"dead_ids":finalized_dead_ids.duplicate(),
		"resolved_deferred_event_ids":resolved_deferred,
		"canceled_deferred_event_ids":canceled_deferred,
		"movement_results":movement_results,
		"effect_event_ids":effect_event_ids,
		"battle_outcome":battle_outcome()
	}

func battle_outcome() -> String:
	if group_state==null:
		return "ongoing"
	var living_teams:Array[String]=[]
	for team_id in group_state.teams.keys():
		var has_living:=false
		for combatant_id in group_state.round_present_members(String(team_id)):
			var combatant:=state.get_combatant(combatant_id)
			if combatant!=null and not combatant.is_death_finalized():
				has_living=true
				break
		if has_living:
			living_teams.append(String(team_id))
	if living_teams.size()==0:
		return "draw"
	if living_teams.size()==1:
		return "winner:"+living_teams[0]
	return "ongoing"

func _capture_start_snapshot() -> Dictionary:
	var snapshot:Dictionary={}
	for combatant_id in state.combatants.keys():
		var combatant:CombatantState=state.get_combatant(String(combatant_id))
		var movement_locked:=_has_active_movement_lock(combatant)
		snapshot[String(combatant_id)]={
			"hp":combatant.hp,
			"death_finalized":combatant.is_death_finalized(),
			"tempo":combatant.tempo,
			"movement_locked":movement_locked,
			"zone":zone_state.zone_of(String(combatant_id)) if zone_state!=null else -1
		}
	return snapshot

func _has_active_movement_lock(combatant:CombatantState) -> bool:
	if combatant==null:
		return true
	for active in combatant.active_effects:
		if state.round_number<int(active.get("start_round",999999)) or int(active.get("remaining_rounds",0))<=0:
			continue
		var definition:Dictionary=active.get("definition",{})
		var kind:=String(definition.get("kind","")).to_lower()
		if bool(definition.get("movement_locked",false)) or kind in ["root","stun","freeze","fear"]:
			return true
	return false

func _persistent_targets(record:Dictionary) -> Array[String]:
	if record.has("zone_id") and group_state!=null and zone_state!=null:
		var source_id:=String(record.get("source_id",""))
		var own_team:=group_state.team_of(source_id)
		var targets:Array[String]=[]
		for combatant_id in zone_state.occupants(int(record.get("zone_id",-1))):
			if group_state.team_of(combatant_id)!=own_team:
				targets.append(combatant_id)
		return targets
	var result:Array[String]=[]
	for raw_id in record.get("target_ids",[]):
		var target_id:=String(raw_id)
		var target:=state.get_combatant(target_id)
		if target!=null and not target.is_death_finalized():
			result.append(target_id)
	return result

func _deferred_valid(record:Dictionary) -> bool:
	var event:CombatEvent=record.get("event")
	if event==null:
		return false
	var source:=state.get_combatant(event.source_id)
	var target:=state.get_combatant(event.target_id)
	if bool(record.get("require_source_alive",true)) and (source==null or source.is_death_finalized()):
		return false
	if bool(record.get("require_target_alive",true)) and (target==null or target.is_death_finalized()):
		return false
	return true

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
