class_name EquipmentAbilityLoadout
extends RefCounted

const WEAPON_SLOTS := ["main_hand", "off_hand"]
const MAX_WEAPON_ABILITIES := 3

## Builds five ABI slots from actual equipped item instances:
## weapon[0..2], chest[0], head[0]. Empty positions remain null.
static func build(character: CharacterState, repository: ItemRepository) -> Dictionary:
	var weapon: Array = [null, null, null]
	var chest: Array = [null]
	var head: Array = [null]
	var seen := {}
	var weapon_index := 0
	for slot in WEAPON_SLOTS:
		var item := ItemResolver.resolve_equipped(slot, character.equipment, repository)
		for raw_id in item.get("abilities", []):
			var ability_id := String(raw_id)
			if ability_id.is_empty() or seen.has(ability_id) or weapon_index >= MAX_WEAPON_ABILITIES:
				continue
			weapon[weapon_index] = ability_id
			seen[ability_id] = true
			weapon_index += 1
	chest[0] = _first_unique_ability("chest", character, repository, seen)
	if chest[0] != null: seen[String(chest[0])] = true
	head[0] = _first_unique_ability("head", character, repository, seen)
	return {"weapon": weapon, "chest": chest, "head": head}

static func active_abilities(character: CharacterState, repository: ItemRepository) -> Array[String]:
	var result: Array[String] = []
	var slots := build(character, repository)
	for group in ["weapon", "chest", "head"]:
		for value in slots[group]:
			if value != null: result.append(String(value))
	return result

## CombatSimulator already consumes fighter_data["abilities"]. This adapter makes
## equipped items the authoritative source without coupling the simulator to inventory.
static func apply_to_combat_data(fighter_data: Dictionary, character: CharacterState, repository: ItemRepository) -> Dictionary:
	var combat_data := fighter_data.duplicate(true)
	combat_data["abilities"] = active_abilities(character, repository)
	return combat_data

static func _first_unique_ability(slot: String, character: CharacterState, repository: ItemRepository, seen: Dictionary) -> Variant:
	var item := ItemResolver.resolve_equipped(slot, character.equipment, repository)
	for raw_id in item.get("abilities", []):
		var ability_id := String(raw_id)
		if not ability_id.is_empty() and not seen.has(ability_id): return ability_id
	return null
