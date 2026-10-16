extends SceneTree

## ABI Test Lab must calculate through real CombatEngine/PAR, never bespoke math.
var errors: Array[String] = []

func _initialize() -> void:
	_test_physical()
	_test_magic()
	_test_fireball_and_shared_eff()
	_test_crit_and_invalid_par()
	for error in errors:
		push_error("ABI_TEST_LAB_FAIL: " + error)
	print("ABI_TEST_LAB_TEST=", "PASS" if errors.is_empty() else "FAIL", " failures=", errors.size())
	quit(0 if errors.is_empty() else 1)

func _check(success: bool, message: String) -> void:
	if not success:
		errors.append(message)

func _test_physical() -> void:
	var lab := AbiTestLabSession.new()
	var setup: Dictionary = lab.reset({"preset": "LAB_PHYSICAL", "damage": 100,
		"damage_type": "slashing", "hit_roll": 1, "crit_roll": 100})
	_check(bool(setup.get("ok", false)), "physical setup accepted")
	if not bool(setup.get("ok", false)):
		return
	var result: Dictionary = lab.next_round()
	_check(bool(result.get("ok", false)) and int(result.get("damage_dealt", -1)) == 100,
		"physical 100 base gives 100 damage without defence")
	_check(int(result.get("mana_before", -1)) == int(result.get("mana_after", -2)),
		"zero-cost custom ability does not spend mana")
	_check(_has_kind(result, "ATTACK") and _has_kind(result, "DAMAGE"),
		"physical ability uses ATTACK then DAMAGE event chain")

	setup = lab.reset({"preset": "LAB_PHYSICAL", "damage": 100,
		"damage_type": "slashing", "hit_roll": 1, "crit_roll": 100,
		"par_values": {"dummy:PAR101": 10}})
	_check(bool(setup.get("ok", false)), "physical armour setup accepted")
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		# 10 flat chest armour -> 100 rating -> 10% at level 1.
		_check(int(result.get("damage_dealt", -1)) == 90,
			"PAR101 uses canonical armour-to-rating reduction (100 -> 90)")

	setup = lab.reset({"preset": "LAB_PHYSICAL", "damage": 100,
		"damage_type": "slashing", "hit_roll": 1, "crit_roll": 100,
		"par_values": {"dummy:PAR101": 10, "caster:PAR126": 100}})
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 100, "PAR126 penetration removes chest armour")
	else:
		_check(false, "PAR126 physical armour penetration setup")

func _test_magic() -> void:
	var lab := AbiTestLabSession.new()
	var setup: Dictionary = lab.reset({"preset": "LAB_MAGIC", "damage": 100,
		"damage_type": "fire", "hit_roll": 1, "crit_roll": 100,
		"par_values": {"caster:PAR150": 200, "dummy:PAR190": 100}})
	_check(bool(setup.get("ok", false)), "magic setup accepted")
	if not bool(setup.get("ok", false)):
		return
	var result: Dictionary = lab.next_round()
	# PAR150 +20% at level 1, PAR190 10% resist => 100*1.2*0.9=108.
	_check(int(result.get("damage_dealt", -1)) == 108, "PAR150 + PAR190 magic calculation (108)")
	_check(_has_kind(result, "ATTACK") and _has_kind(result, "DAMAGE"),
		"magic projectile uses canonical ATTACK then DAMAGE")
	setup = lab.reset({"preset": "LAB_MAGIC", "damage": 100,
		"damage_type": "fire", "hit_roll": 1, "crit_roll": 100,
		"par_values": {"dummy:PAR191": 100}})
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 90, "PAR191 fire resistance (100 -> 90)")
	else:
		_check(false, "fire resistance setup accepted")

func _test_fireball_and_shared_eff() -> void:
	var lab := AbiTestLabSession.new()
	var setup: Dictionary = lab.reset({"preset": "ABI003", "damage": 100,
		"hit_roll": 1, "crit_roll": 100})
	_check(bool(setup.get("ok", false)), "canonical ABI003 setup accepted")
	if not bool(setup.get("ok", false)):
		return
	var first: Dictionary = lab.next_round(true)
	_check(int(first.get("damage_dealt", -1)) == 100 and int(first.get("mana_after", -1)) == 490,
		"ABI003 deals 100 and spends 10 mana")
	_check(String(first.get("cast_status", "")) == "cast", "ABI003 cast accepted")
	_check(_first_stacks(first) == 1, "first EFF003 stack")
	var second: Dictionary = lab.next_round(true)
	_check(String(second.get("cast_status", "")) == "cooldown" and int(second.get("damage_dealt", -1)) == 10,
		"ABI003 cooldown one round while EFF003 ticks")
	_check(int(second.get("mana_after", -1)) == 490, "rejected cooldown does not spend mana")
	var third: Dictionary = lab.next_round(true)
	_check(String(third.get("cast_status", "")) == "cast" and int(third.get("damage_dealt", -1)) == 120,
		"round three: Fireball100 + Burning2*10")
	_check(_first_stacks(third) == 2 and int(third.get("mana_after", -1)) == 480,
		"second EFF003 stack shares duration and caster pays 10")
	_check(int(lab.state.get_combatant(AbiTestLabSession.DUMMY_ID).hp) == 9770,
		"dummy retains damage across isolated lab rounds")

func _test_crit_and_invalid_par() -> void:
	var lab := AbiTestLabSession.new()
	var bad: Dictionary = lab.reset({"preset": "LAB_MAGIC", "damage": 100,
		"par_values": {"caster:PAR018": 100}})
	_check(not bool(bad.get("ok", true)), "unimplemented PAR018 rejected, not silently applied")
	var setup: Dictionary = lab.reset({"preset": "LAB_MAGIC", "damage": 100,
		"damage_type": "fire", "hit_roll": 1, "crit_roll": 1,
		"par_values": {"caster:PAR033": 1000}})
	_check(bool(setup.get("ok", false)), "critical-rating setup accepted")
	if bool(setup.get("ok", false)):
		var result: Dictionary = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 150, "PAR033 crit multiplies 100 to 150")
		_check(_has_kind(result, "ATTACK"), "critical trace contains ATTACK")

static func _has_kind(result: Dictionary, expected: String) -> bool:
	for raw_event in Array(result.get("events", [])):
		if String(Dictionary(raw_event).get("kind", "")) == expected:
			return true
	return false

static func _first_stacks(result: Dictionary) -> int:
	for raw_effect in Array(result.get("effects", [])):
		var effect: Dictionary = raw_effect
		if String(effect.get("effect_id", "")) == "EFF003":
			return int(effect.get("stacks", 0))
	return 0
