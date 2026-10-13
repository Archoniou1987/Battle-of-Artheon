class_name ArenaTestEquipment
extends RefCounted

## Preview-only genuine item instances, routed through CharacterState and EquipmentBuilder.
const ITEMS := [
	{"id":"sword","name":"Испытательный меч 4–7","type":"weapon","slots":["main_hand"],"icon":2,"damage":{"min":4,"max":7,"type":"slashing"},"slot":"main_hand"},
	{"id":"dagger","name":"Испытательный кинжал 2–5","type":"weapon","slots":["off_hand"],"icon":15,"damage":{"min":2,"max":5,"type":"piercing"},"slot":"off_hand"},
	{"id":"helmet","name":"Шлем: броня головы 100","type":"armour","slots":["head"],"icon":19,"armour":100,"zone":"head","slot":"head"},
	{"id":"chest","name":"Доспех: броня груди 100","type":"armour","slots":["chest"],"icon":28,"armour":100,"zone":"chest","slot":"chest"},
	{"id":"gloves","name":"Перчатки: броня рук 1","type":"armour","slots":["hands"],"icon":41,"armour":1,"zone":"arms","slot":"hands"},
	{"id":"belt","name":"Пояс: броня пояса 1","type":"armour","slots":["waist"],"icon":30,"armour":1,"zone":"waist","slot":"waist"},
	{"id":"legs","name":"Поножи: броня ног 2","type":"armour","slots":["legs"],"icon":33,"armour":2,"zone":"legs","slot":"legs"},
	{"id":"hp_ring","name":"Кольцо жизни +1000 HP","type":"ring","slots":["ring1","ring2"],"icon":51,"bonus":{"max_hp_flat":1000},"slot":"ring1"},
	{"id":"shield","name":"Щит: +1 зона ручного блока","type":"shield","slots":["off_hand"],"icon":17,"block":1},
	{"id":"dodge_boots","name":"Сапоги уклонения +100","type":"armour","slots":["feet"],"icon":49,"bonus":{"dodge_rating":100},"slot":"feet"},
	{"id":"crit_boots","name":"Сапоги крита +100","type":"armour","slots":["feet"],"icon":49,"bonus":{"crit_rating":100}}
]

static func seed(character: CharacterState, repository: ItemRepository) -> void:
	for definition in ITEMS:
		var id := "arena_test_" + String(definition["id"])
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
			"guaranteed_stats": {},
			"bonuses": Dictionary(definition.get("bonus", {})).duplicate(true),
			"combat_stats": Dictionary(definition.get("bonus", {})).duplicate(true),
			"description": "Тестовая экипировка Arena. Параметры участвуют в расчёте боя."
		}
		if definition.has("damage"):
			item["damage"] = Dictionary(definition["damage"]).duplicate(true)
			item["slot"] = String(definition.get("slot", ""))
		if definition.has("block"):
			item["manual_block_zones_added"] = int(definition["block"])
		if definition.has("armour"):
			item["armour_by_zone"] = {String(definition["zone"]): float(definition["armour"])}
		ItemDurabilityService.initialize_item(item, 100)
		if repository.add_item(item):
			character.receive_item(id, repository)
		if definition.has("slot"):
			character.equip(String(definition["slot"]), id, repository)
