class_name AbilityRuntime
extends RefCounted

static func can_use(ability_id: String, cooldowns: Dictionary, round_number: int) -> bool:
	return round_number >= int(cooldowns.get(ability_id, 0))

static func start_cooldown(ability_id: String, cooldowns: Dictionary, round_number: int, cooldown_rounds: int) -> void:
	cooldowns[ability_id] = round_number + cooldown_rounds + 1

## Hand-authored ABI timing: both settings resolve in the SAME round.
## "instant" executes before the shared calculations; "standard" is part
## of the normal end-of-round combat calculation. Never infer from EFF type.
static func application_timing(definition: Dictionary) -> String:
	return String(definition.get("application_timing", "standard")).to_lower()

static func normalized_definition(ability_id: String, definition: Dictionary) -> Dictionary:
	var normalized := definition.duplicate(true)
	normalized["ability_id"] = ability_id
	normalized["application_timing"] = application_timing(definition)
	normalized["delivery_type"] = String(definition.get("delivery_type", "DIRECT")).to_upper()
	normalized["target_scope"] = String(definition.get("target_scope", "SINGLE")).to_upper()
	normalized["duration_rounds"] = maxi(0, int(definition.get("duration_rounds", 0)))
	normalized["min_zone_distance"] = maxi(0, int(definition.get("min_zone_distance", 0)))
	normalized["max_zone_distance"] = maxi(int(normalized["min_zone_distance"]), int(definition.get("max_zone_distance", 0 if normalized["delivery_type"]=="MELEE" else 2)))
	normalized["two_zone_hit_modifier"] = float(definition.get("two_zone_hit_modifier", -50.0))
	normalized["uses_magic_hit"] = bool(definition.get("uses_magic_hit", false))
	normalized["magic_hit_modifier"] = float(definition.get("magic_hit_modifier", 0.0))
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
	if not ["instant","standard"].has(application_timing(definition)): errors.append("invalid_application_timing")
	if not ["MELEE","PROJECTILE","DIRECT","AREA","CHAIN"].has(String(normalized.get("delivery_type",""))): errors.append("invalid_delivery_type")
	if not ["SINGLE","ALL_MELEE","ALL_RANGED","ALL_ENEMIES","RANDOM_N","TARGET_ADJACENT"].has(String(normalized.get("target_scope",""))): errors.append("invalid_target_scope")
	var components:Array=normalized.get("components",[])
	if components.is_empty(): errors.append("components_required")
	for raw_component in components:
		if not raw_component is Dictionary:
			errors.append("invalid_component")
			continue
		var kind:=String(raw_component.get("kind",""))
		if not ["damage","effect","heal","cleanse"].has(kind): errors.append("invalid_component_kind")
		if kind=="cleanse" and not ["BUFF","DEBUFF"].has(String(raw_component.get("dispel_polarity","")).to_upper()): errors.append("invalid_dispel_polarity")
		if kind=="damage" and float(raw_component.get("amount",-1.0))<0.0: errors.append("invalid_damage_amount")
		if kind=="effect" and String(raw_component.get("effect_id","")).is_empty(): errors.append("effect_id_required")
	if String(normalized.get("combat_role","")).to_upper()=="CLEANSE" and not ["ALLY","ENEMY"].has(String(normalized.get("target_team","")).to_upper()):
		errors.append("cleanse_target_team_required")
	return errors

static func build_action_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	var normalized := normalized_definition(ability_id, definition)
	return state.create_event(CombatEvent.Kind.ACTION, source_id, target_id, {
		"ability_id": ability_id,
		"source_kind": "ability",
		"application_timing": normalized["application_timing"],
		"delivery_type": normalized["delivery_type"],
		"target_scope": normalized["target_scope"],
		"duration_rounds": normalized["duration_rounds"],
		"min_zone_distance": normalized["min_zone_distance"],
		"max_zone_distance": normalized["max_zone_distance"],
		"two_zone_hit_modifier": normalized["two_zone_hit_modifier"],
		"uses_magic_hit": normalized["uses_magic_hit"],
		"magic_hit_modifier": normalized["magic_hit_modifier"],
		"target_team": String(definition.get("target_team", "")),
		"engagement": normalized["engagement"],
		"rolls": definition.get("rolls", {}).duplicate(true) if definition.get("rolls", {}) is Dictionary else {},
		# Zero requests a seeded roll from CombatEngine; explicit 1..100 is a test override.
		"magic_hit_roll": int(definition.get("magic_hit_roll",0)),
		"target_zone_id": int(definition.get("target_zone_id", definition.get("zone_id",-1))),
		"components": normalized["components"],
		"target_ids": [target_id]
	})


static func build_damage_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	# Legacy compatibility: callers now receive the universal action intent.
	return build_action_event(state, source_id, target_id, ability_id, definition)
