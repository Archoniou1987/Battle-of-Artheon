class_name EquipmentAbilityLoadout
extends RefCounted

## Off-hand weapons contribute physical attacks and hit effects, NEVER active weapon ABI.
const WEAPON_SLOTS := ["main_hand"]
const MAX_WEAPON_ABILITIES := 4

## Builds six ABI slots from equipped items:
## weapon[0..3], chest[0], head[0]. Empty positions remain null.
static func build(character: CharacterState, repository: ItemRepository) -> Dictionary:
	var weapon: Array = [null, null, null, null]
	var chest: Array = [null]
	var head: Array = [null]
	var seen := {}
	var weapon_index := 0
	for slot in WEAPON_SLOTS:
		var item := ItemResolver.resolve_equipped(slot, character.equipment, repository)
		if not ItemDurabilityService.is_usable(item):
			continue
		var ids: Array = Array(item.get("abilities",[]))
		# Read-only upgrade for persisted v1.2 dagger items authored before ABI v2.
		# Item ownership and saved rolls are unchanged; generator remains sole ABI owner.
		var old_archetype := String(item.get("generated_from_template",""))
		if String(item.get("origin","")) == "v12_game_generator" and old_archetype in ["DAGGER_ATTACK","DAGGER_DEF","DAGGER_PEN"] and ids.size() == 4 and ids != ItemV12InstanceFactory._physical_weapon_abilities(old_archetype):
			ids = ItemV12InstanceFactory._physical_weapon_abilities(old_archetype)
		for raw_id in ids:
			var ability_id := String(raw_id)
			if ability_id.is_empty() or AbilityCatalog.is_retired_numbered_abi(ability_id) or seen.has(ability_id) or weapon_index >= MAX_WEAPON_ABILITIES:
				continue
			weapon[weapon_index] = ability_id
			seen[ability_id] = true
			weapon_index += 1
	# Resolve in visible slot order: Chest 5 takes precedence over Head 6
	# if two equipped items supply the same ABI ID.
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
	if not ItemDurabilityService.is_usable(item):
		return null
	for raw_id in item.get("abilities", []):
		var ability_id := String(raw_id)
		if not ability_id.is_empty() and not AbilityCatalog.is_retired_numbered_abi(ability_id) and not seen.has(ability_id): return ability_id
	return null
