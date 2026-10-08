extends SceneTree

func _initialize() -> void:
	var templates_doc := TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var loot_doc := TestFixtureLoader.load_json("res://data/test/loot_tables.json")
	var templates: Dictionary = {}
	for raw_template in templates_doc.get("templates", []):
		var template := raw_template as Dictionary
		templates[String(template.get("id", ""))] = template
	var loot_table := (loot_doc.get("loot_tables", []) as Array)[0] as Dictionary
	var repository := ItemRepository.new()
	var player := CharacterState.new("CHEST_PLAYER", "Chest Explorer", 20)
	var chest := ChestState.new("CHEST_TEST_DUNGEON_001", String(loot_table.get("id", "")))
	var generator := ItemGenerator.new(20261006)
	var loot_service := LootService.new(7007)
	var first := ChestService.open_chest(chest, player, loot_table, templates, generator, repository, loot_service)
	var second := ChestService.open_chest(chest, player, loot_table, templates, generator, repository, loot_service)
	var valid := chest.is_open and first.item_ids().size() == 2 and second.item_ids().is_empty()
	valid = valid and repository.size() == 2 and player.inventory.size() == 0
	for instance_id in first.item_ids().duplicate():
		var item:=repository.get_item(instance_id)
		valid = valid and first.available_for(player.character_id).has(instance_id) and repository.has_item(instance_id)
		valid = valid and String(item.get("loot_source_id", "")) == chest.chest_id
		valid = valid and first.claim(instance_id,player,repository)
		valid = valid and not first.claim(instance_id,player,repository)
	valid = valid and player.inventory.size()==2 and first.item_ids().is_empty()
	print("CHEST_LOOT_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
