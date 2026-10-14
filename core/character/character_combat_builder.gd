class_name CharacterCombatBuilder
extends RefCounted

## Converts persistent CharacterState into the exact runtime snapshot used by combat and UI stats.
static func build(character:CharacterState, repository:ItemRepository, base:Dictionary = {}) -> CombatantState:
	# The canonical service owns primary and derived totals. EquipmentBuilder
	# contributes runtime-only weapon profiles, armour, and on-hit triggers.
	var par_snapshot := ParCalculationService.calculate(character, repository)
	var primary: Dictionary = par_snapshot.get("totals", {})
	var canonical := CharacterStatsService.combat_stats(character, repository)
	var health := int(base.get("health", 100 + int(primary.get("PAR010", 0))))
	var mana_pool := int(base.get("mana", 30 + int(primary.get("PAR011", 0))))
	var combatant := CombatantState.new(character.character_id, character.display_name, character.progression.level, health, mana_pool)
	combatant.stats = primary.duplicate(true)
	combatant.combat_stats = base.get("combat_stats", {}).duplicate(true)
	# Stable PAR snapshot for Duel/Pair and combat consumers; no legacy primary keys.
	combatant.combat_stats["par_totals"] = primary.duplicate(true)
	combatant.combat_stats["par_attack_ranges"] = par_snapshot.get("attack_ranges", {}).duplicate(true)
	# One adjacent manual block zone is the baseline; shields add to it.
	if not combatant.combat_stats.has("manual_block_zone_capacity"):
		combatant.combat_stats["manual_block_zone_capacity"] = int(primary.get("PAR073", 2))
	combatant.armour = base.get("armour", {}).duplicate(true)
	combatant.tempo = float(base.get("tempo", 0.0))
	combatant.max_action_points = int(base.get("max_action_points", 5))
	for item in equipped_items(character, repository):
		EquipmentBuilder.equip(combatant, item)
	# Do not add equipment primary bonuses twice.
	combatant.stats = primary.duplicate(true)
	# Preserve combat-only equipment metadata; canonical values override derived
	# character statistics while weapon profiles keep their own explicit owner.
	for key in canonical:
		if key == "weapon_profiles":
			continue # Weapon profiles are owned by EquipmentBuilder when equipped.
		combatant.combat_stats[key] = canonical[key]
	# Canonical attack count and ranges are the only PAR inputs for future ABI001 dispatch.
	combatant.combat_stats["par_attack_count"] = int(primary.get("PAR057", 1))
	# PAR073 overrides legacy equipment block metadata.
	combatant.combat_stats["manual_block_zone_capacity"] = int(primary.get("PAR073", 2))
	# Keep EquipmentBuilder weapon identity, but apply canonical derived damage.
	var damage_bonus := float(primary.get("PAR052", 0.0))
	var runtime_profiles: Array = combatant.combat_stats.get("weapon_profiles", [])
	for i in range(runtime_profiles.size()):
		var profile: Dictionary = runtime_profiles[i]
		profile["damage_min"] = float(profile.get("damage_min", 0.0)) + damage_bonus
		profile["damage_max"] = float(profile.get("damage_max", 0.0)) + damage_bonus
		var attacks: Array = profile.get("attack_profiles", [])
		for j in range(attacks.size()):
			if attacks[j] is Dictionary:
				var attack: Dictionary = attacks[j]
				if attack.has("damage_min"):
					attack["damage_min"] = float(attack["damage_min"]) + damage_bonus
				if attack.has("damage_max"):
					attack["damage_max"] = float(attack["damage_max"]) + damage_bonus
		runtime_profiles[i] = profile
	combatant.combat_stats["weapon_profiles"] = runtime_profiles
	var canonical_profiles:Array = canonical.get("weapon_profiles", [])
	if combatant.combat_stats.get("weapon_profiles", []).is_empty() and not canonical_profiles.is_empty():
		combatant.combat_stats["weapon_profiles"] = canonical_profiles.duplicate(true)
		combatant.combat_stats["weapon_attack_count"] = 1
	# TRA definitions are injected through base for now, independent of test content.
	var trait_definitions: Dictionary = base.get("trait_definitions", {})
	combatant.combat_stats["trait_modifiers"] = collect_trait_modifiers(character, trait_definitions)
	combatant.combat_stats["abilities"] = EquipmentAbilityLoadout.active_abilities(character, repository)
	var main_hand_id:Variant=character.equipment.get_equipped_instance_id("main_hand")
	var main_hand:=repository.get_item(String(main_hand_id)) if main_hand_id!=null and character.is_equipment_active(String(main_hand_id), repository) else {}
	var weapon_class:=String(main_hand.get("weapon_class",main_hand.get("subtype",""))).to_lower()
	var is_bow:=weapon_class.contains("bow")
	combatant.combat_stats["can_manual_block"]=int(primary.get("PAR073", 2)) > 0
	combatant.combat_stats["can_auto_block"]=not is_bow
	combatant.lock_combat_loadout({
		"equipment_slots":character.equipment.slots.duplicate(true),
		"main_hand_instance_id":String(main_hand_id) if main_hand_id!=null else "",
		"weapon_class":weapon_class,
		"can_manual_block":int(primary.get("PAR073", 2)) > 0,
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

## Converts learned TRA IDs into a single runtime overlay.
## A TRA definition can provide {"modifiers": {"magic_damage_flat": 5}}.
static func collect_trait_modifiers(character: CharacterState, definitions: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for trait_id in character.learned_trait_ids:
		var raw: Variant = definitions.get(trait_id, {})
		if not raw is Dictionary:
			continue
		var definition: Dictionary = raw
		if character.progression.level < int(definition.get("required_level", 1)):
			continue
		var modifiers: Variant = definition.get("modifiers", {})
		if not modifiers is Dictionary:
			continue
		for key in modifiers:
			if modifiers[key] is bool:
				totals[key] = bool(totals.get(key, false)) or bool(modifiers[key])
			elif modifiers[key] is int or modifiers[key] is float:
				totals[key] = float(totals.get(key, 0.0)) + float(modifiers[key])
	return totals
