class_name ItemTemplateGeneratorV12
extends RefCounted

## Isolated Core-Balance v1.2 laboratory: NEVER writes ItemRepository or game saves.
## All archetype probabilities are loaded from the approved Project 25 snapshot.
const RULE_PATH := "res://data/items/item_generator_v12_rules.json"
const PROFILE_PATH := "user://boa_template_generator_v12_profile.json"
const PAR_LABELS := {
	"PAR010":"Максимальное HP", "PAR011":"Максимальная мана",
	"PAR031":"Уклонение", "PAR032":"Антиуклонение", "PAR033":"Крит",
	"PAR034":"Антикрит", "PAR035":"Сила крита", "PAR075":"Контрудар",
	"PAR072":"Пробитие щита", "PAR126":"Пробитие брони",
	"PAR135":"Снижение урона", "PAR150":"Сила заклинаний",
	"PAR190":"Магическое сопротивление", "PAR013":"Регенерация маны",
	"PAR164":"Общее пробитие магии", "V12_ATTACK_POWER":"Сила атаки (v1.2)"
}
const ARMOUR_ZONES := {
	# Approved Project 25 matrix V2: each zone sums to 80% without a shield.
	"Шлем":{"PAR100":0.60},
	"Плечи":{"PAR100":0.20,"PAR101":0.30,"PAR102":0.10},
	"Нагрудник":{"PAR101":0.50,"PAR103":0.20},
	"Перчатки":{"PAR102":0.40},
	"Наручи":{"PAR102":0.30},
	"Пояс":{"PAR103":0.25},
	"Штаны":{"PAR103":0.35,"PAR104":0.30},
	"Ботинки":{"PAR104":0.50},
	"Плащ":{}
}
const WEAPON_FACTOR := {"sword":0.90,"dagger":0.65,"axe":1.0,"hammer":0.85,"spear":1.0} # Spear coefficient is provisional, until separately balanced.
const DAMAGE_SPREAD := {"sword":0.15,"dagger":0.05,"axe":0.30,"hammer":0.25,"spear":0.15}
var rules: Dictionary = {}
var par_registry: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _init() -> void:
	par_registry = ParCalculationService.registry()
	if not FileAccess.file_exists(RULE_PATH):
		push_error("v1.2 rule file is missing")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULE_PATH))
	if parsed is Dictionary:
		rules = parsed

func ready_for_generation() -> bool:
	if rules.is_empty():
		return false
	for entry in archetypes():
		var weights: Dictionary = entry.get("weights", {})
		var total := 0.0
		for key in weights:
			total += float(weights[key])
		if absf(total - 100.0) > 0.001:
			return false
	return archetypes().size() == 35

func archetypes() -> Array:
	var result: Array = []
	result.append_array(rules.get("weapon_archetypes", []))
	result.append_array(rules.get("armor_archetypes", []))
	return result

func schools() -> Array:
	return rules.get("schools", [])

func save_profile(config: Dictionary) -> bool:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version":"v1.2","config":config}))
	file.close()
	return true

func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if v is Dictionary and String(v.get("version", "")) == "v1.2":
		var data: Variant = v.get("config", {})
		if data is Dictionary:
			return data
	return {}

func generate(config: Dictionary) -> Dictionary:
	if not ready_for_generation():
		return {"ok":false,"reason":"Правила v1.2 повреждены или не загружены","rows":[]}
	var minimum := clampi(int(config.get("min_level", 10)), 1, 100)
	var maximum := clampi(int(config.get("max_level", 30)), minimum, 100)
	var wanted := clampi(int(config.get("count", 100)), 1, 500)
	var chosen_ids: Array = config.get("archetypes", [])
	var chosen_quality := String(config.get("quality", "any"))
	var chosen_school := String(config.get("school", "any"))
	var chosen_slot := String(config.get("armor_slot", "any"))
	rng.seed = maxi(1, int(config.get("seed", 20261101)))
	var candidates: Array = []
	for spec in archetypes():
		var entry: Dictionary = spec
		if not chosen_ids.is_empty() and not chosen_ids.has(String(entry["id"])):
			continue
		var slots: Array = [String(entry.get("slot","MH"))]
		if String(entry["kind"]) == "armor":
			slots = rules.get("armor_slots", [])
		var school_options: Array = [{"id":"","name":"","pen":""}]
		if bool(entry.get("school_required", false)):
			school_options = schools()
		for slot in slots:
			if String(entry["kind"]) == "armor" and chosen_slot != "any" and chosen_slot != String(slot):
				continue
			for school in school_options:
				if chosen_school != "any" and bool(entry.get("school_required",false)) and String(school["id"]) != chosen_school:
					continue
				for level in range(minimum, maximum + 1):
					candidates.append({"spec":entry,"slot":String(slot),"school":school,"level":level})
	if candidates.is_empty():
		return {"ok":false,"reason":"Нет подходящих архетипов и уровней","rows":[]}
	var rows: Array = []
	var qualities: Dictionary = rules.get("rarities", {})
	for i in range(wanted):
		var choice: Dictionary = candidates[rng.randi_range(0, candidates.size()-1)]
		var level := int(choice["level"])
		var allowed: Array = []
		for q in ["white","green","blue","purple"]:
			if level >= int(Dictionary(qualities.get(q,{})).get("start", 1000)) and (chosen_quality == "any" or chosen_quality == q):
				allowed.append(q)
		if allowed.is_empty():
			continue
		var quality := String(allowed[rng.randi_range(0, allowed.size()-1)])
		var variant := _variant(choice, quality)
		var entry: Dictionary = choice["spec"]
		rows.append({
			"id":"V12-%05d" % (rows.size()+1),
			"archetype_id":String(entry["id"]),
			"archetype_name":String(entry["name"]),
			"kind":String(entry["kind"]), "slot":String(choice["slot"]),
			"school":String(Dictionary(choice["school"]).get("name","")),
			"level":level, "quality":quality, "variant":variant
		})
	if rows.is_empty():
		return {"ok":false,"reason":"Выбранная редкость недоступна на этих уровнях","rows":[]}
	return {"ok":true,"rows":rows,"requested":wanted,"generated":rows.size(),"candidate_count":candidates.size()}

func _variant(choice: Dictionary, quality: String) -> Dictionary:
	var spec: Dictionary = choice["spec"]
	var level := int(choice["level"])
	var slot := String(choice["slot"])
	var quality_def: Dictionary = rules["rarities"][quality]
	var quality_factor := float(quality_def["factor"])
	var armour := {}
	var damage: Array = []
	var offhand_damage: Array = []
	if String(spec["kind"]) == "weapon":
		damage = _weapon_damage(spec, level, slot)
		if slot == "MH/OH":
			offhand_damage = _weapon_damage(spec, level, "OH")
	else:
		armour = _base_armour(spec,slot,level,quality_factor)
	# Template CORE lines belong to the white foundation, not rarity rolls.
	# Lv20 blue+ enables the first CORE; Lv30 all qualities; Lv60 a second CORE.
	var bonus_lines := int(quality_def["bonus"])
	var core_lines := 0
	if level >= 30 or (level >= 20 and ["blue","purple"].has(quality)):
		core_lines = 1
	if level >= 60:
		core_lines = 2
	var total_lines := maxi(1,bonus_lines + core_lines)
	var modifiers := {}
	var rolls: Array = []
	var core_rolls: Array = []
	var weights: Dictionary = spec["weights"]
	var requirements := _requirements(spec,level)
	var core_used := {}
	for i in range(core_lines):
		var logical := _roll_weight(weights,core_used)
		if logical.is_empty():
			break
		core_used[logical] = true
		var par := _resolve_par(logical,choice)
		if logical == "phys_res":
			par = ["PAR127","PAR128","PAR129","PAR130"][rng.randi_range(0,3)]
		var rating := _affix_amount(logical,level,slot,quality_factor,total_lines)
		core_rolls.append({"par":par,"name":par_label(par),"rating":rating,"category":logical,"source":"CORE"})
		modifiers[par] = float(modifiers.get(par,0.0)) + rating
	# Each quality bonus is an independent weighted roll. Duplicates are allowed.
	for i in range(bonus_lines):
		var logical := _roll_weight(weights,{})
		if logical.is_empty():
			break
		var par := _resolve_par(logical,choice)
		if logical == "phys_res":
			par = ["PAR127","PAR128","PAR129","PAR130"][rng.randi_range(0,3)]
		var rating := _affix_amount(logical,level,slot,quality_factor,total_lines)
		rolls.append({"par":par,"name":par_label(par),"rating":rating,"category":logical,"source":"RARITY"})
		modifiers[par] = float(modifiers.get(par,0.0)) + rating
	# Priority main-stat roll occupies a NORMAL affix slot, not an extra one.
	if rolls.size() > 0 and ["Перчатки","Наручи","Пояс"].has(slot) and level >= 10:
		var chance := lerpf(0.40,0.10,float(level-10)/90.0)
		if rng.randf() < chance:
			var req_pars: Array = requirements.keys()
			var primary := String(req_pars[rng.randi_range(0,req_pars.size()-1)])
			var replaced: Dictionary = rolls[rolls.size()-1]
			var old_par := String(replaced["par"])
			modifiers.erase(old_par)
			var added := maxi(1,roundi((18.0 + 2.0*float(level-1))*0.05*quality_factor))
			rolls[rolls.size()-1] = {"par":primary,"name":par_label(primary),"rating":added,"category":"primary"}
			modifiers[primary] = added
	return {"damage":damage,"offhand_damage":offhand_damage,"armour":armour,"core_rolls":core_rolls,"rolls":rolls,"total_par":modifiers,
		"requirements":requirements,"quality_factor":quality_factor}

func _weapon_damage(spec: Dictionary, level: int, slot: String) -> Array:
	var family := String(spec.get("family","staff"))
	if family == "staff":
		# Staff physical base damage has not been approved yet.
		return []
	var base := lerpf(2.8,30.0,float(level-1)/29.0) if level <= 30 else lerpf(30.0,104.2,float(level-30)/70.0)
	var avg := base*float(WEAPON_FACTOR.get(family,1.0))
	if slot == "2H":
		avg *= 1.65
	elif slot == "OH":
		avg *= 0.80
	var spread := float(DAMAGE_SPREAD.get(family,0.15))
	return [maxi(1,roundi(avg*(1.0-spread))),maxi(1,roundi(avg*(1.0+spread)))]

func _base_armour(spec: Dictionary,slot: String,level: int,quality_factor: float) -> Dictionary:
	var material := String(spec.get("material","cloth"))
	var standard := float({"metal":80.0,"leather":50.0,"cloth":20.0}.get(material,20.0))
	var ratio := String(spec.get("profile","50/50")).split("/")
	var target_def := float(ratio[0])
	var ref_def := float({"metal":80.0,"leather":50.0,"cloth":20.0}.get(material,20.0))
	var age := 1.0 + 3.0*float(level-1)/99.0
	var outcome := {}
	var zones: Dictionary = ARMOUR_ZONES.get(slot,{})
	for par in zones:
		outcome[par] = maxi(1,roundi(standard*target_def/ref_def*float(zones[par])*age*quality_factor))
	return outcome

func _requirements(spec: Dictionary,level: int) -> Dictionary:
	var ids: Array = spec.get("requirements",[])
	if ids.is_empty():
		match String(spec.get("family","")):
			"dagger": ids = ["PAR002","PAR006"]
			"staff": ids = ["PAR004","PAR005"]
			"spear": ids = ["PAR002","PAR003"]
			_: ids = ["PAR001","PAR003"]
	var requirement_pool := (18.0 + 2.0*float(level-1))*0.60
	var result := {}
	for p in ids:
		result[String(p)] = maxi(1,roundi(requirement_pool / float(ids.size())))
	return result

func _roll_weight(weights: Dictionary,used: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		if not used.has(key):
			total += maxf(0.0,float(weights[key]))
	if total <= 0.0:
		return ""
	var draw := rng.randf_range(0.0,total)
	for key in weights:
		if used.has(key):
			continue
		draw -= maxf(0.0,float(weights[key]))
		if draw <= 0.0:
			return String(key)
	return String(weights.keys().back())

func _resolve_par(logical: String,choice: Dictionary) -> String:
	var entry: Dictionary = choice["spec"]
	if logical == "magic_pen" and bool(entry.get("school_required",false)):
		return String(Dictionary(choice["school"]).get("pen","PAR164"))
	return String(Dictionary(rules.get("stat_par",{})).get(logical,""))

func _affix_amount(logical: String,level: int,slot: String,quality: float,lines: int) -> float:
	var budget := float(Dictionary(rules.get("slot_budgets",{})).get(slot,7.5))/7.5
	var l := float(level)/100.0
	var amount := 100.0*l*budget*quality/float(maxi(1,lines))
	if logical == "hp":
		amount *= 1.0119
	elif logical == "mana":
		amount *= 0.506
	elif logical == "spell":
		amount *= 5.0
	elif logical == "attack":
		amount *= 0.20
	elif logical == "mana_regen":
		amount *= 0.02
	return float(maxi(1,roundi(amount*rng.randf_range(0.95,1.05))))

func par_label(par: String) -> String:
	if PAR_LABELS.has(par):
		return String(PAR_LABELS[par])
	return String(Dictionary(par_registry.get(par,{})).get("name",par))
