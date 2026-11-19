extends SceneTree

## Synthetic mechanics-only sandbox. No retired ABI IDs or definitions.
## Approved weapon ABI are tested separately by the v1.2 family runners.
var failures: Array[String] = []

func check(value: bool, case_name: String) -> void:
	if not value:
		failures.append(case_name)
		push_error("ABI_LAB_TEST_FAIL: " + case_name)

func _initialize() -> void:
	var lab := AbiTestLabSession.new()
	var setup := lab.reset({"preset":"LAB_PHYSICAL","damage":100,"damage_type":"slashing","hit_roll":1,"crit_roll":100})
	check(bool(setup.get("ok",false)),"physical_setup")
	if bool(setup.get("ok",false)):
		var result := lab.next_round(true)
		check(bool(result.get("ok",false)) and int(result.get("damage_dealt",-1))==100,"physical_attack_damage")

	setup = lab.reset({"preset":"LAB_MAGIC","damage":100,"damage_type":"fire","hit_roll":1,"crit_roll":100,
		"spell_power_scale":0.5,"par_values":{"caster:PAR150":200}})
	check(bool(setup.get("ok",false)),"absolute_sp_setup")
	if bool(setup.get("ok",false)):
		var result := lab.next_round(true)
		check(int(result.get("damage_dealt",-1))==200,"base_plus_k_times_sp")

	setup = lab.reset({"preset":"LAB_MAGIC","damage":100,"damage_type":"fire","hit_roll":1,"crit_roll":100,
		"test_effect_id":"EFF003"})
	check(bool(setup.get("ok",false)),"synthetic_dot_setup")
	if bool(setup.get("ok",false)):
		var first := lab.next_round(true)
		check(int(first.get("damage_dealt",-1))==100,"dot_no_early_tick")
		var second := lab.next_round(false)
		check(int(second.get("damage_dealt",-1))==10,"dot_ticks_next_round")

	setup = lab.reset({"preset":"LAB_HEAL","damage":100,"target":"ally",
		"initial_hp":5000,"mana_cost":10,"cooldown_rounds":1,"test_effect_id":"EFF004"})
	check(bool(setup.get("ok",false)),"synthetic_healing_setup")
	if bool(setup.get("ok",false)):
		var healed := lab.next_round(true)
		check(int(healed.get("healing_done",-1))==100 and int(healed.get("mana_after",-1))==490,"direct_heal_and_cost")
		var subsequent := lab.next_round(false)
		check(int(subsequent.get("healing_done",-1))==10,"hot_ticks_next_round")

	check(not bool(lab.reset({"preset":"ABI003"}).get("ok",true)),"retired_abi_not_lab_preset")
	check(not bool(lab.reset({"preset":"ABI004"}).get("ok",true)),"retired_healing_not_lab_preset")
	check(not bool(lab.reset({"preset":"LAB_MAGIC","par_values":{"caster:PAR018":100}}).get("ok",true)),"unknown_par_rejected")
	print("ABI_TEST_LAB_TEST=" + ("PASS" if failures.is_empty() else "FAIL") + " failures=" + str(failures.size()))
	quit(0 if failures.is_empty() else 1)
