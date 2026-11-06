class_name AbilityRuntime
extends RefCounted

static func can_use(ability_id: String, cooldowns: Dictionary, round_number: int) -> bool:
	return round_number >= int(cooldowns.get(ability_id, 0))

## Number of full rounds still blocking the selected upcoming round.
static func remaining_cooldown(ability_id: String, cooldowns: Dictionary, round_number: int) -> int:
	return maxi(0,int(cooldowns.get(ability_id,0)) - round_number)

static func start_cooldown(ability_id: String, cooldowns: Dictionary, round_number: int, cooldown_rounds: int) -> void:
	cooldowns[ability_id] = round_number + cooldown_rounds + 1

## Hand-authored ABI timing: both settings resolve in the SAME round.
## "instant" executes before the shared calculations; "standard" is part
## of the normal end-of-round combat calculation. Never infer from EFF type.
static func application_timing(definition: Dictionary) -> String:
	return String(definition.get("application_timing", "standard")).to_lower()

## A trigger is a historical eligibility check; it never creates an attack by itself.
static func previous_round_trigger_met(state: CombatState, source_id: String, trigger: String, planned_round: int = -1) -> bool:
	if trigger.is_empty():
		return true
	# Arena preflight runs before begin_round; Scheduler runs after it. Both
	# must inspect the same previous finished round without off-by-one drift.
	var evaluating_round := state.round_number if planned_round < 0 else planned_round
	if evaluating_round < 2:
		return false
	for event in state.event_log:
		if int(event.payload.get("round",-1)) != evaluating_round - 1:
			continue
		if trigger == "block" and event.target_id == source_id and String(event.result.get("outcome","")) in ["manual_block","auto_block"]:
			return true
		if trigger == "dodge" and event.target_id == source_id and String(event.result.get("outcome","")) == "dodge":
			return true
		if trigger == "crit" and event.source_id == source_id and event.kind == CombatEvent.Kind.ATTACK and bool(event.result.get("critical",false)):
			return true
		if trigger == "crit_or_block_crush" and event.source_id == source_id and event.kind == CombatEvent.Kind.ATTACK:
			if bool(event.result.get("critical",false)) or bool(event.result.get("manual_block_crushed",false)) or bool(event.result.get("auto_block_crushed",false)):
				return true
		if trigger == "damage_dealt" and event.source_id == source_id and event.kind == CombatEvent.Kind.DAMAGE and int(event.result.get("final_damage",0)) > 0:
			return true
		if trigger == "damage_taken" and event.target_id == source_id and event.kind == CombatEvent.Kind.DAMAGE and int(event.result.get("final_damage",0)) > 0:
			return true
	return false

static func action_point_cost(definition: Dictionary, source: CombatantState) -> int:
	if bool(definition.get("consume_all_ap",false)):
		return source.action_points
	return maxi(0,int(definition.get("ap_cost",0)))

static func can_pay_action_points(definition: Dictionary, source: CombatantState) -> bool:
	if bool(definition.get("consume_all_ap",false)):
		return source.action_points >= maxi(0,int(definition.get("min_ap_cost",0)))
	return source.action_points >= maxi(0,int(definition.get("ap_cost",0)))

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
	normalized["is_counterattack_abi"] = bool(definition.get("is_counterattack_abi", false))
	normalized["trigger_previous_round"] = String(definition.get("trigger_previous_round", ""))
	normalized["ap_gain"] = maxi(0,int(definition.get("ap_gain", 0)))
	normalized["ap_cost"] = maxi(0,int(definition.get("ap_cost", 0)))
	normalized["consume_all_ap"] = bool(definition.get("consume_all_ap", false))
	normalized["min_ap_cost"] = maxi(0,int(definition.get("min_ap_cost", 0)))
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
	var trigger := String(normalized.get("trigger_previous_round",""))
	if not trigger.is_empty() and not ["block","dodge","crit","crit_or_block_crush","damage_dealt","damage_taken"].has(trigger):
		errors.append("invalid_previous_round_trigger")
	if int(definition.get("ap_gain",0)) < 0 or int(definition.get("ap_cost",0)) < 0 or int(definition.get("min_ap_cost",0)) < 0:
		errors.append("invalid_ap_amount")
	if bool(normalized.get("consume_all_ap",false)) and int(normalized.get("ap_cost",0)) > 0:
		errors.append("ambiguous_ap_cost")
	if bool(normalized.get("is_counterattack_abi",false)):
		if not ["block","dodge","crit"].has(trigger):
			errors.append("counter_abi_trigger_required")
		if normalized.get("delivery_type","") != "MELEE" or normalized.get("target_scope","") != "SINGLE" or bool(normalized.get("uses_magic_hit",false)):
			errors.append("counter_abi_requires_single_physical_melee")
		if int(normalized.get("ap_cost",0)) <= 0 and not bool(normalized.get("consume_all_ap",false)):
			errors.append("counter_abi_ap_cost_required")
		if components.size()!=1 or not components[0] is Dictionary or String(components[0].get("kind",""))!="damage" or not CombatDamagePayload.is_physical_damage_type(String(components[0].get("damage_type","physical"))):
			errors.append("counter_abi_physical_damage_only")
	for raw_component in components:
		if not raw_component is Dictionary:
			errors.append("invalid_component")
			continue
		var kind:=String(raw_component.get("kind",""))
		if not ["damage","effect","heal","cleanse"].has(kind): errors.append("invalid_component_kind")
		if kind=="cleanse" and not ["BUFF","DEBUFF"].has(String(raw_component.get("dispel_polarity","")).to_upper()): errors.append("invalid_dispel_polarity")
		if kind=="damage" and float(raw_component.get("amount",-1.0))<0.0: errors.append("invalid_damage_amount")
		# Optional non-negative K only for direct magic damage or healing.
		# Reject silently ignored K on physical attacks or effects/DoT.
		if raw_component.has("spell_power_scale"):
			var k: Variant = raw_component["spell_power_scale"]
			if not RatingMatrix._number(k) or float(k)<0.0:
				errors.append("invalid_spell_power_scale")
			elif not (kind=="heal" or (kind=="damage" and CombatDamagePayload.is_magic_damage_type(String(raw_component.get("damage_type","physical"))))):
				errors.append("spell_power_scale_requires_magic_damage_or_heal")
		if kind=="effect" and String(raw_component.get("effect_id","")).is_empty(): errors.append("effect_id_required")
		# Timings are hand-authored. Reject an incompatible instant ABI rather
		# than silently rewriting it; periodic damage/healing still means Standard.
		if application_timing(definition)=="instant":
			if kind in ["damage","heal"]:
				errors.append("instant_damage_or_heal_requires_standard")
			elif kind=="effect":
				var eff: Dictionary = EffectCatalog.definition(EffectCatalog.load_json(),String(raw_component.get("effect_id","")))
				if String(eff.get("kind","")).to_lower() in ["dot","hot","heal"] or float(eff.get("damage",0.0))>0.0 or float(eff.get("healing",0.0))>0.0:
					errors.append("instant_periodic_damage_or_heal_requires_standard")
	if String(normalized.get("combat_role","")).to_upper()=="CLEANSE" and not ["ALLY","ENEMY"].has(String(normalized.get("target_team","")).to_upper()):
		errors.append("cleanse_target_team_required")
	return errors

static func build_action_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	var normalized := normalized_definition(ability_id, definition)
	var event := state.create_event(CombatEvent.Kind.ACTION, source_id, target_id, {
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
		"is_counterattack_abi": normalized["is_counterattack_abi"],
		"trigger_previous_round": normalized["trigger_previous_round"],
		"ap_cost": normalized["ap_cost"],
		"ap_gain": normalized["ap_gain"],
		"consume_all_ap": normalized["consume_all_ap"],
		"target_team": String(definition.get("target_team", "")),
		"engagement": normalized["engagement"],
		"rolls": definition.get("rolls", {}).duplicate(true) if definition.get("rolls", {}) is Dictionary else {},
		# Zero requests a seeded roll from CombatEngine; explicit 1..100 is a test override.
		"magic_hit_roll": int(definition.get("magic_hit_roll",0)),
		"target_zone_id": int(definition.get("target_zone_id", definition.get("zone_id",-1))),
		"components": normalized["components"],
		"target_ids": [target_id]
	})
	if not String(definition.get("sword_ability_mode","")).is_empty():
		for field in ["sword_ability_mode","sword_mh_multiplier","sword_eff_id","sword_eff_level",
			"mh_flat_bonus","armor_per_ap","max_targets","crit_pct_per_ap","crit_damage_pct_per_ap","bleed_ticks"]:
			if definition.has(field):
				event.payload[field] = definition[field]
	return event


static func build_damage_event(state: CombatState, source_id: String, target_id: String, ability_id: String, definition: Dictionary) -> CombatEvent:
	# Legacy compatibility: callers now receive the universal action intent.
	return build_action_event(state, source_id, target_id, ability_id, definition)
