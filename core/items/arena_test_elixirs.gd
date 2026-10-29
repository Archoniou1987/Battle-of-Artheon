class_name ArenaTestElixirs
extends RefCounted

## One-time test-only grants. Not loot balance or a player reward system.
## Existing items (including depleted charges) are never replenished.
static func seed(character: CharacterState, repository: ItemRepository) -> bool:
	var fixtures: Array[Dictionary] = [
		{"instance_id":"elixir_test_belt_v1","name":"Пояс испытаний","type":"armour","rarity":"green","equip_slots":["waist"],"slot_usage":["waist"],"elixir_slots":4,"par_stats":{}},
		{"instance_id":"elixir_test_hp_v1","name":"Эликсир здоровья","type":"consumable","rarity":"green","charges":3,"max_charges":3,"cooldown_rounds":1,"elixir_components":[{"kind":"heal","amount":100}]},
		{"instance_id":"elixir_test_mana_v1","name":"Эликсир энергии","type":"consumable","rarity":"green","charges":3,"max_charges":3,"cooldown_rounds":1,"elixir_components":[{"kind":"mana","amount":30}]},
		{"instance_id":"elixir_test_fire_v1","name":"Огненный оберег","type":"consumable","rarity":"blue","charges":2,"max_charges":2,"cooldown_rounds":1,"elixir_components":[{"kind":"effect","effect_id":"EFF005"}]},
		{"instance_id":"elixir_test_ward_v1","name":"Эликсир защиты","type":"consumable","rarity":"green","charges":3,"max_charges":3,"cooldown_rounds":1,"elixir_components":[{"kind":"effect","effect_id":"EFF006"}]},
		{"instance_id":"elixir_test_focus_v1","name":"Эликсир концентрации","type":"consumable","rarity":"blue","charges":3,"max_charges":3,"cooldown_rounds":1,"elixir_components":[{"kind":"effect","effect_id":"EFF007"}]},
		{"instance_id":"elixir_test_cleanse_v1","name":"Эликсир очищения","type":"consumable","rarity":"green","charges":3,"max_charges":3,"cooldown_rounds":1,"elixir_components":[{"kind":"cleanse","dispel_polarity":"DEBUFF","max_effects":2}]}
	]
	var changed := false
	for entry in fixtures:
		var id := String(entry["instance_id"])
		if repository.has_item(id):
			continue
		var item := entry.duplicate(true)
		ItemDurabilityService.initialize_item(item,100)
		if repository.add_item(item) and character.receive_item(id,repository):
			changed = true
	return changed
