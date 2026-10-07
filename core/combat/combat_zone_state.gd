class_name CombatZoneState
extends RefCounted

## Three-zone positional layer for group combat. Zone indexes are absolute;
## forward/backward are derived from each team's flag side.

const ZONE_1:=0
const ZONE_2:=1
const ZONE_3:=2
const MIN_ZONE:=ZONE_1
const MAX_ZONE:=ZONE_3

var group:GroupCombatState
var zone_by_combatant:Dictionary={}
var flag_zone_by_team:Dictionary={}

func _init(group_state:GroupCombatState)->void:
	group=group_state

func set_team_flag(team_id:String,flag_zone:int)->bool:
	if not _valid_zone(flag_zone) or flag_zone==ZONE_2:
		return false
	flag_zone_by_team[team_id]=flag_zone
	return true

func set_zone(combatant_id:String,zone:int)->bool:
	if group.combat_state.get_combatant(combatant_id)==null or not _valid_zone(zone):
		return false
	zone_by_combatant[combatant_id]=zone
	return true

func zone_of(combatant_id:String)->int:
	return int(zone_by_combatant.get(combatant_id,-1))

func distance(a_id:String,b_id:String)->int:
	var a:=zone_of(a_id)
	var b:=zone_of(b_id)
	return -1 if a<0 or b<0 else absi(a-b)

func occupants(zone:int,round_present_only:bool=true)->Array[String]:
	var result:Array[String]=[]
	for raw_id in zone_by_combatant.keys():
		var combatant_id:=String(raw_id)
		if int(zone_by_combatant[combatant_id])!=zone:
			continue
		var combatant:=group.combat_state.get_combatant(combatant_id)
		if combatant==null:
			continue
		if round_present_only and combatant.is_death_finalized():
			continue
		result.append(combatant_id)
	result.sort()
	return result

func enemies_in_zone(combatant_id:String,zone:int)->Array[String]:
	var result:Array[String]=[]
	var own_team:=group.team_of(combatant_id)
	for other_id in occupants(zone):
		if group.team_of(other_id)!=own_team:
			result.append(other_id)
	return result

func direction(combatant_id:String,to_zone:int)->int:
	var from_zone:=zone_of(combatant_id)
	if from_zone<0 or not _valid_zone(to_zone) or absi(to_zone-from_zone)!=1:
		return 0
	var flag_zone:=int(flag_zone_by_team.get(group.team_of(combatant_id),-1))
	if flag_zone<0:
		return 0
	var step:=signi(to_zone-from_zone)
	var forward_step:=1 if flag_zone==ZONE_1 else -1
	return 1 if step==forward_step else -1

func ordinary_navigation_allowed(combatant_id:String,to_zone:int)->bool:
	var from_zone:=zone_of(combatant_id)
	if from_zone<0 or absi(to_zone-from_zone)!=1 or not _valid_zone(to_zone):
		return false
	var move_direction:=direction(combatant_id,to_zone)
	if move_direction==0:
		return false
	if move_direction<0:
		return true
	return enemies_in_zone(combatant_id,from_zone).is_empty()

func _valid_zone(zone:int)->bool:
	return zone>=MIN_ZONE and zone<=MAX_ZONE
