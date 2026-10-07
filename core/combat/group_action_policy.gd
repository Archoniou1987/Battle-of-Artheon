class_name GroupActionPolicy
extends RefCounted

## Universal N x M action policy.
## Every actionable combatant owns a normal primary action. Active opponent is
## a target, never a reservation; multiple allies may focus the same target.

var group:GroupCombatState

func _init(group_state:GroupCombatState)->void:
	group=group_state

func primary_action_context(combatant_id:String)->Dictionary:
	var combatant:=group.combat_state.get_combatant(combatant_id)
	if combatant==null or not combatant.is_alive():
		return {}
	var target_id:=group.active_opponent(combatant_id)
	return {
		"source_id":combatant_id,
		"target_id":target_id,
		"team_id":group.team_of(combatant_id),
		"valid_enemy_targets":group.living_enemies(combatant_id)
	}

func team_action_contexts(team_id:String)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for combatant_id in group.actionable_members(team_id):
		result.append(primary_action_context(combatant_id))
	return result

func focus_target(combatant_ids:Array[String],target_id:String)->Array[String]:
	var changed:Array[String]=[]
	for combatant_id in combatant_ids:
		if group.set_active_opponent(combatant_id,target_id):
			changed.append(combatant_id)
	return changed
