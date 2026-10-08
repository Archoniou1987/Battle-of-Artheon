class_name CombatCommandApiCases
extends RefCounted

static func run()->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",10,100,10)
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
	var scheduler:=AbilityScheduler.new({"RANGED":{"delivery_type":"DIRECT","min_zone_distance":0,"max_zone_distance":1,"mana_cost":5,"cooldown_rounds":2,"components":[{"kind":"damage","amount":7,"damage_type":"fire"}]}},{"hero":["RANGED"]})
	scheduler.cooldowns_by_combatant["hero"]={"COOLDOWN":state.round_number+2}
	var api:=CombatCommandApi.new(state,group,zones,orchestrator,scheduler)
	if not bool(api.select_active_opponent("hero","enemy",{"max_zone_distance":1}).get("ok",false)): return false
	if bool(api.basic_attack_intent("hero").get("ok",true)): return false
	if not bool(api.ability_intent("hero","enemy",{"min_zone_distance":0,"max_zone_distance":1}).get("ok",false)): return false
	var actions:=api.available_actions("hero",{
		"RANGED":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":5},
		"MELEE":{"min_zone_distance":0,"max_zone_distance":0,"mana_cost":0},
		"EXPENSIVE":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":20},
		"COOLDOWN":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":0}
	})
	if bool(actions.get("basic_attack",true)): return false
	if not Array(actions.get("navigation",[])).has(CombatZoneState.ZONE_2): return false
	var ability_views:Dictionary=actions.get("abilities",{})
	var ranged:Dictionary=ability_views.get("RANGED",{})
	if not bool(ranged.get("available",false)) or not Array(ranged.get("targets",[])).has("enemy"): return false
	if bool(Dictionary(ability_views.get("MELEE",{})).get("available",true)): return false
	if bool(Dictionary(ability_views.get("EXPENSIVE",{})).get("resource_ready",true)): return false
	if bool(Dictionary(ability_views.get("COOLDOWN",{})).get("cooldown_ready",true)): return false
	if not bool(api.set_manual_block("hero",["chest","arms"]).get("ok",false)): return false
	if Array(hero.combat_stats.get("manual_block_zones",[])).size()!=2: return false
	if not bool(api.clear_manual_block("hero").get("ok",false)): return false
	if hero.combat_stats.has("manual_block_zones"): return false
	var cast_result:=api.cast_ability("hero","enemy","RANGED")
	if not bool(cast_result.get("ok",false)) or hero.mana!=5: return false
	engine.resolve_pending_events()
	if enemy.hp!=93: return false
	if AbilityRuntime.can_use("RANGED",scheduler.cooldowns_by_combatant.get("hero",{}),state.round_number+1): return false
	var second_cast:=api.cast_ability("hero","enemy","RANGED")
	if bool(second_cast.get("ok",true)): return false
	var movement:=api.request_navigation("hero",CombatZoneState.ZONE_2,1)
	if not bool(movement.get("ok",false)): return false
	var results:=orchestrator.resolve_movement_phase()
	return results.size()==1 and bool(results[0].get("moved",false)) and zones.zone_of("hero")==CombatZoneState.ZONE_2
