class_name ZoneCombatCases
extends RefCounted

static func run()->bool:
	print("CASE_SUITE_START=zone_combat_cases")
	var cases:Dictionary={
		"direction":_direction_relative_to_flag(),
		"front":_front_blocks_forward_only(),
		"reach":_reach_is_zone_based(),
		"tempo":_tempo_only_accepts_or_rejects_declared_move(),
		"special_move":_special_move_can_break_front(),
		"root":_root_blocks_all_movement(),
		"movement_contest":_movement_contest_has_no_initiative(),
		"friendly_fire_reach":_engine_rejects_friendly_fire_and_out_of_reach(),
		"magic_heal":_magic_hit_and_heal_follow_spatial_rules(),
		"physical_projectile_distance":_physical_projectile_distance_penalizes_hit(),
		"zone_magic_distance":_zone_target_magic_hit_uses_zone_distance(),
		"zone_occupants":_zone_target_resolves_current_occupants()
	}
	for case_name in cases:
		if not bool(cases[case_name]): print("ZONE_CASE_FAIL=",case_name)
	return not cases.values().has(false)

static func _fixture()->Dictionary:
	var state:=CombatState.new()
	for id in ["a","b","a2"]:
		state.add_combatant(TestFixtureLoader.new_combatant(id,id.to_upper(),1,100))
	var group:=GroupCombatState.new(state)
	group.add_member("team_a","a")
	group.add_member("team_a","a2")
	group.add_member("team_b","b")
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("team_a",CombatZoneState.ZONE_1)
	zones.set_team_flag("team_b",CombatZoneState.ZONE_3)
	zones.set_zone("a",CombatZoneState.ZONE_2)
	zones.set_zone("a2",CombatZoneState.ZONE_1)
	zones.set_zone("b",CombatZoneState.ZONE_2)
	return {"state":state,"group":group,"zones":zones}

static func _direction_relative_to_flag()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	return zones.direction("a",CombatZoneState.ZONE_3)==1 and zones.direction("a",CombatZoneState.ZONE_1)==-1 and zones.direction("b",CombatZoneState.ZONE_1)==1 and zones.direction("b",CombatZoneState.ZONE_3)==-1

static func _front_blocks_forward_only()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	# A and B share center. Each may retreat toward its own flag, but neither
	# may ordinary-Navigate forward through the opposing line.
	return not zones.ordinary_navigation_allowed("a",CombatZoneState.ZONE_3) and zones.ordinary_navigation_allowed("a",CombatZoneState.ZONE_1) and not zones.ordinary_navigation_allowed("b",CombatZoneState.ZONE_1) and zones.ordinary_navigation_allowed("b",CombatZoneState.ZONE_3)

static func _reach_is_zone_based()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	# Same-zone ranged attacks remain valid. Melee reaches only distance zero.
	var ranged:={"min_zone_distance":0,"max_zone_distance":2,"two_zone_hit_modifier":-50.0}
	var melee:={"min_zone_distance":0,"max_zone_distance":0}
	if not CombatReachPolicy.valid_enemy_targets("a",zones,ranged).has("b"): return false
	if not CombatReachPolicy.valid_enemy_targets("a",zones,melee).has("b"): return false
	zones.set_zone("b",CombatZoneState.ZONE_3)
	return not CombatReachPolicy.valid_enemy_targets("a",zones,melee).has("b") and CombatReachPolicy.valid_enemy_targets("a",zones,ranged).has("b") and CombatReachPolicy.distance_hit_modifier(2,ranged)==-50.0

static func _tempo_only_accepts_or_rejects_declared_move()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("b",CombatZoneState.ZONE_3)
	var resolver:=CombatMovementResolver.new(zones)
	var failed:=resolver.navigation_result("a",CombatZoneState.ZONE_1,-50.0,75)
	if bool(failed["moved"]) or String(failed["reason"])!="tempo_failed" or zones.zone_of("a")!=CombatZoneState.ZONE_2: return false
	var passed:=resolver.navigation_result("a",CombatZoneState.ZONE_1,-50.0,25)
	if not bool(passed["moved"]) or int(passed["to_zone"])!=CombatZoneState.ZONE_1: return false
	if not resolver.apply_result(passed): return false
	return zones.zone_of("a")==CombatZoneState.ZONE_1

static func _special_move_can_break_front()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	var resolver:=CombatMovementResolver.new(zones)
	var ordinary:=resolver.navigation_result("a",CombatZoneState.ZONE_3,0.0,100)
	if bool(ordinary["moved"]) or String(ordinary["reason"])!="front_blocked": return false
	var charge:=resolver.navigation_result("a",CombatZoneState.ZONE_3,0.0,100,true)
	return bool(charge["moved"]) and int(charge["to_zone"])==CombatZoneState.ZONE_3

static func _root_blocks_all_movement()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	var resolver:=CombatMovementResolver.new(zones)
	var rooted_navigation:=resolver.navigation_result("a",CombatZoneState.ZONE_1,0.0,1,false,true)
	var rooted_charge:=resolver.navigation_result("a",CombatZoneState.ZONE_3,0.0,1,true,true)
	return not bool(rooted_navigation["moved"]) and not bool(rooted_charge["moved"]) and String(rooted_charge["reason"])=="movement_locked"


static func _engine_rejects_friendly_fire_and_out_of_reach()->bool:
	var f:=_fixture()
	var state:CombatState=f["state"]
	var group:GroupCombatState=f["group"]
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("a2",CombatZoneState.ZONE_1)
	zones.set_zone("b",CombatZoneState.ZONE_3)
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),{})
	engine.configure_spatial_context(group,zones)
	var attack:=AbilityRuntime.build_action_event(state,"a","b","RANGED",{"delivery_type":"PROJECTILE","max_zone_distance":1,"components":[{"kind":"damage","amount":10.0,"damage_type":"physical"}]})
	attack.payload["target_ids"]=["a2","b"]
	state.queue_event(attack); engine.resolve_pending_events()
	return attack.result.get("resolved_target_ids",[]).is_empty() and state.get_combatant("a2").hp==100 and state.get_combatant("b").hp==100

static func _magic_hit_and_heal_follow_spatial_rules()->bool:
	var f:=_fixture()
	var state:CombatState=f["state"]
	var group:GroupCombatState=f["group"]
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("a2",CombatZoneState.ZONE_2)
	zones.set_zone("b",CombatZoneState.ZONE_3)
	state.get_combatant("a").combat_stats["hit_chance_rating_percent"]=-45.0
	state.get_combatant("a2").hp=50
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),{})
	engine.configure_spatial_context(group,zones)
	var spell:=AbilityRuntime.build_action_event(state,"a","b","SPELL",{"delivery_type":"DIRECT","max_zone_distance":2,"uses_magic_hit":true,"two_zone_hit_modifier":-50.0,"components":[{"kind":"damage","amount":10.0,"damage_type":"fire"}]})
	spell.payload["magic_hit_roll"]=1
	state.queue_event(spell); engine.resolve_pending_events()
	if state.get_combatant("b").hp!=100: return false
	var heal:=AbilityRuntime.build_action_event(state,"a","a2","HEAL",{"delivery_type":"DIRECT","max_zone_distance":1,"components":[{"kind":"heal","amount":20.0}]})
	state.queue_event(heal); engine.resolve_pending_events()
	return state.get_combatant("a2").hp==70 and heal.result.get("resolved_target_ids",[]).has("a2")


static func _movement_contest_has_no_initiative()->bool:
	var f:=_fixture()
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("b",CombatZoneState.ZONE_2)
	var resolver:=CombatMovementResolver.new(zones)
	var tied:=resolver.resolve_simultaneous([
		{"combatant_id":"a","to_zone":CombatZoneState.ZONE_2,"tempo":0.0,"tempo_roll":1,"bypass_front":true,"contest_power":20.0},
		{"combatant_id":"b","to_zone":CombatZoneState.ZONE_1,"tempo":0.0,"tempo_roll":1,"bypass_front":true,"contest_power":20.0}
	])
	if bool(tied[0].get("moved",false)) or bool(tied[1].get("moved",false)): return false
	if zones.zone_of("a")!=CombatZoneState.ZONE_1 or zones.zone_of("b")!=CombatZoneState.ZONE_2: return false
	var won:=resolver.resolve_simultaneous([
		{"combatant_id":"a","to_zone":CombatZoneState.ZONE_2,"tempo":0.0,"tempo_roll":1,"bypass_front":true,"contest_power":30.0},
		{"combatant_id":"b","to_zone":CombatZoneState.ZONE_1,"tempo":0.0,"tempo_roll":1,"bypass_front":true,"contest_power":20.0}
	])
	return bool(won[0].get("moved",false)) and not bool(won[1].get("moved",false)) and zones.zone_of("a")==CombatZoneState.ZONE_2 and zones.zone_of("b")==CombatZoneState.ZONE_2


static func _physical_projectile_distance_penalizes_hit()->bool:
	var f:=_fixture()
	var state:CombatState=f["state"]
	var group:GroupCombatState=f["group"]
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("b",CombatZoneState.ZONE_3)
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),{})
	engine.configure_spatial_context(group,zones)
	var attack:=AbilityRuntime.build_action_event(state,"a","b","BOW_SHOT",{
		"delivery_type":"PROJECTILE",
		"max_zone_distance":2,
		"two_zone_hit_modifier":-50.0,
		"rolls":{"hit":50},
		"components":[{"kind":"damage","amount":10.0,"damage_type":"slashing"}]
	})
	state.queue_event(attack); engine.resolve_pending_events()
	var attack_event:CombatEvent=null
	for logged in state.event_log:
		if logged.parent_event_id==attack.event_id and logged.kind==CombatEvent.Kind.ATTACK:
			attack_event=logged
			break
	return attack_event!=null and String(attack_event.result.get("outcome",""))=="miss" and float(attack_event.result.get("distance_hit_modifier",0.0))==-50.0 and state.get_combatant("b").hp==100


static func _zone_target_magic_hit_uses_zone_distance()->bool:
	var f:=_fixture()
	var state:CombatState=f["state"]
	var group:GroupCombatState=f["group"]
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("b",CombatZoneState.ZONE_3)
	state.get_combatant("a").combat_stats["hit_chance_rating_percent"]=-20.0
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),{})
	engine.configure_spatial_context(group,zones)
	var spell:=AbilityRuntime.build_action_event(state,"a","b","ZONE_SPELL",{
		"delivery_type":"AREA",
		"max_zone_distance":2,
		"uses_magic_hit":true,
		"two_zone_hit_modifier":-50.0,
		"target_zone_id":CombatZoneState.ZONE_3,
		"magic_hit_roll":50,
		"components":[{"kind":"damage","amount":10.0,"damage_type":"fire"}]
	})
	if int(spell.payload.get("target_zone_id",-1))!=CombatZoneState.ZONE_3: return false
	state.queue_event(spell); engine.resolve_pending_events()
	return String(spell.result.get("outcome",""))=="magic_miss" and spell.result.get("child_event_ids",[]).is_empty() and state.get_combatant("b").hp==100


static func _zone_target_resolves_current_occupants()->bool:
	var f:=_fixture()
	var state:CombatState=f["state"]
	var group:GroupCombatState=f["group"]
	var zones:CombatZoneState=f["zones"]
	zones.set_zone("a",CombatZoneState.ZONE_1)
	zones.set_zone("a2",CombatZoneState.ZONE_2)
	zones.set_zone("b",CombatZoneState.ZONE_2)
	var engine:=CombatEngine.new(TestFixtureLoader.canonicalize_state(state),{})
	engine.configure_spatial_context(group,zones)
	var spell:=AbilityRuntime.build_action_event(state,"a","","ZONE_DAMAGE",{
		"delivery_type":"AREA",
		"target_zone_id":CombatZoneState.ZONE_2,
		"max_zone_distance":2,
		"components":[{"kind":"damage","amount":10.0,"damage_type":"fire"}]
	})
	# Move the enemy after cast construction: resolution must use current zone occupancy.
	zones.set_zone("b",CombatZoneState.ZONE_3)
	state.queue_event(spell); engine.resolve_pending_events()
	if not spell.result.get("resolved_target_ids",[]).is_empty(): return false
	if state.get_combatant("a2").hp!=100 or state.get_combatant("b").hp!=100: return false
	zones.set_zone("b",CombatZoneState.ZONE_2)
	var second:=AbilityRuntime.build_action_event(state,"a","","ZONE_DAMAGE",{
		"delivery_type":"AREA",
		"target_zone_id":CombatZoneState.ZONE_2,
		"max_zone_distance":2,
		"components":[{"kind":"damage","amount":10.0,"damage_type":"fire"}]
	})
	state.queue_event(second); engine.resolve_pending_events()
	return second.result.get("resolved_target_ids",[])==["b"] and state.get_combatant("a2").hp==100 and state.get_combatant("b").hp==90
