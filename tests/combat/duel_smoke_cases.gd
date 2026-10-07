class_name DuelSmokeCases
extends RefCounted

## Very small integration cases. These test engine behaviour, not balance.

static func run(balance: Dictionary) -> bool:
	return _equal_duel_finishes(balance) and _locked_actions_survive_death(balance) and _tempo_minus_100_cannot_attack(balance) and _mixed_weapons_keep_attack_profiles(balance)


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
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "mixed" and not bool(event.payload.get("is_extra_attack", false)):
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


static func _make_state(hp_a: int, hp_b: int, damage_a: float, damage_b: float) -> CombatState:
	var state := CombatState.new()
	var a := CombatantState.new("a", "A", 1, hp_a)
	var b := CombatantState.new("b", "B", 1, hp_b)
	a.combat_stats["main_hand_damage"] = damage_a
	b.combat_stats["main_hand_damage"] = damage_b
	state.add_combatant(a)
	state.add_combatant(b)
	return state
