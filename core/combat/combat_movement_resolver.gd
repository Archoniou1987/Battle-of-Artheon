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
	result["moved"]=true
	result["reason"]="ok"
	return result

func apply_result(result:Dictionary)->bool:
	if not bool(result.get("moved",false)):
		return false
	return zones.set_zone(String(result.get("source_id","")),int(result.get("to_zone",-1)))



func resolve_simultaneous(requests:Array[Dictionary])->Array[Dictionary]:
	var results:Array[Dictionary]=[]
	var provisional:Array[Dictionary]=[]
	for request in requests:
		var result:=navigation_result(
			String(request.get("combatant_id","")),
			int(request.get("to_zone",-1)),
			float(request.get("tempo",0.0)),
			int(request.get("tempo_roll",1)),
			bool(request.get("bypass_front",false)),
			bool(request.get("movement_locked",false))
		)
		result["contest_power"]=float(request.get("contest_power",0.0))
		result["movement_kind"]=String(request.get("movement_kind","navigation"))
		provisional.append(result)
	var canceled:Dictionary={}
	for i in range(provisional.size()):
		if canceled.has(i) or not bool(provisional[i].get("moved",false)):
			continue
		for j in range(i+1,provisional.size()):
			if canceled.has(j) or not bool(provisional[j].get("moved",false)):
				continue
			var a:Dictionary=provisional[i]
			var b:Dictionary=provisional[j]
			if int(a.from_zone)==int(b.to_zone) and int(a.to_zone)==int(b.from_zone):
				var a_power:=float(a.get("contest_power",0.0))
				var b_power:=float(b.get("contest_power",0.0))
				if a_power==b_power:
					canceled[i]="contest_tie"; canceled[j]="contest_tie"
				elif a_power>b_power:
					canceled[j]="contest_lost"
				else:
					canceled[i]="contest_lost"
	for i in range(provisional.size()):
		var result:Dictionary=provisional[i]
		if canceled.has(i):
			result["moved"]=false
			result["reason"]=String(canceled[i])
		elif bool(result.get("moved",false)):
			apply_result(result)
		results.append(result)
	return results
