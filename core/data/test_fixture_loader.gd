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
	for item_id in definition.get("equipment",[]):
		var item := _find_by_id(item_db.get("items",[]),String(item_id))
		if not item.is_empty(): EquipmentBuilder.equip(combatant,item)
	return combatant

static func _find_by_id(entries:Array,wanted_id:String)->Dictionary:
	for entry in entries:
		if entry is Dictionary and String(entry.get("id",""))==wanted_id: return entry
	return {}
