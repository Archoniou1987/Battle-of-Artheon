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
	# Opening phase: recover only combatants alive from the previous round.
	# Resource regeneration is not a healing action and cannot revive the dead.
	CombatResourceService.apply_round_regeneration(state)
	CombatTempoService.begin_round(state)
	start_snapshot=_capture_start_snapshot()
	movement_requests.clear()
	return CombatRound.new(state.round_number)

func resolve_locked_actions(round:CombatRound) -> void:
	round.resolve(engine)

func queue_movement_request(combatant_id:String, to_zone:int, tempo_roll:int=1, bypass_front:bool=false, movement_kind:String="navigation", contest:Dictionary={}) -> bool:
	if movement_resolver==null or not start_snapshot.has(combatant_id):
		return false
	for existing in movement_requests:
		if String(existing.get("combatant_id",""))!=combatant_id:
			continue
		if movement_kind=="forced":
			if String(existing.get("movement_kind",""))!="forced":
				existing["movement_kind"]="forced"
				existing["bypass_front"]=true
				existing["forced_effects"]=[]
			var effects:Array=Array(existing.get("forced_effects",[]))
			effects.append({"to_zone":to_zone,"contest":contest.duplicate(true)})
			existing["forced_effects"]=effects
			return true
		if String(existing.get("movement_kind",""))=="forced":
			return false
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
		"movement_kind":movement_kind,
		"contest":contest.duplicate(true),
		"forced_effects":[{"to_zone":to_zone,"contest":contest.duplicate(true)}] if movement_kind=="forced" else []
	})
	return true

func resolve_movement_phase() -> Array[Dictionary]:
	if movement_resolver==null:
		movement_requests.clear()
		return []
	var requests:Array[Dictionary]=[]
	for request in movement_requests:
		var enriched:Dictionary=request.duplicate(true)
		if String(enriched.get("movement_kind",""))=="forced":
			_resolve_forced_direction(enriched)
		var combatant_id:=String(request.get("combatant_id",""))
		var snap:Dictionary=start_snapshot.get(combatant_id,{})
		enriched["movement_locked"]=bool(enriched.get("movement_locked",false)) or bool(snap.get("movement_locked",false))
		if not enriched.has("contest_power"):
			enriched["contest_power"]=_movement_contest_power(combatant_id,enriched)
		requests.append(enriched)
	movement_requests.clear()
	return movement_resolver.resolve_simultaneous(requests)


func _resolve_forced_direction(request:Dictionary)->void:
	var from_zone:=int(request.get("from_zone",-1))
	var combatant_id:=String(request.get("combatant_id",""))
	var totals:Dictionary={}
	for raw_effect in request.get("forced_effects",[]):
		var effect:Dictionary=raw_effect
		var to_zone:=int(effect.get("to_zone",-1))
		if to_zone<CombatZoneState.ZONE_1 or to_zone>CombatZoneState.ZONE_3 or absi(to_zone-from_zone)!=1:
			continue
		var direction:=signi(to_zone-from_zone)
		var contest:Dictionary=effect.get("contest",{})
		totals[direction]=float(totals.get(direction,0.0))+_contest_definition_power(combatant_id,contest)
	var forward:=float(totals.get(1,0.0))
	var backward:=float(totals.get(-1,0.0))
	if forward==backward:
		request["movement_locked"]=true
		return
	request["to_zone"]=from_zone+(1 if forward>backward else -1)
	request["contest_power"]=absf(forward-backward)

func _contest_definition_power(combatant_id:String,contest:Dictionary)->float:
	var combatant:=state.get_combatant(combatant_id)
	if combatant==null:
		return 0.0
	var stats:Array=Array(contest.get("stats",["PAR001","PAR006"]))
	var power:=float(contest.get("flat_power",0.0))
	for raw_stat in stats:
		var stat:=String(raw_stat)
		if not combatant.stats.has(stat):
			push_error("Movement contest missing mandatory parameter: " + stat)
			return 0.0
		power+=float(combatant.stats[stat])
	return power*float(contest.get("multiplier",1.0))

func _movement_contest_power(combatant_id:String,request:Dictionary)->float:
	if request.has("contest_power"):
		return float(request.get("contest_power",0.0))
	var contest:Dictionary=request.get("contest",{})
	return _contest_definition_power(combatant_id,contest)

func defer_event(event:CombatEvent, require_source_alive:bool=true, require_target_alive:bool=true) -> void:
	deferred_events.append({"event":event,"require_source_alive":require_source_alive,"require_target_alive":require_target_alive})

func register_from_action(event:CombatEvent) -> void:
	var duration_rounds:=int(event.payload.get("duration_rounds",0))
	if duration_rounds<=1:
		return
	var zone_id:=int(event.payload.get("target_zone_id",event.payload.get("zone_id",-1)))
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

func resolve_active_timed_effects() -> Array[int]:
	var event_ids:Array[int]=[]
	for combatant in state.combatants.values():
		for active in combatant.active_effects:
			if state.round_number<int(active.get("start_round",999999)) or int(active.get("remaining_rounds",0))<=0:
				continue
			var definition:Dictionary=active.get("definition",{})
			if String(definition.get("kind",""))!="dot":
				continue
			# Shared-duration EFF has one DoT packet per round, multiplied
			# by the current stack count (independent-stack EFF stay unchanged).
			var shared_stacks := maxi(1, int(active.get("stacks", 1))) if String(definition.get("stacking", "")) == "shared_duration" else 1
			var amount:=float(definition.get("damage",0.0)) * float(shared_stacks)
			if amount<=0.0:
				continue
			var event:=state.create_event(CombatEvent.Kind.DAMAGE,String(active.get("source_id","")),combatant.combatant_id,{
				"amount":amount,
				"raw_damage":amount,
				"damage_type":String(definition.get("damage_type","physical")),
				"source":"effect",
				"effect_id":String(active.get("effect_id","")),
				"source_type":String(active.get("source_type","unknown")),
				"source_instance_id":String(active.get("source_instance_id","")),
				"stack_id":String(active.get("stack_id",""))
			})
			state.queue_event(event)
			event_ids.append(event.event_id)
	engine.resolve_pending_events()
	return event_ids

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
	var kill_attribution:Dictionary={}
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
	effect_event_ids.append_array(resolve_active_timed_effects())
	for combatant in state.combatants.values():
		if not combatant.is_alive():
			combatant.death_finalized=true
			finalized_dead_ids.append(combatant.combatant_id)
			var killers:=state.fatal_round_killers(combatant.combatant_id)
			if not killers.is_empty():
				kill_attribution[combatant.combatant_id]=killers
	# Death is finalized before threshold checks; dead fighters cannot stun/rebound.
	CombatTempoService.end_round(state)
	_tick_effect_durations()
	return {
		"dead_ids":finalized_dead_ids.duplicate(),
		"kill_attribution":kill_attribution,
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
		var movement_locked := _has_active_movement_lock(combatant) or CombatTempoService.is_stunned(combatant, state.round_number)
		snapshot[String(combatant_id)]={
			"hp":combatant.hp,
			"death_finalized":combatant.is_death_finalized(),
			"tempo":CombatModifierService.effective_tempo(combatant, state.round_number),
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
		var targets:Array[String]=[]
		for combatant_id in zone_state.occupants(int(record.get("zone_id",-1))):
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
