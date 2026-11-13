extends SceneTree

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var lab := ItemBalanceWorkbench.new()
	var failures: Array[String] = []
	var config := {
		"min_level": 10, "max_level": 30, "count":100, "seed":20261029,
		"types":["Топор 2H · Физ"], "unique_templates":true,
		"par_weights":{"PAR033":70, "PAR035":30},
		"par_settings":{}, "bonus_scale":1.0,
		"spread":0.0, "high_requirement":70.0, "medium_requirement":40.0
	}
	var result := lab.generate(config)
	var rows: Array = result.get("rows", [])
	if not bool(result.get("ok", false)):
		failures.append("No axe results")
	if rows.size() != 84:
		failures.append("Expected four axe template origins over 21 levels = 84")
	var unique: Dictionary = {}
	var found_crit := false
	for raw in rows:
		var row: Dictionary = raw
		if not String(row["item_type"]).contains("Топор 2H"):
			failures.append("Type filtering failed")
		var key := "%s/%d" % [row["source_template"], int(row["level"])]
		if unique.has(key):
			failures.append("Repeated unique template")
		unique[key] = true
		var level := int(row["level"])
		var variants: Array = row["variants"]
		if variants.is_empty() or variants.size() > 3:
			failures.append("Unexpected rarity count for levels 10-30")
		for variant in variants:
			var v: Dictionary = variant
			var q := String(v["quality"])
			if level < 25 and (q == "blue" or q == "purple"):
				failures.append("Locked rarity generated")
			for par in v.get("rolls", []):
				var bonus: Dictionary = par
				for stat in bonus:
					if stat != "PAR033" and stat != "PAR035":
						failures.append("Rolled PAR outside direct archetype")
					if stat == "PAR033":
						found_crit = true
	if not found_crit:
		failures.append("Direct archetype never rolled crit")
	config["unique_templates"] = false
	var random_run: Dictionary = lab.generate(config)
	if (random_run.get("rows", []) as Array).size() != 100:
		failures.append("100 item instances failed")
	if JSON.stringify(random_run) != JSON.stringify(lab.generate(config)):
		failures.append("Seed did not reproduce results")
	config["unique_templates"] = true
	config["par_settings"] = {
		"PAR033":{"max":7500.0,"rating100_lv1":20.0,"rating100_lv100":2.0}
	}
	var changed: Dictionary = lab.generate(config)
	var before_value := 0
	var after_value := 0
	for raw in rows:
		var entry: Dictionary = raw
		for version in entry["variants"]:
			before_value += int((version as Dictionary).get("total_par", {}).get("PAR033", 0))
	for raw in changed["rows"]:
		var entry: Dictionary = raw
		for version in entry["variants"]:
			after_value += int((version as Dictionary).get("total_par", {}).get("PAR033", 0))
	if after_value <= before_value:
		failures.append("Editing PAR maximum did not change generated values")
	if not is_equal_approx(lab.percentage("PAR033",100,25,config["par_settings"]),
		2.0 * lab.percentage("PAR033",100,25,{})):
		failures.append("Edited rating scale did not affect percentages")
	# 50/50 specialization benchmark: roughly 15% from primary stats, 15% from gear.
	var target25 := lab.required_rating("PAR033",15.0,25,{})
	var target30 := lab.required_rating("PAR033",15.0,30,{})
	if target25 < 190.0 or target25 > 195.0 or target30 < 200.0 or target30 > 208.0:
		failures.append("Unexpected gear rating target at Lv25-30")
	if not is_equal_approx(lab.expected_affix("PAR033",25,{}),41.25):
		failures.append("Standalone item formula no longer produces expected crit budget")
	var soft_cap := {"PAR033":{"diminish_start_pct":20.0,"diminish_width_pct":15.0}}
	var primary_rating := 185.0
	var raw_gain := lab.equipment_contribution("PAR033",primary_rating,target25,25,{})
	var dampened_gain := lab.equipment_contribution("PAR033",primary_rating,target25,25,soft_cap)
	if not is_equal_approx(raw_gain,15.0) or dampened_gain >= raw_gain:
		failures.append("Diminishing must reduce marginal gear crit, not raw base")
	if lab.default_par_settings("PAR033")["gear_target_pct"] != 15.0:
		failures.append("Gear contribution target not exposed")

	# Requirement attributes must represent both form identity and the specialization.
	config["par_weights"] = {"PAR033": 100.0}
	config["par_settings"] = {}
	var crit_axe: Dictionary = lab.generate(config)
	for item_raw in crit_axe.get("rows", []):
		var item: Dictionary = item_raw
		for version_raw in item["variants"]:
			var version: Dictionary = version_raw
			var requirements: Dictionary = version["requirements"]
			if not requirements.has("PAR001") or not requirements.has("PAR003") or requirements.has("PAR006"):
				failures.append("Critical 2H axe requirements must be STR+INTU")
				break
			if version.get("requirement_rule", "") != ItemBalanceWorkbench.REQUIREMENT_RULE:
				failures.append("Requirement provenance missing from generated item")
				break
	config["par_weights"] = {"PAR031": 100.0}
	var dodge_axe: Dictionary = lab.generate(config)
	for item_raw in dodge_axe.get("rows", []):
		var item: Dictionary = item_raw
		var requirements: Dictionary = (item["variants"][0] as Dictionary)["requirements"]
		if not requirements.has("PAR001") or not requirements.has("PAR002"):
			failures.append("Dodge 2H axe requirements must be STR+DEX")
			break
	config["par_weights"] = {}
	var fallback: Dictionary = lab.generate(config)
	var fallback_req: Dictionary = (((fallback.get("rows",[]) as Array)[0] as Dictionary)["variants"][0] as Dictionary)["requirements"]
	if not fallback_req.has("PAR001") or not fallback_req.has("PAR006"):
		failures.append("Without a specialization the axe should keep STR+END")
	config["par_weights"] = {"PAR033": 100.0}
	config["archetype_name"] = "Крит; двойные \"кавычки\""
	var export_result: Dictionary = lab.generate(config)
	var csv := ItemLabCsvExporter.build(config, export_result, lab)
	if not csv.begins_with("\uFEFF"):
		failures.append("CSV missing UTF-8 BOM")
	if not csv.contains("BOA_ITEM_LAB_CSV_V1") or not csv.contains("PAR_EFFECTIVE") or not csv.contains("requirements_json"):
		failures.append("CSV missing metadata, effective PAR or explicit columns")
	if not csv.contains("Крит; двойные"):
		failures.append("CSV lost semicolon/Cyrillic inside archetype")
	if not csv.contains("item_primary_plus_weighted_affix_secondary_v1"):
		failures.append("CSV missing requirement formula provenance")
	var item_rows := 0
	var rarity_variants := 0
	for item_raw in export_result["rows"]:
		rarity_variants += ((item_raw as Dictionary)["variants"] as Array).size()
	for line in csv.split("\n"):
		if line.begins_with("\"ITEM\";"):
			item_rows += 1
	if item_rows != rarity_variants:
		failures.append("CSV must contain exactly one row per generated rarity variant")
	if csv != ItemLabCsvExporter.build(config, export_result, lab):
		failures.append("Identical snapshot must produce identical CSV")
	var quotes := ItemLabCsvExporter._csv_line(["a;b", "x\"y"])
	if quotes != "\"a;b\";\"x\"\"y\"":
		failures.append("CSV escaping failed")
		# Explicit archetype requirements override slot identity and affix choices.
	config["types"] = ["Топор 2H · Физ", "Щит", "Ботинки / Лёгкая", "Нагрудник / Тяжёлая"]
	config["min_level"] = 25
	config["max_level"] = 25
	config["requirement_pars"] = ["PAR002", "PAR006"]
	config["par_weights"] = {"PAR033":100.0}
	var custom_result: Dictionary = lab.generate(config)
	if not bool(custom_result.get("ok",false)):
		failures.append("Explicit DEX+STA archetype failed generation")
	var amounts: Dictionary = {}
	for item_raw in custom_result.get("rows",[]):
		var item: Dictionary = item_raw
		for variation_raw in item["variants"]:
			var variation: Dictionary = variation_raw
			var reqs: Dictionary = variation["requirements"]
			if reqs.size() != 2 or not reqs.has("PAR002") or not reqs.has("PAR006"):
				failures.append("Every item must require only DEX and STA")
				break
			if String(variation["requirement_rule"]) != ItemBalanceWorkbench.SELECTED_REQUIREMENT_RULE:
				failures.append("Explicit requirement rule not recorded")
				break
			if String(variation["requirement_sources"]["mode"]) != "selected_archetype":
				failures.append("Explicit requirement origin not recorded")
				break
			amounts[String(item["slot"])] = int(reqs["PAR002"])
	if not amounts.has("2H") or not amounts.has("Ботинки") or int(amounts.get("2H",0)) <= int(amounts.get("Ботинки",0)):
		failures.append("Required DEX/STA amount must vary by slot at same level")
	config["min_level"] = 30
	config["max_level"] = 30
	var higher: Dictionary = lab.generate(config)
	for item_raw in higher.get("rows",[]):
		var item: Dictionary = item_raw
		if String(item["slot"]) == "2H":
			var requirements: Dictionary = (item["variants"][0] as Dictionary)["requirements"]
			if int(requirements["PAR002"]) <= int(amounts.get("2H",0)):
				failures.append("Required DEX/STA amount must grow with item level")
			break
	var csv_override := ItemLabCsvExporter.build(config,higher,lab)
	if not csv_override.contains("selected_archetype_primary_pars_by_slot_level_v2") or not csv_override.contains("requirement_pars"):
		failures.append("CSV must include explicit requirement choices and formula")
	config["requirement_pars"] = ["PAR002","PAR002"]
	if bool(lab.generate(config).get("ok",true)):
		failures.append("Duplicate selected requirement stats must be rejected")
	config.erase("requirement_pars")
		# Editable laboratory settings must survive closing the screen.
	var profile_path := "user://boa_item_lab_ci_profile.json"
	var profile_data := {"archetype_name":"Mobile test","preview_level":30,
		"par_weights":{"PAR033":75.0,"PAR031":25.0},
		"par_settings":{"PAR033":{"rating100_lv1":12.0,"max":4200.0}},
		"types":["Топор 2H · Физ"]}
	if not lab.save_profile(profile_data,profile_path):
		failures.append("Cannot save local test profile")
	else:
		var restored := lab.load_profile(profile_path)
		if String(restored.get("archetype_name","")) != "Mobile test" or int(restored.get("preview_level",0)) != 30:
			failures.append("Saved profile name or level missing")
		if not is_equal_approx(float((restored.get("par_weights",{}) as Dictionary).get("PAR033",0)),75.0):
			failures.append("Saved archetype weight not restored")
		if not is_equal_approx(float(((restored.get("par_settings",{}) as Dictionary).get("PAR033",{}) as Dictionary).get("max",0)),4200.0):
			failures.append("Saved PAR maximum not restored")
		if not (restored.get("types",[]) as Array).has("Топор 2H · Физ"):
			failures.append("Saved item type selection not restored")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	if not lab.load_profile(profile_path).is_empty():
		failures.append("Missing profile should load as empty")
	if not is_equal_approx(lab.percentage("PAR033",100.0,25,{}),7.818181818):
		failures.append("100 rating must equal 7.82% at Lv25")
		print("ITEM_WORKBENCH_TEST=", "PASS" if failures.is_empty() else "FAIL")
	print(JSON.stringify({"templates":rows.size(),"samples":(random_run.get("rows",[]) as Array).size(),
		"crit_before":before_value,"crit_after":after_value,"errors":failures}))
	quit(0 if failures.is_empty() else 1)
