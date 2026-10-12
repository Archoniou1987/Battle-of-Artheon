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
	var scheduler:=AbilityScheduler.new({
		"RANGED":{"delivery_type":"DIRECT","min_zone_distance":0,"max_zone_distance":1,"mana_cost":5,"cooldown_rounds":2,"components":[{"kind":"damage","amount":7,"damage_type":"fire"}]},
		"ZONE":{"delivery_type":"AREA","target_scope":"ALL_ENEMIES","min_zone_distance":0,"max_zone_distance":2,"mana_cost":1,"components":[{"kind":"damage","amount":4,"damage_type":"fire"}]}
	},{"hero":["RANGED","ZONE"]})
	scheduler.cooldowns_by_combatant["hero"]={"COOLDOWN":state.round_number+2}
	var api:=CombatCommandApi.new(state,group,zones,orchestrator,scheduler)
	hero.combat_stats["weapon_profiles"]=[{
		"damage_min":8.0,"damage_max":10.0,"damage_type":"blunt",
		"attack_profiles":[
			{"id":"staff_strike","delivery_type":"MELEE","min_zone_distance":0,"max_zone_distance":0},
			{"id":"arcane_bolt","delivery_type":"PROJECTILE","min_zone_distance":0,"max_zone_distance":2,"damage_min":6.0,"damage_max":6.0,"damage_type":"fire","uses_magic_hit":true}
		]
	}]
	if not bool(api.select_active_opponent("hero","enemy",{"max_zone_distance":1}).get("ok",false)): return false
	if bool(api.basic_attack_intent("hero","staff_strike").get("ok",true)): return false
	if not bool(api.basic_attack_intent("hero","arcane_bolt").get("ok",false)): return false
	enemy.combat_stats["dodge"]=100.0
	var ranged_basic:=api.queue_basic_attack("hero",{"hit":100,"magic_hit":1,"dodge":1,"crit":100},"arcane_bolt",0)
	if not bool(ranged_basic.get("ok",false)): return false
	engine.resolve_pending_events()
	if enemy.hp!=94: return false
	var ranged_event:CombatEvent=state.event_log.back()
	# Damage event resolves after the attack; locate the parent attack and verify it used Magic Hit.
	for logged_event in state.event_log:
		if logged_event.event_id==int(ranged_basic.get("event_id",-1)):
			ranged_event=logged_event
			break
	if String(ranged_event.result.get("hit_system",""))!="magic": return false
	if String(ranged_event.result.get("outcome",""))!="connected": return false
	enemy.combat_stats["dodge"]=0.0
	var zone_cast:=api.cast_zone_ability("hero",CombatZoneState.ZONE_2,"ZONE")
	if not bool(zone_cast.get("ok",false)) or int(zone_cast.get("target_zone_id",-1))!=CombatZoneState.ZONE_2: return false
	var zone_event:CombatEvent=state.pending_events.back()
	if int(zone_event.payload.get("target_zone_id",-1))!=CombatZoneState.ZONE_2: return false
	if hero.mana!=9: return false
	if not bool(api.ability_intent("hero","enemy",{"min_zone_distance":0,"max_zone_distance":1}).get("ok",false)): return false
	var actions:=api.available_actions("hero",{
		"RANGED":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":5},
		"MELEE":{"min_zone_distance":0,"max_zone_distance":0,"mana_cost":0},
		"EXPENSIVE":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":20},
		"COOLDOWN":{"min_zone_distance":0,"max_zone_distance":1,"mana_cost":0}
	})
	if not bool(actions.get("basic_attack",false)): return false
	if Array(actions.get("body_zones",[]))!=["head","chest","arms","waist","legs"]: return false
	if String(actions.get("default_body_zone",""))!="chest": return false
	# Ambiguous weapon profiles without an explicit default expose no automatic sequence.
	if not Array(actions.get("default_weapon_attack_sequence",[])).is_empty(): return false
	var invalid_zone:=api.queue_basic_attack("hero",{"zone":"hands"},"arcane_bolt",0)
	if bool(invalid_zone.get("ok",true)) or String(invalid_zone.get("reason",""))!="invalid_body_zone": return false
	var basic_attacks:Array=actions.get("basic_attacks",[])
	if basic_attacks.size()!=1 or String(Dictionary(basic_attacks[0]).get("id",""))!="arcane_bolt": return false
	if not Array(actions.get("navigation",[])).has(CombatZoneState.ZONE_2): return false
	var ability_views:Dictionary=actions.get("abilities",{})
	var ranged:Dictionary=ability_views.get("RANGED",{})
	if not bool(ranged.get("available",false)) or not Array(ranged.get("targets",[])).has("enemy"): return false
	if bool(Dictionary(ability_views.get("MELEE",{})).get("available",true)): return false
	if bool(Dictionary(ability_views.get("EXPENSIVE",{})).get("resource_ready",true)): return false
	if bool(Dictionary(ability_views.get("COOLDOWN",{})).get("cooldown_ready",true)): return false
	hero.combat_stats["manual_block_zone_capacity"]=2
	if bool(api.set_manual_block("hero",["head","arms"]).get("ok",true)): return false
	if not bool(api.set_manual_block("hero",["chest","arms"]).get("ok",false)): return false
	if Array(hero.combat_stats.get("manual_block_zones",[])).size()!=2: return false
	if not bool(api.clear_manual_block("hero").get("ok",false)): return false
	if hero.combat_stats.has("manual_block_zones"): return false
	var cast_result:=api.cast_ability("hero","enemy","RANGED")
	if not bool(cast_result.get("ok",false)): return false
	if hero.mana!=4: return false
	engine.resolve_pending_events()
	if enemy.hp!=83: return false
	if AbilityRuntime.can_use("RANGED",scheduler.cooldowns_by_combatant.get("hero",{}),state.round_number+1): return false
	var second_cast:=api.cast_ability("hero","enemy","RANGED")
	if bool(second_cast.get("ok",true)): return false
	var movement:=api.request_navigation("hero",CombatZoneState.ZONE_2,1)
	if not bool(movement.get("ok",false)): return false
	var results:=orchestrator.resolve_movement_phase()
	if results.size()!=1 or not bool(results[0].get("moved",false)) or zones.zone_of("hero")!=CombatZoneState.ZONE_2: return false
	var attack:=api.queue_basic_attack("hero",{"hit":1,"dodge":100,"crit":100,"damage":0.0},"staff_strike")
	if not bool(attack.get("ok",false)): return false
	engine.resolve_pending_events()
	if enemy.hp!=75: return false
	# Physical projectile profiles (bows) keep the physical Hit/Dodge path and distance penalty.
	zones.set_zone("hero",CombatZoneState.ZONE_1)
	zones.set_zone("enemy",CombatZoneState.ZONE_3)
	hero.combat_stats["weapon_profiles"]=[{
		"damage_min":5.0,"damage_max":7.0,"damage_type":"piercing",
		"attack_profiles":[{"id":"bow_shot","delivery_type":"PROJECTILE","min_zone_distance":1,"max_zone_distance":2,"two_zone_hit_modifier":-50.0}]
	}]
	enemy.combat_stats["dodge"]=100.0
	var bow_attack:=api.queue_basic_attack("hero",{"hit":1,"dodge":1,"crit":100,"damage":0.0},"bow_shot",0)
	if not bool(bow_attack.get("ok",false)): return false
	engine.resolve_pending_events()
	var bow_event:CombatEvent=state.event_log.back()
	for logged_event in state.event_log:
		if logged_event.event_id==int(bow_attack.get("event_id",-1)):
			bow_event=logged_event
			break
	if String(bow_event.result.get("hit_system",""))!="physical": return false
	if float(bow_event.result.get("distance_hit_modifier",0.0))!=-50.0: return false
	if String(bow_event.result.get("outcome",""))!="dodge": return false
	if enemy.hp!=75: return false
	enemy.combat_stats["dodge"]=0.0
	# Multi-hit is profile-driven: every hit gets an independent combat roll chain.
	zones.set_zone("hero",CombatZoneState.ZONE_2)
	zones.set_zone("enemy",CombatZoneState.ZONE_2)
	hero.combat_stats["weapon_profiles"]=[{
		"damage_min":4.0,"damage_max":4.0,"damage_type":"slashing",
		"attack_profiles":[{"id":"dual_slash","delivery_type":"MELEE","hit_count":2}]
	}]
	enemy.combat_stats["dodge"]=50.0
	var multi:=api.queue_basic_attack("hero",{
		"hits":[
			{"hit":1,"dodge":1,"crit":100,"damage":0.0},
			{"hit":1,"dodge":100,"crit":100,"damage":0.0}
		]
	},"dual_slash",0)
	if not bool(multi.get("ok",false)): return false
	if int(multi.get("hit_count",0))!=2 or Array(multi.get("event_ids",[])).size()!=2: return false
	engine.resolve_pending_events()
	if enemy.hp!=71: return false
	var multi_outcomes:Array[String]=[]
	for logged_event in state.event_log:
		if Array(multi.get("event_ids",[])).has(logged_event.event_id):
			multi_outcomes.append(String(logged_event.result.get("outcome","")))
	if multi_outcomes.size()!=2 or multi_outcomes[0]!="dodge" or multi_outcomes[1]!="connected": return false
	# One Base Attack action grants AP once even when its profile contains multiple hits.
	var multi_ap_events:=0
	for logged_event in state.event_log:
		if Array(multi.get("event_ids",[])).has(logged_event.event_id) and int(logged_event.result.get("ap_gained",0))>0:
			multi_ap_events+=1
	if multi_ap_events!=1: return false
	# Per-hit body zones are validated before any multi-hit event is queued.
	var nested_pending_before:=state.pending_events.size()
	var invalid_nested:=api.queue_basic_attack("hero",{"hits":[{"zone":"head"},{"zone":"hands"}]},"dual_slash",0)
	if bool(invalid_nested.get("ok",true)) or String(invalid_nested.get("reason",""))!="invalid_body_zone": return false
	if int(invalid_nested.get("hit_index",-1))!=1 or state.pending_events.size()!=nested_pending_before: return false
	enemy.combat_stats["dodge"]=0.0
	# MH/OH are independent weapon attacks and may target different body zones.
	hero.combat_stats["weapon_profiles"]=[
		{"damage_min":3.0,"damage_max":3.0,"damage_type":"slashing","attack_profiles":[{"id":"weapon_slash","delivery_type":"MELEE"}]},
		{"damage_min":5.0,"damage_max":5.0,"damage_type":"chopping","attack_profiles":[{"id":"weapon_chop","delivery_type":"MELEE"}]}
	]
	var weapon_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","zone":"chest","rolls":{"hit":1,"dodge":100,"crit":100,"damage":0.0}},
		{"weapon_index":1,"attack_profile_id":"weapon_chop","zone":"arms","rolls":{"hit":1,"dodge":100,"crit":100,"damage":0.0}}
	])
	if not bool(weapon_sequence.get("ok",false)) or int(weapon_sequence.get("attack_count",0))!=2: return false
	if Array(weapon_sequence.get("event_ids",[])).size()!=2: return false
	engine.resolve_pending_events()
	if enemy.hp!=63: return false
	var sequence_zones:Array[String]=[]
	var sequence_weapons:Array[int]=[]
	for logged_event in state.event_log:
		if Array(weapon_sequence.get("event_ids",[])).has(logged_event.event_id):
			sequence_zones.append(String(logged_event.payload.get("zone","")))
			sequence_weapons.append(int(logged_event.payload.get("weapon_index",-1)))
	if sequence_zones!=["chest","arms"] or sequence_weapons!=[0,1]: return false
	var sequence_ap_events:=0
	for logged_event in state.event_log:
		if Array(weapon_sequence.get("event_ids",[])).has(logged_event.event_id) and int(logged_event.result.get("ap_gained",0))>0:
			sequence_ap_events+=1
	if sequence_ap_events!=1: return false
	# AP follows the first connected constituent, not merely the first queued hit.
	# MH may miss while OH connects: the action must still earn exactly one AP.
	var ap_before_fallback:=hero.action_points
	var fallback_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","rolls":{"hit":100,"dodge":100,"crit":100,"damage":0.0}},
		{"weapon_index":1,"attack_profile_id":"weapon_chop","rolls":{"hit":1,"dodge":100,"crit":100,"damage":0.0}}
	])
	if not bool(fallback_sequence.get("ok",false)):
		print("COMMAND_AP_FALLBACK queue=",fallback_sequence)
		return false
	engine.resolve_pending_events()
	if hero.action_points!=ap_before_fallback+1: return false
	var fallback_ap_events:=0
	for logged_event in state.event_log:
		if Array(fallback_sequence.get("event_ids",[])).has(logged_event.event_id) and int(logged_event.result.get("ap_gained",0))>0:
			fallback_ap_events+=1
	if fallback_ap_events!=1: return false
	# Normal Base Attack derives one default attack per equipped weapon automatically.
	var automatic:=api.queue_default_weapon_attacks("hero",{
		0:{"zone":"head","hit":1,"dodge":100,"crit":100,"damage":0.0},
		1:{"zone":"legs","hit":1,"dodge":100,"crit":100,"damage":0.0}
	})
	if not bool(automatic.get("ok",false)) or int(automatic.get("attack_count",0))!=2: return false
	engine.resolve_pending_events()
	# The fallback sequence above dealt another 5 damage before this 8-damage automatic sequence.
	if enemy.hp!=50: return false
	var automatic_weapons:Array[int]=[]
	var automatic_zones:Array[String]=[]
	for logged_event in state.event_log:
		if Array(automatic.get("event_ids",[])).has(logged_event.event_id):
			automatic_weapons.append(int(logged_event.payload.get("weapon_index",-1)))
			automatic_zones.append(String(logged_event.payload.get("zone","")))
	if automatic_weapons!=[0,1] or automatic_zones!=["head","legs"]: return false
	# Multiple profiles require an explicit default; never guess between e.g. staff strike and bolt.
	hero.combat_stats["weapon_profiles"]=[{
		"damage_min":8.0,"damage_max":10.0,"damage_type":"blunt",
		"attack_profiles":[
			{"id":"staff_strike","delivery_type":"MELEE"},
			{"id":"arcane_bolt","delivery_type":"PROJECTILE","max_zone_distance":2}
		]
	}]
	var no_default:=api.default_weapon_attack_sequence("hero")
	if bool(no_default.get("ok",true)) or String(no_default.get("reason",""))!="no_default_weapon_attacks": return false
	hero.combat_stats["weapon_profiles"][0]["attack_profiles"][0]["is_default"]=true
	var explicit_default:=api.default_weapon_attack_sequence("hero")
	if not bool(explicit_default.get("ok",false)): return false
	var default_attacks:Array=explicit_default.get("attacks",[])
	if default_attacks.size()!=1 or String(Dictionary(default_attacks[0]).get("attack_profile_id",""))!="staff_strike": return false
	# Restore independent weapons for sequence atomicity and shield coverage.
	hero.combat_stats["weapon_profiles"]=[
		{"damage_min":3.0,"damage_max":3.0,"damage_type":"slashing","attack_profiles":[{"id":"weapon_slash","delivery_type":"MELEE"}]},
		{"damage_min":5.0,"damage_max":5.0,"damage_type":"chopping","attack_profiles":[{"id":"weapon_chop","delivery_type":"MELEE"}]}
	]
	# Body-zone validation is also atomic across an MH/OH sequence.
	var zone_pending_before:=state.pending_events.size()
	var rejected_zone_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","zone":"head"},
		{"weapon_index":1,"attack_profile_id":"weapon_chop","zone":"hands"}
	])
	if bool(rejected_zone_sequence.get("ok",true)) or String(rejected_zone_sequence.get("attack_reason",""))!="invalid_body_zone": return false
	if state.pending_events.size()!=zone_pending_before: return false
	# Nested per-hit zones are equally atomic across the complete MH/OH sequence.
	var nested_sequence_pending_before:=state.pending_events.size()
	var rejected_nested_zone_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","rolls":{"hits":[{"zone":"head"}]}},
		{"weapon_index":1,"attack_profile_id":"weapon_chop","rolls":{"hits":[{"zone":"hands"}]}}
	])
	if bool(rejected_nested_zone_sequence.get("ok",true)) or String(rejected_nested_zone_sequence.get("attack_reason",""))!="invalid_body_zone": return false
	if int(rejected_nested_zone_sequence.get("attack_index",-1))!=1 or int(rejected_nested_zone_sequence.get("hit_index",-1))!=0: return false
	if state.pending_events.size()!=nested_sequence_pending_before: return false
	# Sequence validation is atomic: an invalid OH/profile cannot leave MH queued.
	var pending_before:=state.pending_events.size()
	var rejected_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","rolls":{"hit":1}},
		{"weapon_index":1,"attack_profile_id":"missing_profile","rolls":{"hit":1}}
	])
	if bool(rejected_sequence.get("ok",true)): return false
	if state.pending_events.size()!=pending_before: return false
	if not Array(rejected_sequence.get("queued_event_ids",[])).is_empty(): return false
	# Shield sectors block only their explicit contiguous zones; open zones continue through defence.
	enemy.combat_stats["manual_block_zone_capacity"]=2
	enemy.combat_stats["manual_block_zones"]=["chest","arms"]
	enemy.combat_stats["auto_block"]=0.0
	var shield_sequence:=api.queue_weapon_attack_sequence("hero",[
		{"weapon_index":0,"attack_profile_id":"weapon_slash","zone":"chest","rolls":{"hit":1,"dodge":100,"block_crush":100,"crit":100,"damage":0.0}},
		{"weapon_index":1,"attack_profile_id":"weapon_chop","zone":"waist","rolls":{"hit":1,"dodge":100,"auto_block":100,"crit":100,"damage":0.0}}
	])
	if not bool(shield_sequence.get("ok",false)): return false
	engine.resolve_pending_events()
	if enemy.hp!=45: return false
	var shield_outcomes:Array[String]=[]
	for logged_event in state.event_log:
		if Array(shield_sequence.get("event_ids",[])).has(logged_event.event_id):
			shield_outcomes.append(String(logged_event.result.get("outcome","")))
	if shield_outcomes!=["manual_block","connected"]: return false
	enemy.combat_stats.erase("manual_block_zones")
	# Restore the staff fixture before duplicate-profile selection coverage.
	hero.combat_stats["weapon_profiles"]=[{
		"damage_min":8.0,"damage_max":10.0,"damage_type":"blunt",
		"attack_profiles":[
			{"id":"staff_strike","delivery_type":"MELEE","min_zone_distance":0,"max_zone_distance":0},
			{"id":"arcane_bolt","delivery_type":"PROJECTILE","min_zone_distance":0,"max_zone_distance":2,"damage_min":6.0,"damage_max":6.0,"damage_type":"fire","uses_magic_hit":true}
		]
	}]
	zones.set_zone("hero",CombatZoneState.ZONE_2)
	zones.set_zone("enemy",CombatZoneState.ZONE_2)
	# Duplicate profile ids across weapons must never silently select the first weapon.
	hero.combat_stats["weapon_profiles"].append({
		"damage_min":3.0,"damage_max":3.0,"damage_type":"piercing",
		"attack_profiles":[{"id":"arcane_bolt","delivery_type":"PROJECTILE","min_zone_distance":0,"max_zone_distance":2}]
	})
	var ambiguous:=api.basic_attack_intent("hero","arcane_bolt")
	if bool(ambiguous.get("ok",true)) or String(ambiguous.get("reason",""))!="ambiguous_attack_profile": return false
	var offhand_intent:=api.basic_attack_intent("hero","arcane_bolt",1)
	if not bool(offhand_intent.get("ok",false)) or int(offhand_intent.get("weapon_index",-1))!=1: return false
	var mainhand_intent:=api.basic_attack_intent("hero","arcane_bolt",0)
	if not bool(mainhand_intent.get("ok",false)) or int(mainhand_intent.get("weapon_index",-1))!=0: return false
	# Damage range rolls are deterministic when supplied, so replay/CI can cover both bounds.
	if CombatMath.roll_damage(8.0,10.0,0.0)!=8.0: return false
	if CombatMath.roll_damage(8.0,10.0,1.0)!=10.0: return false
	return CombatMath.roll_damage(8.0,10.0,0.5)==9.0
