extends SceneTree

## Locked simultaneous intents: only designated preparation ABI precede combat math.
## Damage and healing share the same provisional HP pool; one-shot wins at end.
func _init() -> void:
	var ok := _test_preparation_effect() and _test_heal_damage_commute() and _test_cleansing_targets()
	print("INTEGRATED_ROUND_PHASES_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _test_preparation_effect() -> bool:
	var damage_after_prep := _run_prep_case(true)
	var damage_without_prep := _run_prep_case(false)
	var pure_preparation := AbilityRuntime.resolution_phase({
		"combat_role":"DEBUFF",
		"components":[{"kind":"effect","effect_id":"EFF_PREP_TEST"}]
	}) == "PREPARATION"
	var mixed_stays_combat := AbilityRuntime.resolution_phase({
		"combat_role":"DEBUFF",
		"components":[{"kind":"damage","amount":2.0,"damage_type":"fire"},{"kind":"effect","effect_id":"EFF_PREP_TEST"}]
	}) == "COMBAT"
	var control_stays_combat := AbilityRuntime.resolution_phase({
		"combat_role":"CONTROL",
		"components":[{"kind":"effect","effect_id":"EFF_PREP_TEST"}]
	}) == "COMBAT"
	var ok := damage_after_prep == 80 and damage_without_prep == 60 and pure_preparation and mixed_stays_combat and control_stays_combat
	if not ok:
		print("PREPARATION_PHASE_FAIL with_prep_hp=",damage_after_prep," without_prep_hp=",damage_without_prep)
	return ok

func _run_prep_case(is_preparation: bool) -> int:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("attacker","Attacker",5,100)
	var target := TestFixtureLoader.new_combatant("target","Target",5,100)
	state.add_combatant(attacker)
	state.add_combatant(target)
	state.begin_round()
	var engine := CombatEngine.new(state,{"effects":{
		"EFF_PREP_TEST":{"kind":"buff","duration_rounds":2,"damage_reduction":0.5}
	}})
	var round := CombatRound.new(state.round_number)
	var definition := {
		"combat_role":"BUFF" if is_preparation else "CONTROL",
		"target_team":"ALLY",
		"components":[{"kind":"effect","effect_id":"EFF_PREP_TEST","base_chance":100}]
	}
	var buff := AbilityRuntime.build_action_event(state,"target","target","ABI_PREP_TEST",definition)
	round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"attacker","target",{"amount":40.0,"damage_type":"physical"}))
	round.lock_action(buff) # Locking order does not override phase classification.
	round.resolve(engine)
	return target.hp

func _test_heal_damage_commute() -> bool:
	var a := _resolve_hp_case(false,false,false)
	var b := _resolve_hp_case(true,false,false)
	var cap := _resolve_hp_case(true,true,false)
	var one_shot := _resolve_hp_case(true,false,true)
	var ok := a == 70 and b == 70 and cap == 100 and one_shot == -1
	if not ok:
		print("HEAL_DAMAGE_COMMUTE_FAIL damage_first=",a," heal_first=",b," capped=",cap," one_shot=",one_shot)
	return ok

func _resolve_hp_case(heal_first: bool, overheal_only: bool, lethal_one_shot: bool) -> int:
	var state := CombatState.new()
	var actor := TestFixtureLoader.new_combatant("actor","Actor",5,100)
	var target := TestFixtureLoader.new_combatant("target","Target",5,100)
	target.hp = 90
	state.add_combatant(actor)
	state.add_combatant(target)
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine)
	var round := orchestrator.begin_round()
	var heal := AbilityRuntime.build_action_event(state,"target","target","ABI_HEAL_TEST",{
		"target_team":"ALLY",
		"components":[{"kind":"heal","amount":50.0}]
	})
	var damage := state.create_event(CombatEvent.Kind.DAMAGE,"actor","target",{
		"amount":100.0 if lethal_one_shot else 70.0,"damage_type":"physical"
	})
	if heal_first:
		round.lock_action(heal)
		if not overheal_only: round.lock_action(damage)
	else:
		if not overheal_only: round.lock_action(damage)
		round.lock_action(heal)
	orchestrator.resolve_locked_actions(round)
	orchestrator.end_round()
	if target.is_death_finalized():
		return -1
	return target.hp

## Dispel enemy beneficial EFF before damage, cleanse harmful EFF from ally,
## but never cleanse the wrong team or a nonmatching polarity.
func _test_cleansing_targets() -> bool:
	var enemy_case := _cleanse_case(true)
	var ally_case := _cleanse_case(false)
	if not enemy_case or not ally_case:
		print("CLEANSE_PHASE_FAIL enemy=",enemy_case," ally=",ally_case)
	return enemy_case and ally_case

func _cleanse_case(enemy_buff: bool) -> bool:
	var state := CombatState.new()
	var source := TestFixtureLoader.new_combatant("source","Source",5,100)
	var friend := TestFixtureLoader.new_combatant("friend","Friend",5,100)
	var enemy := TestFixtureLoader.new_combatant("enemy","Enemy",5,100)
	state.add_combatant(source)
	state.add_combatant(friend)
	state.add_combatant(enemy)
	var groups := GroupCombatState.new(state)
	groups.add_member("A","source")
	groups.add_member("A","friend")
	groups.add_member("B","enemy")
	var target: CombatantState = enemy if enemy_buff else friend
	var effect_id := "EFF_POSITIVE" if enemy_buff else "EFF_NEGATIVE"
	var definition: Dictionary = {"kind":"buff","damage_reduction":0.5,"duration_rounds":3} if enemy_buff else {"kind":"dot","damage":10,"damage_type":"fire","duration_rounds":3}
	target.active_effects.append({
		"effect_id":effect_id,"definition":definition,
		"source_id":"source","start_round":1,"remaining_rounds":3,"stacks":1
	})
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine,groups)
	var round := orchestrator.begin_round()
	var polarity := "BUFF" if enemy_buff else "DEBUFF"
	var team := "ENEMY" if enemy_buff else "ALLY"
	var ability_definition := {"combat_role":"CLEANSE","target_team":team,"components":[{"kind":"cleanse","dispel_polarity":polarity,"max_effects":1}]}
	if not AbilityRuntime.validate_definition("ABI_CLEANSE",ability_definition).is_empty():
		return false
	var cast := AbilityRuntime.build_action_event(state,"source",target.combatant_id,"ABI_CLEANSE",ability_definition)
	round.lock_action(cast)
	if enemy_buff:
		round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"source","enemy",{"amount":40.0,"damage_type":"physical"}))
	orchestrator.resolve_locked_actions(round)
	var found_cleanse := false
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("dispel_polarity","")) == polarity:
			found_cleanse = int(event.result.get("removed_count",0)) == 1
	if not found_cleanse or target.active_effects.size() != 0:
		return false
	var result := orchestrator.end_round()
	if not Array(result.get("dead_ids",[])).is_empty():
		return false
	return enemy.hp == 60 if enemy_buff else friend.hp == 100
