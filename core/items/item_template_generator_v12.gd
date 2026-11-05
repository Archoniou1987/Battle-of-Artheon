class_name ItemTemplateGeneratorV12
extends RefCounted

## Isolated Core-Balance v1.2 laboratory: NEVER writes ItemRepository or game saves.
## All archetype probabilities are loaded from the approved Project 25 snapshot.
const RULE_PATH := "res://data/items/item_generator_v12_rules.json"
const PAR_REGISTRY_PATH := "res://data/parameters/par_registry.json"
const PROFILE_PATH := "user://boa_template_generator_v12_profile.json"
const PAR_LABELS := {
	"PAR010":"Максимальное HP", "PAR011":"Максимальная мана",
	"PAR031":"Уклонение", "PAR032":"Антиуклонение", "PAR033":"Крит",
	"PAR034":"Антикрит", "PAR035":"Сила крита",
	"PAR072":"Пробитие щита", "PAR126":"Пробитие брони",
	"PAR135":"Снижение урона", "PAR150":"Сила заклинаний",
	"PAR190":"Магическое сопротивление", "PAR013":"Регенерация маны вне боя (ед./10 сек)",
	"PAR015":"Регенерация маны в бою (за раунд)",
	"PAR164":"Общее пробитие магии", "V12_ATTACK_POWER":"Сила атаки"
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
## Project 25 Core-Balance v1.2. DR acts on percentages after reductions.
const DR_RULES = CombatRatingCurves.DR_RULES

const ARMOUR_IDS := ["PAR100","PAR101","PAR102","PAR103","PAR104"]
## v1.2 K15:N15: only these budget directions are explicitly specified.
## This is diagnostic metadata, NOT a hidden item-value multiplier.
## Unknown categories stay "unclassified" until confirmed in the v1.2 tab.
const PAR_BUDGET_DIRECTIONS := {
	"hp":{"defence":1.0,"attack":0.0},
	"reduce":{"defence":1.0,"attack":0.0},
	"phys_res":{"defence":1.0,"attack":0.0},
	"magic_res":{"defence":1.0,"attack":0.0},
	"dodge":{"defence":1.0,"attack":0.0},
	"anticrit":{"defence":1.0,"attack":0.0},
	"anti_dodge":{"defence":0.0,"attack":1.0},
	"crit":{"defence":0.0,"attack":1.0},
	"crit_damage":{"defence":0.0,"attack":1.0},
	"attack":{"defence":0.0,"attack":1.0},
	"spell":{"defence":0.0,"attack":1.0},
	"armour_pen":{"defence":0.0,"attack":1.0},
	"shield_pen":{"defence":0.0,"attack":1.0},
	"magic_pen":{"defence":0.0,"attack":1.0}
}

## Apply the armour defence/attack profile as the final multiplier of
## each independent affix. No redistribution among unlocked PAR cells.
static func armour_par_multiplier(logical: String, profile: Dictionary) -> float:
	if profile.is_empty():
		return 1.0
	var direction := par_budget_direction(logical)
	if String(direction.get("status","")) != "V12_APPROVED":
		return 1.0
	return float(profile["defence_pct"])/100.0*float(direction["defence"]) + float(profile["attack_pct"])/100.0*float(direction["attack"])

static func par_budget_direction(logical: String) -> Dictionary:
	if not PAR_BUDGET_DIRECTIONS.has(logical):
		return {"status":"UNCLASSIFIED"}
	var fractions: Dictionary = PAR_BUDGET_DIRECTIONS[logical]
	return {"status":"V12_APPROVED","defence":fractions["defence"],"attack":fractions["attack"]}


## Exact Project 25 A13/B13 spreadsheet curve. Never apply to
## primary attributes, HP, Mana, regeneration or Spell Power.
static func diminishing(raw_pct: float, category: String) -> float:
	return CombatRatingCurves.diminishing(raw_pct,category)

## Lv1:20% / 100 rating; Lv100:4% / 100 rating.
static func rating_to_pct(rating: float, level: int) -> float:
	var pct_per_100 := lerpf(20.0,4.0,float(clampi(level,1,100)-1)/99.0)
	return maxf(0.0,rating)*pct_per_100/100.0

static func armour_raw_pct(armour_rating: float, level: int) -> float:
	return CombatRatingCurves.armour_raw_pct(armour_rating,level)

## Pure diagnostics: DR is a display calculation, not mutation of raw PAR.
func preview_effects(armour: Dictionary, bonus: Dictionary, level: int) -> Dictionary:
	var result := {"armour":{},"ratings":{}}
	for par in ARMOUR_IDS:
		var total := float(armour.get(par,0.0)) + float(bonus.get(par,0.0))
		if total > 0.0:
			var before := armour_raw_pct(total,level)
			result["armour"][par] = {"raw_pct":before,"after_dr_pct":diminishing(before,"armour")}
	for item in [{"par":"PAR031","type":"dodge"},{"par":"PAR033","type":"crit"}]:
		var par := String(item["par"])
		var amount := float(bonus.get(par,0.0))
		if amount > 0.0:
			var before := rating_to_pct(amount,level)
			result["ratings"][par] = {"raw_pct":before,"after_dr_pct":diminishing(before,String(item["type"]))}
	if float(bonus.get("PAR032",0.0)) > 0.0:
		result["ratings"]["PAR032"] = {"raw_pct":rating_to_pct(float(bonus["PAR032"]),level),"after_dr_pct":rating_to_pct(float(bonus["PAR032"]),level)}
	for item in [
		{"par":"PAR135","category":"reduce"},
		{"par":"PAR190","category":"magic_res"},
		{"par":"PAR164","category":""},
		{"par":"PAR126","category":""}
	]:
		var id := String(item["par"])
		var total_rating := float(bonus.get(id,0.0))
		if total_rating > 0.0:
			var raw := rating_to_pct(total_rating,level)
			result["ratings"][id] = {"raw_pct":raw,"after_dr_pct":diminishing(raw,String(item["category"]))}
	return result

var rules: Dictionary = {}
var par_registry: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _init() -> void:
	par_registry = _load_registry()
	if not FileAccess.file_exists(RULE_PATH):
		push_error("v1.2 rule file is missing")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULE_PATH))
	if parsed is Dictionary:
		rules = parsed

## Read the locked PAR catalogue as plain data; the item generator does not
## depend on ParCalculationService, RatingMatrix or Combat Engine.
func _load_registry() -> Dictionary:
	if not FileAccess.file_exists(PAR_REGISTRY_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAR_REGISTRY_PATH))
	if not parsed is Dictionary or not bool(parsed.get("locked",false)):
		return {}
	var result := {}
	for raw in parsed.get("parameters",[]):
		if raw is Dictionary:
			var entry: Dictionary = raw
			var id := String(entry.get("id",""))
			if id.begins_with("PAR"):
				result[id] = entry.duplicate(true)
	return result

func ready_for_generation() -> bool:
	if rules.is_empty() or par_registry.is_empty():
		return false
	for entry in archetypes():
		if ["armor","jewelry"].has(String(entry.get("kind",""))) and armour_budget_split(entry).is_empty():
			return false
		var weights: Dictionary = entry.get("weights", {})
		var total := 0.0
		for key in weights:
			total += float(weights[key])
		if absf(total - 100.0) > 0.001:
			return false
	return archetypes().size() == 45

func archetypes() -> Array:
	var result: Array = []
	result.append_array(rules.get("weapon_archetypes", []))
	result.append_array(rules.get("armor_archetypes", []))
	result.append_array(rules.get("jewelry_archetypes", []))
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
	var grouped := bool(config.get("group_qualities", false))
	var chosen_ids: Array = config.get("archetypes", [])
	var chosen_quality := String(config.get("quality", "any"))
	var chosen_school := String(config.get("school", "any"))
	var chosen_slot := String(config.get("armor_slot", "any"))
	var chosen_hand := String(config.get("weapon_hand", "any"))
	var exclude_oh := bool(config.get("exclude_oh", false))
	if not ["any","MH","OH","2H"].has(chosen_hand):
		return {"ok":false,"reason":"Неизвестный слот руки оружия","rows":[]}
	rng.seed = maxi(1, int(config.get("seed", 20261101)))
	var candidates: Array = []
	for spec in archetypes():
		var entry: Dictionary = spec
		if not chosen_ids.is_empty() and not chosen_ids.has(String(entry["id"])):
			continue
		if chosen_hand != "any" and String(entry["kind"]) != "weapon":
			continue
		var slots: Array = entry.get("slots",[String(entry.get("slot","MH"))])
		if String(entry["kind"]) == "armor":
			slots = rules.get("armor_slots", [])
		elif String(entry.get("slot","")) == "MH/OH":
			# One template per archetype; equip position does not change rolls.
			slots = ["MH"]
		var school_options: Array = [{"id":"","name":"","pen":""}]
		if bool(entry.get("school_required", false)):
			school_options = schools()
		for slot in slots:
			if chosen_slot != "any" and (not ["armor","jewelry"].has(String(entry["kind"])) or chosen_slot != String(slot)):
				continue
			if String(entry["kind"]) == "weapon" and chosen_hand != "any":
				if chosen_hand == "OH" and (String(slot) != "MH" or not WeaponHandPolicy.DUAL_ARCHETYPES.has(String(entry["id"]))):
					continue
				if chosen_hand == "MH" and String(slot) != "MH":
					continue
				if chosen_hand == "2H" and String(slot) != "2H":
					continue
			if exclude_oh and String(slot) == "OH":
				continue
			if chosen_school != "any" and not bool(entry.get("school_required",false)):
				continue
			for school in school_options:
				if chosen_school != "any" and String(school["id"]) != chosen_school:
					continue
				for level in range(minimum, maximum + 1):
					var allowed: Array = []
					for quality in ["white","green","blue","purple"]:
						if level >= int(Dictionary(rules["rarities"][quality]).get("start",1000)) and (chosen_quality == "any" or chosen_quality == quality):
							allowed.append(quality)
					if not allowed.is_empty():
						candidates.append({"spec":entry,"slot":String(slot),"school":school,"level":level,"qualities":allowed})
	if candidates.is_empty():
		return {"ok":false,"reason":"Нет подходящих архетипов и уровней","rows":[]}
	var rows: Array = []
	for i in range(wanted):
		var choice: Dictionary = candidates[rng.randi_range(0,candidates.size()-1)]
		var level := int(choice["level"])
		var allowed: Array = choice["qualities"]
		var quality_order: Array = ["white","green","blue","purple"] if grouped else [String(allowed[rng.randi_range(0, allowed.size()-1)])]
		# Same roll sequence for each quality of one template. CORE and
		# baseline damage stay comparable; rarity adds its own PAR slots.
		var template_state := rng.state
		var next_state := template_state
		var group_id := "V12-%05d" % (i+1)
		for quality in quality_order:
			if not allowed.has(quality):
				continue
			if grouped:
				rng.state = template_state
			var variant := _variant(choice, String(quality))
			if grouped:
				next_state = rng.state
			var entry: Dictionary = choice["spec"]
			rows.append({
				"id":group_id + ("-" + String(quality) if grouped else ""),
				"group_id":group_id,
				"archetype_id":String(entry["id"]),
				"archetype_name":String(entry["name"]),
				"kind":String(entry["kind"]), "slot":String(choice["slot"]),
				"school":String(Dictionary(choice["school"]).get("name","")),
				"level":level, "quality":String(quality), "variant":variant
			})
		if grouped:
			rng.state = next_state
	if rows.is_empty():
		return {"ok":false,"reason":"Выбранная редкость недоступна на этих уровнях","rows":[]}
	return {"ok":true,"rows":rows,"requested":wanted,"generated":rows.size(),"group_count":wanted if grouped else rows.size(),"candidate_count":candidates.size()}

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
		damage = _weapon_damage(spec, level, slot, float(Dictionary(rules["damage_quality_factors"]).get(quality,1.0)))
		# One persistent base damage range; off-hand scaling occurs at equip.
	elif String(spec["kind"]) == "armor":
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
		var rating := _affix_amount(logical,level,slot,quality_factor,total_lines,armour_budget_split(spec))
		core_rolls.append({"par":par,"name":par_label(par),"rating":rating,"category":logical,"budget_direction":par_budget_direction(logical),"calibration":calibration_status(logical),"source":"CORE"})
		modifiers[par] = float(modifiers.get(par,0.0)) + rating
	# Each quality bonus is an independent weighted roll. Duplicates are allowed.
	for i in range(bonus_lines):
		var logical := _roll_weight(weights,{})
		if logical.is_empty():
			break
		var par := _resolve_par(logical,choice)
		if logical == "phys_res":
			par = ["PAR127","PAR128","PAR129","PAR130"][rng.randi_range(0,3)]
		var rating := _affix_amount(logical,level,slot,quality_factor,total_lines,armour_budget_split(spec))
		rolls.append({"par":par,"name":par_label(par),"rating":rating,"category":logical,"budget_direction":par_budget_direction(logical),"calibration":calibration_status(logical),"source":"RARITY"})
		modifiers[par] = float(modifiers.get(par,0.0)) + rating
	# Each eligible item reserves ONE rarity cell for a base attribute.
	# Current test includes gloves/bracers/belt/cloak. Future jewellery
	# joins the same 25%-of-base-stat full-gear budget, not another budget.
	if rolls.size() > 0 and ["Перчатки","Наручи","Пояс","Плащ","Кулон"].has(slot) and level >= 10:
		# Lv10 has no equip requirements; use the archetype's stat priorities
			# rather than attempting to choose from an empty requirements map.
		var req_pars: Array = requirements.keys()
		if req_pars.is_empty():
			req_pars = _requirement_attributes(spec)
		var primary := String(req_pars[rng.randi_range(0,req_pars.size()-1)])
		var replaced: Dictionary = rolls[rolls.size()-1]
		var old_par := String(replaced["par"])
		var remainder := float(modifiers.get(old_par,0.0)) - float(replaced["rating"])
		if remainder > 0.001:
			modifiers[old_par] = remainder
		else:
			modifiers.erase(old_par)
		var added := primary_stat_amount(level,slot,quality_factor)
		rolls[rolls.size()-1] = {"par":primary,"name":par_label(primary),"rating":added,"category":"primary","source":"RARITY","calibration":"V12_25PCT_BASE_STAT_BUDGET"}
		modifiers[primary] = float(modifiers.get(primary,0.0)) + added
	# Independently, 30% of eligible items replace one unlocked CORE
	# with a profile base stat. No additional slot is created.
	if core_rolls.size() > 0 and ["Перчатки","Наручи","Пояс","Плащ","Кулон"].has(slot) and rng.randf() < 0.30:
		var core_attributes: Array = requirements.keys()
		if core_attributes.is_empty():
			core_attributes = _requirement_attributes(spec)
		var core_primary := String(core_attributes[rng.randi_range(0,core_attributes.size()-1)])
		var old_core: Dictionary = core_rolls[core_rolls.size()-1]
		var previous_par := String(old_core["par"])
		var previous_remainder := float(modifiers.get(previous_par,0.0)) - float(old_core["rating"])
		if previous_remainder > 0.001:
			modifiers[previous_par] = previous_remainder
		else:
			modifiers.erase(previous_par)
		var core_added := primary_stat_amount(level,slot,quality_factor)
		core_rolls[core_rolls.size()-1] = {"par":core_primary,"name":par_label(core_primary),"rating":core_added,"category":"primary","source":"CORE","calibration":"V12_25PCT_BASE_STAT_BUDGET"}
		modifiers[core_primary] = float(modifiers.get(core_primary,0.0)) + core_added
	return {"damage":damage,"offhand_damage":offhand_damage,"armour":armour,
		"par_slot_budget_pct":float(Dictionary(rules["slot_budgets"]).get(slot,0.0)),
		"par_slot_budget_status":"V12_APPROVED",
		"budget_split":armour_budget_split(spec),"core_rolls":core_rolls,"rolls":rolls,"total_par":modifiers,
		"requirements":requirements,"quality_factor":quality_factor,
		"preview":preview_effects(armour,modifiers,level)}

func primary_stat_amount(level: int, slot: String, quality_factor: float) -> float:
	# Existing v1.2 reference: 25% of level-based attribute pool across
	# all planned eligible slots. A second CORE roll is an optional extra.
	var full_stat_pool := 18.0 + 2.0*float(level-1)
	var slot_weight := float(Dictionary(rules["slot_budgets"]).get(slot,3.8))
	return float(maxi(1,roundi(full_stat_pool*0.25*slot_weight/37.7*quality_factor)))

func attack_rating_to_pct(rating: float, level: int) -> float:
	return rating_to_pct(rating,level)

func _weapon_damage(spec: Dictionary, level: int, slot: String, damage_quality_factor: float = 1.0) -> Array:
	var family := String(spec.get("family","staff"))
	if family == "staff":
		# Staff physical base damage has not been approved yet.
		return []
	var base := lerpf(2.8,30.0,float(level-1)/29.0) if level <= 30 else lerpf(30.0,104.2,float(level-30)/70.0)
	var avg := base*float(WEAPON_FACTOR.get(family,1.0))*damage_quality_factor
	if slot == "2H":
		avg *= 1.65
	# No OH-only item variant or generation-time damage penalty.
	var spread := float(DAMAGE_SPREAD.get(family,0.15))
	return [maxi(1,roundi(avg*(1.0-spread))),maxi(1,roundi(avg*(1.0+spread)))]

## v1.2 armour profile is a DEFENCE / ATTACK budget split, NOT a
## source of extra PAR rolls. K3:N12 in "Генератор v1.2" gives reference
## helm Lv1: 80/20->48, 65/35->39, 50/50->30, 20/80->12.
static func armour_budget_split(spec: Dictionary) -> Dictionary:
	if not ["armor","jewelry"].has(String(spec.get("kind",""))):
		return {}
	var pieces := String(spec.get("profile","")).split("/")
	if pieces.size() != 2:
		return {}
	if not String(pieces[0]).is_valid_int() or not String(pieces[1]).is_valid_int():
		return {}
	var defence := int(pieces[0])
	var attack := int(pieces[1])
	if defence < 0 or attack < 0 or defence + attack != 100:
		return {}
	return {"defence_pct":defence,"attack_pct":attack}

func _base_armour(spec: Dictionary,slot: String,level: int,quality_factor: float) -> Dictionary:
	var allocation := armour_budget_split(spec)
	if allocation.is_empty():
		return {}
	var defence_budget := float(allocation["defence_pct"])
	var age := 1.0 + 3.0*float(level-1)/99.0
	var outcome := {}
	var zones: Dictionary = ARMOUR_ZONES.get(slot,{})
	for par in zones:
		# This is algebraically identical to the previous formula:
		# material_base * defence_budget/material_base * zone * age.
		outcome[par] = maxi(1,roundi(defence_budget*float(zones[par])*age*quality_factor))
	return outcome

## Project 25 requirement entry curve. Empty requirements on Lv1-10 are valid.
## No own item affix counts towards equipping; Combat Engine is not consulted.
static func requirement_factor(level: int) -> float:
	if level <= 10:
		return 0.0
	if level >= 20:
		return 1.0
	match level:
		11: return 0.25
		12: return 0.3125
		13: return 0.375
		14: return 0.4375
		15: return 0.5
		16: return 0.6
		17: return 0.7
		18: return 0.8
		19: return 0.9
	return 0.0

func _requirement_attributes(spec: Dictionary) -> Array:
	var ids: Array = spec.get("requirements",[])
	if not ids.is_empty():
		return ids
	match String(spec.get("family","")):
		"dagger": return ["PAR002","PAR006"]
		"staff": return ["PAR004","PAR005"]
		"spear": return ["PAR002","PAR003"]
		_: return ["PAR001","PAR003"]

func _requirements(spec: Dictionary,level: int) -> Dictionary:
	var factor := requirement_factor(level)
	if factor <= 0.0:
		return {}
	var ids := _requirement_attributes(spec)
	if ids.is_empty():
		return {}
	# Full cost from base pool B(L) = 18 + 2*(L-1), divided by N.
	# Profile K = 0.70 (high) or 0.40 (moderate).
	var k := 0.4 if String(spec.get("id","")) == "STAFF_SUPPORT" else float(spec.get("requirement_k",0.7))
	var cost := (18.0+2.0*float(level-1))*k/float(ids.size())*factor
	var result := {}
	for p in ids:
		result[String(p)] = maxi(1,roundi(cost))
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

## 14 slots sum to 100% in Project 25. One reference affix slot is 100/14.
## Ratings are calculated per budget share: unlocking another slot NEVER reduces
## any previously unlocked CORE line. Quality is applied exactly once.
const REFERENCE_SLOT_BUDGET := 100.0 / 14.0
const FULL_BUILD_REFERENCE_LINES := 14.0 * 2.0 * 1.5

func nominal_affix(logical: String, level: int, slot: String, quality: float) -> float:
	var slot_weight := float(Dictionary(rules.get("slot_budgets",{})).get(slot,7.5))
	var share := slot_weight / REFERENCE_SLOT_BUDGET
	var l := float(clampi(level,1,100))
	var baseline := 0.0
	match logical:
		"hp":
			# Project 25: 101.19 HP per reference PAR at Lv100 / white.
			baseline = 101.19*l/100.0
		"mana":
			# Project 25: 50.60 mana per reference PAR at Lv100 / white.
			baseline = 50.60*l/100.0
		"attack":
			# Project 25 build targets: +50% at Lv10, +150% at Lv100.
			# Intermediate interpolation is a LAB calibration, not a combat rule.
			var build_target := lerpf(50.0,150.0,clampf((l-10.0)/90.0,0.0,1.0))
			if l < 10.0:
				build_target *= l/10.0
			# Convert planned build percentage into an additive rating.
			# Raw rating is displayed; percentage is computed after aggregation.
			baseline = (build_target * 2.0 / FULL_BUILD_REFERENCE_LINES) * 100.0 / (20.0 - 16.0*(l-1.0)/99.0)
		"mana_regen":
			# Provisional fixed units of mana per combat round, for a
			# white 7.5%-weight reference line, before quality scaling.
			# Anchors: Lv30 +4, Lv60 +9, Lv90 +13.5, Lv100 +15.
			if l <= 30.0:
				baseline = 4.0*l/30.0
			elif l <= 60.0:
				baseline = lerpf(4.0,9.0,(l-30.0)/30.0)
			elif l <= 90.0:
				baseline = lerpf(9.0,13.5,(l-60.0)/30.0)
			else:
				baseline = lerpf(13.5,15.0,(l-90.0)/10.0)
			baseline *= REFERENCE_SLOT_BUDGET/7.5
		"spell":
			# Project 25 specialised build targets: ~200 SP Lv20, ~2000 SP Lv100.
			# Between those anchors, interpolation remains a lab-only assumption.
			var build_target := lerpf(200.0,2000.0,clampf((l-20.0)/80.0,0.0,1.0))
			if l < 20.0:
				build_target *= l/20.0
			baseline = build_target / FULL_BUILD_REFERENCE_LINES
		_:
			# No approved per-PAR numerical extremum yet.
			# Provisional per-PAR calibration targets TWO matching lines,
			# not six: repeated same-PAR rolls beyond two are rare.
			# Other independent PAR slots do not dilute this line.
			baseline = 100.0*l/100.0*REFERENCE_SLOT_BUDGET/7.5/2.0
	return maxf(0.0,baseline*share*quality)

func calibration_status(logical: String) -> String:
	if logical == "mana_regen":
		return "PROVISIONAL_MANA_PER_ROUND_ANCHORS"
	if ["hp","mana"].has(logical):
		return "PROJECT25_ANCHOR"
	if ["attack","spell"].has(logical):
		return "PROJECT25_TARGET_INTERPOLATED"
	return "PROVISIONAL_EXTREMUM"

func _affix_amount(logical: String,level: int,slot: String,quality: float,_lines: int,profile: Dictionary = {}) -> float:
	var amount := nominal_affix(logical,level,slot,quality)
	amount *= armour_par_multiplier(logical,profile)
	var rolled := amount*rng.randf_range(0.95,1.05)
	if logical == "mana_regen":
		return snappedf(maxf(0.0,rolled),0.01)
	if logical == "attack":
		return float(maxi(1,roundi(rolled)))
	return float(maxi(1,roundi(rolled)))

func par_label(par: String) -> String:
	if PAR_LABELS.has(par):
		return String(PAR_LABELS[par])
	return String(Dictionary(par_registry.get(par,{})).get("name",par))
