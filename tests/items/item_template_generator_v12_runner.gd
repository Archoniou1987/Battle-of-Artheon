extends SceneTree

## Contract smoke: does not touch saves, live inventory or Combat Engine.
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var problems: Array[String] = []
	var generator := ItemTemplateGeneratorV12.new()
	if not generator.ready_for_generation():
		problems.append("v1.2 catalog is incomplete or probabilities do not sum to 100")
	if generator.archetypes().size() != 35:
		problems.append("Expected 35 approved archetypes")
	if generator.schools().size() != 6:
		problems.append("Expected exactly six staff schools")
	for raw in generator.archetypes():
		var entry: Dictionary = raw
		var sum := 0
		for key in entry["weights"]:
			sum += int(entry["weights"][key])
		if sum != 100:
			problems.append(String(entry["id"]) + " total is not 100")
	var medium: Dictionary = {}
	for raw in generator.archetypes():
		var entry: Dictionary = raw
		if String(entry["id"]) == "MEDIUM_DEF":
			medium = entry
	if medium.is_empty() or int(Dictionary(medium.get("weights",{})).get("counter",0)) != 15:
		problems.append("Medium protective armour counterstrike probability differs from approved rules")
	var config := {"archetypes":["SWORD_CRIT"],"min_level":30,"max_level":30,
		"quality":"blue","count":100,"seed":123456,"school":"any","armor_slot":"any"}
	var generated := generator.generate(config)
	if not bool(generated.get("ok",false)) or int(generated.get("generated",0)) != 100:
		problems.append("100 blue sword templates were not generated")
	else:
		for row in generated["rows"]:
			var entry: Dictionary = row
			if int(entry["level"]) != 30 or String(entry["quality"]) != "blue":
				problems.append("Level or rarity filter ignored")
			if String(entry["archetype_id"]) != "SWORD_CRIT":
				problems.append("Archetype filter ignored")
			if (Dictionary(entry["variant"]).get("rolls",[]) as Array).size() != 3:
				problems.append("Lv30 blue must have two random + one template PAR lines")
				break
	var full := generator.generate({"archetypes":["MEDIUM_DEF"],"min_level":10,
		"max_level":30,"quality":"any","count":500,"seed":48,"armor_slot":"Наручи"})
	if not bool(full.get("ok",false)) or int(full.get("generated",0)) != 500:
		problems.append("500 armor templates were not generated")
	var magic := generator.generate({"archetypes":["STAFF_PEN"],"min_level":60,"max_level":60,
		"quality":"purple","count":20,"seed":117,"school":"fire"})
	if not bool(magic.get("ok",false)) or int(magic.get("generated",0)) != 20:
		problems.append("Magic staff templates missing")
	else:
		for raw in magic["rows"]:
			var row: Dictionary = raw
			if String(row["school"]) != "Fire":
				problems.append("Staff school filter ignored")
			var par_bonuses: Dictionary = Dictionary(row["variant"]).get("total_par",{})
			if not par_bonuses.has("PAR165") or par_bonuses.has("PAR164"):
				problems.append("Fire staff penetration is not PAR165")
				break
	var source := load("res://scenes/debug/item_template_generator_v12.tscn") as PackedScene
	if source == null:
		problems.append("v1.2 menu scene missing")
	else:
		var screen: ItemTemplateGeneratorV12Screen = source.instantiate() as ItemTemplateGeneratorV12Screen
		root.add_child(screen)
		await process_frame
		await process_frame
		if screen.engine == null or screen.tabs.get_tab_count() != 2:
			problems.append("v1.2 editor tabs not available")
		if screen.results.is_empty() or screen.csv_button.disabled:
			problems.append("v1.2 startup generation or CSV missing")
		screen.queue_free()
	if problems.is_empty():
		print("ITEM_TEMPLATE_V12=PASS · 35 archetypes, 6 schools, filters, 500 items and UI")
		quit(0)
	else:
		for problem in problems:
			push_error("ITEM_TEMPLATE_V12=FAIL: " + problem)
		quit(1)
