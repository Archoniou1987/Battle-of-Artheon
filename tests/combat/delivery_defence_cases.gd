class_name DeliveryDefenceCases
extends RefCounted

static func run(balance: Dictionary) -> bool:
	return (
		_case_projectile_can_dodge(balance)
		and _case_projectile_magic_ignores_physical_block(balance)
		and _case_melee_physical_can_block(balance)
		and _case_manual_block_uses_explicit_shield_sector(balance)
		and _case_bow_loadout_has_no_block(balance)
		and _case_direct_bypasses_active_defence(balance)
	)

static func _state() -> CombatState:
	var state := CombatState.new()
	var source := CombatantState.new("source", "Source", 10, 100)
	var target := CombatantState.new("target", "Target", 10, 100)
	state.add_combatant(source)
	state.add_combatant(target)
	state.begin_round()
	return state

static func _action(state:CombatState, delivery:String, damage_type:String, rolls:Dictionary) -> CombatEvent:
	var event := AbilityRuntime.build_action_event(state, "source", "target", "ABI_DEFENCE", {
		"delivery_type": delivery,
		"target_scope": "SINGLE",
		"components": [{"kind":"damage","amount":10,"damage_type":damage_type}]
	})
	event.payload["rolls"] = rolls
	return event

static func _resolve(state:CombatState, balance:Dictionary, event:CombatEvent) -> void:
	state.queue_event(event)
	CombatEngine.new(state, balance).resolve_pending_events()

static func _case_projectile_can_dodge(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").combat_stats["dodge"] = 100.0
	var event := _action(state, "PROJECTILE", "fire", {"hit":1,"dodge":1})
	_resolve(state, balance, event)
	return state.get_combatant("target").hp == 100 and _child_outcome(state, event.event_id) == "dodge"

static func _case_projectile_magic_ignores_physical_block(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").combat_stats["manual_block_zone"] = "chest"
	state.get_combatant("target").combat_stats["auto_block"] = 100.0
	var event := _action(state, "PROJECTILE", "fire", {"hit":1,"dodge":100,"auto_block":1,"crit":100})
	_resolve(state, balance, event)
	return state.get_combatant("target").hp == 90 and _child_outcome(state, event.event_id) == "connected"

static func _case_melee_physical_can_block(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").combat_stats["manual_block_zone"] = "chest"
	var event := _action(state, "MELEE", "physical", {"hit":1,"dodge":100,"block_crush":100})
	_resolve(state, balance, event)
	return state.get_combatant("target").hp == 100 and _child_outcome(state, event.event_id) == "manual_block"

static func _case_direct_bypasses_active_defence(balance:Dictionary) -> bool:
	var state := _state()
	state.get_combatant("target").combat_stats["dodge"] = 100.0
	state.get_combatant("target").combat_stats["manual_block_zone"] = "chest"
	state.get_combatant("target").combat_stats["auto_block"] = 100.0
	var event := _action(state, "DIRECT", "lightning", {"hit":100,"dodge":1,"auto_block":1})
	_resolve(state, balance, event)
	return state.get_combatant("target").hp == 90 and _has_direct_damage_child(state, event.event_id)

static func _child_outcome(state:CombatState, parent_id:int) -> String:
	for logged in state.event_log:
		if logged.parent_event_id == parent_id and logged.kind == CombatEvent.Kind.ATTACK:
			return String(logged.result.get("outcome", ""))
	return ""

static func _has_direct_damage_child(state:CombatState, parent_id:int) -> bool:
	for logged in state.event_log:
		if logged.parent_event_id == parent_id and logged.kind == CombatEvent.Kind.DAMAGE:
			return true
	return false


static func _case_manual_block_uses_explicit_shield_sector(balance:Dictionary)->bool:
	var state:=_state()
	var target:=state.get_combatant("target")
	target.combat_stats["manual_block_zone_count"]=2
	target.combat_stats["manual_block_zones"]=["head","chest"]
	var blocked:=_action(state,"MELEE","physical",{"hit":1,"dodge":100,"block_crush":100})
	blocked.payload["components"][0]["zone"]="head"
	_resolve(state,balance,blocked)
	if target.hp!=100 or _child_outcome(state,blocked.event_id)!="manual_block":
		return false
	var open_zone:=_action(state,"MELEE","physical",{"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100})
	open_zone.payload["components"][0]["zone"]="arms"
	_resolve(state,balance,open_zone)
	return target.hp==90 and _child_outcome(state,open_zone.event_id)=="connected"


static func _case_bow_loadout_has_no_block(balance:Dictionary)->bool:
	var state:=_state()
	var target:=state.get_combatant("target")
	target.combat_stats["manual_block_zone"]="chest"
	target.combat_stats["auto_block"]=100.0
	target.combat_stats["can_manual_block"]=false
	target.combat_stats["can_auto_block"]=false
	target.lock_combat_loadout({"weapon_class":"bow","can_manual_block":false,"can_auto_block":false})
	var event:=_action(state,"MELEE","physical",{"hit":1,"dodge":100,"auto_block":1,"block_crush":100,"crit":100})
	_resolve(state,balance,event)
	return target.hp==90 and _child_outcome(state,event.event_id)=="connected"
