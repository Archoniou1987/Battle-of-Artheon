class_name ArenaTestEquipment
extends RefCounted

## Five fixed development templates. PAR IDs are immutable; see locked registry.
## Existing test instances refresh from templates without changing instance IDs or wear.
const PAR_REGISTRY_PATH := "res://data/parameters/par_registry.json"
const ITEMS := [
	{"id":"sword_mh","name":"Тестовый меч","type":"weapon","slots":["main_hand"],"icon":2,"damage":{"min":10,"max":14,"type":"slashing"},"slot":"main_hand","weapon_class":"sword","par_stats":{"PAR033":200,"PAR031":200}},
	{"id":"dagger_oh","name":"Тестовый кинжал","type":"weapon","slots":["off_hand"],"icon":15,"damage":{"min":6,"max":9,"type":"piercing"},"slot":"off_hand","weapon_class":"dagger","par_stats":{"PAR031":200,"PAR030":500}},
	{"id":"ring_attributes","name":"Кольцо характеристик","type":"ring","slots":["ring1","ring2"],"icon":51,"par_stats":{"PAR010":2000,"PAR001":50,"PAR002":45,"PAR003":40,"PAR004":35,"PAR005":30,"PAR006":25}},
	{"id":"ring_defense","name":"Кольцо защиты","type":"ring","slots":["ring1","ring2"],"icon":52,"par_stats":{"PAR034":600,"PAR032":600}},
	{"id":"shield","name":"Тестовый щит","type":"shield","slots":["off_hand"],"icon":17,"par_stats":{"PAR070":400},"armour":{"head":200,"chest":200},"block":1}
]

static func seed(character: CharacterState, repository: ItemRepository) -> bool:
	var changed := false
	var par_keys := _load_par_keys()
	if par_keys.is_empty():
		push_error("ArenaTestEquipment: locked PAR registry unavailable")
		return false
	for definition in ITEMS:
		var id := "combat_test_v1_" + String(definition["id"])
		var legacy_stats := {}
		for par_id in definition["par_stats"]:
			if not par_keys.has(par_id):
				push_error("ArenaTestEquipment: unknown PAR ID " + String(par_id))
				return changed
			legacy_stats[String(par_keys[par_id])] = definition["par_stats"][par_id]
		var item := {
			"instance_id": id,
			"id": String(definition["id"]),
			"name": String(definition["name"]),
			"type": String(definition["type"]),
			"rarity": "green",
			"item_level": 1,
			"level": 1,
			"icon_id": "ICON_%04d" % int(definition["icon"]),
			"equip_slots": definition["slots"].duplicate(),
			"requirements": {},
			"par_stats": Dictionary(definition["par_stats"]).duplicate(true),
			"guaranteed_stats": legacy_stats.duplicate(true),
			"bonuses": {},
			"combat_stats": {},
			"description": "Настоящий тестовый экземпляр для проверки расчётов."
		}
		if definition.has("damage"):
			item["damage"] = Dictionary(definition["damage"]).duplicate(true)
			item["slot"] = String(definition["slot"])
			item["weapon_class"] = String(definition["weapon_class"])
		if definition.has("block"):
			item["manual_block_zones_added"] = int(definition["block"])
		if definition.has("armour"):
			item["armour_by_zone"] = Dictionary(definition["armour"]).duplicate(true)
		if repository.has_item(id):
			var previous := repository.get_item(id)
			# Preserve all per-instance fields not defined by the template,
			# including durability and wear; refresh only template-owned fields.
			for field in previous:
				if not item.has(field):
					item[field] = previous[field]
			if repository.update_item(item):
				changed = true
		else:
			ItemDurabilityService.initialize_item(item, 100)
			if repository.add_item(item):
				character.receive_item(id, repository)
				changed = true
	return changed

static func _load_par_keys() -> Dictionary:
	if not FileAccess.file_exists(PAR_REGISTRY_PATH):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAR_REGISTRY_PATH))
	if not raw is Dictionary or not bool(raw.get("locked", false)):
		return {}
	var keys := {}
	for entry in raw.get("parameters", []):
		if entry is Dictionary:
			var par_id := String(entry.get("id", ""))
			var source_key := String(entry.get("source_key", ""))
			if not par_id.is_empty() and not source_key.is_empty():
				keys[par_id] = source_key
	return keys
