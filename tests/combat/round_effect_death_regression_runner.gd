extends SceneTree

## Combined end-of-round invariants through the REAL orchestrator and engine:
## simultaneous damage/heal, timed DoT/HoT, cleanse, one-shot and finalized death.
## These tests add coverage; they do not change the gameplay contract.
const DOT_ID := "EFF_ROUND_REGRESSION_DOT"
const HOT_ID := "EFF_ROUND_REGRESSION_HOT"

func _init() -> void:
	var cases: Array[Dictionary] = [
		{"id":"damage_heal_hot_order", "ok":_test_damage_heal_hot_order()},
		{"id":"one_shot_heal_hot", "ok":_test_one_shot_heal_hot()},
		{"id":"dot_hot_order", "ok":_test_dot_hot_order()},
		{"id":"cleanse_prevents_dot_tick", "ok":_test_cleanse_prevents_dot_tick()},
		{"id":"cleanse_skips_future_effect", "ok":_test_cleanse_skips_future_effect()},
		{"id":"death_finalized_once", "ok":_test_death_finalized_once()}
	]
	var all_pass := true
	for item in cases:
		print("ROUND_EFFECT_DEATH_CASE=", item["id"], " ", "PASS" if bool(item["ok"]) else "FAIL")
		all_pass = all_pass and bool(item["ok"])
	print("ROUND_EFFECT_DEATH_REGRESSION=", "PASS" if all_pass else "FAIL")
	quit(0 if all_pass else 1)

func _fixture() -> Dictionary:
	var state := CombatState.new()
	var attacker := TestFixtureLoader.new_combatant("attacker","Attacker",5,100)
	var target := TestFixtureLoader.new_combatant("target","Target",5,100)
	state.add_combatant(attacker)
	state.add_combatant(target)
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine)
	return {"state":state,"attacker":attacker,"target":target,"orchestrator":orchestrator}

func _add_timed(target:CombatantState,id:String,definition:Dictionary,source_id:String,start_round:int=1) -> void:
	target.active_effects.append({
		"effect_id":id,
		"definition":definition.duplicate(true),
		"source_id":source_id,
		"start_round":start_round,
		"remaining_rounds":2,
		"stacks":1,
		"active_stacks":1
	})

func _hot_definition() -> Dictionary:
	return {"kind":"hot","healing":20,"duration_rounds":2,"stacking":"shared_duration"}

func _dot_definition() -> Dictionary:
	return {"kind":"dot","damage":30,"damage_type":"physical","duration_rounds":2,"stacking":"shared_duration"}

func _count_tick(state:CombatState,kind:CombatEvent.Kind,id:String,round_no:int) -> int:
	var count := 0
	for event in state.event_log:
		if event.kind==kind and String(event.payload.get("effect_id",""))==id and int(event.payload.get("round",-1))==round_no and String(event.payload.get("source",""))=="effect":
			count+=1
	return count

func _direct_case(heal_first:bool,damage:int) -> Dictionary:
	var scene := _fixture()
	var state:CombatState=scene["state"]
	var target:CombatantState=scene["target"]
	var orchestrator:RoundOrchestrator=scene["orchestrator"]
	target.hp=70
	_add_timed(target,HOT_ID,_hot_definition(),"target")
	var combat_round:=orchestrator.begin_round()
	var healing:=state.create_event(CombatEvent.Kind.EFFECT,"target","target",{"inline_heal":60,"source":"ability"})
	var strike:=state.create_event(CombatEvent.Kind.DAMAGE,"attacker","target",{"amount":float(damage),"damage_type":"physical"})
	if heal_first:
		combat_round.lock_action(healing)
		combat_round.lock_action(strike)
	else:
		combat_round.lock_action(strike)
		combat_round.lock_action(healing)
	orchestrator.resolve_locked_actions(combat_round)
	var summary:Dictionary=orchestrator.end_round()
	return {
		"hp":target.hp,
		"visible_hp":target.visible_hp(),
		"dead":target.is_death_finalized(),
		"one_shot":target.one_shot_kill,
		"deaths":Array(summary.get("dead_ids",[])),
		"killers":Dictionary(summary.get("kill_attribution",{})).get("target",[]),
		"hot_ticks":_count_tick(state,CombatEvent.Kind.EFFECT,HOT_ID,1),
		"round":state.round_number
	}

func _test_damage_heal_hot_order() -> bool:
	var heal_first:=_direct_case(true,80)
	var damage_first:=_direct_case(false,80)
	# 70 + 60 - 80 + 20 = 70, irrespective of input or EFF tick order.
	for item in [heal_first,damage_first]:
		if int(item["hp"])!=70 or bool(item["dead"]) or bool(item["one_shot"]):
			print("ROUND_NET_HP_FAIL=",item)
			return false
		if int(item["hot_ticks"])!=1 or not Array(item["deaths"]).is_empty():
			return false
	return heal_first==damage_first

func _test_one_shot_heal_hot() -> bool:
	var heal_first:=_direct_case(true,100)
	var damage_first:=_direct_case(false,100)
	# A single 100-HP hit remains fatal even though net HP is positive:
	# 70 + 60 - 100 + 20 = 50.
	for item in [heal_first,damage_first]:
		if not bool(item["dead"]) or not bool(item["one_shot"]):
			print("ROUND_ONE_SHOT_FAIL=",item)
			return false
		if int(item["hp"])!=50 or int(item["visible_hp"])!=0:
			return false
		if Array(item["deaths"])!=["target"] or Array(item["killers"])!=["attacker"]:
			return false
		if int(item["hot_ticks"])!=1:
			return false
	return heal_first==damage_first

func _dot_hot_case(dot_first:bool) -> Dictionary:
	var scene:=_fixture()
	var state:CombatState=scene["state"]
	var target:CombatantState=scene["target"]
	var orchestrator:RoundOrchestrator=scene["orchestrator"]
	target.hp=10
	if dot_first:
		_add_timed(target,DOT_ID,_dot_definition(),"attacker")
		_add_timed(target,HOT_ID,_hot_definition(),"target")
	else:
		_add_timed(target,HOT_ID,_hot_definition(),"target")
		_add_timed(target,DOT_ID,_dot_definition(),"attacker")
	var combat_round:=orchestrator.begin_round()
	orchestrator.resolve_locked_actions(combat_round)
	var summary:Dictionary=orchestrator.end_round()
	return {
		"hp":target.hp,
		"dead":target.is_death_finalized(),
		"deaths":Array(summary.get("dead_ids",[])),
		"dot":_count_tick(state,CombatEvent.Kind.DAMAGE,DOT_ID,1),
		"hot":_count_tick(state,CombatEvent.Kind.EFFECT,HOT_ID,1)
	}

func _test_dot_hot_order() -> bool:
	var first:=_dot_hot_case(true)
	var second:=_dot_hot_case(false)
	# Both packets happen in the EFF phase; 10 - 30 + 20 = 0 -> dead.
	if int(first["hp"])!=0 or not bool(first["dead"]) or Array(first["deaths"])!=["target"]:
		print("ROUND_DOT_HOT_FAIL=",first)
		return false
	return first==second and int(first["dot"])==1 and int(first["hot"])==1

func _cleanse_case(timing:String) -> bool:
	var scene:=_fixture()
	var state:CombatState=scene["state"]
	var target:CombatantState=scene["target"]
	var orchestrator:RoundOrchestrator=scene["orchestrator"]
	target.hp=45
	_add_timed(target,DOT_ID,_dot_definition(),"attacker")
	# One logical shared-duration DOT with three stacks must be removed as
	# one EFF record by cleanse; none of its stacks can tick afterward.
	target.active_effects[0]["stacks"] = 3
	target.active_effects[0]["active_stacks"] = 3
	var combat_round:=orchestrator.begin_round()
	var cleanse:=AbilityRuntime.build_action_event(state,"target","target","ABI_CLEANSE_DOT",{
		"application_timing":timing,
		"combat_role":"CLEANSE",
		"target_team":"ALLY",
		"components":[{"kind":"cleanse","dispel_polarity":"DEBUFF","max_effects":1}]
	})
	combat_round.lock_action(cleanse)
	orchestrator.resolve_locked_actions(combat_round)
	var removed_count:=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.EFFECT and event.parent_event_id==cleanse.event_id:
			removed_count+=int(event.result.get("removed_count",0))
	var summary:Dictionary=orchestrator.end_round()
	return removed_count==1 and target.hp==45 and target.active_effects.is_empty() and _count_tick(state,CombatEvent.Kind.DAMAGE,DOT_ID,1)==0 and Array(summary.get("dead_ids",[])).is_empty()

func _test_cleanse_prevents_dot_tick() -> bool:
	return _cleanse_case("instant") and _cleanse_case("standard")

func _test_cleanse_skips_future_effect() -> bool:
	var scene:=_fixture()
	var state:CombatState=scene["state"]
	var target:CombatantState=scene["target"]
	var orchestrator:RoundOrchestrator=scene["orchestrator"]
	target.hp=70
	_add_timed(target,DOT_ID,_dot_definition(),"attacker",2)
	var first:=orchestrator.begin_round()
	var cleanse:=AbilityRuntime.build_action_event(state,"target","target","ABI_CLEANSE_PENDING",{
		"application_timing":"instant",
		"target_team":"ALLY",
		"components":[{"kind":"cleanse","dispel_polarity":"DEBUFF","max_effects":1}]
	})
	first.lock_action(cleanse)
	orchestrator.resolve_locked_actions(first)
	var removed:=0
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.EFFECT and event.parent_event_id==cleanse.event_id:
			removed=int(event.result.get("removed_count",0))
	orchestrator.end_round()
	if removed!=0 or target.hp!=70 or target.active_effects.size()!=1:
		return false
	var second:=orchestrator.begin_round()
	orchestrator.resolve_locked_actions(second)
	orchestrator.end_round()
	return target.hp==40 and _count_tick(state,CombatEvent.Kind.DAMAGE,DOT_ID,1)==0 and _count_tick(state,CombatEvent.Kind.DAMAGE,DOT_ID,2)==1

func _test_death_finalized_once() -> bool:
	var scene:=_fixture()
	var state:CombatState=scene["state"]
	var target:CombatantState=scene["target"]
	var orchestrator:RoundOrchestrator=scene["orchestrator"]
	target.hp=10
	var combat_round:=orchestrator.begin_round()
	combat_round.lock_action(state.create_event(CombatEvent.Kind.DAMAGE,"attacker","target",{"amount":30.0,"damage_type":"physical"}))
	orchestrator.resolve_locked_actions(combat_round)
	if target.is_death_finalized() or target.hp!=-20:
		return false
	var first:Dictionary=orchestrator.end_round()
	if Array(first.get("dead_ids",[]))!=["target"] or not target.is_death_finalized():
		return false
	var second_round:=orchestrator.begin_round()
	orchestrator.resolve_locked_actions(second_round)
	var second:Dictionary=orchestrator.end_round()
	return Array(second.get("dead_ids",[])).is_empty() and target.is_death_finalized() and target.restore_hp(50)==0
