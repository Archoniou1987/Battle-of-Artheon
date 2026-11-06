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
	var player := CharacterState.new("PLAYER_01", "Artheon Hero", 20)
	TestFixtureLoader.equip_character_weapon(player, repository, 35)
	var player_fighter := CharacterCombatBuilder.build(player, repository, {"health":160,"mana":30})
	var bandit := TestFixtureLoader.new_combatant("NPC_TEST_BANDIT_001", "Test Bandit", 10, 25, 0)
	bandit.combat_stats.merge({"weapon_profiles":[{"damage_min":1.0,"damage_max":1.0,"damage_type":"slashing"}]}, true)

	var state := CombatState.new()
	state.add_combatant(player_fighter)
	state.add_combatant(bandit)
	var balance: Dictionary = TestFixtureLoader.load_json("res://data/balance/physical_combat.json")
	var simulator := CombatSimulator.new(TestFixtureLoader.canonicalize_state(state), balance, 6060)
	simulator.max_rounds = 10
	var result := simulator.run_duel(player.character_id, bandit.combatant_id)

	var generator := ItemGenerator.new(20261006)
	var loot_service := LootService.new(4242)
	var pool:=CombatRewardService.create_duel_loot_pool(result, bandit.combatant_id, player, loot_table, templates, generator, repository, loot_service)
	var drops:Array[Dictionary]=[]
	for item_id in pool.item_ids():
		drops.append(repository.get_item(item_id))
	var valid:=not pool.item_ids().is_empty() and player.bag_item_count()==0
	valid=valid and  String(result.get("winner_id", "")) == player.character_id and String(result.get("loser_id", "")) == bandit.combatant_id
	valid = valid and drops.size() == 2 and repository.size() == 3 and pool.item_ids().size() == 2
	for item in drops:
		var instance_id := String(item.get("instance_id", ""))
		valid = valid and pool.available_for(player.character_id).has(instance_id) and repository.has_item(instance_id)
		valid = valid and String(item.get("loot_source_id", "")) == bandit.combatant_id

	for item_id in pool.item_ids().duplicate():
		valid=valid and pool.claim(item_id,player,repository)
	valid=valid and player.bag_item_count()==2 and pool.item_ids().is_empty()
	print("COMBAT_LOOT outcome=%s bandit_hp=%d drops=%d inventory=%d repository=%d" % [String(result.get("outcome", "")), int(result.get("second_hp", -1)), drops.size(), player.inventory.size(), repository.size()])
	for item in drops:
		print("COMBAT_LOOT_ITEM " + JSON.stringify(item))
	print("COMBAT_TO_LOOT_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
