extends SceneTree

const PREPARATION_EFF_FIXTURES = {
	"EFF_PREP_TEST": {"kind":"buff", "duration_rounds":2, "damage_reduction":0.5},
	"EFF_PREP_DEBUFF": {"kind":"debuff", "duration_rounds":2, "damage_reduction":-0.15},
	"EFF_PREP_DOT": {"kind":"dot", "duration_rounds":2, "damage":8, "damage_type":"fire"},
	"EFF_PREP_HOT": {"kind":"hot", "duration_rounds":2, "healing":8},
	"EFF_PREP_STUN": {"kind":"stun", "duration_rounds":2},
	"EFF_PREP_DISGUISED_CONTROL": {"kind":"debuff", "duration_rounds":2, "tempo_modifier":-100}
}

## Locked simultaneous intents: only designated preparation ABI precede combat math.
## Damage and healing share the same provisional HP pool; one-shot wins at end.
func _init() -> void:
	var ok := _test_preparation_effect() and _test_application_timing() and _test_delayed_ability_once() and _test_delayed_damage_cancelled_on_death() and _test_heal_damage_commute() and _test_cleansing_targets()
	print("INTEGRATED_ROUND_PHASES_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _test_preparation_effect() -> bool:
	var immediate_hp: int = _run_prep_case("immediate")
	var next_round_hp: int = _run_prep_case("next_round")
	var ok: bool = immediate_hp==80 and next_round_hp==60
	if not ok:
		print("ABI_TIMING_PREP_FAIL immediate=",immediate_hp," deferred=",next_round_hp)
	return ok

## No EFF/category inspection: one explicit setting governs the whole ABI.
func _test_application_timing() -> bool:
	var components: Array[Dictionary] = [
		{"kind":"heal","amount":50},
		{"kind":"damage","amount":20,"damage_type":"fire"},
		{"kind":"effect","effect_id":"EFF_PREP_DOT"},
		{"kind":"effect","effect_id":"EFF_PREP_STUN"},
		{"kind":"cleanse","dispel_polarity":"BUFF"}
	]
	for part in components:
		var now: Dictionary = {"application_timing":"immediate","components":[part]}
		var later: Dictionary = {"application_timing":"next_round","components":[part]}
		if AbilityRuntime.application_timing(now)!="immediate" or AbilityRuntime.application_timing(later)!="next_round":
			return false
		if not AbilityRuntime.validate_definition("ABI_NOW",now).is_empty():
			return false
		if not AbilityRuntime.validate_definition("ABI_LATER",later).is_empty():
			return false
	var mixed:Dictionary={"application_timing":"next_round","components":[components[0],components[2]]}
	if AbilityRuntime.application_timing(mixed)!="next_round":
		return false
	var invalid:Dictionary={"application_timing":"when_crit","components":[components[0]]}
	if not AbilityRuntime.validate_definition("ABI_INVALID",invalid).has("invalid_application_timing"):
		return false
	return AbilityRuntime.application_timing({"components":[components[0]]})=="immediate"

func _run_prep_case(timing: String) -> int:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("attacker","Attacker",5,100)
	var target := TestFixtureLoader.new_combatant("target","Target",5,100)
	state.add_combatant(attacker)
	state.add_combatant(target)
	state.begin_round()
	var engine := CombatEngine.new(state, {"effects":PREPARATION_EFF_FIXTURES})
	var round := CombatRound.new(state.round_number)
	var definition := {
		"application_timing":timing,
		"target_team":"ALLY",
		"components":[{"kind":"effect","effect_id":"EFF_PREP_TEST","base_chance":100}]
	}
	var buff := AbilityRuntime.build_action_event(state,"target","target","ABI_PREP_TEST",definition)
	round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"attacker","target",{"amount":40.0,"damage_type":"physical"}))
	round.lock_action(buff)
	round.resolve(engine)
	# The immediate defensive EFF must protect this round even when locked
	# after the incoming damage. NEXT_ROUND cannot affect this round's damage.
	return target.hp

func _test_delayed_ability_once() -> bool:
	var state := CombatState.new()
	var caster := TestFixtureLoader.new_combatant("caster","Caster",5,100)
	var target := TestFixtureLoader.new_combatant("target","Target",5,100,50)
	target.hp=50
	state.add_combatant(caster)
	state.add_combatant(target)
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine)
	var first := orchestrator.begin_round()
	var ability:Dictionary={
		"application_timing":"next_round",
		"target_team":"ALLY",
		"mana_cost":10,
		"cooldown_rounds":1,
		"components":[{"kind":"heal","amount":30}]
	}
	var scheduler:=AbilityScheduler.new({"ABI_DELAYED_HEAL":ability},{"target":["ABI_DELAYED_HEAL"]})
	var cast:=scheduler.cast_event(state,"target","target","ABI_DELAYED_HEAL")
	if cast==null or target.mana!=40:
		return false
	first.lock_action(cast)
	orchestrator.resolve_locked_actions(first)
	if target.hp!=50 or target.mana!=40 or state.scheduled_abi_intents.size()!=1:
		return false
	orchestrator.end_round()
	var second := orchestrator.begin_round()
	second.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"caster","target",{"amount":20.0,"damage_type":"physical"}))
	orchestrator.resolve_locked_actions(second)
	if target.hp!=60 or target.mana!=40 or not state.scheduled_abi_intents.is_empty():
		return false
	orchestrator.end_round()
	var third := orchestrator.begin_round()
	orchestrator.resolve_locked_actions(third)
	orchestrator.end_round()
	var original_actions:=0
	var executed_actions:=0
	for event in state.event_log:
		if String(event.payload.get("ability_id",""))=="ABI_DELAYED_HEAL" and event.kind==CombatEvent.Kind.ACTION:
			if String(event.result.get("outcome",""))=="scheduled_next_round":
				original_actions+=1
			elif int(event.payload.get("scheduled_from_round",-1))==1:
				executed_actions+=1
	return original_actions==1 and executed_actions==1 and target.hp==60

## A delayed offensive ABI resolves exactly once next round. If its caster
## died in the declared round, the action is canceled by ordinary death rules.
func _test_delayed_damage_cancelled_on_death() -> bool:
	for kill_caster in [false, true]:
		var state:=CombatState.new()
		var actor:=TestFixtureLoader.new_combatant("actor","Actor",5,100)
		var victim:=TestFixtureLoader.new_combatant("victim","Victim",5,100)
		state.add_combatant(actor)
		state.add_combatant(victim)
		var engine:=CombatEngine.new(state)
		var orchestrator:=RoundOrchestrator.new(state,engine)
		var round_one:=orchestrator.begin_round()
		var delayed:Dictionary={"application_timing":"next_round","components":[{"kind":"damage","amount":25.0,"damage_type":"physical"}]}
		round_one.lock_action(AbilityRuntime.build_action_event(state,"actor","victim","ABI_DELAYED_STRIKE",delayed))
		if kill_caster:
			round_one.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"victim","actor",{"amount":100.0,"damage_type":"physical"}))
		orchestrator.resolve_locked_actions(round_one)
		if victim.hp!=100:
			return false
		orchestrator.end_round()
		if actor.is_death_finalized()!=kill_caster:
			return false
		var round_two:=orchestrator.begin_round()
		orchestrator.resolve_locked_actions(round_two)
		orchestrator.end_round()
		if victim.hp!=(100 if kill_caster else 75):
			return false
		var fired:=0
		for event in state.event_log:
			if event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI_DELAYED_STRIKE" and int(event.payload.get("scheduled_from_round",-1))==1:
				fired+=1
				if kill_caster and String(event.result.get("outcome",""))!="source_dead":
					return false
		if fired!=1:
			return false
	return true

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
