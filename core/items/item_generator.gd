class_name ItemGenerator
extends RefCounted

const STAT_POOL := ["STR", "DEX", "INTU", "INT", "WIS", "END"]
const QUALITY_RULES := {
	"poor":{"min_mult":0.70,"max_mult":0.80,"mods":0,"mod_min":0,"mod_max":0},
	"common":{"min_mult":0.95,"max_mult":1.05,"mods":0,"mod_min":0,"mod_max":0},
	"green":{"min_mult":1.05,"max_mult":1.10,"mods":1,"mod_min":2,"mod_max":3},
	"blue":{"min_mult":1.10,"max_mult":1.15,"mods":2,"mod_min":2,"mod_max":3},
	"purple":{"min_mult":1.15,"max_mult":1.25,"mods":3,"mod_min":3,"mod_max":4}}
var rng:=RandomNumberGenerator.new(); var serial:int=0
func _init(seed_value:int=1)->void:rng.seed=seed_value
func generate(template:Dictionary,quality:String,condition_rule:Dictionary={})->Dictionary:
	var rule:Dictionary=QUALITY_RULES.get(quality,{})
	if rule.is_empty():return {}
	serial+=1; var multiplier:=rng.randf_range(float(rule.min_mult),float(rule.max_mult))
	var base_stats:Dictionary=template.get("base_stats",{}); var scaled_stats:Dictionary={}
	for stat in base_stats:scaled_stats[stat]=int(round(float(base_stats[stat])*multiplier))
	var rolled_mods:Array[Dictionary]=[]; var final_stats:=scaled_stats.duplicate(true)
	for i in range(int(rule.mods)):
		var stat:=String(STAT_POOL[rng.randi_range(0,STAT_POOL.size()-1)]); var value:=rng.randi_range(int(rule.mod_min),int(rule.mod_max))
		rolled_mods.append({"stat":stat,"value":value}); final_stats[stat]=int(final_stats.get(stat,0))+value
	var dmin:=int(round(float(template.get("damage_min",0))*multiplier)); var dmax:=int(round(float(template.get("damage_max",0))*multiplier))
	var item:Dictionary={"instance_id":"GEN-%06d"%serial,"template_id":String(template.get("id","")),"name":String(template.get("name","")),"item_level":int(template.get("item_level",1)),"quality":quality,"quality_multiplier":multiplier,"equip_slots":template.get("equip_slots",[]).duplicate(true),"slot_usage":template.get("slot_usage",[]).duplicate(true),"damage_min":dmin,"damage_max":dmax,"damage":{"min":dmin,"max":dmax,"type":String(template.get("damage_type","slashing"))} if dmax>0 else {},"base_stats":scaled_stats,"rolled_mods":rolled_mods,"final_stats":final_stats,"manual_block_zones_added":int(template.get("manual_block_zones_added",1)),"combat_stats":template.get("combat_stats",{}).duplicate(true),"armour_all_zones_all_physical":float(template.get("armour_all_zones_all_physical",0.0))}
	if template.has("on_hit_effect"):item["on_hit_effect"]=(template.get("on_hit_effect",{}) as Dictionary).duplicate(true)
	if template.has("on_manual_block_effect"):item["on_manual_block_effect"]=(template.get("on_manual_block_effect",{}) as Dictionary).duplicate(true)
	if template.has("abilities"):item["abilities"]=(template.get("abilities",[]) as Array).duplicate(true)
	_initialize_condition(item,int(template.get("durability_max",50)),condition_rule)
	return item
func generate_batch(template:Dictionary,count:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]; var qualities:=QUALITY_RULES.keys()
	for i in range(count):result.append(generate(template,String(qualities[rng.randi_range(0,qualities.size()-1)])))
	return result


func _initialize_condition(item:Dictionary,base_max:int,rule:Dictionary)->void:
	var origin:=String(rule.get("origin","crafted"))
	item["origin"]=origin
	if origin=="crafted":
		ItemDurabilityService.initialize_item(item,base_max)
		return
	var max_wear_min:=clampf(float(rule.get("max_wear_min",0.0)),0.0,1.0)
	var max_wear_max:=clampf(float(rule.get("max_wear_max",max_wear_min)),max_wear_min,1.0)
	var damage_min:=clampf(float(rule.get("damage_min",0.0)),0.0,1.0)
	var damage_max:=clampf(float(rule.get("damage_max",damage_min)),damage_min,1.0)
	var max_wear:=rng.randf_range(max_wear_min,max_wear_max)
	var maximum:=clampi(int(round(float(base_max)*(1.0-max_wear))),1,base_max)
	var damage:=rng.randf_range(damage_min,damage_max)
	var current:=clampi(int(round(float(maximum)*(1.0-damage))),0,maximum)
	var hidden_limit:=maxi(0,maximum-2)
	var hidden_progress:=0
	if hidden_limit>0:
		var hidden_min:=clampf(float(rule.get("hidden_progress_min",0.0)),0.0,1.0)
		var hidden_max:=clampf(float(rule.get("hidden_progress_max",hidden_min)),hidden_min,1.0)
		hidden_progress=clampi(int(round(float(hidden_limit)*rng.randf_range(hidden_min,hidden_max))),0,hidden_limit)
	ItemDurabilityService.initialize_item(item,maximum,current,hidden_progress)
