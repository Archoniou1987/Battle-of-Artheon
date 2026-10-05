class_name ItemGenerator
extends RefCounted

const STAT_POOL := ["STR", "DEX", "INTU", "INT", "WIS", "END"]
const QUALITY_RULES := {
	"poor": {"min_mult":0.70,"max_mult":0.80,"mods":0,"mod_min":0,"mod_max":0},
	"common": {"min_mult":0.95,"max_mult":1.05,"mods":0,"mod_min":0,"mod_max":0},
	"green": {"min_mult":1.05,"max_mult":1.10,"mods":1,"mod_min":2,"mod_max":3},
	"blue": {"min_mult":1.10,"max_mult":1.15,"mods":2,"mod_min":2,"mod_max":3},
	"purple": {"min_mult":1.15,"max_mult":1.25,"mods":3,"mod_min":3,"mod_max":4}
}

var rng := RandomNumberGenerator.new()
var serial: int = 0

func _init(seed_value:int=1)->void:
	rng.seed=seed_value

func generate(template:Dictionary,quality:String)->Dictionary:
	var rule:Dictionary=QUALITY_RULES.get(quality,{})
	if rule.is_empty(): return {}
	serial+=1
	var multiplier:=rng.randf_range(float(rule.min_mult),float(rule.max_mult))
	var base_stats:Dictionary=template.get("base_stats",{})
	var scaled_stats:Dictionary={}
	for stat in base_stats: scaled_stats[stat]=int(round(float(base_stats[stat])*multiplier))
	var rolled_mods:Array[Dictionary]=[]
	for i in range(int(rule.mods)):
		var stat:=String(STAT_POOL[rng.randi_range(0,STAT_POOL.size()-1)])
		rolled_mods.append({"stat":stat,"value":rng.randi_range(int(rule.mod_min),int(rule.mod_max))})
	return {
		"instance_id":"GEN-%06d" % serial,
		"template_id":String(template.get("id","")),
		"name":String(template.get("name","")),
		"item_level":int(template.get("item_level",1)),
		"quality":quality,
		"quality_multiplier":multiplier,
		"damage_min":int(round(float(template.get("damage_min",0))*multiplier)),
		"damage_max":int(round(float(template.get("damage_max",0))*multiplier)),
		"base_stats":scaled_stats,
		"rolled_mods":rolled_mods
	}

func generate_batch(template:Dictionary,count:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var qualities:=QUALITY_RULES.keys()
	for i in range(count): result.append(generate(template,String(qualities[rng.randi_range(0,qualities.size()-1)])))
	return result
