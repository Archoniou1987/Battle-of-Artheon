extends SceneTree

const SLOT_BY_TEMPLATE := {"CHEST_15":"chest","LEGS_16":"legs","HEAD_17":"head","FEET_18":"feet","SWORD_19":"main_hand","SHIELD_20":"off_hand"}

func _initialize() -> void:
	var data: Dictionary = TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var repository := ItemRepository.new()
	var generator := ItemGenerator.new(20261006)
	var bot_a := CharacterState.new("BOT_A", "Durability Bot A", 20)
	var bot_b := CharacterState.new("BOT_B", "Durability Bot B", 20)
	for template in data.get("templates", []):
		for bot in [bot_a, bot_b]:
			var item := generator.generate(template, "green")
			repository.add_item(item)
			bot.receive_item(String(item.instance_id), repository)
			bot.equip(String(SLOT_BY_TEMPLATE[String(template.id)]), String(item.instance_id), repository)

	var base := {"health":100,"mana":30,"stats":{"STR":5,"DEX":5,"INTU":5,"INT":5,"WIS":5,"END":5},"combat_stats":{"mana_regen":2.0,"crit":5.0,"dodge":5.0}}
	var wins := {bot_a.character_id:0, bot_b.character_id:0}
	var draws := 0
	for battle in range(100):
		var state := CombatState.new()
		state.add_combatant(CharacterCombatBuilder.build(bot_a, repository, base))
		state.add_combatant(CharacterCombatBuilder.build(bot_b, repository, base))
		var simulator := CombatSimulator.new(state, TestFixtureLoader.load_json("res://data/balance/physical_combat.json"), 10000 + battle)
		var result := simulator.run_duel(bot_a.character_id, bot_b.character_id)
		var loser_id := String(result.get("loser_id", ""))
		if loser_id.is_empty():
			draws += 1
		else:
			var loser := bot_a if loser_id == bot_a.character_id else bot_b
			var damaged := CombatConsequenceService.apply_defeat_wear(result, loser, repository, 1)
			wins[String(result.get("winner_id", ""))] += 1
			if damaged.size() != 6:
				print("BOT_DURABILITY_100_TEST=FAIL wear_count battle=", battle + 1, " count=", damaged.size())
				quit(1)
				return

	var report := {"battles":100,"wins":{bot_a.character_id:wins[bot_a.character_id],bot_b.character_id:wins[bot_b.character_id]},"draws":draws,"bots":[_bot_report(bot_a, repository),_bot_report(bot_b, repository)]}
	var report_file := FileAccess.open("user://hundred_bot_durability_report.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	print("BOT_DURABILITY_100_REPORT=" + JSON.stringify(report))
	_print_equipment(bot_a, repository)
	_print_equipment(bot_b, repository)
	var expected_a := 50 - int(wins[bot_b.character_id])
	var expected_b := 50 - int(wins[bot_a.character_id])
	var valid := expected_a >= 0 and expected_b >= 0
	for bot in [bot_a, bot_b]:
		var expected := expected_a if bot == bot_a else expected_b
		for item in CharacterCombatBuilder.equipped_items(bot, repository):
			valid = valid and int(item.get("durability_current", -1)) == expected
	print("BOT_DURABILITY_100_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _print_equipment(bot: CharacterState, repository: ItemRepository) -> void:
	for slot in ["head","chest","legs","feet","main_hand","off_hand"]:
		var item := ItemResolver.resolve_equipped(slot, bot.equipment, repository)
		print("BOT_ITEM bot=%s slot=%s item=%s durability=%d/%d" % [bot.character_id, slot, String(item.get("name","")), int(item.get("durability_current",0)), int(item.get("durability_max",0))])


func _bot_report(bot: CharacterState, repository: ItemRepository) -> Dictionary:
	var items: Array[Dictionary] = []
	for slot in ["head","chest","legs","feet","main_hand","off_hand"]:
		var item := ItemResolver.resolve_equipped(slot, bot.equipment, repository)
		items.append({"slot":slot,"instance_id":String(item.get("instance_id","")),"name":String(item.get("name","")),"durability_current":int(item.get("durability_current",0)),"durability_max":int(item.get("durability_max",0))})
	return {"bot_id":bot.character_id,"items":items}
