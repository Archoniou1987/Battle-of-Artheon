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
	print("ITEM_WORKBENCH_TEST=", "PASS" if failures.is_empty() else "FAIL")
	print(JSON.stringify({"templates":rows.size(),"samples":(random_run.get("rows",[]) as Array).size(),
		"crit_before":before_value,"crit_after":after_value,"errors":failures}))
	quit(0 if failures.is_empty() else 1)
