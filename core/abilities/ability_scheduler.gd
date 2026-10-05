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
	for raw_id in AbilityCatalog.assigned_abilities(loadouts, source_id):
		var ability_id := String(raw_id)
		if not AbilityRuntime.can_use(ability_id, cooldowns, state.round_number): continue
		var definition := AbilityCatalog.definition(definitions, ability_id)
		if definition.is_empty(): continue
		events.append(AbilityRuntime.build_damage_event(state, source_id, target_id, ability_id, definition))
		AbilityRuntime.start_cooldown(ability_id, cooldowns, state.round_number, int(definition.get("cooldown_rounds", 0)))
	cooldowns_by_combatant[source_id] = cooldowns
	return events
