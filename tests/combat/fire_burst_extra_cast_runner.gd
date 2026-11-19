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
	# Real scheduler cast path must deduct resources immediately and set CD on lock.
	var catalog := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var live_state := CombatState.new()
	live_state.round_number = 1
	var live_caster := TestFixtureLoader.new_combatant("caster","Caster",40,1000,500)
	var live_target := TestFixtureLoader.new_combatant("target","Target",40,10000,0)
	live_state.add_combatant(live_caster)
	live_state.add_combatant(live_target)
	var live := AbilityScheduler.new(catalog,{"caster":["ABI801","ABI802","ABI803","ABI804"]})
	var first := live.cast_event(live_state,"caster","target","ABI801")
	_assert(first!=null,"live_first_fireball")
	_assert(live_caster.mana==465,"live_first_mana")
	var second := live.cast_event(live_state,"caster","target","ABI802")
	_assert(second!=null,"live_second_blast")
	_assert(live_caster.mana==427,"live_extra_mana_25")
	_assert(int(Dictionary(live.cooldowns_by_combatant.get("caster",{})).get("ABI802",0))==5,"live_extra_cd_plus_one")
	_assert(first!=null and second!=null and first.event_id<second.event_id,"live_selection_sequence")
	_assert(live.cast_event(live_state,"caster","target","ABI803")==null,"live_third_rejected")
	var reversed_state := CombatState.new()
	reversed_state.round_number=1
	var reversed_caster := TestFixtureLoader.new_combatant("caster2","Caster2",40,1000,500)
	reversed_state.add_combatant(reversed_caster)
	reversed_state.add_combatant(TestFixtureLoader.new_combatant("target2","Target2",40,10000,0))
	var reversed_live := AbilityScheduler.new(catalog,{"caster2":["ABI801","ABI802"]})
	_assert(reversed_live.cast_event(reversed_state,"caster2","target2","ABI802")!=null,"live_reverse_blast")
	_assert(reversed_live.cast_event(reversed_state,"caster2","target2","ABI801")!=null,"live_reverse_fireball")
	_assert(reversed_caster.mana==426,"live_reverse_second_mana")
	_assert(int(Dictionary(reversed_live.cooldowns_by_combatant.get("caster2",{})).get("ABI801",0))==4,"live_reverse_extra_cd")
	print("FIRE_BURST_EXTRA_CAST=", "PASS" if failures.is_empty() else "FAIL", " failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
