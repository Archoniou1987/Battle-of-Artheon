class_name CombatReachPolicy
extends RefCounted

## Pure reach policy. Distance penalties modify Hit/Magic Hit; they do not
## silently redirect an action or change its magnitude.

static func can_reach(distance:int,min_distance:int,max_distance:int)->bool:
	return distance>=min_distance and distance<=max_distance

static func distance_hit_modifier(distance:int,definition:Dictionary)->float:
	if distance<=1:
		return 0.0
	return float(definition.get("two_zone_hit_modifier",0.0))

static func valid_enemy_targets(source_id:String,zone_state:CombatZoneState,definition:Dictionary)->Array[String]:
	var result:Array[String]=[]
	var min_distance:=int(definition.get("min_zone_distance",0))
	var max_distance:=int(definition.get("max_zone_distance",0))
	for target_id in zone_state.group.living_enemies(source_id):
		var d:=zone_state.distance(source_id,target_id)
		if d>=0 and can_reach(d,min_distance,max_distance):
			result.append(target_id)
	result.sort()
	return result
