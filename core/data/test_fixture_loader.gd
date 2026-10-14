class_name TestFixtureLoader
extends RefCounted

## Development-only loader for the tiny combat database under data/test/.

static func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

static func build_combatant(combatant_id: String) -> CombatantState:
	var combatant_db := load_json("res://data/test/combatants.json")
	var item_db := load_json("res://data/test/items.json")
	var defaults: Dictionary = combatant_db.get("defaults", {})
	var definition := _find_by_id(combatant_db.get("combatants", []), combatant_id)
	if definition.is_empty(): return null
	var combatant := CombatantState.new(String(definition.get("id",combatant_id)),String(definition.get("name",combatant_id)),int(definition.get("level",defaults.get("level",1))),int(definition.get("hp",defaults.get("hp",100))),int(definition.get("mana",defaults.get("mana",0))))
	combatant.tempo = float(definition.get("tempo",defaults.get("tempo",0.0)))
	combatant.combat_stats["mana_regen"] = int(definition.get("mana_regen",defaults.get("mana_regen",0)))
	combatant.max_action_points = int(definition.get("max_action_points",defaults.get("max_action_points",5)))
	combatant.action_points = int(definition.get("action_points",defaults.get("action_points",0)))
	var equipment_index := 0
	for item_id in definition.get("equipment",[]):
		var item := _find_by_id(item_db.get("items",[]),String(item_id))
		if not item.is_empty():
			item["instance_id"] = combatant_id + "_fixture_" + str(equipment_index)
			equipment_index += 1
			EquipmentBuilder.equip(combatant,item)
			# These engine-only fixtures explicitly supply direct chances, not ratings.
			for key in item.get("combat_stats", {}):
				combatant.combat_stats[key] = float(combatant.combat_stats.get(key, 0)) + float(item.combat_stats[key])
	# Dual weapons share the one-zone fixture baseline; a shield adds a sector.
	combatant.combat_stats["manual_block_zone_capacity"] = int(definition["manual_block_zone_capacity"])
	canonicalize_combatant(combatant)
	return combatant

static func _find_by_id(entries:Array,wanted_id:String)->Dictionary:
	for entry in entries:
		if entry is Dictionary and String(entry.get("id",""))==wanted_id: return entry
	return {}

## Explicit migration boundary for engine-only test fixtures, never gameplay data.
## Their configured weapon damage is the complete damage; no primary-derived bonus.
static func canonicalize_combatant(combatant: CombatantState) -> CombatantState:
	if combatant.combat_stats.has("par_totals"):
		return combatant
	var weapons: Array = combatant.combat_stats.get("weapon_profiles", [])
	if weapons.is_empty():
		return combatant
	var ranges := {}
	for i in range(weapons.size()):
		var weapon: Dictionary = weapons[i]
		weapon["slot"] = "main_hand" if i == 0 else "off_hand"
		if not weapon.has("instance_id"):
			weapon["instance_id"] = combatant.combatant_id + "_fixture_" + str(i)
		var id := "PAR050" if i == 0 else "PAR051"
		ranges[id] = {"min":weapon["damage_min"], "max":weapon["damage_max"], "type":weapon.get("damage_type", "slashing")}
	combatant.combat_stats["par_totals"] = {"PAR052":0, "PAR057":weapons.size(), "PAR073":combatant.combat_stats.get("manual_block_zone_capacity", 1)}
	combatant.combat_stats["par_attack_ranges"] = ranges
	return combatant

static func canonicalize_state(state: CombatState) -> CombatState:
	for combatant in state.combatants.values():
		canonicalize_combatant(combatant)
	return state

static func new_combatant(id: String, name: String, level: int, hp: int, mana: int = 0) -> CombatantState:
	var combatant := CombatantState.new(id, name, level, hp, mana)
	combatant.stats = {"PAR001":0, "PAR002":0, "PAR003":0, "PAR004":0, "PAR005":0, "PAR006":0}
	return combatant

static func equip_character_weapon(character: CharacterState, repository: ItemRepository, damage: float) -> void:
	var id := character.character_id + "_fixture_weapon"
	var item := {"instance_id":id, "equip_slots":["main_hand"], "slot_usage":["main_hand"], "par_stats":{"PAR057":1}, "damage":{"min":damage,"max":damage,"type":"slashing"}}
	ItemDurabilityService.initialize_item(item, 100)
	assert(repository.add_item(item))
	assert(character.receive_item(id, repository))
	assert(character.equip("main_hand", id, repository))
