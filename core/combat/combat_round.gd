class_name CombatRound
extends RefCounted

## Every ABI is committed for THIS round after all choices are locked.
## "instant" executes first, before shared combat calculations.
## "standard" resolves alongside ordinary attacks/damage/healing/control.
## Nothing is scheduled for a future round and death is finalized later.

var number: int
var locked_actions: Array[CombatEvent] = []
var preparation_actions: Array[CombatEvent] = []
var resolved: bool = false

func _init(round_number: int) -> void:
	number = round_number

func lock_action(event: CombatEvent) -> void:
	if resolved:
		return
	if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("source_kind", "")) == "ability":
		var timing: String = String(event.payload.get("application_timing", "standard"))
		if timing == "instant":
			preparation_actions.append(event)
			return
		if timing != "standard":
			push_error("Invalid ABI application_timing: " + timing)
			return
	locked_actions.append(event)

func resolve(engine: CombatEngine) -> void:
	if resolved:
		return
	# ABI301 enhances the round's existing first MH hit, never inserts a
	# second weapon attack. Attach before the sealed action batch resolves.
	for abi_action in locked_actions:
		if abi_action.kind != CombatEvent.Kind.ACTION or String(abi_action.payload.get("ability_id","")) != "ABI301":
			continue
		for mh in locked_actions:
			if mh.kind != CombatEvent.Kind.ATTACK or mh.source_id != abi_action.source_id:
				continue
			if not bool(mh.payload.get("is_weapon_attack",false)) or int(mh.payload.get("weapon_index",-1)) != 0 or int(mh.payload.get("hit_index",0)) != 0:
				continue
			mh.payload["sword_abi_id"] = "ABI301"
			mh.payload["sword_eff_level"] = int(abi_action.payload.get("sword_eff_level",1))
			mh.payload["sword_mh_bonus_flat"] = float(abi_action.payload.get("mh_flat_bonus",0.0))
			break
	# Axe ABI501 enhances ONE existing ordinary MH attack, never adds a hit.
	for abi_action in locked_actions:
		if abi_action.kind != CombatEvent.Kind.ACTION or String(abi_action.payload.get("ability_id","")) != AxeAbiCombatService.RAGE_ABI:
			continue
		for mh in locked_actions:
			if mh.kind != CombatEvent.Kind.ATTACK or mh.source_id != abi_action.source_id:
				continue
			if not bool(mh.payload.get("is_weapon_attack",false)) or int(mh.payload.get("weapon_index",-1)) != 0 or int(mh.payload.get("hit_index",0)) != 0:
				continue
			mh.payload["axe_abi_id"] = AxeAbiCombatService.RAGE_ABI
			mh.payload["axe_mh_damage_bonus_pct"] = float(abi_action.payload.get("mh_damage_bonus_pct",0.0))
			break
	# Hammer ABI601 similarly buffs the FIRST ordinary MH attack rather
	# than producing a second hit.
	for abi_action in locked_actions:
		if abi_action.kind != CombatEvent.Kind.ACTION or String(abi_action.payload.get("ability_id","")) != HammerAbiCombatService.HEAVY:
			continue
		for mh in locked_actions:
			if mh.kind != CombatEvent.Kind.ATTACK or mh.source_id != abi_action.source_id:
				continue
			if not bool(mh.payload.get("is_weapon_attack",false)) or int(mh.payload.get("weapon_index",-1)) != 0 or int(mh.payload.get("hit_index",0)) != 0:
				continue
			mh.payload["hammer_abi_id"] = HammerAbiCombatService.HEAVY
			mh.payload["hammer_mh_damage_bonus_pct"] = float(abi_action.payload.get("mh_damage_bonus_pct",0.0))
			break
	# Counter ABI inherits the FIRST ordinary MH strike zone in the sealed round.
	# The OH zone is never a fallback. No implicit chest target is permitted.
	var mh_zone_by_source:Dictionary={}
	for attack in locked_actions:
		if attack.kind != CombatEvent.Kind.ATTACK or not bool(attack.payload.get("is_weapon_attack",false)):
			continue
		if int(attack.payload.get("weapon_index",-1))!=0 or int(attack.payload.get("hit_index",0))!=0:
			continue
		if not mh_zone_by_source.has(attack.source_id):
			mh_zone_by_source[attack.source_id]=String(attack.payload.get("zone",""))
	for action in locked_actions:
		if action.kind==CombatEvent.Kind.ACTION and bool(action.payload.get("is_counterattack_abi",false)):
			action.payload["counter_abi_mh_zone"]=String(mh_zone_by_source.get(action.source_id,""))
		if action.kind==CombatEvent.Kind.ACTION and (DaggerAbiCombatService.is_dagger_ability(String(action.payload.get("ability_id",""))) or AxeAbiCombatService.is_axe_ability(String(action.payload.get("ability_id",""))) or HammerAbiCombatService.is_hammer_ability(String(action.payload.get("ability_id","")))):
			if mh_zone_by_source.has(action.source_id):
				action.payload["zone"]=String(mh_zone_by_source[action.source_id])
	# Only instant ABI effects modify the conditions of this round's
	# subsequent shared combat resolution.
	for event in preparation_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	# ABI404/405 apply their current-round defensive/offensive EFF BEFORE
	# any regular attacks, independent of the sealed action order.
	for event in locked_actions:
		if event.kind == CombatEvent.Kind.ACTION and DaggerAbiCombatService.is_dagger_ability(String(event.payload.get("ability_id",""))):
			DaggerAbiCombatService.prepare_action(engine,event)
		if event.kind == CombatEvent.Kind.ACTION and AxeAbiCombatService.is_axe_ability(String(event.payload.get("ability_id",""))):
			AxeAbiCombatService.prepare_action(engine,event)
	engine.resolve_pending_events()
	for event in locked_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	resolved = true
