extends SceneTree

func _initialize() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("HERO", "Hero", 20)
	var generator := ItemGenerator.new(701)
	for template in [
		{"id":"LOSS_SWORD","name":"Sword","equip_slots":["main_hand"],"slot_usage":["main_hand"],"damage_min":2,"damage_max":3,"durability_max":50},
		{"id":"LOSS_HELM","name":"Helm","equip_slots":["head"],"slot_usage":["head"],"durability_max":40}
	]:
		var item := generator.generate(template, "common")
		repository.add_item(item)
		hero.receive_item(String(item.instance_id), repository)
		hero.equip(String((template.equip_slots as Array)[0]), String(item.instance_id), repository)
	var enemy := CombatantState.new("NPC_WINNER", "Winner", 20, 100, 0)
	enemy.combat_stats = {"main_hand_damage_min":100.0,"main_hand_damage_max":100.0,"main_hand_damage_type":"slashing"}
	var hero_fighter := CharacterCombatBuilder.build(hero, repository, {"health":10,"mana":0,"stats":{},"combat_stats":{"main_hand_damage_min":1.0,"main_hand_damage_max":1.0}})
	var state := CombatState.new()
	state.add_combatant(hero_fighter)
	state.add_combatant(enemy)
	var simulator := CombatSimulator.new(state, TestFixtureLoader.load_json("res://data/balance/physical_combat.json"), 9090)
	var result := simulator.run_duel(hero.character_id, enemy.combatant_id)
	var damaged := CombatConsequenceService.apply_defeat_wear(result, hero, repository, 2)
	var sword := repository.get_item(String(hero.equipment.get_equipped_instance_id("main_hand")))
	var helm := repository.get_item(String(hero.equipment.get_equipped_instance_id("head")))
	var ok := String(result.get("winner_id", "")) == enemy.combatant_id and String(result.get("loser_id", "")) == hero.character_id
	ok = ok and damaged.size() == 2 and int(sword.durability_current) == 48 and int(helm.durability_current) == 38
	print("COMBAT_CONSEQUENCE_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
