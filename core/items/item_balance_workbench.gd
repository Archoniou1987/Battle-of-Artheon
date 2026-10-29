class_name ItemBalanceWorkbench
extends RefCounted

## Development-only calculations. Existing game generator, saves and runtime items stay unchanged.
const QUALITY := ["white", "green", "blue", "purple"]
const MULTIPLIER := {"white":1.0, "green":1.15, "blue":1.30, "purple":1.50}
const UNLOCK := {"white":1, "green":10, "blue":25, "purple":40}
const ZONES := ["PAR100", "PAR101", "PAR102", "PAR103", "PAR104"]

var source := ItemGeneratorLab.new()
var rng := RandomNumberGenerator.new()

func available_types() -> Array:
	var names: Dictionary = {}
	for raw in source.database.get("templates", []):
		var t: Dictionary = raw
		names[template_type(t)] = true
	var out: Array = names.keys()
	out.sort()
	return out

func template_type(t: Dictionary) -> String:
	var archetype := String(t.get("archetype", ""))
	if String(t.get("slot", "")) == "MH" or String(t.get("slot", "")) == "OH" or String(t.get("slot", "")) == "2H":
		return archetype
	return String(t.get("class", t.get("slot", "")))

func default_archetype() -> Dictionary:
	return {"PAR002":20.0, "PAR003":20.0, "PAR031":20.0, "PAR033":25.0, "PAR035":15.0}

func default_par_settings(par: String) -> Dictionary:
	var info: Dictionary = source.database.get("parameters", {}).get(par, {})
	return {
		"max": float(info.get("cap", 0)),
		"min_level": int(info.get("minimum", 999)),
		"rating100_lv1": 10.0,
		"rating100_lv100": 1.0,
		"growth": 1.0,
		"value_scale": 1.0
	}

func parameter_settings(par: String, overrides: Dictionary) -> Dictionary:
	var info := default_par_settings(par)
	var modified: Dictionary = overrides.get(par, {})
	for key in modified:
		info[key] = modified[key]
	return info

func is_percentage(par: String) -> bool:
	var id := int(par.trim_prefix("PAR"))
	if id >= 30 and id <= 35:
		return true
	if id >= 53 and id <= 56:
		return true
	if id >= 71 and id <= 75:
		return true
	if id >= 100 and id <= 135:
		return true
	if id >= 151 and id <= 157:
		return true
	if id >= 164 and id <= 170:
		return true
	return id >= 190 and id <= 196

func percentage(par: String, value: float, level: int, overrides: Dictionary) -> float:
	if not is_percentage(par):
		return NAN
	var settings := parameter_settings(par, overrides)
	var lv := float(clampi(level, 1, 100) - 1) / 99.0
	var percent_for_100 := lerpf(float(settings["rating100_lv1"]), float(settings["rating100_lv100"]), lv)
	return value / 100.0 * percent_for_100

func generate(config: Dictionary) -> Dictionary:
	var min_lv := clampi(int(config.get("min_level", 10)), 1, 100)
	var max_lv := clampi(int(config.get("max_level", 30)), min_lv, 100)
	var selected: Array = config.get("types", [])
	var candidates: Array = []
	for raw in source.database.get("templates", []):
		var t: Dictionary = raw
		if not selected.is_empty() and not selected.has(template_type(t)):
			continue
		for level in range(min_lv, max_lv + 1):
			# Each distinct (source white template, target item level) occurs once.
			candidates.append({"template": t, "level": level})
	if candidates.is_empty():
		return {"ok":false, "reason":"Нет исходных шаблонов выбранных типов", "rows":[]}
	rng.seed = maxi(1, int(config.get("seed", 20261029)))
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var want := clampi(int(config.get("count", 100)), 1, 500)
	var unique_mode := bool(config.get("unique_templates", true))
	var total := mini(want, candidates.size()) if unique_mode else want
	var rows: Array = []
	var missed := 0
	for i in range(total):
		var choice: Dictionary = candidates[i] if unique_mode else candidates[rng.randi_range(0, candidates.size() - 1)]
		var template: Dictionary = choice["template"]
		var level := int(choice["level"])
		var variants: Array = []
		if unique_mode:
			for quality in QUALITY:
				if _quality_allowed(template, level, quality):
					variants.append(_variant(template, level, quality, config))
		else:
			var selected_quality := _choose_quality(template, level, config)
			variants.append(_variant(template, level, selected_quality, config))
		if variants.is_empty():
			missed += 1
			continue
		rows.append({
			"id": "LAB-T%05d" % (i + 1),
			"source_template": String(template.get("id", "")),
			"item_type": template_type(template),
			"slot": String(template.get("slot", "")),
			"level": level,
			"variants": variants
		})
	return {"ok":true, "rows":rows, "requested":want, "available_unique":candidates.size(),
		"returned":rows.size(), "skipped":missed, "unique_templates":unique_mode}

func _quality_allowed(t: Dictionary, level: int, quality: String) -> bool:
	if level < int(UNLOCK.get(quality, 1)):
		return false
	var slot := String(t.get("slot", ""))
	if slot == "Кольцо" and level < 15:
		return false
	if slot == "Амулет" and level < 25:
		return false
	if quality == "white" and (slot == "Кольцо" or slot == "Амулет" or
		(slot == "OH" and String(t.get("class", "")).contains("Магическая"))):
		return false
	return true

func _choose_quality(t: Dictionary, level: int, config: Dictionary) -> String:
	var weights: Dictionary = config.get("rarities", {"white":1.0, "green":1.0, "blue":1.0, "purple":1.0})
	var valid: Array = []
	var weight_total := 0.0
	for quality in QUALITY:
		if not _quality_allowed(t, level, quality):
			continue
		var weight := maxf(0.0, float(weights.get(quality, 0)))
		if weight <= 0.0:
			continue
		weight_total += weight
		valid.append({"quality":quality, "cutoff":weight_total})
	if valid.is_empty():
		for quality in QUALITY:
			if _quality_allowed(t, level, quality):
				return quality
		return "white"
	var rolled := rng.randf() * weight_total
	for entry in valid:
		if rolled < float(entry["cutoff"]):
			return String(entry["quality"])
	return String(valid.back()["quality"])

func _variant(t: Dictionary, level: int, quality: String, config: Dictionary) -> Dictionary:
	var original_level := maxi(1, int(t.get("level", 1)))
	var level_ratio := float(level) / float(original_level)
	var spread := clampf(float(config.get("spread", 5)), 0.0, 20.0) / 100.0
	var base_damage: Array = []
	for n in t.get("damage", []):
		base_damage.append(maxi(1, int(floor(float(n) * level_ratio * float(config.get("damage_scale", 1.0)) + 0.5))))
	var armor: Dictionary = {}
	for key in t.get("armour", {}):
		armor[key] = maxi(1, int(floor(float(t["armour"][key]) * level_ratio * float(config.get("armour_scale", 1.0)) + 0.5)))
	var pars: Dictionary = {}
	var opts: Dictionary = config.get("par_settings", {})
	for key in t.get("fixed_par", {}):
		var settings := parameter_settings(String(key), opts)
		var source_max := float(source.database.get("parameters", {}).get(key, {}).get("cap", 1000))
		var cap_ratio := float(settings["max"]) / maxf(1.0, source_max)
		var value := float(t["fixed_par"][key]) * level_ratio * cap_ratio * float(MULTIPLIER[quality])
		pars[key] = maxi(1, int(floor(value * rng.randf_range(1.0 - spread, 1.0 + spread) + 0.5)))
	var rolled: Array = []
	for i in range(QUALITY.find(quality)):
		var bonus := _roll_direct(t, level, config, spread)
		if not bonus.is_empty():
			rolled.append(bonus)
			for key in bonus:
				pars[key] = int(pars.get(key, 0)) + int(bonus[key])
	var requirements: Dictionary = {}
	var requirements_original: Dictionary = t.get("requirements", {})
	var strictness := int(t.get("strictness", 70))
	var required_fraction := float(config.get("high_requirement", 70)) if strictness >= 70 else float(config.get("medium_requirement", 40))
	var n := maxi(1, requirements_original.size())
	for key in requirements_original:
		var needed := float(18 + 2 * (level - 1)) * required_fraction / 100.0 / float(n) * _requirement_open(level)
		requirements[key] = maxi(0, int(floor(needed + 0.5)))
	return {"quality":quality, "damage":base_damage, "armour":armor,
		"fixed_par":pars, "rolls":rolled, "total_par":pars, "requirements":requirements}

func _requirement_open(level: int) -> float:
	if level <= 10:
		return 0.0
	if level >= 20:
		return 1.0
	var opening := {11:0.25, 12:0.3125, 13:0.375, 14:0.4375, 15:0.5,
		16:0.6, 17:0.7, 18:0.8, 19:0.9}
	return float(opening.get(level, 1.0))

func _roll_direct(t: Dictionary, level: int, config: Dictionary, spread: float) -> Dictionary:
	var weights: Dictionary = config.get("par_weights", {})
	var overrides: Dictionary = config.get("par_settings", {})
	var choices: Array = []
	var total := 0.0
	for par in weights:
		var key := String(par)
		var info := parameter_settings(key, overrides)
		var weight := maxf(0.0, float(weights[par]))
		if weight <= 0.0 or float(info["max"]) <= 0.0 or level < int(info["min_level"]):
			continue
		if not _par_compatible(key, t):
			continue
		total += weight
		choices.append({"par":key, "cutoff":total})
	if choices.is_empty():
		return {}
	var number := rng.randf() * total
	var chosen := String(choices.back()["par"])
	for entry in choices:
		if number < float(entry["cutoff"]):
			chosen = String(entry["par"])
			break
	var settings := parameter_settings(chosen, overrides)
	var baseline_ratio := 0.005
	var references: Dictionary = t.get("green_reference", {})
	if references.is_empty():
		references = t.get("blue_reference", {})
	for key in references:
		var default_cap := float(source.database.get("parameters", {}).get(key, {}).get("cap", 0))
		if default_cap > 0.0:
			baseline_ratio = float(references[key]) / default_cap
			break
	var src_level := maxi(1, int(t.get("level", 1)))
	var growth := clampf(float(settings["growth"]), 0.1, 5.0)
	var level_scale := pow(float(level) / float(src_level), growth)
	var amount := baseline_ratio * float(settings["max"]) * level_scale
	amount *= clampf(float(settings["value_scale"]), 0.0, 20.0) * clampf(float(config.get("bonus_scale", 1.0)), 0.0, 20.0)
	amount *= rng.randf_range(1.0 - spread, 1.0 + spread)
	var value := maxi(1, int(floor(amount + 0.5)))
	var out: Dictionary = {}
	var number := int(chosen.trim_prefix("PAR"))
	# A zonal armour roll applies as one property to every covered zone.
	if number >= 100 and number <= 104:
		for zone in t.get("armour", {}):
			out[zone] = value
	elif number >= 105 and number <= 124:
		var physical_type := (number - 105) % 4
		for zone in t.get("armour", {}):
			var zone_index := ZONES.find(String(zone))
			if zone_index >= 0:
				out["PAR%03d" % (105 + zone_index * 4 + physical_type)] = value
	else:
		out[chosen] = value
	return out

func _par_compatible(par: String, t: Dictionary) -> bool:
	var id := int(par.trim_prefix("PAR"))
	if id >= 100 and id <= 124:
		return not (t.get("armour", {}) as Dictionary).is_empty()
	# These are system/weapon-identity fields, not random item bonuses.
	if id == 50 or id == 51 or id == 57 or id == 74 or id == 76 or id == 212:
		return false
	return true
