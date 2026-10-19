extends SceneTree

## ABI Test Lab must calculate through real CombatEngine/PAR, never bespoke math.
var errors: Array[String] = []

func _initialize() -> void:
	_test_physical()
	_test_magic()
	_test_fireball_and_shared_eff()
	_test_crit_and_invalid_par()
	_test_magic_dot_scaling_and_rounding()
	_test_two_dot_casters()
	_test_healing_and_hot()
	_test_hp_one_shot_and_round_cap()
	_test_finalized_death_boundaries()
	_test_lab_lifecycle_and_event_totals()
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

	# Same-level baseline hit is 95%; PAR030 rating 100 adds 10% at level 1.
	setup = lab.reset({"preset": "LAB_PHYSICAL", "damage": 100,
		"damage_type": "slashing", "hit_roll": 99, "crit_roll": 100})
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 0, "hit 99 misses before PAR030 bonus")
	setup = lab.reset({"preset": "LAB_PHYSICAL", "damage": 100,
		"damage_type": "slashing", "hit_roll": 99, "crit_roll": 100,
		"par_values": {"caster:PAR030": 100}})
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 100, "PAR030 raises hit rating into a hit")

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
		"par_values": {"dummy:PAR135": 25}})
	if bool(setup.get("ok", false)):
		result = lab.next_round()
		_check(int(result.get("damage_dealt", -1)) == 75, "PAR135 reduces final magic damage by 25%")
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
	_check(String(third.get("cast_status", "")) == "cast" and int(third.get("damage_dealt", -1)) == 110,
		"round three: Fireball100 + previous Burning1*10")
	_check(_first_stacks(third) == 2 and int(third.get("mana_after", -1)) == 480,
		"second EFF003 stack shares duration and caster pays 10")
	_check(int(lab.state.get_combatant(AbiTestLabSession.DUMMY_ID).hp) == 9780,
		"dummy retains damage across isolated lab rounds")

func _test_magic_dot_scaling_and_rounding() -> void:
	var lab := AbiTestLabSession.new()
	var setup := lab.reset({"preset":"ABI003", "damage":100, "hit_roll":1, "crit_roll":100,
		"par_values":{"caster:PAR150":130}})
	_check(bool(setup.get("ok", false)), "magic scaling setup")
	if not bool(setup.get("ok", false)):
		return
	var first := lab.next_round(true)
	_check(int(first.get("damage_dealt",-1)) == 113, "PAR150 130: exact 113 damage, no float loss")
	var second := lab.next_round(false)
	_check(int(second.get("damage_dealt",-1)) == 11, "PAR150 130: 10*1.13 DoT floors to 11")
	var third := lab.next_round(true)
	_check(int(third.get("damage_dealt",-1)) == 124, "new stack waits; 113 Fireball + 11 prior DoT")
	var fourth := lab.next_round(false)
	_check(int(fourth.get("damage_dealt",-1)) == 22, "two stacks scale 20*1.13 -> 22")
	var fifth := lab.next_round(false)
	_check(int(fifth.get("damage_dealt",-1)) == 22, "refreshed tick 2")
	var sixth := lab.next_round(false)
	_check(int(sixth.get("damage_dealt",-1)) == 22, "refreshed tick 3")
	var seventh := lab.next_round(false)
	_check(int(seventh.get("damage_dealt",-1)) == 0, "no DoT after third future tick")
	# Defender resistance applies to each scaled tick.
	setup = lab.reset({"preset":"ABI003", "damage":100, "hit_roll":1, "crit_roll":100,
		"par_values":{"caster:PAR150":200, "dummy:PAR190":200}})
	if bool(setup.get("ok",false)):
		first = lab.next_round(true)
		second = lab.next_round(false)
		_check(int(first.get("damage_dealt",-1)) == 96, "magic resistance on PAR150 boosted Fireball")
		_check(int(second.get("damage_dealt",-1)) == 9, "20% resistance on boosted 12 DoT -> floor 9")

func _test_two_dot_casters() -> void:
	var state := CombatState.new()
	var source_a := TestFixtureLoader.new_combatant("caster_a","A",1,100,0)
	var source_b := TestFixtureLoader.new_combatant("caster_b","B",1,100,0)
	var target := TestFixtureLoader.new_combatant("target","Target",1,1000,0)
	source_a.combat_stats["magic_damage_rating_percent"] = 20.0
	source_b.combat_stats["magic_damage_rating_percent"] = 50.0
	state.add_combatant(source_a)
	state.add_combatant(source_b)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	var orchestrator := RoundOrchestrator.new(state,engine)
	orchestrator.begin_round()
	for caster_id in ["caster_a","caster_b"]:
		engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT,caster_id,"target",
			{"effect_id":"EFF003","base_chance":100.0,"effect_roll":1,"resist_type":"fire"}))
	_check(target.active_effects.size() == 2, "same EFF from different casters creates separate records")
	orchestrator.end_round()
	_check(target.hp == 1000, "new source DoT stacks never tick on application round")
	orchestrator.begin_round()
	orchestrator.end_round()
	_check(target.hp == 973, "independent PAR150: caster A 12 + caster B 15 = 27")
	# Changing one caster's rating affects only their next tick.
	source_a.combat_stats["magic_damage_rating_percent"] = 0.0
	orchestrator.begin_round()
	orchestrator.end_round()
	_check(target.hp == 948, "dynamic ratings: A 10 + B 15 = 25")

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

func _test_healing_and_hot() -> void:
	var lab := AbiTestLabSession.new()
	var setup := lab.reset({"preset":"ABI004", "damage":100, "target":"ally", "initial_hp":5000})
	_check(bool(setup.get("ok", false)), "ABI004 allied healing setup accepted")
	if not bool(setup.get("ok", false)):
		return
	var first := lab.next_round(true)
	_check(String(first.get("target_id","")) == AbiTestLabSession.ALLY_ID, "ABI004 explicitly targets ally")
	_check(int(first.get("healing_done",-1)) == 100 and int(first.get("mana_after",-1)) == 490, "direct heal restores 100 and consumes 10 mana")
	_check(_first_effect_stacks(first, "EFF004") == 1, "EFF004 first HoT stack")
	var second := lab.next_round(true)
	_check(String(second.get("cast_status","")) == "cooldown" and int(second.get("healing_done",-1)) == 10, "HoT tick during cooldown")
	var third := lab.next_round(true)
	_check(int(third.get("healing_done",-1)) == 110 and _first_effect_stacks(third,"EFF004") == 2, "new HoT stack waits until next round")
	var fourth := lab.next_round(false)
	_check(int(fourth.get("healing_done",-1)) == 20, "two HoT stacks tick together")
	var fifth := lab.next_round(true)
	_check(int(fifth.get("healing_done",-1)) == 120 and _first_effect_stacks(fifth,"EFF004") == 3, "third stack starts next round")
	var sixth := lab.next_round(false)
	_check(int(sixth.get("healing_done",-1)) == 30, "three HoT stacks heal 30 per round")
	var seventh := lab.next_round(false)
	var eighth := lab.next_round(false)
	var ninth := lab.next_round(false)
	_check(int(seventh.get("healing_done",-1)) == 30 and int(eighth.get("healing_done",-1)) == 30 and int(ninth.get("healing_done",-1)) == 0, "HoT expires after 3 future ticks")
	setup = lab.reset({"preset":"ABI004", "damage":100, "target":"caster", "initial_hp":5000})
	_check(bool(setup.get("ok",false)), "self heal setup accepted")
	if bool(setup.get("ok",false)):
		var self_result := lab.next_round(true)
		_check(String(self_result.get("target_id","")) == AbiTestLabSession.CASTER_ID and int(self_result.get("healing_done",-1)) == 100, "explicit self target heals caster")
	setup = lab.reset({"preset":"ABI004", "target":"dummy"})
	_check(not bool(setup.get("ok",true)), "ABI004 enemy targeting rejected")

func _test_hp_one_shot_and_round_cap() -> void:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("enemy","Enemy",1,100,0)
	var target := TestFixtureLoader.new_combatant("ally","Ally",1,100,0)
	state.add_combatant(attacker)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	var rounds := RoundOrchestrator.new(state,engine)
	rounds.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT,"ally","ally",{"inline_heal":150}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"enemy","ally",{"amount":99.0,"damage_type":"fire"}))
	_check(target.hp == 151 and not target.one_shot_kill, "provisional HP may exceed max inside round")
	rounds.end_round()
	_check(target.hp == 100 and not target.death_finalized, "end round caps surplus HP, survives 99 hit")
	rounds.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT,"ally","ally",{"inline_heal":150}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE,"enemy","ally",{"amount":100.0,"damage_type":"fire"}))
	rounds.end_round()
	_check(target.death_finalized and target.one_shot_kill, "100 damage at 100 max HP is one shot despite prior healing")
	var another := TestFixtureLoader.new_combatant("another","Another",1,100,0)
	var second_state := CombatState.new()
	second_state.add_combatant(another)
	var second_engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(second_state))
	var second_rounds := RoundOrchestrator.new(second_state, second_engine)
	second_rounds.begin_round()
	second_engine.resolve_event(second_state.create_event(CombatEvent.Kind.DAMAGE,"another","another",{"amount":70.0,"damage_type":"fire"}))
	second_engine.resolve_event(second_state.create_event(CombatEvent.Kind.DAMAGE,"another","another",{"amount":70.0,"damage_type":"fire"}))
	second_engine.resolve_event(second_state.create_event(CombatEvent.Kind.EFFECT,"another","another",{"inline_heal":100}))
	second_rounds.end_round()
	_check(another.hp == 60 and not another.death_finalized, "two non-one-shot 70 hits plus 100 heal survive at 60")

func _test_finalized_death_boundaries() -> void:
	var state := CombatState.new()
	var healer := TestFixtureLoader.new_combatant("healer", "Healer", 1, 100, 50)
	var target := TestFixtureLoader.new_combatant("target", "Target", 1, 100, 50)
	state.add_combatant(healer)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	var rounds := RoundOrchestrator.new(state, engine)
	rounds.begin_round()
	# Provisional negative HP is still healable before death finalization.
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE, "healer", "target", {"amount":70.0, "damage_type":"physical"}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE, "healer", "target", {"amount":70.0, "damage_type":"physical"}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT, "healer", "target", {"inline_heal":100}))
	_check(target.hp == 60 and not target.is_death_finalized(), "two hits and same-round heal rescue provisional death")
	rounds.end_round()
	_check(target.hp == 60 and not target.is_death_finalized(), "rescued target survives end round")
	rounds.begin_round()
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE, "healer", "target", {"amount":70.0, "damage_type":"physical"}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.DAMAGE, "healer", "target", {"amount":70.0, "damage_type":"physical"}))
	var lethal_summary := rounds.end_round()
	_check(target.is_death_finalized() and target.hp == -80 and Array(lethal_summary.get("dead_ids",[])).has("target"), "target dies at end round without one-shot")
	var hp_after_death := target.hp
	var damage_event := state.create_event(CombatEvent.Kind.DAMAGE, "healer", "target", {"amount":70.0, "damage_type":"physical"})
	engine.resolve_event(damage_event)
	var heal_event := state.create_event(CombatEvent.Kind.EFFECT, "healer", "target", {"inline_heal":100})
	engine.resolve_event(heal_event)
	var attack_event := state.create_event(CombatEvent.Kind.ATTACK, "healer", "target", {"raw_damage":10.0, "damage_type":"slashing", "zone":"chest"})
	engine.resolve_event(attack_event)
	_check(target.hp == hp_after_death and int(damage_event.result.get("hp_removed",-1)) == 0 and String(damage_event.result.get("outcome","")) == "target_dead", "finalized target ignores later damage")
	_check(not bool(heal_event.result.get("resolved",true)) and String(heal_event.result.get("outcome","")) == "target_dead", "finalized target ignores later healing")
	_check(String(attack_event.result.get("outcome","")) == "target_dead", "attack ignores finalized defender")
	var dead_action := state.create_event(CombatEvent.Kind.ACTION, "target", "healer", {"components":[{"kind":"heal", "amount":10.0}], "target_team":"ALLY"})
	engine.resolve_event(dead_action)
	_check(String(dead_action.result.get("outcome","")) == "source_dead", "dead caster cannot create direct ACTION children")
	var mana_before := target.mana
	var definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var scheduler := AbilityScheduler.new({"ABI004":definitions.get("ABI004",{})}, {"target":["ABI004"]})
	_check(scheduler.cast_event(state,"target","healer","ABI004") == null and target.mana == mana_before, "dead caster cannot spend mana or start ABI")
	_check(target.apply_damage(10) == 0 and target.hp == hp_after_death and not target.spend_mana(10), "defensive combatant API protects finalized death")
	rounds.begin_round()
	var repeat_summary := rounds.end_round()
	_check(not Array(repeat_summary.get("dead_ids",[])).has("target"), "death is only finalized/reported once")

func _test_lab_lifecycle_and_event_totals() -> void:
	var lab := AbiTestLabSession.new()
	var setup := lab.reset({"preset":"ABI004", "target":"ally", "initial_hp":100, "target_max_hp":100,
		"damage":100, "incoming_damage":70, "incoming_hits":2, "event_order":"damage_first"})
	_check(bool(setup.get("ok",false)), "lab multi-hit healing scenario initialized")
	if not bool(setup.get("ok",false)):
		return
	var saved := lab.next_round()
	_check(int(saved.get("hp_after",-1)) == 60 and not bool(saved.get("lab_finished",true)), "lab heals from provisional negative HP before round end")
	_check(int(saved.get("damage_dealt",-1)) == 140 and int(saved.get("healing_done",-1)) == 100, "lab reports actual hit damage and healing separately")
	setup = lab.reset({"preset":"ABI004", "target":"ally", "initial_hp":100, "target_max_hp":100,
		"damage":20, "incoming_damage":70, "incoming_hits":2, "event_order":"heal_first"})
	if bool(setup.get("ok",false)):
		var death := lab.next_round()
		_check(bool(death.get("death_finalized",false)) and not bool(death.get("one_shot_kill",true)), "two non-one-shot hits kill ally at end of round")
		_check(String(death.get("lab_outcome","")) == "target_dead" and bool(death.get("lab_finished",false)), "lab reports target death without claiming a team battle result")
		var mana_after := lab.state.get_combatant(AbiTestLabSession.CASTER_ID).mana
		var logged := lab.state.event_log.size()
		var blocked := lab.next_round()
		_check(not bool(blocked.get("ok",true)) and String(blocked.get("reason","")) == "lab_battle_finished", "lab rejects subsequent rounds after selected target death")
		_check(lab.state.round_number == 1 and lab.state.event_log.size() == logged and lab.state.get_combatant(AbiTestLabSession.CASTER_ID).mana == mana_after, "blocked lab round has no events or mana loss")
	setup = lab.reset({"preset":"ABI004", "target":"caster", "initial_hp":100, "target_max_hp":100,
		"damage":150, "incoming_damage":100, "incoming_hits":1, "event_order":"damage_first"})
	if bool(setup.get("ok",false)):
		var self_death := lab.next_round()
		_check(bool(self_death.get("one_shot_kill",false)) and bool(self_death.get("death_finalized",false)), "player self-heal cannot defeat one-shot rule")
		_check(int(self_death.get("hp_after",-1)) == 0 and bool(self_death.get("lab_finished",false)), "self death ends lab scenario and displays zero HP")

static func _first_effect_stacks(result: Dictionary, effect_id: String) -> int:
	for raw_effect in Array(result.get("effects", [])):
		var eff: Dictionary = raw_effect
		if String(eff.get("effect_id","")) == effect_id:
			return int(eff.get("stacks",0))
	return 0
