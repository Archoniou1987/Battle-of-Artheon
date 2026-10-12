class_name CombatApiCases
extends RefCounted

static func run()->bool:
	var state:=CombatState.new()
	var hero:=CombatantState.new("hero","Hero",10,100)
	var enemy:=CombatantState.new("enemy","Enemy",9,80)
	hero.hp=-5
	hero.tempo=10.0
	hero.combat_stats["tempo"]=5.0
	hero.combat_stats["damage_reduction"]=0.25
	hero.active_effects.append({
		"effect_id":"EFF_API",
		"definition":{"tempo":15.0,"damage_reduction":0.25},
		"start_round":1,
		"remaining_rounds":1
	})
	state.add_combatant(hero); state.add_combatant(enemy)
	state.begin_round()
	var group:=GroupCombatState.new(state)
	group.add_member("A","hero"); group.add_member("B","enemy")
	group.set_active_opponent("hero","enemy")
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone("hero",CombatZoneState.ZONE_1)
	zones.set_zone("enemy",CombatZoneState.ZONE_2)
	var api:=CombatApi.new(state,group,zones)
	var hero_view:=api.combatant("hero")
	if int(hero_view.get("hp",-1))!=0 or int(hero_view.get("hp_internal",0))!=-5: return false
	if not is_equal_approx(float(hero_view.get("tempo",0.0)),30.0): return false
	var combat_stats:Dictionary=hero_view.get("combat_stats",{})
	if not is_equal_approx(float(combat_stats.get("effective_tempo",0.0)),30.0): return false
	if not is_equal_approx(float(combat_stats.get("damage_reduction",0.0)),0.5): return false
	if String(hero_view.get("active_opponent_id",""))!="enemy": return false
	if int(hero_view.get("zone_id",-1))!=CombatZoneState.ZONE_1: return false
	var targets:=api.target_options("hero")
	if String(targets.get("active",""))!="enemy": return false
	var snap:=api.snapshot()
	if snap.get("combatants",[]).size()!=2: return false
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"raw_damage":1.0})
	event.set_result("outcome","miss"); state.record_event(event)
	var events:=api.recent_events()
	return events.size()==1 and String(events[0].get("outcome",""))=="miss"
