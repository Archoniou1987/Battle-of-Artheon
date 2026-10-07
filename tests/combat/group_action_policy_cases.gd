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
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("party",CombatZoneState.ZONE_1)
	zones.set_team_flag("enemies",CombatZoneState.ZONE_3)
	zones.set_zone("player",CombatZoneState.ZONE_1)
	zones.set_zone("companion",CombatZoneState.ZONE_1)
	zones.set_zone("enemy_a",CombatZoneState.ZONE_1)
	zones.set_zone("enemy_b",CombatZoneState.ZONE_3)
	var policy:=GroupActionPolicy.new(group,zones)

	# Focus fire is legal in the universal PvE model.
	var melee:Dictionary={"min_zone_distance":0,"max_zone_distance":0}
	var changed:Array[String]=policy.focus_target(["player","companion"],"enemy_a",melee)
	if changed.size()!=2: return false
	if group.active_opponent("player")!="enemy_a": return false
	if group.active_opponent("companion")!="enemy_a": return false

	# A selected target outside the current action reach is not a valid action target.
	group.set_active_opponent("player","enemy_b")
	var context:Dictionary=policy.primary_action_context("player",melee)
	if String(context.get("target_id",""))!="" or context.get("valid_enemy_targets",[]).has("enemy_b"): return false
	group.set_active_opponent("player","enemy_a")

	# The enemy may independently choose either party member.
	group.set_active_opponent("enemy_a","player")
	group.set_active_opponent("enemy_b","player")
	if group.active_opponent("enemy_a")!="player" or group.active_opponent("enemy_b")!="player": return false

	# Every living party member has a full primary action context.
	var contexts:Array[Dictionary]=policy.team_action_contexts("party",melee)
	if contexts.size()!=2: return false
	for context in contexts:
		if String(context.get("target_id",""))!="enemy_a": return false

	var commands:PartyCommandPolicy=PartyCommandPolicy.new()
	commands.need_heal("companion","player")
	var heal:Dictionary={"ai_role":"HEAL"}
	var damage:Dictionary={"ai_role":"DAMAGE"}
	if commands.ability_priority_bonus("companion",heal,"player")<=commands.ability_priority_bonus("companion",damage,"enemy_a"): return false
	commands.attack_target("companion","enemy_b")
	if commands.ability_priority_bonus("companion",damage,"enemy_b")<=0: return false
	return true
