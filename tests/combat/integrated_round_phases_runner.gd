extends SceneTree

const PREPARATION_EFF_FIXTURES = {
	"EFF_PREP_TEST": {"kind":"buff", "duration_rounds":2, "damage_reduction":0.5},
	"EFF_PREP_DEBUFF": {"kind":"debuff", "duration_rounds":2, "damage_reduction":-0.15},
	"EFF_PREP_DOT": {"kind":"dot", "duration_rounds":2, "damage":8, "damage_type":"fire"},
	"EFF_PREP_HOT": {"kind":"hot", "duration_rounds":2, "healing":8},
	"EFF_PREP_STUN": {"kind":"stun", "duration_rounds":2},
	"EFF_PREP_DISGUISED_CONTROL": {"kind":"debuff", "duration_rounds":2, "tempo_modifier":-100}
}

## Every ABI applies in the currently locked round:
## instant at its beginning, standard with its ordinary shared calculation.
## HP remains provisional until end_round and EFF has its own lifecycle.
func _init() -> void:
	var ok := _test_timing_setting() and _test_early_defence() and _test_both_abi_same_round() and _test_no_action_canceled_by_provisional_death() and _test_heal_damage_commute() and _test_cleansing_targets()
	print("INTEGRATED_ROUND_PHASES_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

## Timing is authored manually. Damage and healing (including DoT/HoT)
## must be Standard; protective and cleansing effects may be Instant.
func _test_timing_setting() -> bool:
	var standard_only: Array[Dictionary] = [
		{"kind":"heal","amount":50},
		{"kind":"damage","amount":20,"damage_type":"fire"},
		{"kind":"effect","effect_id":"EFF003"},
		{"kind":"effect","effect_id":"EFF004"}
	]
	for component in standard_only:
		var standard: Dictionary = {"application_timing":"standard","target_team":"ENEMY","components":[component]}
		if AbilityRuntime.application_timing(standard)!="standard" or not AbilityRuntime.validate_definition("ABI_TIMING_TEST",standard).is_empty():
			return false
		var instant: Dictionary = standard.duplicate(true)
		instant["application_timing"]="instant"
		if AbilityRuntime.validate_definition("ABI_TIMING_TEST",instant).is_empty():
			return false
	var instant_ok: Array[Dictionary] = [
		{"kind":"effect","effect_id":"EFF_PREP_STUN"},
		{"kind":"cleanse","dispel_polarity":"BUFF"}
	]
	for component in instant_ok:
		for timing in ["instant","standard"]:
			var definition:Dictionary={"application_timing":timing,"target_team":"ENEMY","components":[component]}
			if AbilityRuntime.application_timing(definition)!=timing or not AbilityRuntime.validate_definition("ABI_TIMING_TEST",definition).is_empty():
				return false
	var mixed: Dictionary = {"application_timing":"instant","components":[standard_only[0],instant_ok[0]]}
	if AbilityRuntime.application_timing(mixed)!="instant" or AbilityRuntime.validate_definition("ABI_MIXED",mixed).is_empty():
		return false
	for invalid_timing in ["next_round","immediate","when_crit"]:
		var invalid:Dictionary={"application_timing":invalid_timing,"components":[standard_only[0]]}
		if not AbilityRuntime.validate_definition("ABI_INVALID_TIMING",invalid).has("invalid_application_timing"):
			return false
	return AbilityRuntime.application_timing({"components":[standard_only[0]]})=="standard"

func _test_early_defence() -> bool:
	var early_hp: int = _run_defence_case("instant")
	var standard_hp: int = _run_defence_case("standard")
	if early_hp!=80 or standard_hp!=60:
		print("ABI_TIMING_PHASE_FAIL instant=",early_hp," standard=",standard_hp)
		return false
	return true

func _run_defence_case(timing:String) -> int:
	var state:=CombatState.new()
	var attacker:=TestFixtureLoader.new_combatant("attacker","Attacker",5,100)
	var target:=TestFixtureLoader.new_combatant("target","Target",5,100)
	state.add_combatant(attacker)
	state.add_combatant(target)
	state.begin_round()
	var engine:=CombatEngine.new(state,{"effects":PREPARATION_EFF_FIXTURES})
	var round:=CombatRound.new(state.round_number)
	var definition:Dictionary={
		"application_timing":timing,
		"target_team":"ALLY",
		"components":[{"kind":"effect","effect_id":"EFF_PREP_TEST","base_chance":100}]
	}
	# Lock the attack FIRST; an instant defence must still resolve before it.
	round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"attacker","target",{"amount":40.0,"damage_type":"physical"}))
	round.lock_action(AbilityRuntime.build_action_event(state,"target","target","ABI_DEFENCE",definition))
	round.resolve(engine)
	return target.hp

func _test_both_abi_same_round() -> bool:
	# Two actors' standard ABI both resolve in the current round, with no
	# queue for the next round and no double payment.
	var state:=CombatState.new()
	var actor:=TestFixtureLoader.new_combatant("actor","Actor",5,100,50)
	var target:=TestFixtureLoader.new_combatant("target","Target",5,100,50)
	target.hp=60
	state.add_combatant(actor)
	state.add_combatant(target)
	var engine:=CombatEngine.new(state)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var round:=orchestrator.begin_round()
	var definitions:Dictionary={
		"ABI_STANDARD_HIT":{"application_timing":"standard","components":[{"kind":"damage","amount":20,"damage_type":"physical"}],"mana_cost":10},
		"ABI_STANDARD_HEAL":{"application_timing":"standard","target_team":"ALLY","components":[{"kind":"heal","amount":30}],"mana_cost":10}
	}
	var scheduler:=AbilityScheduler.new(definitions,{"actor":["ABI_STANDARD_HIT"],"target":["ABI_STANDARD_HEAL"]})
	var hit:=scheduler.cast_event(state,"actor","target","ABI_STANDARD_HIT")
	var heal:=scheduler.cast_event(state,"target","target","ABI_STANDARD_HEAL")
	if hit==null or heal==null or actor.mana!=40 or target.mana!=40:
		return false
	round.lock_action(hit)
	round.lock_action(heal)
	orchestrator.resolve_locked_actions(round)
	# No HP clamping until end of round; both abilities already ran.
	if target.hp!=70 or state.round_number!=1:
		return false
	orchestrator.end_round()
	var action_count:=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id","")) in ["ABI_STANDARD_HIT","ABI_STANDARD_HEAL"]:
			if int(event.payload.get("round",-1))!=1:
				return false
			action_count+=1
	return action_count==2 and target.hp==70 and actor.mana==40 and target.mana==40

func _test_no_action_canceled_by_provisional_death() -> bool:
	# Both participants start their standard ABI in this round. A provisional
	# negative HP does not cancel the already locked action of the other actor.
	var state:=CombatState.new()
	var actor:=TestFixtureLoader.new_combatant("actor","Actor",5,100)
	var victim:=TestFixtureLoader.new_combatant("victim","Victim",5,100)
	actor.hp=10
	victim.hp=10
	state.add_combatant(actor)
	state.add_combatant(victim)
	var engine:=CombatEngine.new(state)
	var orchestrator:=RoundOrchestrator.new(state,engine)
	var round:=orchestrator.begin_round()
	var standard:Dictionary={"application_timing":"standard","components":[{"kind":"damage","amount":20,"damage_type":"physical"}]}
	round.lock_action(AbilityRuntime.build_action_event(state,"actor","victim","ABI_ACTOR",standard))
	round.lock_action(AbilityRuntime.build_action_event(state,"victim","actor","ABI_VICTIM",standard))
	orchestrator.resolve_locked_actions(round)
	if actor.hp!=-10 or victim.hp!=-10 or actor.is_death_finalized() or victim.is_death_finalized():
		return false
	orchestrator.end_round()
	return actor.is_death_finalized() and victim.is_death_finalized()

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
	var ability_definition := {"application_timing":"instant","combat_role":"CLEANSE","target_team":team,"components":[{"kind":"cleanse","dispel_polarity":polarity,"max_effects":1}]}
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
