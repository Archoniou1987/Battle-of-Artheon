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

## Rebuild activation from base stats. Only already-active items grant bonuses.
## A mutually dependent pair cannot activate itself without an independent source.
func active_equipment_ids(repository: ItemRepository) -> Dictionary:
	var active := {}
	var stats := progression.base_stats.duplicate(true)
	var pending := {}
	for slot in EquipmentState.SLOTS:
		var raw_id: Variant = equipment.get_equipped_instance_id(slot)
		if raw_id != null:
			pending[String(raw_id)] = true
	var progress := true
	while progress:
		progress = false
		for slot in EquipmentState.SLOTS:
			var raw_id: Variant = equipment.get_equipped_instance_id(slot)
			if raw_id == null:
				continue
			var id := String(raw_id)
			if not pending.has(id):
				continue
			var item := repository.get_item(id)
			if item.is_empty() or not ItemDurabilityService.is_usable(item):
				continue
			if not _requirements_match(item, stats):
				continue
			active[id] = true
			pending.erase(id)
			_add_primary_bonuses(stats, item)
			progress = true
	return active

func is_equipment_active(instance_id: String, repository: ItemRepository) -> bool:
	return active_equipment_ids(repository).has(instance_id)

func effective_stats(repository: ItemRepository, excluded_id: String = "") -> Dictionary:
	var result := progression.base_stats.duplicate(true)
	var active := active_equipment_ids(repository)
	for slot in EquipmentState.SLOTS:
		var raw_id: Variant = equipment.get_equipped_instance_id(slot)
		if raw_id == null:
			continue
		var id := String(raw_id)
		if id == excluded_id or not active.has(id):
			continue
		active.erase(id)
		_add_primary_bonuses(result, repository.get_item(id))
	return result

func _add_primary_bonuses(stats: Dictionary, item: Dictionary) -> void:
	for field in ["guaranteed_stats", "bonuses"]:
		var bonuses: Variant = item.get(field, {})
		if not bonuses is Dictionary:
			continue
		for stat in progression.base_stats:
			if bonuses.has(stat):
				stats[stat] = int(stats[stat]) + int(bonuses[stat])

func _requirements_match(item: Dictionary, stats: Dictionary) -> bool:
	var requirements: Variant = item.get("requirements", {})
	if not requirements is Dictionary:
		return false
	for stat in requirements:
		if not stats.has(stat) or int(stats[stat]) < int(requirements[stat]):
			return false
	return true

func meets_requirements(item: Dictionary, repository: ItemRepository, include_own_bonuses: bool = false) -> bool:
	var excluded_id := "" if include_own_bonuses else String(item.get("instance_id", ""))
	return _requirements_match(item, effective_stats(repository, excluded_id))

## No automatic unequip: invalid gear remains in its slot and loses all effects.
func _revalidate_equipment(_repository: ItemRepository) -> void:
	pass

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
