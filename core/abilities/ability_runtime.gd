class_name AbilityRuntime
extends RefCounted

static func can_use(ability_id: String, cooldowns: Dictionary, round_number: int) -> bool:
	return round_number >= int(cooldowns.get(ability_id, 0))

static func start_cooldown(ability_id: String, cooldowns: Dictionary, round_number: int, cooldown_rounds: int) -> void:
	cooldowns[ability_id] = round_number + cooldown_rounds + 1

static func build_damage_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	return state.create_event(CombatEvent.Kind.DAMAGE, source_id, target_id, {
		"amount": float(definition.get("damage", 0)),
		"raw_damage": float(definition.get("damage", 0)),
		"damage_type": String(definition.get("damage_type", "physical")),
		"ability_id": ability_id,
		"source_kind": "ability"
	})
