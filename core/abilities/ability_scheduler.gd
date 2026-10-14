class_name AbilityScheduler
extends RefCounted

var definitions: Dictionary
var loadouts: Dictionary
var cooldowns_by_combatant: Dictionary = {}

func _init(ability_definitions: Dictionary = {}, ability_loadouts: Dictionary = {}) -> void:
	definitions = ability_definitions
	loadouts = ability_loadouts

func ready_events(state: CombatState, source_id: String, target_id: String) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var cooldowns: Dictionary = cooldowns_by_combatant.get(source_id, {})
	var source := state.get_combatant(source_id)
	if source == null: return events
	if not _source_ready(source, state.round_number): return events
	for raw_id in AbilityCatalog.assigned_abilities(loadouts, source_id):
		var ability_id := String(raw_id)
		if not AbilityRuntime.can_use(ability_id, cooldowns, state.round_number): continue
		var definition := AbilityCatalog.definition(definitions, ability_id)
		if definition.is_empty(): continue
		var mana_cost := int(definition.get("mana_cost", 0))
		if source.mana < mana_cost: continue
		if not source.spend_mana(mana_cost): continue
		events.append(AbilityRuntime.build_action_event(state, source_id, target_id, ability_id, definition))
		AbilityRuntime.start_cooldown(ability_id, cooldowns, state.round_number, int(definition.get("cooldown_rounds", 0)))
	cooldowns_by_combatant[source_id] = cooldowns
	return events



func cast_zone_event(state:CombatState,source_id:String,zone_id:int,ability_id:String)->CombatEvent:
	var source:=state.get_combatant(source_id)
	if source==null or not _source_ready(source, state.round_number) or not AbilityCatalog.assigned_abilities(loadouts,source_id).has(ability_id):
		return null
	var definition:=AbilityCatalog.definition(definitions,ability_id)
	var cooldowns:Dictionary=cooldowns_by_combatant.get(source_id,{})
	if definition.is_empty() or not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return null
	var mana_cost:=int(definition.get("mana_cost",0))
	if source.mana<mana_cost or not source.spend_mana(mana_cost):
		return null
	var cast_definition:=definition.duplicate(true)
	cast_definition["target_zone_id"]=zone_id
	var event:=AbilityRuntime.build_action_event(state,source_id,"",ability_id,cast_definition)
	AbilityRuntime.start_cooldown(ability_id,cooldowns,state.round_number,int(definition.get("cooldown_rounds",0)))
	cooldowns_by_combatant[source_id]=cooldowns
	return event

func cast_event(state:CombatState,source_id:String,target_id:String,ability_id:String)->CombatEvent:
	var source:=state.get_combatant(source_id)
	if source==null or not _source_ready(source, state.round_number):
		return null
	if not AbilityCatalog.assigned_abilities(loadouts,source_id).has(ability_id):
		return null
	var definition:=AbilityCatalog.definition(definitions,ability_id)
	if definition.is_empty():
		return null
	var cooldowns:Dictionary=cooldowns_by_combatant.get(source_id,{})
	if not AbilityRuntime.can_use(ability_id,cooldowns,state.round_number):
		return null
	var mana_cost:=int(definition.get("mana_cost",0))
	if source.mana<mana_cost or not source.spend_mana(mana_cost):
		return null
	var event:=AbilityRuntime.build_action_event(state,source_id,target_id,ability_id,definition)
	AbilityRuntime.start_cooldown(ability_id,cooldowns,state.round_number,int(definition.get("cooldown_rounds",0)))
	cooldowns_by_combatant[source_id]=cooldowns
	return event

func _source_ready(source: CombatantState, round_number: int) -> bool:
	var status := ParCombatContract.action_status(source, round_number)
	if not bool(status.ok) and String(status.reason) != "stunned":
		push_error("ABI PAR invariant violated: " + String(status.reason))
	return bool(status.ok)
