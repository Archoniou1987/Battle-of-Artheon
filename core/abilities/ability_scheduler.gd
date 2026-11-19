class_name AbilityScheduler
extends RefCounted

var definitions: Dictionary
var loadouts: Dictionary
var cooldowns_by_combatant: Dictionary = {}
## A normal actor has one ABI per round. A second player-selected cast is
## permitted only when one of the two ABI is bonus-eligible.
## Entries are the ordered, immediately-paid casts for the current round.
var cast_round_by_combatant: Dictionary = {}
var cast_history_by_combatant: Dictionary = {}

func _cast_history(source_id: String, round_number: int) -> Array:
	if int(cast_round_by_combatant.get(source_id,-1)) != round_number:
		return []
	return Array(cast_history_by_combatant.get(source_id,[]))

func can_cast_this_round(source_id: String, round_number: int, ability_id: String = "") -> bool:
	var history := _cast_history(source_id,round_number)
	if history.is_empty():
		return true
	if ability_id.is_empty() or history.size()!=1:
		return false
	var first_id := String(history[0])
	if first_id==ability_id:
		return false
	var first := AbilityCatalog.definition(definitions,first_id)
	var second := AbilityCatalog.definition(definitions,ability_id)
	if first.is_empty() or second.is_empty():
		return false
	var first_instant := AbilityRuntime.extra_cast_eligible(first)
	var second_instant := AbilityRuntime.extra_cast_eligible(second)
	return first_instant != second_instant

func mana_cost_for_cast(source_id: String, round_number: int, ability_id: String) -> int:
	var definition := AbilityCatalog.definition(definitions,ability_id)
	var base := maxi(0,int(definition.get("mana_cost",0)))
	return int(ceili(float(base)*1.25)) if not _cast_history(source_id,round_number).is_empty() else base

func _record_cast(source_id: String, round_number: int, ability_id: String) -> void:
	var history := _cast_history(source_id,round_number).duplicate()
	history.append(ability_id)
	cast_history_by_combatant[source_id]=history
	cast_round_by_combatant[source_id]=round_number

func _init(ability_definitions: Dictionary = {}, ability_loadouts: Dictionary = {}) -> void:
	definitions = ability_definitions
	loadouts = ability_loadouts

func ready_events(state: CombatState, source_id: String, target_id: String) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var cooldowns: Dictionary = cooldowns_by_combatant.get(source_id, {})
	var source := state.get_combatant(source_id)
	if source == null: return events
	if not _source_ready(source, state.round_number) or not can_cast_this_round(source_id, state.round_number): return events
	for raw_id in AbilityCatalog.assigned_abilities(loadouts, source_id):
		var ability_id := String(raw_id)
		if not AbilityRuntime.can_use(ability_id, cooldowns, state.round_number): continue
		var definition := AbilityCatalog.definition(definitions, ability_id)
		if definition.is_empty() or not AbilityRuntime.validate_definition(ability_id,definition).is_empty(): continue
		# A self-support cast must not be redirected onto the active enemy.
		var effective_target_id := source_id if String(definition.get("target_team","")).to_upper()=="ALLY" else target_id
		var effective_target := state.get_combatant(effective_target_id)
		if effective_target == null or effective_target.is_death_finalized(): continue
		var mana_cost := int(definition.get("mana_cost", 0))
		if source.mana < mana_cost or not AbilityRuntime.can_pay_action_points(definition,source): continue
		if not AbilityRuntime.previous_round_trigger_met(state,source_id,String(definition.get("trigger_previous_round",""))): continue
		if AxeAbiCombatService.is_axe_ability(ability_id) and not AxeAbiCombatService.can_cast(state,source_id,effective_target_id,ability_id): continue
		var ap_spent:=AbilityRuntime.action_point_cost(definition,source)
		if not source.spend_mana(mana_cost) or not source.spend_action_points(ap_spent): continue
		var event:=AbilityRuntime.build_action_event(state, source_id, effective_target_id, ability_id, definition)
		event.payload["ap_spent"]=ap_spent
		event.payload["ap_gained"]=(0 if bool(definition.get("ap_gain_on_hit",false)) else source.gain_action_points(maxi(0,int(definition.get("ap_gain",0)))))
		events.append(event)
		AbilityRuntime.start_cooldown(ability_id, cooldowns, state.round_number, int(definition.get("cooldown_rounds", 0)))
		_record_cast(source_id, state.round_number, ability_id)
		break # The automatic policy picks at most one ready ABI.
	cooldowns_by_combatant[source_id] = cooldowns
	return events



func cast_zone_event(state:CombatState,source_id:String,zone_id:int,ability_id:String)->CombatEvent:
	var source:=state.get_combatant(source_id)
	if source==null or not _source_ready(source, state.round_number) or not can_cast_this_round(source_id,state.round_number,ability_id) or not AbilityCatalog.assigned_abilities(loadouts,source_id).has(ability_id):
		return null
	var definition:=AbilityCatalog.definition(definitions,ability_id)
	var cooldowns:Dictionary=cooldowns_by_combatant.get(source_id,{})
	if definition.is_empty() or not AbilityRuntime.validate_definition(ability_id,definition).is_empty() or not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return null
	var mana_cost:=mana_cost_for_cast(source_id,state.round_number,ability_id)
	if source.mana<mana_cost or not AbilityRuntime.can_pay_action_points(definition,source):
		return null
	if not AbilityRuntime.previous_round_trigger_met(state,source_id,String(definition.get("trigger_previous_round",""))):
		return null
	if AxeAbiCombatService.is_axe_ability(ability_id) and not AxeAbiCombatService.can_cast(state,source_id,source_id,ability_id):
		return null
	var ap_spent:=AbilityRuntime.action_point_cost(definition,source)
	if not source.spend_mana(mana_cost) or not source.spend_action_points(ap_spent):
		return null
	var cast_definition:=definition.duplicate(true)
	cast_definition["target_zone_id"]=zone_id
	var event:=AbilityRuntime.build_action_event(state,source_id,"",ability_id,cast_definition)
	event.payload["ap_spent"]=ap_spent
	event.payload["ap_gained"]=(0 if bool(definition.get("ap_gain_on_hit",false)) else source.gain_action_points(maxi(0,int(definition.get("ap_gain",0)))))
	AbilityRuntime.start_cooldown(ability_id,cooldowns,state.round_number,int(definition.get("cooldown_rounds",0)) + (1 if _cast_history(source_id,state.round_number).size()==1 else 0))
	cooldowns_by_combatant[source_id]=cooldowns
	_record_cast(source_id,state.round_number,ability_id)
	return event

func cast_event(state:CombatState,source_id:String,target_id:String,ability_id:String)->CombatEvent:
	var source:=state.get_combatant(source_id)
	if source==null or not _source_ready(source, state.round_number) or not can_cast_this_round(source_id,state.round_number,ability_id):
		return null
	# Check target finalization before spending mana or starting cooldown.
	# Provisional HP <= 0 is still legal until the round's death phase.
	var target:=state.get_combatant(target_id)
	if target==null or target.is_death_finalized():
		return null
	if not AbilityCatalog.assigned_abilities(loadouts,source_id).has(ability_id):
		return null
	var definition:=AbilityCatalog.definition(definitions,ability_id)
	if definition.is_empty() or not AbilityRuntime.validate_definition(ability_id,definition).is_empty():
		return null
	var cooldowns:Dictionary=cooldowns_by_combatant.get(source_id,{})
	if not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return null
	var mana_cost:=mana_cost_for_cast(source_id,state.round_number,ability_id)
	if source.mana<mana_cost or not AbilityRuntime.can_pay_action_points(definition,source):
		return null
	if not AbilityRuntime.previous_round_trigger_met(state,source_id,String(definition.get("trigger_previous_round",""))):
		return null
	if AxeAbiCombatService.is_axe_ability(ability_id) and not AxeAbiCombatService.can_cast(state,source_id,target_id,ability_id):
		return null
	var ap_spent:=AbilityRuntime.action_point_cost(definition,source)
	if not source.spend_mana(mana_cost) or not source.spend_action_points(ap_spent):
		return null
	var event:=AbilityRuntime.build_action_event(state,source_id,target_id,ability_id,definition)
	event.payload["ap_spent"]=ap_spent
	event.payload["ap_gained"]=(0 if bool(definition.get("ap_gain_on_hit",false)) else source.gain_action_points(maxi(0,int(definition.get("ap_gain",0)))))
	AbilityRuntime.start_cooldown(ability_id,cooldowns,state.round_number,int(definition.get("cooldown_rounds",0)) + (1 if _cast_history(source_id,state.round_number).size()==1 else 0))
	cooldowns_by_combatant[source_id]=cooldowns
	_record_cast(source_id,state.round_number,ability_id)
	return event

func _source_ready(source: CombatantState, round_number: int) -> bool:
	# HP <= 0 during the current round is provisional, but finalized death is not.
	if source.is_death_finalized():
		return false
	var status := ParCombatContract.action_status(source, round_number)
	if not bool(status.ok) and String(status.reason) != "stunned":
		push_error("ABI PAR invariant violated: " + String(status.reason))
	return bool(status.ok)
