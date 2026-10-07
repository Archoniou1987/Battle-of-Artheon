class_name AoeCases
extends RefCounted

static func run(base_balance:Dictionary) -> bool:
	var balance:=base_balance.duplicate(true)
	var effects:Dictionary=balance.get("effects",{}).duplicate(true)
	effects["EFF_FREEZE"]={"id":"EFF_FREEZE","kind":"freeze","duration_rounds":1,"stacking":"unique","max_stacks":1}
	balance["effects"]=effects
	return _damage_budget(balance) and _effect_budget(balance) and _no_upscale(balance) and _deduplicates_targets(balance)

static func _state(count:int)->CombatState:
	var state:=CombatState.new()
	state.add_combatant(CombatantState.new("source","Source",10,1000))
	for i in range(count):
		state.add_combatant(CombatantState.new("t%d"%i,"Target",10,1000))
	state.begin_round()
	return state

static func _targets(count:int)->Array[String]:
	var ids:Array[String]=[]
	for i in range(count): ids.append("t%d"%i)
	return ids

static func _blizzard(state:CombatState,count:int)->CombatEvent:
	var event:=AbilityRuntime.build_action_event(state,"source","t0","ABI006",{
		"delivery_type":"AREA","target_scope":"ALL_ENEMIES",
		"components":[
			{"kind":"damage","amount":25.0,"damage_type":"frost","full_targets":5},
			{"kind":"effect","effect_id":"EFF_FREEZE","base_chance":80.0,"resist_type":"water","effect_roll":100,"full_targets":3}
		]
	})
	event.payload["target_ids"]=_targets(count)
	return event

static func _damage_budget(balance:Dictionary)->bool:
	var state:=_state(10)
	var event:=_blizzard(state,10)
	state.queue_event(event); CombatEngine.new(state,balance).resolve_pending_events()
	for id in _targets(10):
		if state.get_combatant(id).hp != 988: return false
	return true

static func _effect_budget(balance:Dictionary)->bool:
	var state:=_state(10)
	var event:=_blizzard(state,10)
	event.payload["effect_roll"]=24
	var components:Array=event.payload["components"]
	components[1]["effect_roll"]=24
	state.queue_event(event); CombatEngine.new(state,balance).resolve_pending_events()
	var effect_events:=0
	for logged in state.event_log:
		if logged.kind==CombatEvent.Kind.EFFECT and logged.parent_event_id==event.event_id:
			effect_events+=1
			if not is_equal_approx(float(logged.result.get("base_chance",0.0)),24.0): return false
	return effect_events==10

static func _no_upscale(balance:Dictionary)->bool:
	var state:=_state(3)
	var event:=_blizzard(state,3)
	state.queue_event(event); CombatEngine.new(state,balance).resolve_pending_events()
	for id in _targets(3):
		if state.get_combatant(id).hp != 975: return false
	return true

static func _deduplicates_targets(balance:Dictionary)->bool:
	var state:=_state(2)
	var event:=_blizzard(state,2)
	event.payload["target_ids"]=["t0","t0","t1","missing"]
	state.queue_event(event); CombatEngine.new(state,balance).resolve_pending_events()
	return event.result.get("resolved_target_ids",[]).size()==2 and state.get_combatant("t0").hp==975 and state.get_combatant("t1").hp==975
