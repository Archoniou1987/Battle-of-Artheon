class_name PhysicalAttackCases
extends RefCounted

## Deterministic smoke cases for the physical attack pipeline.

static func run(balance: Dictionary) -> bool:
	var cases := [
		["miss", _case_miss(balance)],
		["dodge", _case_dodge(balance)],
		["manual_block", _case_block(balance)],
		["dodge_does_not_generate_counter", _case_dodge_no_auto_counter(balance)],
		["counter_abi_hit_miss", _case_counter_abi_miss(balance)],
		["counter_abi_bypasses_dodge_block_not_armour", _case_counter_abi_defence(balance)],
		["weapon_skill_penalty_uses_canonical_profile", _case_weapon_skill_penalty_uses_canonical_profile(balance)],
		["magic_weapon_completes_weapon_pipeline", _case_magic_weapon_completes_weapon_pipeline(balance)],
		["independent_on_hit_sources", _case_independent_on_hit_sources(balance)],
		["connected_zero_damage", _case_connected_zero_damage(balance)],
		["manual_block_requires_canonical_zones", _case_manual_block_requires_canonical_zones(balance)]
	]
	var ok := true
	for case_result in cases:
		if not bool(case_result[1]):
			print("PHYSICAL_ATTACK_CASE_FAIL=", String(case_result[0]))
			ok = false
	return ok


static func _base_state() -> CombatState:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("hero", "Hero", 10, 100)
	var defender := TestFixtureLoader.new_combatant("enemy", "Enemy", 10, 100)
	state.add_combatant(attacker)
	state.add_combatant(defender)
	state.begin_round()
	return state


static func _attack(state: CombatState, rolls: Dictionary, damage: float = 20.0) -> CombatEvent:
	return state.create_event(
		CombatEvent.Kind.ATTACK,
		"hero",
		"enemy",
		{"raw_damage": damage, "zone": "chest", "damage_type": "slashing", "rolls": rolls}
	)


static func _case_miss(balance: Dictionary) -> bool:
	var state := _base_state()
	var event := _attack(state, {"hit": 100})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state), balance).resolve_event(event)
	return event.result.get("outcome") == "miss" and state.get_combatant("enemy").hp == 100


static func _case_dodge(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["dodge_rating_percent"] = 40.0
	var event := _attack(state, {"hit": 1, "dodge": 1})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state), balance).resolve_event(event)
	return event.result.get("outcome") == "dodge" and state.get_combatant("enemy").hp == 100


static func _case_block(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["manual_block_zones"] = ["chest"]
	var event := _attack(state, {"hit": 1, "block_crush": 100})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state), balance).resolve_event(event)
	return event.result.get("outcome") == "manual_block" and state.get_combatant("enemy").hp == 100


## A dodge is purely defensive; it never schedules a free counterattack.
static func _case_dodge_no_auto_counter(balance:Dictionary)->bool:
	var state:=_base_state()
	var attacker:=state.get_combatant("hero")
	attacker.combat_stats["dodge_rating_percent"]=100.0
	var incoming:=state.create_event(CombatEvent.Kind.ATTACK,"enemy","hero",{
		"raw_damage":10.0,"zone":"chest","damage_type":"slashing",
		"rolls":{"hit":1,"dodge":1,"crit":100}
	})
	state.queue_event(incoming)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_pending_events()
	return incoming.result.get("outcome")=="dodge" and state.event_log.size()==1 and state.pending_events.is_empty()

## Counter ABI still makes the standard Hit roll, and misses consume the attempt.
static func _case_counter_abi_miss(balance:Dictionary)->bool:
	var state:=_base_state()
	var defender:=state.get_combatant("enemy")
	defender.combat_stats["dodge_rating_percent"]=100.0
	defender.combat_stats["manual_block_zones"]=["chest"]
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":20.0,"zone":"chest","damage_type":"slashing",
		"source_kind":"ability","is_counterattack_abi":true,"uses_physical_block":true,
		"rolls":{"hit":100,"dodge":1,"auto_block":1,"crit":100}
	})
	state.queue_event(event)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_pending_events()
	return event.result.get("outcome")=="miss" and defender.hp==100 and not event.result.has("damage_event_id")

## A connected counter ABI bypasses both active defences, but retains armour.
static func _case_counter_abi_defence(balance:Dictionary)->bool:
	var state:=_base_state()
	var defender:=state.get_combatant("enemy")
	defender.combat_stats["dodge_rating_percent"]=100.0
	defender.combat_stats["manual_block_zones"]=["chest"]
	defender.armour["chest"]={"slashing":5000.0}
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":20.0,"zone":"chest","damage_type":"slashing",
		"source_kind":"ability","is_counterattack_abi":true,"uses_physical_block":true,
		"rolls":{"hit":1,"dodge":1,"auto_block":1,"crit":100}
	})
	state.queue_event(event)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_pending_events()
	var connected:bool = String(event.result.get("outcome", "")) == "connected"
	var bypassed:bool = not event.result.has("dodge_chance") and not event.result.has("auto_block_roll") and not event.result.has("block_crush_roll")
	var mitigated:bool = float(event.result.get("after_armour_damage",-1.0)) < 20.0
	return connected and bypassed and mitigated and defender.hp>80

static func _case_weapon_skill_penalty_uses_canonical_profile(balance:Dictionary)->bool:
	var state:=_base_state()
	var attacker:=state.get_combatant("hero")
	TestFixtureLoader.set_weapon_profiles(attacker, [{
		"weapon_class":"sword","item_level":90,"damage_min":10.0,"damage_max":10.0,"damage_type":"slashing",
		"attack_profiles":[{"id":"heavy_sword","delivery_type":"MELEE"}]
	}])
	attacker.set_weapon_progress("sword",10)
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":10.0,"zone":"chest","damage_type":"slashing","weapon_index":0,"is_weapon_attack":true,
		"rolls":{"hit":50,"dodge":100,"crit":100}
	})
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_event(event)
	return String(event.result.get("outcome",""))=="miss" and is_equal_approx(float(event.result.get("weapon_skill_hit_penalty",0.0)),80.0)

static func _case_magic_weapon_completes_weapon_pipeline(balance:Dictionary)->bool:
	var state:=_base_state()
	var attacker:=state.get_combatant("hero")
	attacker.combat_stats["hit_chance_rating_percent"]=100.0
	attacker.combat_stats["weapon_on_hit_effects"]=[{"chance":100.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"magic_weapon","weapon_index":0}]
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":5.0,"damage_type":"fire","zone":"chest","weapon_index":0,"is_weapon_attack":true,
		"uses_magic_hit":true,"bypass_physical_mitigation":true,"generates_ap":true,
		"rolls":{"magic_hit":1,"on_hit_effect":1}
	})
	state.queue_event(event)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_pending_events()
	if int(event.result.get("ap_gained",0))!=0: return false
	for logged in state.event_log:
		if logged.kind==CombatEvent.Kind.EFFECT and String(logged.payload.get("source_instance_id",""))=="magic_weapon":
			return true
	return false

static func _case_independent_on_hit_sources(balance:Dictionary)->bool:
	var state:=_base_state()
	var attacker:=state.get_combatant("hero")
	attacker.combat_stats["weapon_on_hit_effects"]=[
		{"chance":20.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"weapon_mh","weapon_index":0},
		{"chance":20.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"ring_a","weapon_index":-1},
		{"chance":20.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"ring_b","weapon_index":-1},
		{"chance":100.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"weapon_oh","weapon_index":1}
	]
	var event:=state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{
		"raw_damage":1.0,"zone":"chest","damage_type":"slashing","weapon_index":0,"is_weapon_attack":true,
		"rolls":{"hit":1,"dodge":100,"crit":100,"on_hit_effects":[100,1,100]}
	})
	state.queue_event(event)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state),balance).resolve_pending_events()
	var sources:Array[String]=[]
	for logged in state.event_log:
		if logged.kind==CombatEvent.Kind.EFFECT and logged.parent_event_id==event.event_id:
			sources.append(String(logged.payload.get("source_instance_id","")))
	# MH fails its own 20% roll, ring A succeeds, ring B fails. OH is ineligible.
	return sources==["ring_a"]


static func _case_connected_zero_damage(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").armour["chest"] = {"slashing": 5000.0}
	var event := _attack(state, {"hit": 1, "crit": 100}, 0.5)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state), balance)
	state.queue_event(event)
	engine.resolve_pending_events()
	if state.event_log.size() != 2:
		return false
	var damage_event: CombatEvent = state.event_log[1]
	return (
		event.result.get("outcome") == "connected"
		and damage_event.result.get("final_damage") == 0
		and damage_event.result.get("connected") == true
		and state.get_combatant("enemy").hp == 100
	)


static func _case_manual_block_requires_canonical_zones(balance: Dictionary) -> bool:
	var state := _base_state()
	var defender := state.get_combatant("enemy")
	defender.combat_stats["manual_block_zone"] = "chest"
	var event := _attack(state, {"hit": 1, "dodge": 100, "auto_block": 100, "block_crush": 100, "crit": 100}, 10.0)
	state.queue_event(event)
	CombatEngine.new(TestFixtureLoader.canonicalize_state(state), balance).resolve_pending_events()
	return event.result.get("outcome") == "connected" and defender.hp == 90
