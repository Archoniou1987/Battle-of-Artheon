class_name SoloCombatElixirLoadout
extends RefCounted

## Pure, read-only persistent ownership projection for live Solo combat.
## Do NOT mutate the repository here: round checkpoints cannot yet publish
## consumable charge mutations to both victory and defeat world snapshots.
const SLOT_COUNT := 4

static func inspect(character: CharacterState, repository: ItemRepository) -> Dictionary:
	if character == null or repository == null:
		return {"ok":false,"reason":"elixir_owner_missing"}
	var capacity := character.elixir_capacity(repository)
	if capacity < 0 or capacity > SLOT_COUNT or character.elixir_slots.size() != SLOT_COUNT:
		return {"ok":false,"reason":"elixir_slot_contract_invalid"}
	var slots: Array[Dictionary] = []
	var seen: Dictionary = {}
	for i in range(SLOT_COUNT):
		var id := String(character.elixir_slots[i])
		var entry: Dictionary = {
			"slot":i,
			"unlocked":i < capacity,
			"instance_id":id,
			"charges":0,
			"max_charges":0,
			"cooldown_rounds":0,
			"valid":false,
			"reason":"locked" if i >= capacity else "empty"
		}
		if id.is_empty():
			slots.append(entry)
			continue
		if i >= capacity:
			return {"ok":false,"reason":"elixir_assigned_to_locked_slot","slot":i}
		if seen.has(id) or not character.inventory.owns(id) or character.equipment.is_equipped(id) or not repository.has_item(id):
			return {"ok":false,"reason":"elixir_slot_owner_mismatch","slot":i}
		seen[id] = true
		var item: Dictionary = repository.get_item(id)
		var reason := CombatElixirService.validate_components(item)
		var charges := int(item.get("charges",0))
		var maximum := int(item.get("max_charges",0))
		if reason.is_empty() and (maximum < 1 or charges < 0 or charges > maximum):
			reason = "elixir_invalid_charges"
		if reason.is_empty() and charges == 0:
			reason = "elixir_depleted"
		entry["charges"] = charges
		entry["max_charges"] = maximum
		entry["cooldown_rounds"] = maxi(0,int(item.get("cooldown_rounds",1)))
		entry["valid"] = reason.is_empty()
		entry["reason"] = reason
		slots.append(entry)
	return {"ok":true,"capacity":capacity,"slots":slots}
