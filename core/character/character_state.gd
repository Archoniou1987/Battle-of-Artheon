class_name CharacterState
extends RefCounted

## Persistent gameplay ownership state. CombatantState remains combat-runtime only.
var character_id: String
var display_name: String
var level: int
var progression: CharacterProgression
var inventory: InventoryState
var equipment: EquipmentState
var in_combat := false

func _init(id: String, name: String, character_level: int = 1) -> void:
	character_id = id
	display_name = name
	progression = CharacterProgression.new(character_level)
	level = progression.level
	inventory = InventoryState.new(character_id)
	equipment = EquipmentState.new()

func receive_item(instance_id: String, repository: ItemRepository) -> bool:
	return inventory.add_instance(instance_id, repository)

func equip(slot: String, instance_id: String, repository: ItemRepository) -> bool:
	if in_combat or not repository.has_item(instance_id):
		return false
	var item := repository.get_item(instance_id)
	if not meets_requirements(item, repository):
		return false
	return EquipmentService.equip_instance(slot, instance_id, inventory, equipment, repository)

func unequip(slot: String, repository: ItemRepository = null) -> Variant:
	if in_combat:
		return null
	var removed: Variant = equipment.unequip(slot)
	if removed != null and repository != null:
		_revalidate_equipment(repository)
	return removed

func effective_stats(repository: ItemRepository, excluded_id: String = "") -> Dictionary:
	var result := progression.base_stats.duplicate(true)
	var seen := {}
	for slot in EquipmentState.SLOTS:
		var raw_id: Variant = equipment.get_equipped_instance_id(slot)
		if raw_id == null:
			continue
		var id := String(raw_id)
		if id == excluded_id or seen.has(id):
			continue
		seen[id] = true
		var item := repository.get_item(id)
		for field in ["guaranteed_stats", "bonuses"]:
			var bonuses: Variant = item.get(field, {})
			if not bonuses is Dictionary:
				continue
			for stat in progression.base_stats:
				if bonuses.has(stat):
					result[stat] = int(result[stat]) + int(bonuses[stat])
	return result

func meets_requirements(item: Dictionary, repository: ItemRepository, include_own_bonuses: bool = false) -> bool:
	var requirements: Variant = item.get("requirements", {})
	if not requirements is Dictionary:
		return false
	var excluded_id := "" if include_own_bonuses else String(item.get("instance_id", ""))
	var stats := effective_stats(repository, excluded_id)
	for stat in requirements:
		if not stats.has(stat) or int(stats[stat]) < int(requirements[stat]):
			return false
	return true

func _revalidate_equipment(repository: ItemRepository) -> void:
	var changed := true
	while changed:
		changed = false
		var seen := {}
		for slot in EquipmentState.SLOTS:
			var raw_id: Variant = equipment.get_equipped_instance_id(slot)
			if raw_id == null:
				continue
			var id := String(raw_id)
			if seen.has(id):
				continue
			seen[id] = true
			if not meets_requirements(repository.get_item(id), repository, true):
				equipment.unequip(slot)
				changed = true
				break

func remove_item(instance_id: String) -> bool:
	return inventory.remove_instance(instance_id, equipment)

## Character-level progression is kept outside the combat runtime.
func award_xp(amount: int) -> int:
	var gained := progression.gain_xp(amount)
	level = progression.level
	return gained

func allocate_stat(stat: String) -> bool:
	return progression.allocate_stat(stat)

func progression_snapshot() -> Dictionary:
	return progression.to_dict()

func restore_progression(data: Dictionary) -> bool:
	if not progression.restore(data):
		return false
	level = progression.level
	return true
