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

## Persistent current resources: maximums are derived afresh from PAR010/011.
## Equipping +max HP never heals current HP; removing gear only clamps it.
var current_hp: int = 0
var current_mana: int = 0

## TRA definitions are supplied by the caller; no example talents are hardcoded.
## Only learned trait IDs are persistent. Runtime modifiers are rebuilt for combat.
var learned_trait_ids: Array[String] = []

func learn_trait(trait_id: String, definitions: Dictionary) -> bool:
	if in_combat or trait_id.is_empty() or learned_trait_ids.has(trait_id) or not definitions.has(trait_id):
		return false
	var definition: Variant = definitions[trait_id]
	if not definition is Dictionary:
		return false
	if progression.level < int(definition.get("required_level", 1)):
		return false
	learned_trait_ids.append(trait_id)
	return true

func trait_snapshot() -> Array[String]:
	return learned_trait_ids.duplicate()

func restore_traits(ids: Array, definitions: Dictionary) -> bool:
	var restored: Array[String] = []
	for value in ids:
		if not value is String or String(value).is_empty() or restored.has(String(value)) or not definitions.has(String(value)):
			return false
		var definition: Variant = definitions[String(value)]
		if not definition is Dictionary or progression.level < int(definition.get("required_level", 1)):
			return false
		restored.append(String(value))
	learned_trait_ids = restored
	return true


func _init(id: String, name: String, character_level: int = 1) -> void:
	character_id = id
	display_name = name
	progression = CharacterProgression.new(character_level)
	level = progression.level
	inventory = InventoryState.new(character_id)
	equipment = EquipmentState.new()
	var initial_par := ParCalculationService.calculate(self, null)
	if initial_par.is_empty():
		push_error("Character initial resources require canonical PAR010/PAR011")
	else:
		var totals: Dictionary = initial_par["totals"]
		current_hp = maxi(0, 100 + int(totals["PAR010"]))
		current_mana = maxi(0, 30 + int(totals["PAR011"]))

## The only character-side current/max resource read model.
## Its optional canonical PAR snapshot avoids repeating calculations in the builder.
func resource_snapshot(repository: ItemRepository, par_snapshot: Dictionary = {}) -> Dictionary:
	var snapshot := par_snapshot if not par_snapshot.is_empty() else ParCalculationService.calculate(self, repository)
	if snapshot.is_empty():
		return {}
	var totals: Dictionary = snapshot["totals"]
	var maximum_hp := maxi(0, 100 + int(totals["PAR010"]))
	var maximum_mana := maxi(0, 30 + int(totals["PAR011"]))
	current_hp = clampi(current_hp, 0, maximum_hp)
	current_mana = clampi(current_mana, 0, maximum_mana)
	return {"hp":current_hp, "max_hp":maximum_hp, "mana":current_mana, "max_mana":maximum_mana}

func resources_to_dict() -> Dictionary:
	return {"hp": current_hp, "mana": current_mana}

## Validate first; actual caps are applied after inventory/equipment restoration.
func restore_resources(data: Dictionary) -> bool:
	for key in ["hp", "mana"]:
		if not data.has(key) or not CharacterProgression._is_whole_number(data[key]) or int(data[key]) < 0:
			return false
	current_hp = int(data["hp"])
	current_mana = int(data["mana"])
	return true

## Explicit migration/new-character initialization only; not called by equip.
func reset_resources_to_full(repository: ItemRepository) -> bool:
	var snapshot := ParCalculationService.calculate(self, repository)
	if snapshot.is_empty():
		return false
	var totals: Dictionary = snapshot["totals"]
	current_hp = maxi(0, 100 + int(totals["PAR010"]))
	current_mana = maxi(0, 30 + int(totals["PAR011"]))
	return true

func receive_item(instance_id: String, repository: ItemRepository) -> bool:
	return inventory.add_instance(instance_id, repository)

## Atomic replacement: restore the original slots on any failed validation.
## bag_capacity < 0 means capacity is not configured yet.
var bag_capacity: int = -1

func bag_item_count() -> int:
	var count := 0
	for id in inventory.instance_ids():
		if not equipment.is_equipped(String(id)):
			count += 1
	return count

func equip(slot: String, instance_id: String, repository: ItemRepository) -> bool:
	if in_combat or not inventory.owns(instance_id) or not repository.has_item(instance_id):
		return false
	if equipment.is_equipped(instance_id):
		return false
	if slot == "off_hand":
		var main_id: Variant = equipment.get_equipped_instance_id("main_hand")
		if main_id != null and equipment.get_equipped_instance_id("off_hand") == main_id:
			return false # A two-handed MH reserves OH until explicitly unequipped.
	var item := repository.get_item(instance_id)
	if item.is_empty() or not ItemDurabilityService.is_usable(item):
		return false
	var allowed_slots: Array = item.get("equip_slots", [])
	var alternate_ring := (slot == "ring2" and allowed_slots.has("ring1")) or (slot == "ring1" and allowed_slots.has("ring2"))
	if not allowed_slots.has(slot) and not alternate_ring:
		return false
	var usage: Array = item.get("slot_usage", [slot])
	if alternate_ring and not allowed_slots.has(slot) and usage.size() == 1 and (usage[0] == "ring1" or usage[0] == "ring2"):
		usage = [slot]
	if usage.is_empty():
		usage = [slot]
	if not usage.has(slot):
		usage = usage.duplicate()
		usage.append(slot)
	var displaced := {}
	for target in usage:
		if not equipment.slots.has(target):
			return false
		var old_id: Variant = equipment.get_equipped_instance_id(String(target))
		if old_id != null:
			displaced[String(old_id)] = true
	# The incoming item leaves the bag; every displaced item enters it.
	if bag_capacity >= 0 and bag_item_count() - 1 + displaced.size() > bag_capacity:
		return false
	var original := equipment.slots.duplicate(true)
	for target in usage:
		if equipment.get_equipped_instance_id(String(target)) != null:
			equipment.unequip(String(target))
	# Requirements are evaluated after displacement, before candidate bonuses.
	if not meets_requirements(item, repository):
		equipment.slots = original
		return false
	if not EquipmentService.equip_instance(slot, instance_id, inventory, equipment, repository):
		equipment.slots = original
		return false
	# Clamp immediately after a completed equipment mutation; never grant healing.
	resource_snapshot(repository)
	return true

func unequip(slot: String, repository: ItemRepository = null) -> Variant:
	if in_combat:
		return null
	if equipment.get_equipped_instance_id(slot) == null:
		return null
	if bag_capacity >= 0 and bag_item_count() >= bag_capacity:
		return null
	var removed: Variant = equipment.unequip(slot)
	if removed != null and repository != null:
		_revalidate_equipment(repository)
		resource_snapshot(repository)
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
	# Only canonical PAR item bonuses participate in primary-stat requirements.
	for field in ["par_stats", "par_bonuses"]:
		var bonuses: Variant = item.get(field, {})
		if not bonuses is Dictionary:
			continue
		for par_id in progression.base_stats:
			if bonuses.has(par_id):
				stats[par_id] = int(stats[par_id]) + int(bonuses[par_id])

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
