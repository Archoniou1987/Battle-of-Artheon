class_name CounterAbiCases
extends RefCounted

## Counterattack is a selected physical ABI, never a free dodge reaction.
static func run(balance: Dictionary) -> bool:
	var cases := [
		["invalid_magic_counter", _invalid_magic_counter()],
		["requires_previous_round_trigger", _requires_previous_round_trigger(balance)],
		["counter_miss_consumes_ap", _counter_miss_consumes_ap(balance)],
		["mh_zone_head_oh_chest", _mh_zone_head_oh_chest(balance)],
		["abi_generator_earns_ap", _abi_generator_earns_ap(balance)]
	]
	var ok:=true
	for test_case in cases:
		if not bool(test_case[1]):
			print("COUNTER_ABI_CASE_FAIL=",String(test_case[0]))
			ok=false
	return ok

static func _state() -> CombatState:
	var state:=CombatState.new()
	state.add_combatant(TestFixtureLoader.new_combatant("hero","Hero",10,100))
	state.add_combatant(TestFixtureLoader.new_combatant("enemy","Enemy",10,100))
	TestFixtureLoader.canonicalize_state(state)
	state.begin_round()
	return state

static func _counter_definition(hit_roll:int=1) -> Dictionary:
	return {
		"delivery_type":"MELEE","target_scope":"SINGLE",
		"is_counterattack_abi":true,"trigger_previous_round":"block",
		"ap_cost":3,"ap_gain":0,"mana_cost":0,
		"rolls":{"hit":hit_roll,"dodge":1,"auto_block":1,"crit":100,"block_crush":1},
		"components":[{"kind":"damage","damage_type":"slashing","amount":20.0}]
	}

static func _invalid_magic_counter() -> bool:
	var bad:=_counter_definition()
	bad["components"]=[{"kind":"damage","damage_type":"fire","amount":20.0}]
	if not AbilityRuntime.validate_definition("ABI_TEST_COUNTER",bad).has("counter_abi_physical_damage_only"):
		return false
	bad=_counter_definition()
	bad["delivery_type"]="DIRECT"
	return AbilityRuntime.validate_definition("ABI_TEST_COUNTER",bad).has("counter_abi_requires_single_physical_melee")

static func _qualified_round(state:CombatState)->void:
	var previous:=state.create_event(CombatEvent.Kind.ATTACK,"enemy","hero",{"zone":"chest","damage_type":"slashing"})
	previous.set_result("outcome","manual_block")
	state.record_event(previous)
	state.begin_round()

static func _requires_previous_round_trigger(balance:Dictionary)->bool:
	var state:=_state()
	var hero:=state.get_combatant("hero")
	hero.action_points=4
	var enemy:=state.get_combatant("enemy")
	enemy.combat_stats["dodge_rating_percent"]=100.0
	enemy.combat_stats["manual_block_zones"]=["chest"]
	var definition:=_counter_definition()
	var scheduler:=AbilityScheduler.new({"ABI_TEST_COUNTER":definition},{"hero":["ABI_TEST_COUNTER"]})
	if scheduler.cast_event(state,"hero","enemy","ABI_TEST_COUNTER")!=null: return false
	if hero.action_points!=4: return false
	_qualified_round(state)
	var action:=scheduler.cast_event(state,"hero","enemy","ABI_TEST_COUNTER")
	if action==null or hero.action_points!=1 or int(action.payload.get("ap_spent",-1))!=3: return false
	# The MH zone is selected before the counter ABI is resolved.
	var mh:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":0.0,"zone":"chest","damage_type":"slashing",
		"is_weapon_attack":true,"weapon_index":0,"hit_index":0,"rolls":{"hit":100}
	})
	state.queue_event(mh)
	state.queue_event(action)
	CombatEngine.new(state,balance).resolve_pending_events()
	var counter:CombatEvent=null
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and bool(event.payload.get("is_counterattack_abi",false)):
			counter=event
	if counter==null or counter.result.get("outcome")!="connected": return false
	if counter.result.has("dodge_roll") or counter.result.has("auto_block_roll"): return false
	if enemy.hp>=100: return false
	state.begin_round()
	return not AbilityRuntime.previous_round_trigger_met(state,"hero","block")

## MH selects the counter zone; OH must never override it.
static func _mh_zone_head_oh_chest(balance:Dictionary)->bool:
	var state:=_state()
	var hero:=state.get_combatant("hero")
	hero.action_points=4
	_qualified_round(state)
	var definition:=_counter_definition()
	var scheduler:=AbilityScheduler.new({"ABI_TEST_COUNTER":definition},{"hero":["ABI_TEST_COUNTER"]})
	var action:=scheduler.cast_event(state,"hero","enemy","ABI_TEST_COUNTER")
	if action==null: return false
	var oh:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":0.0,"zone":"chest","damage_type":"slashing","is_weapon_attack":true,
		"weapon_index":1,"hit_index":0,"rolls":{"hit":100}
	})
	var mh:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":0.0,"zone":"head","damage_type":"slashing","is_weapon_attack":true,
		"weapon_index":0,"hit_index":0,"rolls":{"hit":100}
	})
	state.queue_event(oh)
	state.queue_event(action)
	state.queue_event(mh)
	CombatEngine.new(state,balance).resolve_pending_events()
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and bool(event.payload.get("is_counterattack_abi",false)):
			return String(event.payload.get("zone",""))=="head" and String(event.result.get("outcome",""))=="connected"
	return false

static func _counter_miss_consumes_ap(balance:Dictionary)->bool:
	var state:=_state()
	var hero:=state.get_combatant("hero")
	hero.action_points=4
	_qualified_round(state)
	var definition:=_counter_definition(100)
	var scheduler:=AbilityScheduler.new({"ABI_TEST_COUNTER":definition},{"hero":["ABI_TEST_COUNTER"]})
	var action:=scheduler.cast_event(state,"hero","enemy","ABI_TEST_COUNTER")
	if action==null: return false
	# The MH zone is selected before the counter ABI is resolved.
	var mh:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":0.0,"zone":"chest","damage_type":"slashing",
		"is_weapon_attack":true,"weapon_index":0,"hit_index":0,"rolls":{"hit":100}
	})
	state.queue_event(mh)
	state.queue_event(action)
	CombatEngine.new(state,balance).resolve_pending_events()
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and bool(event.payload.get("is_counterattack_abi",false)):
			return event.result.get("outcome")=="miss" and hero.action_points==1 and state.get_combatant("enemy").hp==100
	return false

static func _abi_generator_earns_ap(balance:Dictionary)->bool:
	var state:=_state()
	var hero:=state.get_combatant("hero")
	var generator:Dictionary={
		"delivery_type":"MELEE","target_scope":"SINGLE","ap_gain":1,
		"rolls":{"hit":100},"components":[{"kind":"damage","damage_type":"slashing","amount":10.0}]
	}
	var scheduler:=AbilityScheduler.new({"ABI_GEN":generator},{"hero":["ABI_GEN"]})
	var action:=scheduler.cast_event(state,"hero","enemy","ABI_GEN")
	if action==null or hero.action_points!=1 or int(action.payload.get("ap_gained",0))!=1:
		return false
	state.queue_event(action)
	CombatEngine.new(state,balance).resolve_pending_events()
	return hero.action_points==1 and state.get_combatant("enemy").hp==100
