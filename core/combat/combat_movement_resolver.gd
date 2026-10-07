class_name CombatMovementResolver
extends RefCounted

## Resolves declared one-step movement against the start-of-round positional
## snapshot. A request can fail, but it can never turn into another action.

var zones:CombatZoneState

func _init(zone_state:CombatZoneState)->void:
	zones=zone_state

func navigation_result(combatant_id:String,to_zone:int,tempo:float,tempo_roll:int,bypass_front:bool=false,movement_locked:bool=false)->Dictionary:
	var from_zone:=zones.zone_of(combatant_id)
	var result:={"source_id":combatant_id,"from_zone":from_zone,"to_zone":to_zone,"moved":false,"reason":""}
	if movement_locked:
		result["reason"]="movement_locked"
		return result
	if from_zone<0 or absi(to_zone-from_zone)!=1 or to_zone<CombatZoneState.MIN_ZONE or to_zone>CombatZoneState.MAX_ZONE:
		result["reason"]="invalid_transition"
		return result
	if not bypass_front and not zones.ordinary_navigation_allowed(combatant_id,to_zone):
		result["reason"]="front_blocked"
		return result
	if not _tempo_allows(tempo,tempo_roll):
		result["reason"]="tempo_failed"
		return result
	result["moved"]=true
	result["reason"]="ok"
	return result

func apply_result(result:Dictionary)->bool:
	if not bool(result.get("moved",false)):
		return false
	return zones.set_zone(String(result.get("source_id","")),int(result.get("to_zone",-1)))

func _tempo_allows(tempo:float,roll:int)->bool:
	if tempo<=-100.0:
		return false
	if tempo>=0.0:
		return true
	return CombatMath.roll_success(100.0+tempo,roll)
