class_name ArenaTestEquipment
extends RefCounted

## Five actual inventory instances generated from stable test templates.
## No auto-equip; instances participate in the normal equipment and combat pipeline.
const ITEMS := [
	{"id":"sword_mh","name":"Тестовый меч","type":"weapon","slots":["main_hand"],"icon":2,"damage":{"min":10,"max":14,"type":"slashing"},"slot":"main_hand","weapon_class":"sword","stats":{"crit_chance_rating":200,"dodge_rating":200}},
	{"id":"dagger_oh","name":"Тестовый кинжал","type":"weapon","slots":["off_hand"],"icon":15,"damage":{"min":6,"max":9,"type":"piercing"},"slot":"off_hand","weapon_class":"dagger","stats":{"dodge_rating":200,"hit_chance_rating":500}},
	{"id":"ring_attributes","name":"Кольцо характеристик","type":"ring","slots":["ring1","ring2"],"icon":51,"stats":{"max_hp_flat":2000,"STR":50,"DEX":45,"INTU":40,"INT":35,"WIS":30,"END":25}},
	{"id":"ring_defense","name":"Кольцо защиты","type":"ring","slots":["ring1","ring2"],"icon":52,"stats":{"anti_crit_rating":600,"anti_dodge_rating":600}},
	{"id":"shield","name":"Тестовый щит","type":"shield","slots":["off_hand"],"icon":17,"stats":{"manual_block_rating":400},"armour":{"head":200,"chest":200},"block":1}
]

static func seed(character: CharacterState, repository: ItemRepository) -> bool:
	var added := false
	for definition in ITEMS:
		var id := "combat_test_v1_" + String(definition["id"])
		if repository.has_item(id):
			continue
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
			"guaranteed_stats": Dictionary(definition["stats"]).duplicate(true),
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
		ItemDurabilityService.initialize_item(item, 100)
		if repository.add_item(item):
			character.receive_item(id, repository)
			added = true
	return added
