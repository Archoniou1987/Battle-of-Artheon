class_name ItemV12InstanceFactory
extends RefCounted

## Bridge from the canonical v1.2 calculator to persistable game instances.
## Uses one self-contained instance, because arena_templates.json does NOT
## contain generated archetype/level/quality templates.
const SWORD_ARCHETYPES := ["SWORD_DEF", "SWORD_DODGE", "SWORD_CRIT"]
const DAGGER_ARCHETYPES := ["DAGGER_DEF", "DAGGER_ATTACK", "DAGGER_PEN"]
const AXE_ARCHETYPES := ["AXE_DEF", "AXE_ATTACK", "AXE_SHIELD"]
const HAMMER_ARCHETYPES := ["HAMMER_DEF", "HAMMER_ATTACK"]
const PHYSICAL_ARCHETYPES := SWORD_ARCHETYPES + DAGGER_ARCHETYPES + AXE_ARCHETYPES + HAMMER_ARCHETYPES
const ACCEPTED_QUALITIES := ["white", "green", "blue", "purple"]

static func generate_sword(archetype_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	return generate_weapon(archetype_id, level, quality, seed_value, "MH")

## Canonical v1.2 rolls for all APPROVED physical 1H weapon archetypes.
## ABI are assigned only after their runtime implementation is ready.
static func generate_weapon(archetype_id: String, level: int, quality: String, seed_value: int, hand: String = "MH") -> Dictionary:
	if not PHYSICAL_ARCHETYPES.has(archetype_id) or level < 1 or level > 100 or not ACCEPTED_QUALITIES.has(quality) or not ["MH", "OH"].has(hand):
		return {}
	if hand == "OH" and not DAGGER_ARCHETYPES.has(archetype_id):
		return {}
		return {}
	var engine := ItemTemplateGeneratorV12.new()
	var generated := engine.generate({
		"archetypes": [archetype_id], "weapon_hand": hand,
		"min_level": level, "max_level": level,
		"quality": quality, "count": 1, "seed": maxi(1, seed_value),
		"group_qualities": false
	})
	if not bool(generated.get("ok", false)) or (generated.get("rows", []) as Array).size() != 1:
		return {}
	var row: Dictionary = generated["rows"][0]
	if String(row.get("archetype_id", "")) != archetype_id or String(row.get("slot", "")) != hand or int(row.get("level", -1)) != level or String(row.get("quality", "")) != quality:
		return {}
	var variant: Dictionary = row["variant"]
	var damage: Array = variant.get("damage", [])
	if damage.size() != 2 or int(damage[0]) <= 0 or int(damage[1]) < int(damage[0]):
		return {}
	var known := ParCalculationService.registry()
	var canonical_bonuses := {}
	var pending_bonuses := {}
	for raw_id in Dictionary(variant.get("total_par", {})):
		var par_id := String(raw_id)
		var rating: float = float(Dictionary(variant["total_par"])[raw_id])
		if known.has(par_id):
			canonical_bonuses[par_id] = rating
		elif par_id == "V12_ATTACK_POWER":
			# v1.2 approved this LAB rating, but a live PAR ID is not assigned.
			# Keep the exact value for future migration, never silently mis-map it.
			pending_bonuses[par_id] = rating
		else:
			return {}
	var requirements: Dictionary = variant.get("requirements", {})
	for key in requirements:
		if not ParCalculationService.PRIMARY_IDS.has(String(key)):
			return {}
	var family := _weapon_family(archetype_id)
	var slot := "off_hand" if hand == "OH" else "main_hand"
	var template_id := "V12_%s_%s_L%03d" % [archetype_id, hand, level]
	var result := {
		"id": template_id,
		"generated_from_template": archetype_id,
		"instance_id": _new_instance_id(),
		"name": "%s · %s · Lv%d" % [_family_name(family), _archetype_name(archetype_id), level],
		"type": "weapon",
		"item_type": "weapon",
		"weapon_class": family,
		"item_level": level,
		"quality": quality,
		"rarity": quality,
		"origin": "v12_game_generator",
		"slot": slot,
		"equip_slots": [slot],
		"slot_usage": [slot],
		"icon_id": "ICON_0002", # Placeholder until visual templates/atlas binding stage.
		"damage": {"min": int(damage[0]), "max": int(damage[1]), "type": _damage_type(family)},
		"damage_min": int(damage[0]),
		"damage_max": int(damage[1]),
		"par_stats": {"PAR057": 1},
		"par_bonuses": canonical_bonuses,
		"requirements": requirements.duplicate(true),
		"v12_pending_bonuses": pending_bonuses,
		"v12_core_rolls": (variant.get("core_rolls", []) as Array).duplicate(true),
		"v12_rarity_rolls": (variant.get("rolls", []) as Array).duplicate(true),
		# ABI positions are genuine canonical IDs and survive normal save/restore.
		"abilities": _physical_sword_abilities(archetype_id) if SWORD_ARCHETYPES.has(archetype_id) else [],
		"v12_seed": seed_value
	}
	ItemDurabilityService.initialize_item(result, 100)
	return result if ItemTemplateService.resolve(result).size() > 0 else {}

static func grant_sword(character: CharacterState, repository: ItemRepository, archetype_id: String, level: int, quality: String, seed_value: int) -> Dictionary:
	return grant_weapon(character, repository, archetype_id, level, quality, seed_value, "MH")

static func grant_weapon(character: CharacterState, repository: ItemRepository, archetype_id: String, level: int, quality: String, seed_value: int, hand: String = "MH") -> Dictionary:
	if character == null or repository == null or character.in_combat:
		return {}
	if character.bag_capacity >= 0 and character.bag_item_count() >= character.bag_capacity:
		return {}
	var item := generate_weapon(archetype_id, level, quality, seed_value, hand)
	if item.is_empty():
		return {}
	# A new instance has a fresh ID even when the same template/seed is rolled.
	for _attempt in range(4):
		if not repository.has_item(String(item["instance_id"])):
			break
		item["instance_id"] = _new_instance_id()
	if not repository.add_item(item):
		return {}
	var instance_id := String(item["instance_id"])
	if not character.receive_item(instance_id, repository):
		repository.remove_item(instance_id)
		return {}
	return item

static func _physical_sword_abilities(archetype_id: String) -> Array[String]:
	match archetype_id:
		"SWORD_DEF": return ["ABI301","ABI302","ABI303","ABI306"]
		"SWORD_DODGE": return ["ABI301","ABI302","ABI304","ABI307"]
		"SWORD_CRIT": return ["ABI301","ABI302","ABI305","ABI308"]
	return []

static func _sword_name(archetype_id: String) -> String:
	match archetype_id:
		"SWORD_DEF": return "защитный"
		"SWORD_DODGE": return "уклонение"
		"SWORD_CRIT": return "критический"
	return "неизвестный"

static func _weapon_family(archetype_id: String) -> String:
	if SWORD_ARCHETYPES.has(archetype_id): return "sword"
	if DAGGER_ARCHETYPES.has(archetype_id): return "dagger"
	if AXE_ARCHETYPES.has(archetype_id): return "axe"
	if HAMMER_ARCHETYPES.has(archetype_id): return "hammer"
	return ""

static func _family_name(family: String) -> String:
	match family:
		"sword": return "Меч"
		"dagger": return "Кинжал"
		"axe": return "Топор"
		"hammer": return "Молот"
	return family

static func _archetype_name(archetype_id: String) -> String:
	match archetype_id:
		"SWORD_DEF", "DAGGER_DEF", "AXE_DEF", "HAMMER_DEF": return "защитный"
		"SWORD_DODGE": return "уклонение"
		"SWORD_CRIT": return "критический"
		"DAGGER_ATTACK", "AXE_ATTACK", "HAMMER_ATTACK": return "атакующий"
		"DAGGER_PEN": return "пробивающий"
		"AXE_SHIELD": return "щитолом"
	return archetype_id

static func _damage_type(family: String) -> String:
	match family:
		"dagger": return "piercing"
		"axe": return "chopping"
		"hammer": return "blunt"
	return "slashing"

static func _new_instance_id() -> String:
	var random_bytes := Crypto.new().generate_random_bytes(16)
	return "ITEMID" + str(int(Time.get_unix_time_from_system() * 1000.0)) + random_bytes.hex_encode()
