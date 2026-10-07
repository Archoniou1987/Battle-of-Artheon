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

static func validate_definition(ability_id: String, definition: Dictionary) -> Array[String]:
	var errors:Array[String]=[]
	var normalized:=normalized_definition(ability_id,definition)
	if ability_id.is_empty(): errors.append("ability_id_required")
	if not ["MELEE","PROJECTILE","DIRECT","AREA","CHAIN"].has(String(normalized.get("delivery_type",""))): errors.append("invalid_delivery_type")
	if not ["SINGLE","ALL_MELEE","ALL_RANGED","ALL_ENEMIES","RANDOM_N","TARGET_ADJACENT"].has(String(normalized.get("target_scope",""))): errors.append("invalid_target_scope")
	var components:Array=normalized.get("components",[])
	if components.is_empty(): errors.append("components_required")
	for raw_component in components:
		if not raw_component is Dictionary:
			errors.append("invalid_component")
			continue
		var kind:=String(raw_component.get("kind",""))
		if not ["damage","effect","heal"].has(kind): errors.append("invalid_component_kind")
		if kind=="damage" and float(raw_component.get("amount",-1.0))<0.0: errors.append("invalid_damage_amount")
		if kind=="effect" and String(raw_component.get("effect_id","")).is_empty(): errors.append("effect_id_required")
	return errors

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
