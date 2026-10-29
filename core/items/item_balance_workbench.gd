class_name ItemBalanceWorkbench
extends RefCounted

## Independent v1 laboratory. Generates item forms from local formulas, not Project 25.
## The immutable BoA PAR registry is used only for valid IDs and names.
## Does not modify player saves, ItemRepository or the live combat RatingMatrix.
const QUALITY := ["white", "green", "blue", "purple"]
const RARITY_LEVEL := {"white": 1, "green": 10, "blue": 25, "purple": 40}
const ZONES := ["PAR100", "PAR101", "PAR102", "PAR103", "PAR104"]
const SHAPE := [0.90, 1.00, 1.08, 1.16]
const WEAPONS := [
	{"name":"Меч 1H · Физ", "slot":"MH", "dmg":0.92, "req":["PAR001","PAR003"], "kind":"weapon"},
	{"name":"Меч 2H · Физ", "slot":"2H", "dmg":1.14, "req":["PAR001","PAR006"], "kind":"weapon"},
	{"name":"Кинжал MH/OH · Физ", "slot":"MH/OH", "dmg":0.68, "req":["PAR002","PAR003"], "kind":"weapon"},
	{"name":"Топор 1H · Физ", "slot":"MH", "dmg":1.02, "req":["PAR001","PAR006"], "kind":"weapon"},
	{"name":"Топор 2H · Физ", "slot":"2H", "dmg":1.18, "req":["PAR001","PAR006"], "kind":"weapon"},
	{"name":"Молот 1H · Физ", "slot":"MH", "dmg":1.08, "req":["PAR001","PAR006"], "kind":"weapon"},
	{"name":"Молот 2H · Физ", "slot":"2H", "dmg":1.23, "req":["PAR001","PAR006"], "kind":"weapon"},
	{"name":"Копьё 2H · Физ", "slot":"2H", "dmg":1.07, "req":["PAR002","PAR003"], "kind":"weapon"},
	{"name":"Посох 2H · Маг", "slot":"2H", "dmg":0.75, "req":["PAR004","PAR005"], "kind":"weapon"},
	{"name":"Магический OH", "slot":"OH", "dmg":0.0, "req":["PAR004","PAR005"], "kind":"focus"},
	{"name":"Щит", "slot":"OH", "dmg":0.0, "req":["PAR001","PAR006"], "kind":"shield"}
]
const PIECES := [
	{"name":"Шлем", "zones":[1.0,0.0,0.0,0.0,0.0]},
	{"name":"Плечи", "zones":[0.25,0.55,0.45,0.0,0.0]},
	{"name":"Нагрудник", "zones":[0.0,1.0,0.0,0.35,0.0]},
	{"name":"Наручи", "zones":[0.0,0.0,1.0,0.0,0.0]},
	{"name":"Перчатки", "zones":[0.0,0.0,0.75,0.0,0.0]},
	{"name":"Пояс", "zones":[0.0,0.0,0.0,1.0,0.0]},
	{"name":"Штаны", "zones":[0.0,0.0,0.0,0.65,0.85]},
	{"name":"Ботинки", "zones":[0.0,0.0,0.0,0.0,1.0]}
]
const CLASSES := [
	{"name":"Тяжёлая", "defense":1.00, "req":["PAR001","PAR006"]},
	{"name":"Средняя", "defense":0.53, "req":["PAR002","PAR006"]},
	{"name":"Лёгкая", "defense":0.22, "req":["PAR002","PAR003"]}
]
var registry: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _init() -> void:
	registry = ParCalculationService.registry()

func parameter_ids() -> Array:
	var ids: Array = registry.keys()
	ids.sort()
	return ids

func par_name(par: String) -> String:
	return String(registry.get(par, {}).get("name", par))

func _definitions() -> Array:
	var result: Array = []
	for weapon in WEAPONS:
		result.append(weapon)
	for body in PIECES:
		for gear_class in CLASSES:
			result.append({"name":String(body["name"]) + " / " + String(gear_class["name"]),
				"slot":body["name"],"kind":"armor","zones":body["zones"],
				"defense":gear_class["defense"],"req":gear_class["req"],"dmg":0.0})
	result.append({"name":"Кольцо", "slot":"Кольцо", "kind":"jewelry", "dmg":0.0,"req":["PAR003","PAR006"]})
	result.append({"name":"Амулет", "slot":"Амулет", "kind":"jewelry", "dmg":0.0,"req":["PAR003","PAR005"]})
	return result

func available_types() -> Array:
	var names: Array = []
	for form in _definitions():
		names.append(String(form["name"]))
	names.sort()
	return names

func default_archetype() -> Dictionary:
	return {"PAR002":20.0, "PAR003":20.0, "PAR031":20.0, "PAR033":25.0, "PAR035":15.0}

func default_par_settings(par: String) -> Dictionary:
	var number := int(par.trim_prefix("PAR"))
	var maximum := 3750.0
	var first_level := 15
	if number >= 1 and number <= 6:
		maximum = 120.0
		first_level = 1
	elif number == 10 or number == 11:
		maximum = 15000.0
		first_level = 1
	elif number >= 12 and number <= 21:
		maximum = 500.0
		first_level = 30
	elif number >= 100 and number <= 124:
		first_level = 30
	elif number >= 125:
		first_level = 30
	if [14,19,50,51,57,73,74,76,212].has(number):
		maximum = 0.0
		first_level = 999
	return {"max":maximum, "min_level":first_level,
		"rating100_lv1":10.0, "rating100_lv100":1.0,
		"growth":1.0, "value_scale":1.0,
		"diminish_start_pct":0.0, "diminish_width_pct":15.0}

func parameter_settings(par: String, overrides: Dictionary) -> Dictionary:
	var settings := default_par_settings(par)
	var extra: Dictionary = overrides.get(par, {})
	for key in extra:
		settings[key] = extra[key]
	return settings

func is_percentage(par: String) -> bool:
	var n := int(par.trim_prefix("PAR"))
	return (n >= 30 and n <= 35) or (n >= 53 and n <= 56) or (n >= 71 and n <= 75) or (n >= 100 and n <= 135) or (n >= 151 and n <= 157) or (n >= 164 and n <= 170) or (n >= 190 and n <= 196)

## Diminishing is OFF by default. This pure conversion is for experimentation only.
func percentage(par: String, rating: float, level: int, overrides: Dictionary) -> float:
	if not is_percentage(par):
		return NAN
	var p := parameter_settings(par, overrides)
	var ratio := float(clampi(level,1,100)-1) / 99.0
	var raw := rating / 100.0 * lerpf(float(p["rating100_lv1"]), float(p["rating100_lv100"]), ratio)
	var start := float(p["diminish_start_pct"])
	if start <= 0.0 or raw <= start:
		return raw
	var width := maxf(0.1,float(p["diminish_width_pct"]))
	var excess := raw - start
	return start + excess / (1.0 + excess / width)

## Important when using diminishing: equipment's percentage is a marginal increase,
## not percentage(equipment) added separately to percentage(primary stats).
func equipment_contribution(par: String, base_rating: float, gear_rating: float, level: int, overrides: Dictionary) -> float:
	return percentage(par,base_rating+gear_rating,level,overrides) - percentage(par,base_rating,level,overrides)

func required_rating(par: String, desired_percent: float, level: int, overrides: Dictionary) -> float:
	if not is_percentage(par):
		return NAN
	# Use raw Matrix slope so a diminishing configuration does not hide the required
	# rating. Callers can compare achieved marginal effect separately.
	var p := parameter_settings(par,overrides)
	var k := lerpf(float(p["rating100_lv1"]),float(p["rating100_lv100"]),float(level-1)/99.0)
	return 100.0 * desired_percent / maxf(0.00001,k)

func generate(config: Dictionary) -> Dictionary:
	var low := clampi(int(config.get("min_level",10)),1,100)
	var high := clampi(int(config.get("max_level",30)),low,100)
	var selected: Array = config.get("types",[])
	if selected.is_empty():
		return {"ok":false,"reason":"Выбери хотя бы один тип предметов","rows":[]}
	var types: Array = []
	for definition in _definitions():
		if selected.has(definition["name"]):
			types.append(definition)
	if types.is_empty():
		return {"ok":false,"reason":"Выбранные типы отсутствуют","rows":[]}
	var choices: Array = []
	for definition in types:
		for level in range(low,high+1):
			if not _kind_allowed(definition,level):
				continue
			for form in range(SHAPE.size()):
				choices.append({"type":definition,"level":level,"form":form})
	if choices.is_empty():
		return {"ok":false,"reason":"Нет доступных типов на этих уровнях","rows":[]}
	rng.seed = maxi(1,int(config.get("seed",20261029)))
	for i in range(choices.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var tmp: Variant = choices[i]
		choices[i] = choices[j]
		choices[j] = tmp
	var want := clampi(int(config.get("count",100)),1,500)
	var unique := bool(config.get("unique_templates",true))
	var total := mini(want,choices.size()) if unique else want
	var rows: Array = []
	for i in range(total):
		var choice: Dictionary = choices[i] if unique else choices[rng.randi_range(0,choices.size()-1)]
		var definition: Dictionary = choice["type"]
		var level := int(choice["level"])
		var form := int(choice["form"])
		var variants: Array = []
		if unique:
			for q in QUALITY:
				if _rarity_allowed(definition,level,q):
					variants.append(_variant(definition,level,form,q,config))
		else:
			var selected_quality := _choose_quality(definition,level,config)
			if not selected_quality.is_empty():
				variants.append(_variant(definition,level,form,selected_quality,config))
		if variants.is_empty():
			continue
		rows.append({"id":"BOA-F%05d"%(i+1),"source_template":"FORM%02d"%(form+1),
			"item_type":String(definition["name"]),"slot":String(definition["slot"]),
			"level":level,"variants":variants})
	return {"ok":true,"rows":rows,"returned":rows.size(),
		"requested":want,"available_unique":choices.size(),"unique_templates":unique}

func _kind_allowed(definition: Dictionary,level: int) -> bool:
	var slot := String(definition["slot"])
	return not ((slot == "Кольцо" and level < 15) or (slot == "Амулет" and level < 25))

func _rarity_allowed(definition: Dictionary,level: int,q: String) -> bool:
	if level < int(RARITY_LEVEL[q]) or not _kind_allowed(definition,level):
		return false
	var slot := String(definition["slot"])
	if q == "white" and (slot == "Кольцо" or slot == "Амулет" or String(definition["kind"]) == "focus"):
		return false
	return true

func _choose_quality(definition: Dictionary,level: int,config: Dictionary) -> String:
	var weights: Dictionary = config.get("rarities",{"white":1.0,"green":1.0,"blue":1.0,"purple":1.0})
	var options: Array = []
	var total := 0.0
	for q in QUALITY:
		if not _rarity_allowed(definition,level,q):
			continue
		var w := maxf(0.0,float(weights.get(q,0)))
		if w <= 0.0:
			continue
		total += w
		options.append({"q":q,"cutoff":total})
	if options.is_empty():
		return ""
	var draw := rng.randf()*total
	for entry in options:
		if draw < float(entry["cutoff"]):
			return String(entry["q"])
	return String(options.back()["q"])

func _variant(definition: Dictionary,level: int,form: int,q: String,config: Dictionary) -> Dictionary:
	var kind := String(definition["kind"])
	var shape := float(SHAPE[form])
	var damage: Array = []
	var armour: Dictionary = {}
	if kind == "weapon":
		var midpoint := maxf(2.0,float(level+2)*float(definition["dmg"])*shape*float(config.get("damage_scale",1.0)))
		damage = [maxi(1,int(floor(midpoint*0.88+0.5))),maxi(1,int(floor(midpoint*1.12+0.5)))]
	elif kind == "armor":
		var shares: Array = definition["zones"]
		for i in range(ZONES.size()):
			var share := float(shares[i])
			if share > 0.0:
				var amount := float(level+2)*float(definition["defense"])*share*shape*float(config.get("armour_scale",1.0))
				armour[ZONES[i]] = maxi(1,int(floor(amount+0.5)))
	elif kind == "shield":
		for zone in ZONES:
			armour[zone] = maxi(1,int(floor(float(level+2)*0.36*shape*float(config.get("armour_scale",1.0))+0.5)))
	var modifiers: Dictionary = {}
	var rolled: Array = []
	var spread := clampf(float(config.get("spread",5.0)),0.0,20.0)/100.0
	for i in range(QUALITY.find(q)):
		var bonus := _roll_par(definition,level,config,spread)
		if bonus.is_empty():
			continue
		rolled.append(bonus)
		for key in bonus:
			modifiers[key] = int(modifiers.get(key,0)) + int(bonus[key])
	var req: Dictionary = {}
	var requirement_ids: Array = definition["req"]
	var pct := float(config.get("medium_requirement",40.0)) if kind == "focus" or kind == "jewelry" else float(config.get("high_requirement",70.0))
	var needed := float(18+2*(level-1))*pct/100.0/float(maxi(1,requirement_ids.size()))*_requirement_open(level)
	for par in requirement_ids:
		req[par] = maxi(0,int(floor(needed+0.5)))
	return {"quality":q,"damage":damage,"armour":armour,"fixed_par":{},
		"rolls":rolled,"total_par":modifiers,"requirements":req}

func _requirement_open(level: int) -> float:
	if level <= 10:
		return 0.0
	if level >= 20:
		return 1.0
	return float({11:0.25,12:0.3125,13:0.375,14:0.4375,15:0.5,
		16:0.6,17:0.7,18:0.8,19:0.9}.get(level,1.0))

func _roll_par(definition: Dictionary,level: int,config: Dictionary,spread: float) -> Dictionary:
	var weights: Dictionary = config.get("par_weights",{})
	var overrides: Dictionary = config.get("par_settings",{})
	var choices: Array = []
	var total := 0.0
	var keys: Array = weights.keys()
	keys.sort()
	for raw in keys:
		var key := String(raw)
		if not registry.has(key) or not _compatible(key,definition):
			continue
		var p := parameter_settings(key,overrides)
		var w := maxf(0.0,float(weights[key]))
		if w <= 0.0 or float(p["max"]) <= 0.0 or level < int(p["min_level"]):
			continue
		total += w
		choices.append({"key":key,"cutoff":total})
	if choices.is_empty():
		return {}
	var draw := rng.randf()*total
	var selected := String(choices.back()["key"])
	for entry in choices:
		if draw < float(entry["cutoff"]):
			selected = String(entry["key"])
			break
	var p := parameter_settings(selected,overrides)
	if float(p["value_scale"]) <= 0.0 or float(config.get("bonus_scale",1.0)) <= 0.0:
		return {}
	# Standalone FORMULA. At Lv25, crit roll with default max=3750 is ~41 rating.
	# Six focused crit affixes => ~246 rating (before opponent/DR).
	var lv_ratio := pow(float(level)/25.0,clampf(float(p["growth"]),0.1,5.0))
	var raw := float(p["max"])*0.011*lv_ratio*float(p["value_scale"])*float(config.get("bonus_scale",1.0))
	var amount := maxi(1,int(floor(minf(float(p["max"]),raw*rng.randf_range(1.0-spread,1.0+spread))+0.5)))
	var result: Dictionary = {}
	var num := int(selected.trim_prefix("PAR"))
	if num >= 100 and num <= 104:
		for zone in _zones_for(definition):
			result[zone] = amount
	elif num >= 105 and num <= 124:
		var type_index := (num-105)%4
		for zone in _zones_for(definition):
			var index := ZONES.find(String(zone))
			result["PAR%03d"%(105+index*4+type_index)] = amount
	else:
		result[selected] = amount
	return result

func _zones_for(definition: Dictionary) -> Array:
	if String(definition["kind"]) == "shield":
		return ZONES.duplicate()
	var result: Array = []
	if String(definition["kind"]) != "armor":
		return result
	var shares: Array = definition["zones"]
	for i in range(ZONES.size()):
		if float(shares[i]) > 0.0:
			result.append(ZONES[i])
	return result

func _compatible(par: String,definition: Dictionary) -> bool:
	var n := int(par.trim_prefix("PAR"))
	if n >= 100 and n <= 124:
		return String(definition["kind"]) == "armor" or String(definition["kind"]) == "shield"
	return not [14,19,20,21,50,51,57,73,74,76,212].has(n)
