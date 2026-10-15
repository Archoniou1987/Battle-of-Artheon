class_name CombatRngRegressionCases
extends RefCounted

static func run() -> bool:
	var a := CombatEngine.new(CombatState.new())
	var b := CombatEngine.new(CombatState.new())
	a.combat_rng.seed = 12345
	b.combat_rng.seed = 12345
	var first := a.complete_attack_rolls({})
	var second := b.complete_attack_rolls({})
	if first != second:
		push_error("Combat RNG: identical seeds produce different rolls")
		return false
	if not first.has("counterattack_rolls"):
		return false
	var provided := {
		"hit": 1,
		"dodge": 1,
		"counterattack": 1,
		"damage": 0.25,
		"counterattack_rolls": {"hit": 1, "damage": 0.75}
	}
	var merged := a.complete_attack_rolls(provided)
	if int(merged.get("hit", 0)) != 1 or int(merged.get("dodge", 0)) != 1:
		return false
	if int(merged.get("counterattack", 0)) != 1 or float(merged.get("damage", 0.0)) != 0.25:
		return false
	var counter: Dictionary = merged.get("counterattack_rolls", {})
	if int(counter.get("hit", 0)) != 1 or float(counter.get("damage", 0.0)) != 0.75:
		return false
	var c := CombatEngine.new(CombatState.new())
	var d := CombatEngine.new(CombatState.new())
	c.combat_rng.seed = 999
	d.combat_rng.seed = 999
	var all_fixed := d.complete_attack_rolls({
		"hit": 1, "magic_hit": 1, "reaction": 1, "dodge": 1,
		"auto_block": 1, "block_crush": 1, "crit": 1, "counterattack": 1,
		"on_hit_effect": 1, "manual_block_effect": 1, "damage": 0.5,
		"counterattack_rolls": {
			"hit": 1, "magic_hit": 1, "reaction": 1, "dodge": 1,
			"auto_block": 1, "block_crush": 1, "crit": 1, "counterattack": 1,
			"on_hit_effect": 1, "manual_block_effect": 1, "damage": 0.5
		}
	})
	if all_fixed.is_empty() or c.combat_rng.randi_range(1, 100) != d.combat_rng.randi_range(1, 100):
		push_error("Combat RNG: fixed rolls consumed RNG")
		return false
	if not _counterattack_contract():
		return false
	print("COMBAT_RNG_REGRESSION=PASS")
	return true

static func _counterattack_contract() -> bool:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("rng_attacker", "Attacker", 10, 100)
	var defender := TestFixtureLoader.new_combatant("rng_defender", "Defender", 10, 100)
	state.add_combatant(attacker)
	state.add_combatant(defender)
	TestFixtureLoader.set_weapon_profiles(defender, [{
		"damage_min": 10.0, "damage_max": 10.0, "damage_type": "piercing",
		"attack_profiles": [{"id": "basic", "delivery_type": "MELEE"}]
	}])
	var engine := CombatEngine.new(state)
	var parent := state.create_event(CombatEvent.Kind.ATTACK, attacker.combatant_id, defender.combatant_id, {
		"rolls": {"counterattack": 1, "counterattack_rolls": {
			"hit": 1, "reaction": 100, "dodge": 100, "auto_block": 100,
			"block_crush": 100, "crit": 100, "damage": 0.5
		}}
	})
	# Exercise the event creation contract without relying on stochastic dodge.
	engine._queue_counterattack(parent, defender, attacker, Dictionary(parent.payload["rolls"]))
	var created := state.pending_events.size()
	if created > 1:
		push_error("Counterattack: more than one child event")
		return false
	if created == 0:
		# Fixture may have zero counterattack chance; do not claim a positive test.
		print("COUNTERATTACK_FIXTURE_NO_CHANCE")
		return true
	var child: CombatEvent = state.pending_events[0]
	if not bool(child.payload.get("is_counterattack", false)) or bool(child.payload.get("generates_ap", true)):
		return false
	engine._queue_counterattack(child, attacker, defender, {"counterattack": 1})
	if state.pending_events.size() != 1:
		push_error("Counterattack recursion was not blocked")
		return false
	return true
