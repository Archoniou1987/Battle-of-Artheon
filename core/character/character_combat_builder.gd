class_name CharacterCombatBuilder
extends RefCounted

## Converts persistent CharacterState into the exact runtime snapshot used by combat and UI stats.
static func build(character:CharacterState, repository:ItemRepository, base:Dictionary = {}) -> CombatantState:
	# The canonical service owns primary and derived totals. EquipmentBuilder
	# contributes runtime-only weapon profiles, armour, and on-hit triggers.
	if base.has("stats") or Dictionary(base.get("combat_stats", {})).has("weapon_profiles"):
		push_error("CharacterCombatBuilder rejects primary/profile overrides; equip canonical items instead")
		return null
	var par_snapshot := ParCalculationService.calculate(character, repository)
	if par_snapshot.is_empty():
		push_error("Character combat build rejected: invalid canonical PAR snapshot")
		return null
	var primary: Dictionary = par_snapshot["totals"]
	var canonical := CharacterStatsService.combat_stats(character, repository, {}, par_snapshot)
	if canonical.is_empty():
		push_error("Character combat build rejected: invalid RatingMatrix snapshot")
		return null
	var resources := character.resource_snapshot(repository, par_snapshot)
	if resources.is_empty():
		push_error("Character combat build rejected: unavailable current resource snapshot")
		return null
	var health := int(base.get("health", resources["max_hp"]))
	var mana_pool := int(base.get("mana", resources["max_mana"]))
	var combatant := CombatantState.new(character.character_id, character.display_name, character.progression.level, health, mana_pool)
	# Explicit base health/mana overrides retain their full-pool test/NPC semantics.
	# Ordinary gameplay builds preserve current HP/mana through equipment changes.
	if not base.has("health"):
		combatant.hp = mini(combatant.max_hp, int(resources["hp"]))
	if not base.has("mana"):
		combatant.mana = mini(combatant.max_mana, int(resources["mana"]))
	combatant.stats = primary.duplicate(true)
	combatant.combat_stats = base.get("combat_stats", {}).duplicate(true)
	combatant.combat_stats.erase("weapon_profiles")
	# Stable PAR snapshot for Duel/Pair and combat consumers; no legacy primary keys.
	combatant.combat_stats["par_totals"] = primary.duplicate(true)
	combatant.combat_stats["par_attack_ranges"] = par_snapshot.get("attack_ranges", {}).duplicate(true)
	# PAR073 owns manual block capacity, including the configured baseline.
	if not combatant.combat_stats.has("manual_block_zone_capacity"):
		combatant.combat_stats["manual_block_zone_capacity"] = int(primary["PAR073"])
	combatant.armour = base.get("armour", {}).duplicate(true)
	combatant.tempo = float(base.get("tempo", 0.0))
	combatant.max_action_points = int(base.get("max_action_points", primary["PAR014"]))
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
	combatant.combat_stats["par_attack_count"] = int(primary["PAR057"])
	# PAR073 overrides legacy equipment block metadata.
	combatant.combat_stats["manual_block_zone_capacity"] = int(primary["PAR073"])
	# Keep EquipmentBuilder weapon identity, but apply canonical derived damage.
	var damage_bonus := float(primary["PAR052"])
	var runtime_profiles: Array = combatant.combat_stats.get("weapon_profiles", [])
	# An empty MH is a virtual fist, including when an OH weapon is equipped.
	if not runtime_profiles.any(func(profile): return profile.get("slot") == "main_hand"):
		var fist: Dictionary = par_snapshot["attack_ranges"]["PAR050"]
		if not ParCalculationService.valid_damage_range(fist):
			push_error("Missing mandatory unarmed main-hand range")
			return null
		runtime_profiles.push_front({"slot":"main_hand", "instance_id":"unarmed_main_hand", "is_unarmed":true, "damage_min":float(fist["min"]), "damage_max":float(fist["max"]), "damage_type":String(fist["type"]), "attack_profiles":[]})
	for i in range(runtime_profiles.size()):
		var profile: Dictionary = runtime_profiles[i]
		var attacks: Array = profile.get("attack_profiles", [])
		for j in range(attacks.size()):
			if attacks[j] is Dictionary:
				var attack: Dictionary = attacks[j]
				if attack.has("damage_min"):
					attack["damage_min"] = float(attack["damage_min"]) + damage_bonus
				if attack.has("damage_max"):
					attack["damage_max"] = float(attack["damage_max"]) + damage_bonus
		# PAR050/PAR051 are authoritative for the ordinary weapon damage range.
		# Preserve specialised attack profiles until ABI migration is complete.
		var source_par := "PAR051" if String(profile.get("slot", "")) == "off_hand" else "PAR050"
		var canonical_range: Dictionary = par_snapshot["attack_ranges"][source_par]
		profile["damage_min"] = float(canonical_range["min"]) + damage_bonus
		profile["damage_max"] = float(canonical_range["max"]) + damage_bonus
		profile["damage_type"] = String(canonical_range["type"])
		runtime_profiles[i] = profile
	combatant.combat_stats["weapon_profiles"] = runtime_profiles
	combatant.combat_stats["weapon_attack_count"] = runtime_profiles.size()
	# Virtual MH insertion must not transfer an OH item's trigger to the fist.
	for trigger in combatant.combat_stats.get("weapon_on_hit_effects", []):
		if int(trigger.get("weapon_index", -1)) < 0:
			continue
		var found := false
		for index in range(runtime_profiles.size()):
			if String(runtime_profiles[index].get("instance_id", "")) == String(trigger.get("source_instance_id", "")):
				trigger["weapon_index"] = index
				found = true
				break
		if not found:
			push_error("Weapon trigger missing its active instance")
			return null
	# PhysicalArmourService owns the final 5x4 matrix. Structural item armour
	# was already canonicalized into PAR100-104, so never add EquipmentBuilder
	# runtime armour a second time.
	combatant.armour = PhysicalArmourService.assemble(Dictionary(base.get("armour", {})), primary)
	# TRA definitions are injected through base for now, independent of test content.
	var trait_definitions: Dictionary = base.get("trait_definitions", {})
	combatant.combat_stats["trait_modifiers"] = collect_trait_modifiers(character, trait_definitions)
	combatant.combat_stats["abilities"] = EquipmentAbilityLoadout.active_abilities(character, repository)
	var main_hand_id:Variant=character.equipment.get_equipped_instance_id("main_hand")
	var main_hand:=repository.get_item(String(main_hand_id)) if main_hand_id!=null and character.is_equipment_active(String(main_hand_id), repository) else {}
	var weapon_class:=String(main_hand.get("weapon_class",main_hand.get("subtype",""))).to_lower()
	var is_bow:=weapon_class.contains("bow")
	combatant.combat_stats["can_manual_block"]=int(primary["PAR073"]) > 0
	combatant.combat_stats["can_auto_block"]=not is_bow
	combatant.lock_combat_loadout({
		"equipment_slots":character.equipment.slots.duplicate(true),
		"main_hand_instance_id":String(main_hand_id) if main_hand_id!=null else "",
		"weapon_class":weapon_class,
		"can_manual_block":int(primary["PAR073"]) > 0,
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
		item["slot"] = "main_hand" if str(character.equipment.get_equipped_instance_id("main_hand")) == instance_id else slot
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
## A TRA definition can provide {"modifiers": {"magic_damage_direct_pct": 5}}.
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
