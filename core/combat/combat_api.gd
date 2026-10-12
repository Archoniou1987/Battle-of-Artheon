class_name CombatApi
extends RefCounted

## Read-only presentation boundary for Combat UI.
## UI receives stable dictionaries and never mutates CombatState directly.

var state:CombatState
var group:GroupCombatState
var zones:CombatZoneState

func _init(combat_state:CombatState, group_state:GroupCombatState=null, zone_state:CombatZoneState=null)->void:
	state=combat_state
	group=group_state
	zones=zone_state

func snapshot()->Dictionary:
	var combatants:Array[Dictionary]=[]
	for raw_id in state.combatants.keys():
		var id:=String(raw_id)
		combatants.append(combatant(id))
	combatants.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return String(a.get("id",""))<String(b.get("id","")))
	return {
		"round":state.round_number,
		"combatants":combatants,
		"teams":_teams(),
		"zones":_zones()
	}

func combatant(combatant_id:String)->Dictionary:
	var c:=state.get_combatant(combatant_id)
	if c==null:
		return {}
	var combat_readout:=CombatModifierService.combat_readout(c, state.round_number)
	return {
		"id":c.combatant_id,
		"name":c.display_name,
		"level":c.level,
		"hp":c.visible_hp(),
		"hp_internal":c.hp,
		"max_hp":c.max_hp,
		"mana":c.mana,
		"max_mana":c.max_mana,
		"tempo":float(combat_readout.get("effective_tempo",c.tempo)),
		"combat_stats":combat_readout,
		"alive":not c.is_death_finalized(),
		"death_finalized":c.is_death_finalized(),
		"team_id":group.team_of(combatant_id) if group!=null else "",
		"zone_id":zones.zone_of(combatant_id) if zones!=null else -1,
		"active_opponent_id":group.active_opponent(combatant_id) if group!=null else "",
		"can_manual_block":c.can_manual_block(),
		"can_auto_block":c.can_auto_block()
	}

func target_options(combatant_id:String)->Dictionary:
	if group==null:
		return {"active":"","alternatives":[]}
	return {
		"active":group.active_opponent(combatant_id),
		"alternatives":group.alternative_targets(combatant_id)
	}

func recent_events(after_event_id:int=0)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for event in state.event_log:
		if event.event_id<=after_event_id:
			continue
		result.append({
			"id":event.event_id,
			"round":int(event.payload.get("round",0)),
			"kind":int(event.kind),
			"source_id":event.source_id,
			"target_id":event.target_id,
			"parent_event_id":event.parent_event_id,
			"outcome":String(event.result.get("outcome","")),
			"result":event.result.duplicate(true)
		})
	return result

func _teams()->Dictionary:
	if group==null:
		return {}
	var result:Dictionary={}
	for raw_team in group.teams.keys():
		var team_id:=String(raw_team)
		result[team_id]=group.round_present_members(team_id)
	return result

func _zones()->Dictionary:
	if zones==null:
		return {}
	var result:Dictionary={}
	for zone in range(CombatZoneState.MIN_ZONE,CombatZoneState.MAX_ZONE+1):
		result[str(zone)]=zones.occupants(zone)
	return result
