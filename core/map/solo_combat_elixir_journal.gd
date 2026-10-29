class_name SoloCombatElixirJournal
extends RefCounted

## No second item database: consumed elixirs are reconstructed exclusively
## from engine-resolved EFFECT events in the canonical combat checkpoint.
## The expedition revision is pinned by SoloCombatSessionManifest.
static func inspect(state: CombatState, player: CharacterState, repository: ItemRepository) -> Dictionary:
	if state == null or player == null or repository == null:
		return {"ok":false,"reason":"elixir_journal_missing_owner"}
	var uses: Array[Dictionary] = []
	var by_round: Dictionary = {}
	var components_by_round: Dictionary = {}
	var components_seen: Dictionary = {}
	for event in state.event_log:
		if event.kind != CombatEvent.Kind.EFFECT or String(event.payload.get("source_type","")) != "elixir":
			continue
		if event.source_id != player.character_id or event.target_id != player.character_id:
			return {"ok":false,"reason":"elixir_journal_wrong_actor"}
		var item_id := String(event.payload.get("source_instance_id",""))
		var round_number := int(event.payload.get("round",-1))
		if round_number < 1 or round_number > state.round_number or not player.inventory.owns(item_id) or not player.elixir_slots.has(item_id):
			return {"ok":false,"reason":"elixir_journal_invalid_source"}
		var item: Dictionary = repository.get_item(item_id)
		if item.is_empty() or not CombatElixirService.validate_components(item).is_empty():
			return {"ok":false,"reason":"elixir_journal_invalid_item"}
		# Match the resolved EFFECT payload against one authored elixir
		# component. Count alone cannot prove a genuine charge was spent.
		var signatures: Array = components_seen.get(round_number,[])
		var candidates: Array = item.get("elixir_components",[])
		var matched := -1
		for part_index in range(candidates.size()):
			if signatures.has(part_index):
				continue
			var part: Dictionary = candidates[part_index]
			var kind := String(part.get("kind",""))
			var valid := false
			match kind:
				"heal":
					valid = int(event.payload.get("inline_heal",-1)) == int(part.get("amount",0)) and bool(event.payload.get("clamp_heal_to_max",false))
				"mana":
					valid = int(event.payload.get("inline_mana",-1)) == int(part.get("amount",0))
				"effect":
					valid = String(event.payload.get("effect_id","")) == String(part.get("effect_id","")) and bool(event.payload.get("preparation_effect",false))
				"cleanse":
					valid = String(event.payload.get("dispel_polarity","")) == "DEBUFF" and int(event.payload.get("max_effects",-1)) == int(part.get("max_effects",1))
			if valid:
				matched = part_index
				break
		if matched < 0:
			return {"ok":false,"reason":"elixir_journal_component_payload_mismatch"}
		signatures.append(matched)
		components_seen[round_number] = signatures
		components_by_round[round_number] = int(components_by_round.get(round_number,0)) + 1
		if not by_round.has(round_number):
			by_round[round_number] = item_id
			uses.append({"round":round_number,"item_id":item_id})
		elif String(by_round[round_number]) != item_id:
			return {"ok":false,"reason":"elixir_journal_multiple_items_same_round"}
	# One usage may generate multiple component events; group by round.
	uses.sort_custom(func(a: Dictionary,b: Dictionary): return int(a["round"]) < int(b["round"]))
	var counts: Dictionary = {}
	var next_available := 0
	var last_used_round := -1
	for record in uses:
		var number := int(record["round"])
		var id := String(record["item_id"])
		# Each canonical elixir component generates one EFFECT record.
		# A partial or replayed group is not a valid paid use.
		var definition_item := repository.get_item(id)
		if int(components_by_round.get(number,0)) != Array(definition_item.get("elixir_components",[])).size():
			return {"ok":false,"reason":"elixir_journal_component_count_mismatch"}
		if number < next_available:
			return {"ok":false,"reason":"elixir_journal_shared_cooldown_broken"}
		counts[id] = int(counts.get(id,0)) + 1
		var item: Dictionary = repository.get_item(id)
		var max_charges := int(item.get("max_charges",0))
		var current := int(item.get("charges",-1))
		if max_charges < 1 or current < 0 or current > max_charges:
			return {"ok":false,"reason":"elixir_journal_invalid_charges"}
		last_used_round = number
		next_available = number + maxi(0,int(item.get("cooldown_rounds",1))) + 1
	return {"ok":true,"uses":uses,"counts":counts,"next_available_round":next_available,"last_used_round":last_used_round}

## Compare a pinned PRECOMBAT repository with the checkpoint and create a
## validated new instance table. This never mutates the input repository.
static func apply_to_baseline(state: CombatState, player: CharacterState, baseline: ItemRepository) -> Dictionary:
	var audit := inspect(state,player,baseline)
	if not bool(audit.get("ok",false)):
		return audit
	var copied := ItemRepository.from_dict(baseline.to_dict())
	for raw_id in Dictionary(audit["counts"]).keys():
		var id := String(raw_id)
		var item := copied.get_item(id)
		var spent := int(audit["counts"][id])
		var original := int(item.get("charges",-1))
		if original < spent:
			return {"ok":false,"reason":"elixir_journal_overspends_item","instance_id":id}
		item["charges"] = original - spent
		if not copied.update_item(item):
			return {"ok":false,"reason":"elixir_journal_update_failed"}
	return {"ok":true,"repository":copied,"audit":audit}

## JSON round-trips may change numeric Variant types at ANY nesting
## depth (e.g. rarity metadata 1 -> 1.0). Compare every key and element,
## accepting only value-equivalent numbers. Never omit a property.
static func _same_json_value(left: Variant, right: Variant) -> bool:
	if left is Dictionary:
		if not right is Dictionary:
			return false
		var a: Dictionary = left
		var b: Dictionary = right
		if a.size() != b.size():
			return false
		for key in a.keys():
			if not b.has(key) or not _same_json_value(a[key],b[key]):
				return false
		return true
	if left is Array:
		if not right is Array:
			return false
		var a: Array = left
		var b: Array = right
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _same_json_value(a[i],b[i]):
				return false
		return true
	if left is int or left is float:
		if not (right is int or right is float):
			return false
		if left is int and right is int:
			return left == right
		return is_finite(float(left)) and is_finite(float(right)) and float(left) == float(right)
	# Strings, bools and nulls must retain their exact JSON kind and value.
	return typeof(left) == typeof(right) and left == right

static func same_repository(expected: ItemRepository, staged: ItemRepository) -> bool:
	if expected == null or staged == null:
		return false
	return _same_json_value(expected.to_dict(),staged.to_dict())

static func preflight(state: CombatState, player: CharacterState, repository: ItemRepository, slot: int) -> Dictionary:
	if slot < 0:
		return {"ok":true,"item_id":""}
	var loadout := SoloCombatElixirLoadout.inspect(player,repository)
	if not bool(loadout.get("ok",false)):
		return loadout
	var entries: Array = loadout["slots"]
	if slot >= entries.size():
		return {"ok":false,"reason":"elixir_slot_out_of_range"}
	var entry: Dictionary = entries[slot]
	if not bool(entry.get("unlocked",false)) or not bool(entry.get("valid",false)):
		return {"ok":false,"reason":"elixir_slot_unavailable"}
	var audit := inspect(state,player,repository)
	if not bool(audit.get("ok",false)):
		return audit
	if state.round_number + 1 < int(audit["next_available_round"]):
		return {"ok":false,"reason":"elixir_shared_cooldown"}
	var actor := state.get_combatant(player.character_id)
	if actor == null or actor.is_death_finalized() or actor.hp <= 0 or CombatTempoService.is_stunned(actor,state.round_number+1):
		return {"ok":false,"reason":"elixir_actor_unavailable"}
	return {"ok":true,"item_id":String(entry["instance_id"]),"slot":slot,"audit":audit}
