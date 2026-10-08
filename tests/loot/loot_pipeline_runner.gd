extends SceneTree

func _initialize() -> void:
	var templates_doc := _load_json("res://data/test/bot_equipment_templates.json")
	var loot_doc := _load_json("res://data/test/loot_tables.json")
	var templates: Dictionary = {}
	for raw_template in templates_doc.get("templates", []):
		var template := raw_template as Dictionary
		templates[String(template.get("id", ""))] = template
	var loot_table := (loot_doc.get("loot_tables", []) as Array)[0] as Dictionary
	var repository := ItemRepository.new()
	var player := CharacterState.new("PLAYER_LOOT_TEST", "Loot Tester", 1)
	var inventory := player.inventory
	var generator := ItemGenerator.new(20261006)
	var loot := LootService.new(4242)
	var drops := loot.roll_drops("NPC_TEST_BANDIT_001", loot_table, templates, generator, repository)
	var pool := EncounterLootPool.new()
	for item in drops:
		pool.add_drop(String(item.get("instance_id", "")), "NPC_TEST_BANDIT_001")
	pool.assign_all(player.character_id)
	var valid := drops.size() == 2 and repository.size() == 2 and inventory.size() == 0 and pool.item_ids().size() == 2
	var ids: Array[String] = []
	for item in drops:
		var instance_id := String(item.get("instance_id", ""))
		ids.append(instance_id)
		valid = valid and pool.available_for(player.character_id).has(instance_id) and repository.has_item(instance_id)
		valid = valid and String(item.get("loot_source_id", "")) == "NPC_TEST_BANDIT_001"
		valid = valid and String(item.get("loot_table_id", "")) == "LOOT_TEST_BANDIT"
	for item_id in pool.item_ids().duplicate():
		valid = valid and pool.claim(item_id, player, repository)
	valid = valid and inventory.size() == 2 and pool.item_ids().is_empty()
	print("LOOT_PIPELINE source=NPC_TEST_BANDIT_001 drops=%d inventory=%d repository=%d ids=%s" % [drops.size(), inventory.size(), repository.size(), str(ids)])
	for item in drops:
		print("LOOT_ITEM " + JSON.stringify(item))
	if valid:
		print("LOOT_PIPELINE_TEST=PASS")
		quit(0)
	else:
		push_error("LOOT_PIPELINE_TEST=FAIL")
		quit(1)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
