class_name CombatCommandApiCases
extends RefCounted

static func run()->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",10,100)
	var enemy:=CombatantState.new("enemy","Enemy",10,100)
	state.add_combatant(hero)
	state.add_combatant(enemy)
	var group:=GroupCombatState.new(state)
	group.add_member("A","hero")
	group.add_member("B","enemy")
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("hero",CombatZoneState.ZONE_1)
	zones.set_zone("enemy",CombatZoneState.ZONE_2)
	var engine:=CombatEngine.new(state,{})
	var orchestrator:=RoundOrchestrator.new(state,engine,group,zones)
	orchestrator.begin_round()
	var api:=CombatCommandApi.new(state,group,zones,orchestrator)
	if not bool(api.select_active_opponent("hero","enemy",{"max_zone_distance":1}).get("ok",false)): return false
	if bool(api.basic_attack_intent("hero").get("ok",true)): return false
	if not bool(api.ability_intent("hero","enemy",{"min_zone_distance":0,"max_zone_distance":1}).get("ok",false)): return false
	var movement:=api.request_navigation("hero",CombatZoneState.ZONE_2,1)
	if not bool(movement.get("ok",false)): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and bool(results[0].get("moved",false)) and zones.zone_of("hero")==CombatZoneState.ZONE_2
