extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lab := ItemGeneratorLab.new()
	var failures: Array[String] = []
	if lab.database.is_empty() or lab.archetypes().size() < 10:
		failures.append("Project25 data not loaded")
	var config := {
		"count": 100, "level_min": 10, "level_max": 30,
		"seed": 20261029, "archetypes": [],
		"rarity_weights": {"white": 15, "green": 60, "blue": 25, "purple": 0},
		"high_requirement_pct": 70, "medium_requirement_pct": 40,
		"crit_weight": 1.0, "par_value_scale": 1.0,
		"spread_pct": 5.0
	}
	var result := lab.generate(config)
	var items: Array = result.get("items", [])
	if not bool(result.get("ok", false)) or items.size() != 100:
		failures.append("100-item generation failed")
	var ids: Dictionary = {}
	var locked := 0
	var blue := 0
	for item in items:
		var uid := String(item.get("instance_id", ""))
		if ids.has(uid):
			failures.append("Duplicate instance ID")
		ids[uid] = true
		var level := int(item.get("level", 0))
		if level < 10 or level > 30:
			failures.append("Level escaped range")
		var q := String(item.get("quality", ""))
		if not ItemGeneratorLab.QUALITIES.has(q):
			failures.append("Unknown rarity")
		if bool(item.get("rarity_locked", false)):
			locked += 1
		if q == "blue":
			blue += 1
			if level < 25:
				failures.append("Blue below level threshold")
		if q == "purple":
			failures.append("Purple generated below 40")
		for key in item.get("total_par", {}):
			if not lab.database.get("parameters", {}).has(key):
				failures.append("Unknown PAR: " + String(key))
		for key in item.get("requirements", {}):
			if not ParCalculationService.PRIMARY_IDS.has(key):
				failures.append("Invalid requirement PAR")
	if locked > 0:
		failures.append("Normal batch included locked items")
	var repeat: Dictionary = lab.generate(config)
	var other: Array = repeat.get("items", [])
	if other.size() != items.size() or JSON.stringify(other) != JSON.stringify(items):
		failures.append("Same seed was not deterministic")
	config["comparison"] = true
	config["count"] = 100
	var comparison: Dictionary = lab.generate(config)
	var four: Array = comparison.get("items", [])
	if four.size() != 100:
		failures.append("Comparison did not create 25x4")
	else:
		for i in range(25):
			var tpl := String(four[i * 4].get("template_id", ""))
			for j in range(4):
				var item: Dictionary = four[i * 4 + j]
				if String(item.get("template_id", "")) != tpl:
					failures.append("Comparison group changed template")
				if String(item.get("quality", "")) != String(ItemGeneratorLab.QUALITIES[j]):
					failures.append("Comparison rarity order")
				if j == 3 and not bool(item.get("comparison_only", false)):
					failures.append("Locked purple not labelled")
	var output := {"generated": items.size(), "blue": blue, "comparison": four.size(),
		"profiles": lab.archetypes().size(), "failures": failures}
	print("ITEM_GENERATOR_LAB_TEST=", "PASS" if failures.is_empty() else "FAIL")
	print(JSON.stringify(output))
	quit(0 if failures.is_empty() else 1)
