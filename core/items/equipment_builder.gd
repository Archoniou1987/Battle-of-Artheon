class_name EquipmentBuilder
extends RefCounted
const PHYSICAL_TYPES := ["piercing","slashing","chopping","blunt"]
const HIT_ZONES := ["head","chest","arms","waist","legs"]
static func equip(combatant:CombatantState,item:Dictionary)->void:
	# Numeric item modifiers are aggregated exclusively by ParCalculationService.
	# This builder owns weapon identity, triggers, blocking layout and armour runtime data.
	var equipped_types:Array=combatant.combat_stats.get("equipped_item_types",[])
	var item_type:=String(item.get("item_type",""))
	if not item_type.is_empty() and not equipped_types.has(item_type):
		equipped_types.append(item_type)
		combatant.combat_stats["equipped_item_types"]=equipped_types
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
			"on_hit_effect":item.get("on_hit_effect",{}).duplicate(true),
			"attack_profiles":item.get("attack_profiles",[]).duplicate(true)
		}
		if not weapon_profile["on_hit_effect"].is_empty():
			weapon_profile["on_hit_effect"]["source_type"]="item"
			weapon_profile["on_hit_effect"]["source_instance_id"]=weapon_profile["instance_id"]
		weapon_profiles.append(weapon_profile)
		combatant.combat_stats["weapon_profiles"]=weapon_profiles
		combatant.combat_stats["weapon_attack_count"]=weapon_profiles.size()
		combatant.combat_stats["manual_block_zone_capacity"]=maxi(int(combatant.combat_stats.get("manual_block_zone_capacity",0)),int(item.get("manual_block_zones_added",0)))
		var weapon_effects:Array=combatant.combat_stats.get("weapon_on_hit_effects",[])
		var weapon_effect:Dictionary=weapon_profile["on_hit_effect"].duplicate(true)
		if not weapon_effect.is_empty():
			weapon_effect["weapon_index"]=weapon_profiles.size()-1
			weapon_effects.append(weapon_effect)
		combatant.combat_stats["weapon_on_hit_effects"]=weapon_effects
	else:
		var added:=int(item.get("manual_block_zones_added",0)); combatant.combat_stats["manual_block_zone_capacity"]=int(combatant.combat_stats.get("manual_block_zone_capacity",0))+added
		if item.has("on_hit_effect"):
			var item_effect:Dictionary=item.get("on_hit_effect",{}).duplicate(true)
			if not item_effect.is_empty():
				item_effect["source_type"]="item"
				item_effect["source_instance_id"]=String(item.get("instance_id",item.get("id","")))
				item_effect["weapon_index"]=-1
				var global_weapon_effects:Array=combatant.combat_stats.get("weapon_on_hit_effects",[])
				global_weapon_effects.append(item_effect)
				combatant.combat_stats["weapon_on_hit_effects"]=global_weapon_effects
	if item.has("on_manual_block_effect"):
		var triggers:Array=combatant.combat_stats.get("on_manual_block_effects",[])
		var block_effect:Dictionary=item.on_manual_block_effect.duplicate(true); block_effect["source_type"]="item"; block_effect["source_instance_id"]=String(item.get("instance_id",item.get("id","")))
		triggers.append(block_effect); combatant.combat_stats["on_manual_block_effects"]=triggers
	var zoned_armour:Dictionary=item.get("armour_by_zone",{})
	for raw_zone in zoned_armour:
		var zone:=String(raw_zone)
		if not HIT_ZONES.has(zone):
			continue
		var value:=float(zoned_armour[raw_zone])
		var zone_armour:Dictionary=combatant.armour.get(zone,{})
		for damage_type in PHYSICAL_TYPES:
			zone_armour[damage_type]=float(zone_armour.get(damage_type,0.0))+value
		combatant.armour[zone]=zone_armour
	var armour:=float(item.get("armour_all_zones_all_physical",0.0))
	if armour>0.0:_add_universal_physical_armour(combatant,armour)
static func set_manual_block_zones(combatant:CombatantState,zones:Array)->void:
	var capacity:=clampi(int(combatant.combat_stats.get("par_totals", {}).get("PAR073", 2)),1,4)
	var selected:Array[String]=[]
	for zone in zones:
		var normalized:=String(zone).to_lower()
		if HIT_ZONES.has(normalized) and not selected.has(normalized):
			selected.append(normalized)
	if selected.size()!=capacity:
		combatant.combat_stats.erase("manual_block_zones")
		return
	var indices:Array[int]=[]
	for zone in selected:
		indices.append(HIT_ZONES.find(zone))
	indices.sort()
	for i in range(1,indices.size()):
		if indices[i]!=indices[i-1]+1:
			combatant.combat_stats.erase("manual_block_zones")
			return
	combatant.combat_stats["manual_block_zones"]=selected
static func _add_universal_physical_armour(combatant:CombatantState,amount:float)->void:
	for zone in HIT_ZONES:
		var zone_armour:Dictionary=combatant.armour.get(zone,{})
		for damage_type in PHYSICAL_TYPES:zone_armour[damage_type]=float(zone_armour.get(damage_type,0.0))+amount
		combatant.armour[zone]=zone_armour
