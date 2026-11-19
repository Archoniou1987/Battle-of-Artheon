extends SceneTree

## Guard the immediately locked ABI1 + ABI2 contract without changing legacy ABI.
var failures: Array[String] = []

func _assert(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("FIRE_BURST_EXTRA_CAST_FAIL=" + label)

func _initialize() -> void:
	var defs := {
		"TEST_FIREBALL":{"mana_cost":35,"cooldown_rounds":1,"application_timing":"standard"},
		"TEST_BLAST":{"mana_cost":30,"cooldown_rounds":2,"application_timing":"standard","instant_bonus_eligible":true},
		"TEST_OTHER":{"mana_cost":45,"cooldown_rounds":3,"application_timing":"standard"},
		"TEST_SECOND_INSTANT":{"mana_cost":20,"application_timing":"standard","instant_bonus_eligible":true}
	}
	var a := AbilityScheduler.new(defs,{})
	_assert(a.can_cast_this_round("hero",1,"TEST_FIREBALL"),"initial_cast")
	_assert(a.mana_cost_for_cast("hero",1,"TEST_FIREBALL")==35,"initial_mana")
	a._record_cast("hero",1,"TEST_FIREBALL")
	_assert(a.can_cast_this_round("hero",1,"TEST_BLAST"),"fireball_then_blast")
	_assert(a.mana_cost_for_cast("hero",1,"TEST_BLAST")==38,"second_mana_ceil_25pct")
	_assert(not a.can_cast_this_round("hero",1,"TEST_OTHER"),"no_second_standard")
	_assert(not a.can_cast_this_round("hero",1,"TEST_FIREBALL"),"no_duplicate")
	a._record_cast("hero",1,"TEST_BLAST")
	_assert(not a.can_cast_this_round("hero",1,"TEST_OTHER"),"no_third")
	_assert(a.can_cast_this_round("hero",2,"TEST_OTHER"),"next_round_reset")
	var b := AbilityScheduler.new(defs,{})
	b._record_cast("hero",1,"TEST_BLAST")
	_assert(b.can_cast_this_round("hero",1,"TEST_FIREBALL"),"blast_then_fireball")
	_assert(b.mana_cost_for_cast("hero",1,"TEST_FIREBALL")==44,"reverse_second_mana_ceil")
	_assert(not b.can_cast_this_round("hero",1,"TEST_SECOND_INSTANT"),"no_two_instants")
	var physical := AbilityScheduler.new(defs,{})
	physical._record_cast("fighter",1,"TEST_FIREBALL")
	_assert(not physical.can_cast_this_round("fighter",1,"TEST_OTHER"),"physical_one_abi")
	print("FIRE_BURST_EXTRA_CAST=", "PASS" if failures.is_empty() else "FAIL", " failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
