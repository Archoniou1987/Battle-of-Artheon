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
			var variant: Dictionary = entry["variant"]
			if (variant.get("rolls",[]) as Array).size() != 2 or (variant.get("core_rolls",[]) as Array).size() != 1:
				problems.append("Lv30 blue must have two rarity + one stable CORE PAR lines")
				break
	# Approved zone matrix V2: 80% in each zone without the shield.
	var expected := {"PAR100":0.8,"PAR101":0.8,"PAR102":0.8,"PAR103":0.8,"PAR104":0.8}
	var sum_by_zone := {"PAR100":0.0,"PAR101":0.0,"PAR102":0.0,"PAR103":0.0,"PAR104":0.0}
	for slot in ItemTemplateGeneratorV12.ARMOUR_ZONES:
		for zone in ItemTemplateGeneratorV12.ARMOUR_ZONES[slot]:
			sum_by_zone[zone] += float(ItemTemplateGeneratorV12.ARMOUR_ZONES[slot][zone])
	for zone in expected:
		if not is_equal_approx(float(sum_by_zone[zone]),float(expected[zone])):
			problems.append("Armor matrix missing 80% without shield at " + String(zone))
	# Milestones: Lv20 blue unlocks CORE; Lv30 white gets CORE;
	# Lv60 purple has two CORE plus three distinct rarity slots.
	var checks := [
		{"level":20,"quality":"blue","core":1,"bonus":2},
		{"level":30,"quality":"white","core":1,"bonus":0},
		{"level":60,"quality":"purple","core":2,"bonus":3}
	]
	for checkpoint in checks:
		var output := generator.generate({"archetypes":["SWORD_CRIT"],"min_level":checkpoint["level"],
			"max_level":checkpoint["level"],"quality":checkpoint["quality"],"count":1,"seed":113})
		if not bool(output.get("ok",false)):
			problems.append("Missing v1.2 CORE milestone " + str(checkpoint["level"]))
			continue
		var v: Dictionary = Dictionary(output["rows"][0]).get("variant",{})
		if (v.get("core_rolls",[]) as Array).size() != int(checkpoint["core"]) or (v.get("rolls",[]) as Array).size() != int(checkpoint["bonus"]):
			problems.append("Incorrect CORE/rarity line separation at Lv" + str(checkpoint["level"]))
	var full := generator.generate({"archetypes":["MEDIUM_DEF"],"min_level":10,
		"max_level":30,"quality":"any","count":500,"seed":48,"armor_slot":"Наручи"})
	if not bool(full.get("ok",false)) or int(full.get("generated",0)) != 500:
		problems.append("500 armor templates were not generated")
	# Source: Project 25 'Генератор v1.2', A13:B22 and E4:I11.
	if absf(ItemTemplateGeneratorV12.diminishing(30.0,"armour") - 30.0) > 0.0001:
		problems.append("Armour DR incorrectly changes values before threshold")
	if absf(ItemTemplateGeneratorV12.diminishing(40.0,"armour") - 39.515635) > 0.01:
		problems.append("Armour DR at 40% differs from Project 25")
	if absf(ItemTemplateGeneratorV12.diminishing(100.0,"armour") - 68.707771) > 0.01:
		problems.append("Armour DR at 100% differs from Project 25")
	if absf(ItemTemplateGeneratorV12.rating_to_pct(100.0,1) - 20.0) > 0.0001:
		problems.append("Lv1 100-rating critical/dodge scale is incorrect")
	if absf(ItemTemplateGeneratorV12.rating_to_pct(100.0,100) - 4.0) > 0.0001:
		problems.append("Lv100 100-rating critical/dodge scale is incorrect")
	if absf(ItemTemplateGeneratorV12.armour_raw_pct(48.0,1) - 24.0) > 0.0001:
		problems.append("Lv1 heavy helmet should be 24% raw armour")
	if absf(ItemTemplateGeneratorV12.armour_raw_pct(192.0,100) - 24.0) > 0.0001:
		problems.append("Age factor K must preserve same armor percent for 4x rating")
	var diagnostic := generator.preview_effects({"PAR100":48},{"PAR033":100,"PAR031":100},1)
	if not is_equal_approx(float(diagnostic["armour"]["PAR100"]["after_dr_pct"]),24.0):
		problems.append("Armour DR diagnostic must combine base and direct PAR bonuses")
	if not is_equal_approx(float(diagnostic["ratings"]["PAR033"]["after_dr_pct"]),20.0):
		problems.append("Crit DR diagnostic must retain 20% below threshold")
	# Rare-only filters must exclude unavailable levels BEFORE selecting candidates.
	var rare := generator.generate({"archetypes":["SWORD_CRIT"],"min_level":30,"max_level":40,
		"quality":"purple","count":100,"seed":1989})
	if not bool(rare.get("ok",false)) or int(rare.get("generated",0)) != 100:
		problems.append("Rare-only v1.2 filter returned fewer than 100 available templates")
	else:
		for raw in rare["rows"]:
			if int(Dictionary(raw).get("level",0)) != 40:
				problems.append("Purple was generated before Lv40")
				break
	var school_only := generator.generate({"min_level":40,"max_level":40,
		"school":"fire","count":15,"seed":9})
	if not bool(school_only.get("ok",false)):
		problems.append("School-only generator filter failed")
	else:
		for raw in school_only["rows"]:
			if String(Dictionary(raw).get("school","")) != "Fire":
				problems.append("School-only filter included nonstaff items")
				break
	var slot_only := generator.generate({"min_level":40,"max_level":40,
		"armor_slot":"Шлем","count":15,"seed":9})
	if not bool(slot_only.get("ok",false)):
		problems.append("Armour-slot generator filter failed")
	else:
		for raw in slot_only["rows"]:
			if String(Dictionary(raw).get("slot","")) != "Шлем":
				problems.append("Armour-slot filter included weapons")
				break
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
			if par_bonuses.has("PAR164") or par_bonuses.has("PAR166") or par_bonuses.has("PAR167"):
				problems.append("Fire staff has universal or another school's penetration")
				break
			var all_rolls: Array = (Dictionary(row["variant"]).get("core_rolls",[]) as Array).duplicate()
			all_rolls.append_array(Dictionary(row["variant"]).get("rolls",[]))
			for raw_line in all_rolls:
				var line: Dictionary = raw_line
				if String(line.get("category","")) == "magic_pen" and String(line.get("par","")) != "PAR165":
					problems.append("Fire staff rolled an incorrect penetration PAR")
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
