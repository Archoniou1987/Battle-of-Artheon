class_name GroupActionPolicyCases
extends RefCounted

static func run()->bool:
	var state:=CombatState.new()
	for id in ["player","companion","enemy_a","enemy_b"]:
		state.add_combatant(CombatantState.new(id,id,10,100))
	var group:=GroupCombatState.new(state)
	group.add_member("party","player")
	group.add_member("party","companion")
	group.add_member("enemies","enemy_a")
	group.add_member("enemies","enemy_b")
	var policy:=GroupActionPolicy.new(group)

	# Focus fire is legal in the universal PvE model.
	var changed:=policy.focus_target(["player","companion"],"enemy_a")
	if changed.size()!=2: return false
	if group.active_opponent("player")!="enemy_a": return false
	if group.active_opponent("companion")!="enemy_a": return false

	# The enemy may independently choose either party member.
	group.set_active_opponent("enemy_a","player")
	group.set_active_opponent("enemy_b","player")
	if group.active_opponent("enemy_a")!="player" or group.active_opponent("enemy_b")!="player": return false

	# Every living party member has a full primary action context.
	var contexts:=policy.team_action_contexts("party")
	if contexts.size()!=2: return false
	for context in contexts:
		if String(context.get("target_id",""))!="enemy_a": return false

	var commands:=PartyCommandPolicy.new()
	commands.need_heal("companion","player")
	var heal:Dictionary={"ai_role":"HEAL"}
	var damage:Dictionary={"ai_role":"DAMAGE"}
	if commands.ability_priority_bonus("companion",heal,"player")<=commands.ability_priority_bonus("companion",damage,"enemy_a"): return false
	commands.attack_target("companion","enemy_b")
	if commands.ability_priority_bonus("companion",damage,"enemy_b")<=0: return false
	return true
