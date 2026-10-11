class_name CharacterCombatBuilder
extends RefCounted

## Converts persistent CharacterState into the exact runtime snapshot used by combat and UI stats.
static func build(character:CharacterState, repository:ItemRepository, base:Dictionary = {}) -> CombatantState:
	var base_stats:Dictionary = base.get("stats", {}).duplicate(true)
	var end_value := float(base_stats.get("END", 0.0))
	var wis_value := float(base_stats.get("WIS", 0.0))
	var health := int(base.get("health", 100 + int(end_value) * 10))
	var mana_pool := int(base.get("mana", int(wis_value) * 15))
	var combatant := CombatantState.new(character.character_id, character.display_name, character.level, health, mana_pool)
	combatant.stats = base_stats
	combatant.combat_stats = base.get("combat_stats", {}).duplicate(true)
	combatant.armour = base.get("armour", {}).duplicate(true)
	combatant.tempo = float(base.get("tempo", 0.0))
	combatant.max_action_points = int(base.get("max_action_points", 5))
	for item in equipped_items(character, repository): EquipmentBuilder.equip(combatant, item)
	# Primary-stat resource bonuses from equipment are resolved after all items are equipped.
	var equipped_end := float(combatant.stats.get("END", 0.0)) - end_value
	var equipped_wis := float(combatant.stats.get("WIS", 0.0)) - wis_value
	combatant.max_hp += int(equipped_end) * 10
	combatant.hp = combatant.max_hp
	combatant.max_mana += int(equipped_wis) * 15
	combatant.mana = combatant.max_mana
	combatant.combat_stats["abilities"] = EquipmentAbilityLoadout.active_abilities(character, repository)
	var main_hand_id:Variant=character.equipment.get_equipped_instance_id("main_hand")
	var main_hand:=repository.get_item(String(main_hand_id)) if main_hand_id!=null and character.is_equipment_active(String(main_hand_id), repository) else {}
	var weapon_class:=String(main_hand.get("weapon_class",main_hand.get("subtype",""))).to_lower()
	var is_bow:=weapon_class.contains("bow")
	combatant.combat_stats["can_manual_block"]=not is_bow
	combatant.combat_stats["can_auto_block"]=not is_bow
	combatant.lock_combat_loadout({
		"equipment_slots":character.equipment.slots.duplicate(true),
		"main_hand_instance_id":String(main_hand_id) if main_hand_id!=null else "",
		"weapon_class":weapon_class,
		"can_manual_block":not is_bow,
		"can_auto_block":not is_bow,
		"abilities":combatant.combat_stats["abilities"].duplicate(true)
	})
	return combatant

static func equipped_items(character:CharacterState, repository:ItemRepository) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var seen:Dictionary = {}
	var active:Dictionary = character.active_equipment_ids(repository)
	for slot in EquipmentState.SLOTS:
		var value:Variant = character.equipment.get_equipped_instance_id(slot)
		if value == null: continue
		var instance_id := String(value)
		if instance_id.is_empty() or seen.has(instance_id) or not active.has(instance_id): continue
		var item := repository.get_item(instance_id)
		if item.is_empty() or not ItemDurabilityService.is_usable(item): continue
		seen[instance_id] = true
		result.append(item)
	return result

static func stats_snapshot(combatant:CombatantState) -> Dictionary:
	return {
		"character_id":combatant.combatant_id,"name":combatant.display_name,"level":combatant.level,
		"hp":combatant.hp,"max_hp":combatant.max_hp,"mana":combatant.mana,"max_mana":combatant.max_mana,
		"action_points":combatant.action_points,"max_action_points":combatant.max_action_points,"tempo":combatant.tempo,
		"stats":combatant.stats.duplicate(true),"combat_stats":combatant.combat_stats.duplicate(true),"armour":combatant.armour.duplicate(true),
		"abilities":combatant.combat_stats.get("abilities", []).duplicate(true)
	}
