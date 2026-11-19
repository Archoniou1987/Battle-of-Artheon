class_name CombatRngRegressionCases
extends RefCounted

## Only the common Hit/Dodge/Block/Crit rolls belong to ordinary attacks.
## Counterattacks are explicit ABI attacks; there is no separate counter roll.
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
	if first.has("counterattack") or first.has("counterattack_rolls"):
		push_error("Legacy automatic counterattack rolls must be absent")
		return false
	var provided := {"hit": 1, "dodge": 1, "damage": 0.25}
	var merged := a.complete_attack_rolls(provided)
	if int(merged.get("hit", 0)) != 1 or int(merged.get("dodge", 0)) != 1:
		return false
	if float(merged.get("damage", 0.0)) != 0.25:
		return false
	var c := CombatEngine.new(CombatState.new())
	var d := CombatEngine.new(CombatState.new())
	c.combat_rng.seed = 999
	d.combat_rng.seed = 999
	var fixed := {
		"hit": 1, "magic_hit": 1, "reaction": 1, "dodge": 1,
		"auto_block": 1, "block_crush": 1, "crit": 1,
		"on_hit_effect": 1, "manual_block_effect": 1, "damage": 0.5
	}
	var all_fixed := d.complete_attack_rolls(fixed)
	if all_fixed.is_empty() or c.combat_rng.randi_range(1, 100) != d.combat_rng.randi_range(1, 100):
		push_error("Combat RNG: fixed rolls consumed RNG")
		return false
	print("COMBAT_RNG_REGRESSION=PASS")
	return true
