class_name EquipmentBuilder
extends RefCounted
const PHYSICAL_TYPES := ["piercing","slashing","chopping","blunt"]
const HIT_ZONES := ["head","chest","arms","waist","legs"]
static func equip(combatant:CombatantState,item:Dictionary)->void:
	var item_stats:Dictionary=item.get("combat_stats",{})
	for stat_name in item_stats:combatant.combat_stats[stat_name]=float(combatant.combat_stats.get(stat_name,0.0))+float(item_stats[stat_name])
	var final_stats:Dictionary=item.get("final_stats",{})
	for stat_name in final_stats:combatant.stats[stat_name]=float(combatant.stats.get(stat_name,0.0))+float(final_stats[stat_name])
	var damage:Dictionary=item.get("damage",{}); var is_weapon:=not damage.is_empty()
	if is_weapon:
		var weapon_profiles:Array=combatant.combat_stats.get("weapon_profiles",[])
		var weapon_profile:Dictionary={
			"item_id":String(item.get("id","")),
			"instance_id":String(item.get("instance_id",item.get("id",""))),
			"slot":String(item.get("slot","")),
			"weapon_class":String(item.get("weapon_class","")),
			"item_level":maxi(1,int(item.get("level",1))),
			"requires_off_hand_type":String(item.get("requires_off_hand_type","")),
			"damage_min":float(damage.get("min",0.0)),
			"damage_max":float(damage.get("max",0.0)),
			"damage_type":String(damage.get("type","slashing")),
			"on_hit_effect":item.get("on_hit_effect",{}).duplicate(true)
		}
		if not weapon_profile["on_hit_effect"].is_empty():
			weapon_profile["on_hit_effect"]["source_type"]="item"
			weapon_profile["on_hit_effect"]["source_instance_id"]=weapon_profile["instance_id"]
		weapon_profiles.append(weapon_profile)
		combatant.combat_stats["weapon_profiles"]=weapon_profiles
		combatant.combat_stats["weapon_attack_count"]=weapon_profiles.size()
		combatant.combat_stats["manual_block_zone_capacity"]=maxi(int(combatant.combat_stats.get("manual_block_zone_capacity",0)),int(item.get("manual_block_zones_added",0)))
		var weapon_effects:Array=combatant.combat_stats.get("weapon_on_hit_effects",[])
		weapon_effects.append(weapon_profile["on_hit_effect"].duplicate(true))
		combatant.combat_stats["weapon_on_hit_effects"]=weapon_effects
		# Legacy aliases remain during Combat v2 migration. New attack code uses weapon_profiles.
		if weapon_profiles.size()==1:
			combatant.combat_stats["main_hand_damage_min"]=weapon_profile["damage_min"]; combatant.combat_stats["main_hand_damage_max"]=weapon_profile["damage_max"]; combatant.combat_stats["main_hand_damage"]=(weapon_profile["damage_min"]+weapon_profile["damage_max"])/2.0; combatant.combat_stats["main_hand_damage_type"]=weapon_profile["damage_type"]
	else:
		var added:=int(item.get("manual_block_zones_added",0)); combatant.combat_stats["manual_block_zone_capacity"]=int(combatant.combat_stats.get("manual_block_zone_capacity",0))+added
	if item.has("on_manual_block_effect"):
		var triggers:Array=combatant.combat_stats.get("on_manual_block_effects",[])
		var block_effect:Dictionary=item.on_manual_block_effect.duplicate(true); block_effect["source_type"]="item"; block_effect["source_instance_id"]=String(item.get("instance_id",item.get("id","")))
		triggers.append(block_effect); combatant.combat_stats["on_manual_block_effects"]=triggers
	var armour:=float(item.get("armour_all_zones_all_physical",0.0))
	if armour>0.0:_add_universal_physical_armour(combatant,armour)
static func set_manual_block_zones(combatant:CombatantState,zones:Array)->void:
	var capacity:=int(combatant.combat_stats.get("manual_block_zone_capacity",0)); var selected:Array[String]=[]
	for zone in zones:
		var normalized:=String(zone).to_lower()
		if HIT_ZONES.has(normalized) and not selected.has(normalized) and selected.size()<capacity:selected.append(normalized)
	combatant.combat_stats["manual_block_zones"]=selected
static func _add_universal_physical_armour(combatant:CombatantState,amount:float)->void:
	for zone in HIT_ZONES:
		var zone_armour:Dictionary=combatant.armour.get(zone,{})
		for damage_type in PHYSICAL_TYPES:zone_armour[damage_type]=float(zone_armour.get(damage_type,0.0))+amount
		combatant.armour[zone]=zone_armour
