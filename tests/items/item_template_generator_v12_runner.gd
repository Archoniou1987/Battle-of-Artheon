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
	if ItemTemplateGeneratorV12.ARMOUR_COMPENSATION["metal"] != 0.0 or ItemTemplateGeneratorV12.ARMOUR_COMPENSATION["leather"] != 0.5 or ItemTemplateGeneratorV12.ARMOUR_COMPENSATION["cloth"] != 0.8:
		problems.append("Incorrect armour class compensation shares")
	var light10 := generator.generate({"archetypes":["LIGHT_RESOURCE"],
		"min_level":10,"max_level":10,"quality":"white",
		"armor_slot":"Шлем","count":5,"seed":17})
	if not bool(light10.get("ok",false)):
		problems.append("Light Lv10 compensation fixture failed")
	else:
		for row in light10["rows"]:
			var variant: Dictionary = row["variant"]
			if (variant.get("compensation_rolls",[]) as Array).size() != 1:
				problems.append("Light armor compensation missing at Lv10")
				break
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
	# Approved Project 25 equip-stat gates B(L) * K/N * F(L), rounded once.
	var sword_spec: Dictionary = {}
	var heavy_three_spec: Dictionary = {}
	var support_spec: Dictionary = {}
	for raw_spec in generator.archetypes():
		var spec: Dictionary = raw_spec
		match String(spec.get("id","")):
			"SWORD_CRIT": sword_spec = spec
			"HEAVY_ASSAULT": heavy_three_spec = spec
			"STAFF_SUPPORT": support_spec = spec
	if sword_spec.is_empty() or heavy_three_spec.is_empty() or support_spec.is_empty():
		problems.append("Approved v1.2 requirement archetypes unavailable")
	else:
		for checkpoint in [
			{"lvl":1,"n":0},{"lvl":10,"n":0},{"lvl":11,"n":3},
			{"lvl":12,"n":4},{"lvl":15,"n":8},{"lvl":19,"n":17},
			{"lvl":20,"n":20},{"lvl":30,"n":27},{"lvl":100,"n":76}
		]:
			var lvl := int(checkpoint["lvl"])
			var stat_requirements := generator._requirements(sword_spec,lvl)
			if int(checkpoint["n"]) == 0:
				if not stat_requirements.is_empty():
					problems.append("Item Lv" + str(lvl) + " must have no equipment requirements")
			elif stat_requirements.size() != 2 or int(stat_requirements.get("PAR001",0)) != int(checkpoint["n"]) or int(stat_requirements.get("PAR003",0)) != int(checkpoint["n"]):
				problems.append("Equip requirement ramp mismatch for sword Lv" + str(lvl))
		var hybrid := generator._requirements(heavy_three_spec,30)
		if hybrid.size() != 3 or int(hybrid.get("PAR003",0)) != 18:
			problems.append("Third requirement attribute must share, not increase, total cost")
		var support := generator._requirements(support_spec,30)
		if support.size() != 2 or int(support.get("PAR004",0)) != 15:
			problems.append("Support staff must use moderate K=0.4 requirement")
	var level10 := generator.generate({"archetypes":["MEDIUM_DEF"],"min_level":10,
		"max_level":10,"quality":"green","count":100,"seed":105,"armor_slot":"Наручи"})
	if not bool(level10.get("ok",false)) or int(level10.get("generated",0)) != 100:
		problems.append("Lv10 green bracer generation failed")
	else:
		for raw_row in level10["rows"]:
			var variant: Dictionary = Dictionary(raw_row).get("variant",{})
			if not Dictionary(variant.get("requirements",{})).is_empty():
				problems.append("Lv10 generated item requires stats before Lv11")
				break
			for raw_line in variant.get("rolls",[]):
				var line: Dictionary = raw_line
				if String(line.get("category","")) == "primary" and not ["PAR002","PAR006"].has(String(line.get("par",""))):
					problems.append("Lv10 main stat roll selected outside archetype priorities")
					break
	# Numerically anchored HP/Mana budget: 14 equip slots = 100% of the pool.
	var weights: Dictionary = generator.rules.get("slot_budgets",{})
	var slots: Array = ["MH","OH","Шлем","Плечи","Нагрудник","Перчатки",
		"Наручи","Пояс","Штаны","Ботинки","Плащ"]
	var sum_percent := 3.0 * 7.5 # 2 rings and necklace; pending dedicated archetypes
	for slot in slots:
		sum_percent += float(weights.get(slot,0))
	if absf(sum_percent-100.0) > 0.0001:
		problems.append("14 slot PAR weights no longer total 100 percent")
	for level in [10,30,60,100]:
		var slot_share := 7.5 / ItemTemplateGeneratorV12.REFERENCE_SLOT_BUDGET
		var hp_expected := 101.19*float(level)/100.0*slot_share
		var mana_expected := 50.60*float(level)/100.0*slot_share
		if absf(generator.nominal_affix("hp",level,"Шлем",1.0)-hp_expected) > 0.001:
			problems.append("HP white nominal mismatch at Lv" + str(level))
		if absf(generator.nominal_affix("mana",level,"Шлем",1.0)-mana_expected) > 0.001:
			problems.append("Mana white nominal mismatch at Lv" + str(level))
		var current_white := generator.nominal_affix("hp",level,"Шлем",1.0)
		var epic := generator.nominal_affix("hp",level,"Шлем",1.5)
		if absf(epic-current_white*1.5) > 0.001:
			problems.append("HP rarity modifier applied incorrectly at Lv" + str(level))
	# Target build anchors are normalized to 14 slots, two PAR lines, epic 1.5.
	var ref_share := 7.5 / ItemTemplateGeneratorV12.REFERENCE_SLOT_BUDGET
	for entry in [
		{"stat":"attack","level":10,"target":50.0},
		{"stat":"attack","level":100,"target":150.0},
		{"stat":"spell","level":20,"target":200.0},
		{"stat":"spell","level":100,"target":2000.0}
	]:
		var per_line := generator.nominal_affix(String(entry["stat"]),int(entry["level"]),"Шлем",1.0)
		var projected := per_line / ref_share * ItemTemplateGeneratorV12.FULL_BUILD_REFERENCE_LINES
		if absf(projected-float(entry["target"])) > 0.001:
			problems.append("v1.2 target mismatch for " + String(entry["stat"]) + " Lv" + str(entry["level"]))
	# A baseline white CORE value is independent of the number of unlocked
	# rarity lines: quality multiplies the line, never divides it.
	var white_hp := generator.nominal_affix("hp",60,"Шлем",1.0)
	var purple_hp := generator.nominal_affix("hp",60,"Шлем",1.5)
	if absf(purple_hp / white_hp - 1.5) > 0.00001:
		problems.append("New rarity lines incorrectly dilute the full CORE allocation")
	if generator.calibration_status("hp") != "PROJECT25_ANCHOR" or generator.calibration_status("crit") != "PROVISIONAL_EXTREMUM":
		problems.append("Generator must label calibrated and provisional PAR separately")
	var sample_blue := generator.generate({"archetypes":["HAMMER_DEF"],"min_level":30,"max_level":30,
		"quality":"blue","count":40,"seed":415})
	if bool(sample_blue.get("ok",false)):
		for sample in sample_blue["rows"]:
			var result: Dictionary = Dictionary(sample).get("variant",{})
			var all_lines: Array = (result.get("core_rolls",[]) as Array).duplicate()
			all_lines.append_array(result.get("rolls",[]))
			for line in all_lines:
				if not Dictionary(line).has("calibration"):
					problems.append("Bonus line lacks calibration status")
					break
	else:
		problems.append("Unable to check real v1.2 bonus calibration annotations")
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
