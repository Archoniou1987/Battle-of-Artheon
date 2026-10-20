class_name CombatElixirService
extends RefCounted

## Consumables are immediate Mind Game actions. They change combat state
## through CombatEngine EFFECT events, never through alternate damage formulas.
## Their inventory charges are written to ItemRepository only after validation.
var state: CombatState
var engine: CombatEngine
var next_available_round: Dictionary = {}
var used_round: Dictionary = {}

func _init(p_state: CombatState, p_engine: CombatEngine) -> void:
	state = p_state
	engine = p_engine

static func validate_components(item: Dictionary) -> String:
	if String(item.get("type", "")) != "consumable":
		return "not_consumable"
	var components: Variant = item.get("elixir_components", [])
	if not components is Array or components.is_empty():
		return "missing_elixir_components"
	for raw in components:
		if not raw is Dictionary:
			return "invalid_elixir_component"
		var part: Dictionary = raw
		var kind := String(part.get("kind", ""))
		match kind:
			"heal", "mana":
				if int(part.get("amount", 0)) <= 0:
					return "invalid_recovery_amount"
			"effect":
				var effect_id := String(part.get("effect_id", ""))
				if effect_id.is_empty() or EffectCatalog.definition(EffectCatalog.load_json(), effect_id).is_empty():
					return "unknown_effect"
				# Consumables cannot be used to bypass Standard ABI DoT/HoT.
				var effect := EffectCatalog.definition(EffectCatalog.load_json(), effect_id)
				if String(effect.get("kind", "")).to_lower() in ["dot", "hot"] or float(effect.get("damage", 0.0)) > 0.0 or float(effect.get("healing", 0.0)) > 0.0:
					return "periodic_effect_not_preparation"
			"cleanse":
				if String(part.get("dispel_polarity", "")).to_upper() != "DEBUFF" or int(part.get("max_effects", 1)) < 1:
					return "invalid_cleanse"
			_:
				return "invalid_elixir_component_kind"
	return ""

func can_use(source: CombatantState, round_number: int) -> bool:
	return source != null and not source.is_death_finalized() and source.hp > 0 and not CombatTempoService.is_stunned(source, round_number) and int(used_round.get(source.combatant_id, -1)) != round_number and round_number >= int(next_available_round.get(source.combatant_id, 0))

func remaining_cooldown(source_id: String, round_number: int) -> int:
	return maxi(0, int(next_available_round.get(source_id, 0)) - round_number)

func use(source_id: String, item_id: String, repository: ItemRepository) -> Dictionary:
	var source := state.get_combatant(source_id)
	if not can_use(source, state.round_number):
		return {"ok":false, "reason":"elixir_unavailable"}
	var item := repository.get_item(item_id)
	var error := validate_components(item)
	if not error.is_empty():
		return {"ok":false, "reason":error}
	var charges := int(item.get("charges", 0))
	if charges <= 0 or charges > maxi(1, int(item.get("max_charges", 1))):
		return {"ok":false, "reason":"invalid_charges"}
	# The state has already been validated; each component uses the
	# same canonical engine path used by ABI/EFF processing.
	var event_ids: Array[int] = []
	for raw in Array(item["elixir_components"]):
		var part: Dictionary = raw
		var payload: Dictionary = {"source_type":"elixir", "source_instance_id":item_id}
		match String(part.get("kind", "")):
			"heal":
				payload["inline_heal"] = int(part["amount"])
				payload["clamp_heal_to_max"] = true
			"mana":
				payload["inline_mana"] = int(part["amount"])
			"effect":
				payload["effect_id"] = String(part["effect_id"])
				payload["base_chance"] = 100.0
				payload["effect_roll"] = 1
				payload["preparation_effect"] = true
			"cleanse":
				payload["dispel_polarity"] = "DEBUFF"
				payload["max_effects"] = int(part.get("max_effects", 1))
		var event := state.create_event(CombatEvent.Kind.EFFECT, source_id, source_id, payload)
		engine.resolve_event(event)
		event_ids.append(event.event_id)
	item["charges"] = charges - 1
	if not repository.update_item(item):
		push_error("Validated elixir instance vanished before charge commit: " + item_id)
		return {"ok":false, "reason":"repository_update_failed"}
	used_round[source_id] = state.round_number
	var cooldown: int = maxi(0, int(item.get("cooldown_rounds", 1)))
	next_available_round[source_id] = state.round_number + cooldown + 1
	return {"ok":true, "charges":int(item["charges"]), "event_ids":event_ids}
