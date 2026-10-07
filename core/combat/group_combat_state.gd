class_name GroupCombatState
extends RefCounted

## Structural state for group combat. Engagement policy is intentionally kept
## outside this class and is added in Phase 9.

var combat_state:CombatState
var teams:Dictionary={}
var combatant_team:Dictionary={}
var active_opponent_by_combatant:Dictionary={}

func _init(state:CombatState) -> void:
	combat_state=state

func add_member(team_id:String, combatant_id:String) -> bool:
	if combat_state.get_combatant(combatant_id)==null or team_id.is_empty():
		return false
	remove_member(combatant_id)
	if not teams.has(team_id):
		teams[team_id]=[]
	var members:Array=teams[team_id]
	members.append(combatant_id)
	teams[team_id]=members
	combatant_team[combatant_id]=team_id
	return true

func remove_member(combatant_id:String) -> void:
	var old_team:=String(combatant_team.get(combatant_id,""))
	if not old_team.is_empty() and teams.has(old_team):
		var members:Array=teams[old_team]
		members.erase(combatant_id)
		teams[old_team]=members
	combatant_team.erase(combatant_id)
	active_opponent_by_combatant.erase(combatant_id)
	for owner_id in active_opponent_by_combatant.keys():
		if String(active_opponent_by_combatant.get(owner_id,""))==combatant_id:
			active_opponent_by_combatant.erase(owner_id)

func team_of(combatant_id:String) -> String:
	return String(combatant_team.get(combatant_id,""))

func living_members(team_id:String) -> Array[String]:
	var result:Array[String]=[]
	for raw_id in teams.get(team_id,[]):
		var combatant_id:=String(raw_id)
		var combatant:=combat_state.get_combatant(combatant_id)
		if combatant!=null and not combatant.is_death_finalized():
			result.append(combatant_id)
	return result

func living_enemies(combatant_id:String) -> Array[String]:
	var own_team:=team_of(combatant_id)
	var result:Array[String]=[]
	for team_id in teams.keys():
		if String(team_id)==own_team:
			continue
		result.append_array(living_members(String(team_id)))
	return result

func set_active_opponent(combatant_id:String, opponent_id:String) -> bool:
	if not living_enemies(combatant_id).has(opponent_id):
		return false
	active_opponent_by_combatant[combatant_id]=opponent_id
	return true

func active_opponent(combatant_id:String) -> String:
	var opponent_id:=String(active_opponent_by_combatant.get(combatant_id,""))
	if living_enemies(combatant_id).has(opponent_id):
		return opponent_id
	return ""

func external_enemies(combatant_id:String) -> Array[String]:
	var result:=living_enemies(combatant_id)
	result.erase(active_opponent(combatant_id))
	return result

func prune_finalized_deaths() -> Array[String]:
	var removed:Array[String]=[]
	for combatant_id in combatant_team.keys().duplicate():
		var combatant:=combat_state.get_combatant(String(combatant_id))
		if combatant==null or combatant.is_death_finalized():
			removed.append(String(combatant_id))
			remove_member(String(combatant_id))
	return removed
