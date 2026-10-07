class_name GroupCombatController
extends RefCounted

var group:GroupCombatState

func _init(group_state:GroupCombatState) -> void:
	group=group_state

func initialize_active_opponents() -> void:
	for combatant_id in group.combatant_team.keys():
		ensure_active_opponent(String(combatant_id))

func ensure_active_opponent(combatant_id:String) -> String:
	var current:=group.active_opponent(combatant_id)
	if not current.is_empty():
		return current
	var candidates:=group.living_enemies(combatant_id)
	if candidates.is_empty():
		group.active_opponent_by_combatant.erase(combatant_id)
		return ""
	var replacement:=String(candidates[0])
	group.set_active_opponent(combatant_id,replacement)
	return replacement

func after_end_round(round_summary:Dictionary) -> Dictionary:
	var previous:Dictionary=group.active_opponent_by_combatant.duplicate()
	var removed:=group.prune_finalized_deaths()
	var replacements:Dictionary={}
	for combatant_id in group.combatant_team.keys():
		var owner_id:=String(combatant_id)
		var before:=String(previous.get(owner_id,""))
		var after:=ensure_active_opponent(owner_id)
		if before!=after and not after.is_empty():
			replacements[owner_id]={"from":before,"to":after}
	return {
		"dead_ids":round_summary.get("dead_ids",[]).duplicate(),
		"removed_ids":removed,
		"active_replacements":replacements
	}

func combat_finished() -> bool:
	var living_teams:=0
	for team_id in group.teams.keys():
		if not group.living_members(String(team_id)).is_empty():
			living_teams+=1
	return living_teams<=1

func winning_team() -> String:
	if not combat_finished():
		return ""
	for team_id in group.teams.keys():
		if not group.living_members(String(team_id)).is_empty():
			return String(team_id)
	return ""
