class_name ItemGeneratorLab
extends RefCounted

## Read-only diagnostic generator. Never writes to ItemRepository, saves or loot.
## The separate legacy ItemGenerator remains untouched until balance is approved.
const DATA_PATH := "res://data/items/project25_generator_lab.json"
const QUALITIES := ["white", "green", "blue", "purple"]
const RARITY_NAMES := {"white": "Белый", "green": "Зелёный", "blue": "Синий", "purple": "Фиолетовый"}
const RARITY_FACTOR := {"white": 1.0, "green": 1.15, "blue": 1.30, "purple": 1.50}
const RARITY_LEVEL := {"white": 1, "green": 10, "blue": 25, "purple": 40}
const ZONES := ["PAR100", "PAR101", "PAR102", "PAR103", "PAR104"]

var database: Dictionary = {}
var rng := RandomNumberGenerator.new()
var serial := 0

func _init() -> void:
	if FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			database = parsed

func archetypes() -> Array:
	var names: Dictionary = {}
	for entry in database.get("templates", []):
		var name := String(entry.get("archetype", ""))
		if not name.is_empty():
			names[name] = true
	var result: Array = names.keys()
	result.sort()
	return result

func generate(config: Dictionary) -> Dictionary:
	if database.is_empty():
		return {"ok": false, "reason": "Project 25 lab templates missing", "items": []}
	var low := clampi(int(config.get("level_min", 10)), 1, 100)
	var high := clampi(int(config.get("level_max", 30)), low, 100)
	var requested = config.get("archetypes", [])
	var templates: Array = []
	for raw in database.get("templates", []):
		var t: Dictionary = raw
		var level := int(t.get("level", 1))
		if level < low or level > high:
			continue
		if requested is Array and not requested.is_empty() and not requested.has(t.get("archetype", "")):
			continue
		templates.append(t)
	if templates.is_empty():
		return {"ok": false, "reason": "Нет шаблонов для выбранного уровня и архетипов", "items": []}
	rng.seed = maxi(1, int(config.get("seed", 20261029)))
	serial = 0
	var count := clampi(int(config.get("count", 100)), 1, 200)
	var comparison := bool(config.get("comparison", false))
	var items: Array = []
	if comparison:
		# Four versions of one template, with a clear warning for unavailable rarities.
		var groups := mini(50, maxi(1, int(ceil(float(count) / 4.0))))
		for i in range(groups):
			var t: Dictionary = templates[rng.randi_range(0, templates.size() - 1)]
			for q in QUALITIES:
				items.append(_make_item(t, q, config, i + 1, true))
	else:
		for i in range(count):
			var t: Dictionary = templates[rng.randi_range(0, templates.size() - 1)]
			var q := _choose_rarity(t, config)
			items.append(_make_item(t, q, config, i + 1, false))
	return {"ok": true, "items": items, "templates_available": templates.size(), "mode": "comparison" if comparison else "list"}

func _choose_rarity(t: Dictionary, config: Dictionary) -> String:
	var weights: Dictionary = config.get("rarity_weights", {"white": 15, "green": 60, "blue": 25, "purple": 0})
	var options: Array = []
	var total := 0.0
	for q in QUALITIES:
		if not _rarity_allowed(t, q):
			continue
		var w := maxf(0.0, float(weights.get(q, 0)))
		if w <= 0.0:
			continue
		total += w
		options.append({"quality": q, "cutoff": total})
	if options.is_empty():
		for q in QUALITIES:
			if _rarity_allowed(t, q):
				return q
		return "green"
	var roll := rng.randf() * total
	for item in options:
		if roll < float(item["cutoff"]):
			return String(item["quality"])
	return String(options.back()["quality"])

func _rarity_allowed(t: Dictionary, quality: String) -> bool:
	var lvl := int(t.get("level", 1))
	if lvl < int(RARITY_LEVEL.get(quality, 1)):
		return false
	var slot := String(t.get("slot", ""))
	if quality == "white" and (slot == "Кольцо" or slot == "Амулет" or (slot == "OH" and String(t.get("class", "")).contains("Магическая"))):
		return false
	if slot == "Кольцо" and lvl < 15:
		return false
	if slot == "Амулет" and lvl < 25:
		return false
	return true

func _make_item(t: Dictionary, quality: String, config: Dictionary, group_id: int, comparison: bool) -> Dictionary:
	serial += 1
	var level := int(t.get("level", 1))
	var spread := clampf(float(config.get("spread_pct", 5.0)), 0.0, 20.0) / 100.0
	var fixed: Dictionary = {}
	for key in t.get("fixed_par", {}):
		var raw := float(t["fixed_par"][key]) * float(RARITY_FACTOR.get(quality, 1.0))
		fixed[key] = maxi(1, int(floor(raw * rng.randf_range(1.0 - spread, 1.0 + spread) + 0.5)))
	var bonuses: Array = []
	for i in range(QUALITIES.find(quality)):
		var picked: Dictionary = _roll_bonus(t, config, spread)
		if not picked.is_empty():
			bonuses.append(picked)
	var combined: Dictionary = fixed.duplicate()
	for bonus in bonuses:
		for key in bonus.get("values", {}):
			combined[key] = int(combined.get(key, 0)) + int(bonus["values"][key])
	var level_factor := _requirement_fraction(level)
	var strictness := int(t.get("strictness", 70))
	var required_k: float = float(config.get("high_requirement_pct", 70.0)) if strictness >= 70 else float(config.get("medium_requirement_pct", 40.0))
	var requirements: Dictionary = {}
	var original: Dictionary = t.get("requirements", {})
	var n := maxi(1, original.size())
	for key in original:
		requirements[key] = maxi(0, int(floor(float(18 + 2 * (level - 1)) * required_k / 100.0 / float(n) * level_factor + 0.5)))
	var armour: Dictionary = {}
	for key in t.get("armour", {}):
		armour[key] = maxi(0, int(floor(float(t["armour"][key]) * float(config.get("armour_scale", 1.0)) + 0.5)))
	var damage: Array = []
	for v in t.get("damage", []):
		damage.append(maxi(0, int(floor(float(v) * float(config.get("damage_scale", 1.0)) + 0.5))))
	return {
		"instance_id": "LAB-%06d" % serial,
		"template_id": String(t.get("id", "")),
		"level": level, "quality": quality, "rarity_name": RARITY_NAMES[quality],
		"archetype": String(t.get("archetype", "")), "slot": String(t.get("slot", "")),
		"type": String(t.get("class", "")), "requirements": requirements,
		"base_armour": armour, "damage": damage, "fixed_par": fixed,
		"bonuses": bonuses, "total_par": combined,
		"rarity_locked": not _rarity_allowed(t, quality),
		"comparison_only": comparison and not _rarity_allowed(t, quality),
		"group_id": group_id
	}

func _requirement_fraction(level: int) -> float:
	if level <= 10:
		return 0.0
	if level >= 20:
		return 1.0
	var opening := {11: 0.25, 12: 0.3125, 13: 0.375, 14: 0.4375,
		15: 0.5, 16: 0.6, 17: 0.7, 18: 0.8, 19: 0.9}
	return float(opening.get(level, 1.0))

func _roll_bonus(t: Dictionary, config: Dictionary, spread: float) -> Dictionary:
	var archetype := String(t.get("archetype", ""))
	var profiles: Dictionary = database.get("weights", {})
	var group_weights: Dictionary = profiles.get(archetype, {})
	var definitions: Dictionary = database.get("groups", {})
	var parameters: Dictionary = database.get("parameters", {})
	var candidates: Array = []
	var weight_sum := 0.0
	var lvl := int(t.get("level", 1))
	for group in group_weights:
		var group_id := String(group)
		var eligible := _eligible_pars(group_id, definitions.get(group_id, []), t, parameters, lvl)
		if eligible.is_empty():
			continue
		var weight := maxf(0.0, float(group_weights[group]))
		if group_id == "GRP011":
			weight *= clampf(float(config.get("crit_weight", 1.0)), 0.0, 10.0)
		if weight <= 0.0:
			continue
		weight_sum += weight
		candidates.append({"id": group_id, "pars": eligible, "cutoff": weight_sum})
	if candidates.is_empty():
		return {}
	var picked: Dictionary = candidates.back()
	var n := rng.randf() * weight_sum
	for c in candidates:
		if n < float(c["cutoff"]):
			picked = c
			break
	var par_options: Array = picked["pars"]
	var chosen := String(par_options[rng.randi_range(0, par_options.size() - 1)])
	var amount := _budget_value(t, chosen, parameters, config, spread)
	var values: Dictionary = {}
	var group_name := String(picked["id"])
	if group_name == "GRP016":
		for zone in t.get("armour", {}):
			values[zone] = amount
	elif group_name == "GRP017":
		# One physical damage type across every zone protected by this item.
		var type_offset := (int(chosen.trim_prefix("PAR")) - 105) % 4
		for zone in t.get("armour", {}):
			var zone_index := ZONES.find(String(zone))
			if zone_index >= 0:
				values["PAR%03d" % (105 + zone_index * 4 + type_offset)] = amount
	else:
		values[chosen] = amount
	return {"group": group_name, "values": values}

func _eligible_pars(group_id: String, keys: Array, t: Dictionary, parameters: Dictionary, level: int) -> Array:
	var eligible: Array = []
	var covered: Dictionary = t.get("armour", {})
	if (group_id == "GRP016" or group_id == "GRP017") and covered.is_empty():
		return eligible
	for par in keys:
		var key := String(par)
		var info: Dictionary = parameters.get(key, {})
		if info.is_empty() or int(info.get("minimum", 999)) > level or float(info.get("cap", 0)) <= 0.0:
			continue
		eligible.append(key)
	return eligible

func _budget_value(t: Dictionary, target: String, parameters: Dictionary, config: Dictionary, spread: float) -> int:
	var examples: Dictionary = t.get("green_reference", {})
	if examples.is_empty():
		examples = t.get("blue_reference", {})
	var normalized := 0.004
	for key in examples:
		var info: Dictionary = parameters.get(String(key), {})
		var cap := float(info.get("cap", 0))
		if cap > 0.0:
			normalized = float(examples[key]) / cap
			break
	var target_info: Dictionary = parameters.get(target, {})
	var maximum := float(target_info.get("cap", 1000))
	var tuned := normalized * maximum * clampf(float(config.get("par_value_scale", 1.0)), 0.1, 5.0)
	return maxi(1, int(floor(tuned * rng.randf_range(1.0 - spread, 1.0 + spread) + 0.5)))
