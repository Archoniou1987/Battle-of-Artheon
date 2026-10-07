class_name AbilityRuntime
extends RefCounted

static func can_use(ability_id: String, cooldowns: Dictionary, round_number: int) -> bool:
	return round_number >= int(cooldowns.get(ability_id, 0))

static func start_cooldown(ability_id: String, cooldowns: Dictionary, round_number: int, cooldown_rounds: int) -> void:
	cooldowns[ability_id] = round_number + cooldown_rounds + 1

static func normalized_definition(ability_id: String, definition: Dictionary) -> Dictionary:
	var normalized := definition.duplicate(true)
	normalized["ability_id"] = ability_id
	normalized["delivery_type"] = String(definition.get("delivery_type", "DIRECT")).to_upper()
	normalized["target_scope"] = String(definition.get("target_scope", "SINGLE")).to_upper()
	normalized["duration_rounds"] = maxi(0, int(definition.get("duration_rounds", 0)))
	normalized["engagement"] = definition.get("engagement", {}).duplicate(true) if definition.get("engagement", {}) is Dictionary else {}
	var components:Array = definition.get("components", []).duplicate(true) if definition.get("components", []) is Array else []
	if components.is_empty() and (definition.has("damage") or definition.has("damage_type")):
		components.append({
			"kind": "damage",
			"amount": float(definition.get("damage", 0)),
			"damage_type": String(definition.get("damage_type", "physical"))
		})
	normalized["components"] = components
	return normalized

static func build_damage_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	var normalized := normalized_definition(ability_id, definition)
	var damage_component:Dictionary = {}
	for raw_component in normalized.get("components", []):
		if raw_component is Dictionary and String(raw_component.get("kind", "")) == "damage":
			damage_component = raw_component
			break
	return state.create_event(CombatEvent.Kind.DAMAGE, source_id, target_id, {
		"amount": float(damage_component.get("amount", 0)),
		"raw_damage": float(damage_component.get("amount", 0)),
		"damage_type": String(damage_component.get("damage_type", "physical")),
		"ability_id": ability_id,
		"source_kind": "ability",
		"delivery_type": normalized["delivery_type"],
		"target_scope": normalized["target_scope"],
		"duration_rounds": normalized["duration_rounds"],
		"engagement": normalized["engagement"],
		"components": normalized["components"]
	})
