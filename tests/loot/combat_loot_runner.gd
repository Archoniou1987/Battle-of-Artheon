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
	var player_fighter := CharacterCombatBuilder.build(player, repository, {"health":160,"mana":30,"stats":{"STR":10,"DEX":10,"INTU":10,"INT":10,"WIS":10,"END":10},"combat_stats":{"main_hand_damage_min":35.0,"main_hand_damage_max":35.0,"main_hand_damage_type":"slashing"}})
	var bandit := CombatantState.new("NPC_TEST_BANDIT_001", "Test Bandit", 10, 25, 0)
	bandit.combat_stats = {"main_hand_damage_min":1.0,"main_hand_damage_max":1.0,"main_hand_damage_type":"slashing"}

	var state := CombatState.new()
	state.add_combatant(player_fighter)
	state.add_combatant(bandit)
	var balance: Dictionary = TestFixtureLoader.load_json("res://data/balance/physical_combat.json")
	var simulator := CombatSimulator.new(state, balance, 6060)
	simulator.max_rounds = 10
	var result := simulator.run_duel(player.character_id, bandit.combatant_id)

	var generator := ItemGenerator.new(20261006)
	var loot_service := LootService.new(4242)
	var drops := CombatRewardService.award_duel_loot(result, bandit.combatant_id, player, loot_table, templates, generator, repository, loot_service)
	var valid := String(result.get("outcome", "")) == player.character_id and int(result.get("second_hp", 1)) == 0
	valid = valid and drops.size() == 2 and repository.size() == 2 and player.inventory.size() == 2
	for item in drops:
		var instance_id := String(item.get("instance_id", ""))
		valid = valid and player.inventory.owns(instance_id) and repository.has_item(instance_id)
		valid = valid and String(item.get("loot_source_id", "")) == bandit.combatant_id

	print("COMBAT_LOOT outcome=%s bandit_hp=%d drops=%d inventory=%d repository=%d" % [String(result.get("outcome", "")), int(result.get("second_hp", -1)), drops.size(), player.inventory.size(), repository.size()])
	for item in drops:
		print("COMBAT_LOOT_ITEM " + JSON.stringify(item))
	print("COMBAT_TO_LOOT_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
