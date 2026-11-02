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
	# Golden values come ONLY from Project 25 "Генератор v1.2" K3:N12.
	# 80/20 and similar labels describe a defence/attack budget split,
	# not an extra PAR roll and not a probability of selecting a bonus.
	var profile_cases := [
		{"id":"HEAVY_DEF","defence":80,"attack":20,"head":48,"shoulder":16},
		{"id":"HEAVY_ASSAULT","defence":65,"attack":35,"head":39,"shoulder":13},
		{"id":"MEDIUM_UNIVERSAL","defence":50,"attack":50,"head":30,"shoulder":10},
		{"id":"LIGHT_BATTLE","defence":20,"attack":80,"head":12,"shoulder":4}
	]
	for case_data in profile_cases:
		var profile_spec: Dictionary = {}
		for raw_spec in generator.archetypes():
			var candidate_spec: Dictionary = raw_spec
			if String(candidate_spec["id"]) == String(case_data["id"]):
				profile_spec = candidate_spec
				break
		if profile_spec.is_empty():
			problems.append("Missing approved armour profile " + String(case_data["id"]))
			continue
		var allocation := ItemTemplateGeneratorV12.armour_budget_split(profile_spec)
		if int(allocation.get("defence_pct",-1)) != int(case_data["defence"]) or int(allocation.get("attack_pct",-1)) != int(case_data["attack"]):
			problems.append("Incorrect defence/attack ratio for " + String(case_data["id"]))
		for level in [1,100]:
			var scale := 1 if level == 1 else 4
			var helm_values := generator._base_armour(profile_spec,"Шлем",level,1.0)
			var shoulder_values := generator._base_armour(profile_spec,"Плечи",level,1.0)
			if int(helm_values.get("PAR100",-1)) != int(case_data["head"])*scale:
				problems.append("Helmet armor differs from v1.2 control at Lv" + str(level))
			if int(shoulder_values.get("PAR100",-1)) != int(case_data["shoulder"])*scale:
				problems.append("Shoulder armor differs from v1.2 control at Lv" + str(level))
		var purple_helm := generator._base_armour(profile_spec,"Шлем",1,1.5)
		if int(purple_helm.get("PAR100",-1)) != roundi(float(case_data["head"])*1.5):
			problems.append("Quality multiplier changed armor budget unexpectedly")
	var pure_weapon := {"kind":"weapon","profile":"80/20"}
	if not ItemTemplateGeneratorV12.armour_budget_split(pure_weapon).is_empty():
		problems.append("Weapon must not have an armour defence/attack split")
	var profile_output := generator.generate({"archetypes":["HEAVY_DEF"],
		"min_level":30,"max_level":30,"quality":"white",
		"armor_slot":"Шлем","count":1,"seed":101})
	if bool(profile_output.get("ok",false)):
		var metadata: Dictionary = profile_output["rows"][0]["variant"]
		if int(Dictionary(metadata.get("budget_split",{})).get("defence_pct",-1)) != 80:
			problems.append("Generated armour lost its v1.2 defence/attack budget")
	# Independent final multiplier: direction fractions never depend on line count.
	var profile_80 := {"defence_pct":80,"attack_pct":20}
	for value in [
		{"name":"hp","expected":0.8},
		{"name":"crit","expected":0.2},
		{"name":"dodge","expected":0.8},
		{"name":"counter","expected":0.2}
	]:
		if absf(ItemTemplateGeneratorV12.armour_par_multiplier(String(value["name"]),profile_80)-float(value["expected"])) > 0.0001:
			problems.append("Wrong armour PAR multiplier: "+String(value["name"]))
	var profile_20 := {"defence_pct":20,"attack_pct":80}
	if absf(ItemTemplateGeneratorV12.armour_par_multiplier("hp",profile_20)-0.2) > 0.0001 or absf(ItemTemplateGeneratorV12.armour_par_multiplier("spell",profile_20)-0.8) > 0.0001:
		problems.append("Light profile does not apply its final budget multipliers")
	# The ONLY explicitly approved per-PAR direction splits in v1.2.
	for expectation in [
		{"logical":"hp","defence":1.0,"attack":0.0},
		{"logical":"reduce","defence":1.0,"attack":0.0},
		{"logical":"dodge","defence":1.0,"attack":0.0},
		{"logical":"counter","defence":0.0,"attack":1.0},
		{"logical":"crit","defence":0.0,"attack":1.0},
		{"logical":"attack","defence":0.0,"attack":1.0},
		{"logical":"spell","defence":0.0,"attack":1.0},
		{"logical":"armour_pen","defence":0.0,"attack":1.0}
	]:
		var split := ItemTemplateGeneratorV12.par_budget_direction(String(expectation["logical"]))
		if String(split.get("status","")) != "V12_APPROVED":
			problems.append("Missing approved PAR budget direction")
		elif absf(float(split["defence"])-float(expectation["defence"])) > 0.0001 or absf(float(split["attack"])-float(expectation["attack"])) > 0.0001:
			problems.append("PAR budget direction differs from v1.2")
	if String(ItemTemplateGeneratorV12.par_budget_direction("mana_regen").get("status","")) != "UNCLASSIFIED":
		problems.append("Unclassified regen must not receive invented budget direction")
	if String(Dictionary(generator.rules.get("stat_par",{})).get("mana_regen","")) != "PAR015":
		problems.append("Support staff must use combat mana regeneration, not out-of-combat PAR013")
	# v1.2 K30:N32 and K51:N51: MH 15%, OH 7.5%, OH base damage 80%.
	var mh_dagger := generator.generate({"archetypes":["DAGGER_ATTACK"],
		"min_level":100,"max_level":100,"quality":"purple",
		"weapon_hand":"MH","count":3,"seed":440})
	var oh_dagger := generator.generate({"archetypes":["DAGGER_ATTACK"],
		"min_level":100,"max_level":100,"quality":"purple",
		"weapon_hand":"OH","count":3,"seed":440})
	if not bool(mh_dagger.get("ok",false)) or not bool(oh_dagger.get("ok",false)):
		problems.append("Independent MH and OH dagger variants missing")
	else:
		var mh: Dictionary = mh_dagger["rows"][0]
		var oh: Dictionary = oh_dagger["rows"][0]
		var mh_variant: Dictionary = mh["variant"]
		var oh_variant: Dictionary = oh["variant"]
		if String(mh["slot"]) != "MH" or String(oh["slot"]) != "OH":
			problems.append("Dagger hand filter ignored")
		if float(mh_variant.get("par_slot_budget_pct",0.0)) != 15.0 or float(oh_variant.get("par_slot_budget_pct",0.0)) != 7.5:
			problems.append("Dagger PAR budgets do not follow selected hand")
		var mh_dmg: Array = mh_variant.get("damage",[])
		var oh_dmg: Array = oh_variant.get("damage",[])
		if mh_dmg.size() != 2 or oh_dmg.size() != 2:
			problems.append("Dagger physical damage was not generated")
		else:
			var mh_mid := 0.5 * float(int(mh_dmg[0])+int(mh_dmg[1]))
			var oh_mid := 0.5 * float(int(oh_dmg[0])+int(oh_dmg[1]))
			if absf(oh_mid/mh_mid-0.8) > 0.03:
				problems.append("OH base damage is not 80 percent of MH")
		var mh_affix := generator.nominal_affix("hp",100,"MH",1.0)
		var oh_affix := generator.nominal_affix("hp",100,"OH",1.0)
		if absf(oh_affix/mh_affix-0.5) > 0.0001:
			problems.append("OH PAR value does not use half of MH slot share")
	var both_hands := generator.generate({"archetypes":["DAGGER_ATTACK"],
		"min_level":30,"max_level":30,"quality":"white",
		"weapon_hand":"any","count":2,"seed":440})
	if not bool(both_hands.get("ok",false)) or int(both_hands.get("candidate_count",0)) != 2:
		problems.append("MH/OH archetype must expose exactly two hand candidates")
	var impossible_hand := generator.generate({"archetypes":["SWORD_CRIT"],
		"min_level":30,"max_level":30,"quality":"white",
		"weapon_hand":"OH","count":1,"seed":440})
	if bool(impossible_hand.get("ok",false)):
		problems.append("MH-only sword should not appear in an OH-only search")
	# 2H uses the sole 22.5% provisional value on the v1.2 tab.
	if absf(float(Dictionary(generator.rules.get("slot_budgets",{})).get("2H",0.0))-22.5) > 0.0001:
		problems.append("2H lab PAR share diverges from the v1.2 proposal")
	var two_handed := generator.generate({"archetypes":["2H_SWORD"],
		"min_level":30,"max_level":30,"quality":"blue",
		"weapon_hand":"2H","count":1,"seed":782})
	if bool(two_handed.get("ok",false)):
		var two_handed_variant: Dictionary = two_handed["rows"][0]["variant"]
		if float(two_handed_variant.get("par_slot_budget_pct",0.0)) != 22.5:
			problems.append("2H item uses an external PAR budget")
		if String(two_handed_variant.get("par_slot_budget_status","")) != "V12_APPROVED":
			problems.append("Approved 2H budget is not labelled")
	else:
		problems.append("2H item failed to generate")
	var hand_only := generator.generate({"archetypes":[],
		"min_level":10,"max_level":10,"quality":"white",
		"weapon_hand":"OH","count":50,"seed":782})
	if bool(hand_only.get("ok",false)):
		for hand_item in hand_only["rows"]:
			if String(Dictionary(hand_item).get("kind","")) != "weapon" or String(Dictionary(hand_item).get("slot","")) != "OH":
				problems.append("Weapon-hand filter allowed armour or another hand")
				break
	else:
		problems.append("OH-only laboratory generation failed")
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
