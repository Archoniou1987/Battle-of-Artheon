class_name WeaponAttackProfile
extends RefCounted

## Canonical normalization for weapon attack profiles.
## Spatial target validation belongs to CombatCommandApi; consumers without a
## spatial context (for example duel smoke simulation) can still use the same
## weapon semantics.

static func all(combatant:CombatantState)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var weapons:Array=combatant.combat_stats.get("weapon_profiles",[])
	for weapon_index in range(weapons.size()):
		var weapon:Dictionary=weapons[weapon_index]
		var configured:Array=weapon.get("attack_profiles",[])
		if configured.is_empty():
			configured=[{}]
		for raw_profile in configured:
			if not raw_profile is Dictionary:
				continue
			result.append(normalize(weapon,Dictionary(raw_profile),weapon_index))
	if result.is_empty():
		result.append({
			"id":"basic","weapon_index":0,"delivery_type":"MELEE",
			"min_zone_distance":0,"max_zone_distance":0,"two_zone_hit_modifier":-50.0,
			"damage_min":float(combatant.combat_stats.get("main_hand_damage_min",combatant.combat_stats.get("main_hand_damage",0.0))),
			"damage_max":float(combatant.combat_stats.get("main_hand_damage_max",combatant.combat_stats.get("main_hand_damage",0.0))),
			"damage_type":String(combatant.combat_stats.get("main_hand_damage_type","slashing")),
			"uses_magic_hit":false,"magic_hit_modifier":0.0,"hit_count":1
		})
	return result

static func normalize(weapon:Dictionary,raw_profile:Dictionary,weapon_index:int)->Dictionary:
	var profile:Dictionary=raw_profile.duplicate(true)
	profile["id"]=String(profile.get("id","basic"))
	profile["weapon_index"]=weapon_index
	profile["delivery_type"]=String(profile.get("delivery_type","MELEE")).to_upper()
	profile["min_zone_distance"]=int(profile.get("min_zone_distance",0))
	profile["max_zone_distance"]=int(profile.get("max_zone_distance",0 if profile["delivery_type"]=="MELEE" else 2))
	profile["two_zone_hit_modifier"]=float(profile.get("two_zone_hit_modifier",-50.0))
	profile["damage_min"]=float(profile.get("damage_min",weapon.get("damage_min",0.0)))
	profile["damage_max"]=float(profile.get("damage_max",weapon.get("damage_max",profile["damage_min"])))
	profile["damage_type"]=String(profile.get("damage_type",weapon.get("damage_type","slashing")))
	profile["uses_magic_hit"]=bool(profile.get("uses_magic_hit",weapon.get("uses_magic_hit",false)))
	profile["magic_hit_modifier"]=float(profile.get("magic_hit_modifier",weapon.get("magic_hit_modifier",0.0)))
	profile["hit_count"]=maxi(1,int(profile.get("hit_count",weapon.get("hit_count",1))))
	return profile
