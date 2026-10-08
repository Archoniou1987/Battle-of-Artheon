class_name DuelSmokeCases
extends RefCounted

## Very small integration cases. These test engine behaviour, not balance.

static func run(balance: Dictionary) -> bool:
	var equal_duel := _equal_duel_finishes(balance)
	print("DUEL_CASE=equal_duel ok=", equal_duel)
	if not equal_duel: return false
	var locked := _locked_actions_survive_death(balance)
	print("DUEL_CASE=locked_actions ok=", locked)
	if not locked: return false
	var tempo := _tempo_minus_100_cannot_attack(balance)
	print("DUEL_CASE=tempo_minus_100 ok=", tempo)
	if not tempo: return false
	var mixed := _mixed_weapons_keep_attack_profiles(balance)
	print("DUEL_CASE=mixed_weapons ok=", mixed)
	if not mixed: return false
	var skill := _weapon_skill_penalties(balance)
	print("DUEL_CASE=weapon_skill ok=", skill)
	if not skill: return false
	var bow := _bow_requires_quiver(balance)
	print("DUEL_CASE=bow_quiver ok=", bow)
	if not bow: return false
	var defaults := _multiple_profiles_require_default(balance)
	print("DUEL_CASE=canonical_defaults ok=", defaults)
	if not defaults: return false
	var schema := _abi_v2_schema()
	print("DUEL_CASE=abi_schema ok=", schema)
	if not schema: return false
	var payload := _abi_v2_scheduler_payload()
	print("DUEL_CASE=abi_payload ok=", payload)
	return payload


static func _equal_duel_finishes(balance: Dictionary) -> bool:
	var state := _make_state(30, 30, 10.0, 10.0)
	var result := CombatSimulator.new(state, balance, 42).run_duel("a", "b")
	return result.get("rounds", 0) > 0 and result.get("rounds", 0) <= 100 and result.get("outcome", "timeout") != "timeout"


static func _locked_actions_survive_death(balance: Dictionary) -> bool:
	var state := _make_state(10, 10, 50.0, 50.0)
	state.begin_round()
	var round := CombatRound.new(state.round_number)
	var a := state.create_event(CombatEvent.Kind.ATTACK, "a", "b", {"raw_damage": 50.0, "zone": "chest", "damage_type": "slashing", "rolls": {"hit": 1, "crit": 100}})
	var b := state.create_event(CombatEvent.Kind.ATTACK, "b", "a", {"raw_damage": 50.0, "zone": "chest", "damage_type": "slashing", "rolls": {"hit": 1, "crit": 100}})
	round.lock_action(a)
	round.lock_action(b)
	round.resolve(CombatEngine.new(state, balance))
	return not state.get_combatant("a").is_alive() and not state.get_combatant("b").is_alive()


static func _tempo_minus_100_cannot_attack(balance: Dictionary) -> bool:
	var state := _make_state(30, 30, 10.0, 10.0)
	state.get_combatant("a").tempo = -100.0
	var simulator := CombatSimulator.new(state, balance, 7)
	simulator.max_rounds = 1
	simulator.run_duel("a", "b")
	var attacks_from_a := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "a":
			attacks_from_a += 1
	return attacks_from_a == 0



static func _mixed_weapons_keep_attack_profiles(balance: Dictionary) -> bool:
	var attacker := TestFixtureLoader.build_combatant("TEST_MIXED_WEAPON_FIGHTER")
	var defender := CombatantState.new("target", "Target", 10, 1000)
	if attacker == null: return false
	attacker.combatant_id = "mixed"
	attacker.combat_stats["hit_modifier"] = 100.0
	defender.combat_stats["dodge"] = 0.0
	var state := CombatState.new()
	state.add_combatant(attacker)
	state.add_combatant(defender)
	var simulator := CombatSimulator.new(state, balance, 17)
	simulator.max_rounds = 1
	simulator.run_duel("mixed", "target")
	var attacks:Array[CombatEvent]=[]
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "mixed":
			attacks.append(event)
	if attacks.size()!=2: return false
	return (
		int(attacks[0].payload.get("weapon_index",-1))==0
		and String(attacks[0].payload.get("damage_type",""))=="piercing"
		and float(attacks[0].payload.get("raw_damage",0.0))>=2.0
		and float(attacks[0].payload.get("raw_damage",0.0))<=3.0
		and int(attacks[1].payload.get("weapon_index",-1))==1
		and String(attacks[1].payload.get("damage_type",""))=="chopping"
		and float(attacks[1].payload.get("raw_damage",0.0))>=4.0
		and float(attacks[1].payload.get("raw_damage",0.0))<=5.0
	)


static func _weapon_skill_penalties(balance: Dictionary) -> bool:
	var attacker := TestFixtureLoader.build_combatant("TEST_DAGGER_FIGHTER")
	if attacker == null: return false
	attacker.combatant_id = "skill"
	var defender := CombatantState.new("skill_target", "Skill Target", 10, 100)
	var state := CombatState.new()
	state.add_combatant(attacker); state.add_combatant(defender)
	var engine := CombatEngine.new(state,balance)
	var checks := [[15,15,0.0],[15,5,10.0],[15,1,14.0],[100,1,80.0]]
	for check in checks:
		var profiles:Array=attacker.combat_stats.get("weapon_profiles",[])
		profiles[0]["item_level"]=int(check[0])
		attacker.set_weapon_progress("dagger",int(check[1]))
		var event:=state.create_event(CombatEvent.Kind.ATTACK,"skill","skill_target",{"raw_damage":2.0,"zone":"chest","damage_type":"piercing","weapon_index":0,"rolls":{"hit":100}})
		engine.resolve_event(event)
		if not is_equal_approx(float(event.result.get("weapon_skill_hit_penalty",-1.0)),float(check[2])): return false
	return true

static func _bow_requires_quiver(balance: Dictionary) -> bool:
	var without := TestFixtureLoader.build_combatant("TEST_BOW_NO_QUIVER")
	var with_quiver := TestFixtureLoader.build_combatant("TEST_BOW_WITH_QUIVER")
	if without == null or with_quiver == null: return false
	without.combatant_id="bow_without"; with_quiver.combatant_id="bow_with"
	var canonical_profiles:=WeaponAttackProfile.all(with_quiver)
	if canonical_profiles.is_empty() or String(canonical_profiles[0].get("requires_off_hand_type",""))!="quiver": return false
	var target_a:=CombatantState.new("target_a","Target A",10,1000)
	var state_a:=CombatState.new(); state_a.add_combatant(without); state_a.add_combatant(target_a)
	var sim_a:=CombatSimulator.new(state_a,balance,31); sim_a.max_rounds=1; sim_a.run_duel("bow_without","target_a")
	for event in state_a.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and event.source_id=="bow_without": return false
	var target_b:=CombatantState.new("target_b","Target B",10,1000)
	var state_b:=CombatState.new(); state_b.add_combatant(with_quiver); state_b.add_combatant(target_b)
	var sim_b:=CombatSimulator.new(state_b,balance,31); sim_b.max_rounds=1; sim_b.run_duel("bow_with","target_b")
	for event in state_b.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and event.source_id=="bow_with": return true
	return false

static func _multiple_profiles_require_default(balance:Dictionary)->bool:
	var profiles=[{
		"damage_min":3.0,"damage_max":3.0,"damage_type":"blunt",
		"attack_profiles":[
			{"id":"strike","delivery_type":"MELEE"},
			{"id":"bolt","delivery_type":"PROJECTILE","max_zone_distance":2}
		]
	}]
	var attacker:=CombatantState.new("profile_user","Profile User",10,100)
	attacker.combat_stats["weapon_profiles"]=profiles.duplicate(true)
	var state:=CombatState.new(); state.add_combatant(attacker); state.add_combatant(CombatantState.new("profile_target","Profile Target",10,1000))
	var simulator:=CombatSimulator.new(state,balance,44); simulator.max_rounds=1
	simulator.run_duel("profile_user","profile_target")
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and event.source_id=="profile_user": return false
	profiles[0]["attack_profiles"][0]["is_default"]=true
	var clean:=CombatantState.new("profile_user2","Profile User",10,100)
	clean.combat_stats["weapon_profiles"]=profiles.duplicate(true)
	var clean_state:=CombatState.new(); clean_state.add_combatant(clean); clean_state.add_combatant(CombatantState.new("profile_target2","Profile Target 2",10,1000))
	var simulator2:=CombatSimulator.new(clean_state,balance,44); simulator2.max_rounds=1
	simulator2.run_duel("profile_user2","profile_target2")
	for event in clean_state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and event.source_id=="profile_user2":
			return String(event.payload.get("attack_profile_id",""))=="strike"
	return false
static func _abi_v2_schema() -> bool:
	var definitions:=AbilityCatalog.load_json("res://data/test/abilities.json")
	var fireball:=AbilityRuntime.normalized_definition("ABI001",AbilityCatalog.definition(definitions,"ABI001"))
	var legacy:=AbilityRuntime.normalized_definition("ABI004",AbilityCatalog.definition(definitions,"ABI004"))
	var charge:=AbilityRuntime.normalized_definition("ABI005",AbilityCatalog.definition(definitions,"ABI005"))
	var blizzard:=AbilityRuntime.normalized_definition("ABI006",AbilityCatalog.definition(definitions,"ABI006"))
	if String(fireball.get("delivery_type",""))!="PROJECTILE" or String(fireball.get("target_scope",""))!="SINGLE": return false
	var fire_components:Array=fireball.get("components",[])
	if fire_components.size()!=1 or float(fire_components[0].get("amount",0))!=5.0: return false
	var legacy_components:Array=legacy.get("components",[])
	if legacy_components.size()!=1 or float(legacy_components[0].get("amount",0))!=5.0: return false
	if String(legacy.get("delivery_type",""))!="DIRECT": return false
	var engagement:Dictionary=charge.get("engagement",{})
	if String(charge.get("delivery_type",""))!="MELEE" or not bool(engagement.get("request_target_change",false)): return false
	var blizzard_components:Array=blizzard.get("components",[])
	return String(blizzard.get("target_scope",""))=="ALL_ENEMIES" and int(blizzard.get("duration_rounds",0))==3 and blizzard_components.size()==2 and int(blizzard_components[0].get("full_targets",0))==5 and int(blizzard_components[1].get("full_targets",0))==3

static func _abi_v2_scheduler_payload() -> bool:
	var definitions:=AbilityCatalog.load_json("res://data/test/abilities.json")
	if not AbilityRuntime.validate_definition("ABI001",AbilityCatalog.definition(definitions,"ABI001")).is_empty(): return false
	if not AbilityRuntime.validate_definition("ABI004",AbilityCatalog.definition(definitions,"ABI004")).is_empty(): return false
	if AbilityRuntime.validate_definition("BAD",{"delivery_type":"TELEPORT","target_scope":"SINGLE","components":[]}).is_empty(): return false
	var source:=CombatantState.new("abi_source","ABI Source",10,100)
	source.mana=100
	var target:=CombatantState.new("abi_target","ABI Target",10,100)
	var state:=CombatState.new(); state.add_combatant(source); state.add_combatant(target)
	var scheduler:=AbilityScheduler.new(definitions,{"abi_source":["ABI001"]})
	var events:=scheduler.ready_events(state,"abi_source","abi_target")
	if events.size()!=1: return false
	var payload:Dictionary=events[0].payload
	var components:Array=payload.get("components",[])
	return String(payload.get("delivery_type",""))=="PROJECTILE" and String(payload.get("target_scope",""))=="SINGLE" and String(payload.get("ability_id",""))=="ABI001" and components.size()==1 and float(components[0].get("amount",0.0))==5.0 and payload.get("target_ids",[]).size()==1 and source.mana==90

static func _make_state(hp_a: int, hp_b: int, damage_a: float, damage_b: float) -> CombatState:
	var state := CombatState.new()
	var a := CombatantState.new("a", "A", 1, hp_a)
	var b := CombatantState.new("b", "B", 1, hp_b)
	a.combat_stats["main_hand_damage"] = damage_a
	b.combat_stats["main_hand_damage"] = damage_b
	state.add_combatant(a)
	state.add_combatant(b)
	return state
