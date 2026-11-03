class_name SwordAbiCombatService
extends RefCounted

## Physical sword ABI301-308 use the ordinary engine ATTACK/DAMAGE/EFFECT
## events. No parallel damage pipeline, no direct HP writes, and no DoT crit.
const ABILITIES := ["ABI301","ABI302","ABI303","ABI304","ABI305","ABI306","ABI307","ABI308"]
const BLEED := "EFF301"
const DEBUFFS := {"ABI303":"EFF302","ABI304":"EFF303","ABI305":"EFF304"}

static func is_sword_ability(ability_id: String) -> bool:
	return ABILITIES.has(ability_id)

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var mode := String(action.payload.get("sword_ability_mode",""))
	if mode == "single_mh":
		# ABI301 rides the existing MH weapon ATTACK; CombatRound attached
		# its identity before any locked attack was resolved.
		action.set_result("outcome","linked_to_existing_mh")
		action.set_result("child_event_ids",[])
		return
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var mh_profile := {}
	for raw_profile in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw_profile
		if int(profile.get("weapon_index",-1)) == 0 and String(profile.get("weapon_class","")).to_lower() == "sword":
			mh_profile = profile
			break
	if mh_profile.is_empty():
		action.set_result("outcome","sword_mh_required")
		return
	var max_targets := 1
	if mode == "aoe_3":
		max_targets = 3
	elif mode == "dodge_ultimate":
		max_targets = 5
	var targets := _targets(engine, action, max_targets)
	var child_ids: Array[int] = []
	var ap_spent := int(action.payload.get("ap_spent",0))
	for target_id in targets:
		var roll_damage := engine.combat_rng.randf()
		var base_damage := CombatMath.roll_damage(float(mh_profile.get("damage_min",0.0)),float(mh_profile.get("damage_max",0.0)),roll_damage)
		var multiplier := float(action.payload.get("sword_mh_multiplier",1.0))
		if mode == "def_ultimate":
			var armour_total := 0.0
			for zone in CombatEngine.HIT_ZONES:
				# One physical defence value per hit zone. A shield's armour
				# is already incorporated in each zone, NOT counted separately.
				armour_total += float(Dictionary(source.armour.get(zone,{})).get("slashing",0.0))
			base_damage = 0.5 * base_damage + 0.02 * armour_total * float(ap_spent)
		elif mode == "dodge_ultimate":
			base_damage *= multiplier * float(ap_spent)
		else:
			base_damage *= multiplier
		var component := {"damage_type":"slashing","zone":String(action.payload.get("zone","chest"))}
		var payload := CombatDamagePayload.ability_attack_payload(action,component,base_damage,1.0)
		payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
		payload["sword_abi_id"] = String(action.payload.get("ability_id",""))
		payload["sword_eff_level"] = maxi(1,int(action.payload.get("sword_eff_level",1)))
		payload["sword_ap_spent"] = ap_spent
		payload["sword_eff_id"] = String(action.payload.get("sword_eff_id",""))
		if mode == "crit_ultimate":
			payload["sword_crit_chance_pct"] = float(action.payload.get("crit_pct_per_ap",10)) * ap_spent
			payload["sword_crit_damage_pct"] = float(action.payload.get("crit_damage_pct_per_ap",25)) * ap_spent
		var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
		engine.state.queue_event(attack)
		child_ids.append(attack.event_id)
	action.set_result("outcome","dispatched" if not child_ids.is_empty() else "no_reachable_target")
	action.set_result("child_event_ids",child_ids)
	action.set_result("resolved_target_ids",targets)

static func _targets(engine: CombatEngine, action: CombatEvent, limit: int) -> Array[String]:
	var primary := String(action.target_id)
	var source_team := engine.group_state.team_of(action.source_id) if engine.group_state != null else ""
	var eligible: Array[String] = []
	for raw_id in engine.state.combatants.keys():
		var target_id := String(raw_id)
		var target := engine.state.get_combatant(target_id)
		if target_id == action.source_id or target == null or target.is_death_finalized():
			continue # HP 0 is still targetable until end-of-round death.
		if engine.group_state != null and engine.group_state.team_of(target_id) == source_team:
			continue
		if engine.zone_state != null and engine.zone_state.distance(action.source_id,target_id) != 0:
			continue
		eligible.append(target_id)
	eligible.sort()
	var targets: Array[String] = []
	if eligible.has(primary):
		targets.append(primary)
		eligible.erase(primary)
	# Random additional targets without replacement and without duplicates.
	while targets.size() < limit and not eligible.is_empty():
		var index := engine.combat_rng.randi_range(0,eligible.size()-1)
		targets.append(eligible[index])
		eligible.remove_at(index)
	return targets

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, source: CombatantState, target: CombatantState) -> void:
	var ability_id := String(attack.payload.get("sword_abi_id",""))
	if not is_sword_ability(ability_id):
		return
	var eff_level := maxi(1,int(attack.payload.get("sword_eff_level",1)))
	if ability_id in ["ABI301","ABI302"]:
		_award_hit_ap(engine,attack,source,1 if ability_id=="ABI301" else 2)
		_apply_effect(engine,attack,BLEED,1,eff_level)
	elif DEBUFFS.has(ability_id):
		_apply_effect(engine,attack,String(DEBUFFS[ability_id]),1,eff_level)
	elif ability_id == "ABI306":
		_apply_effect(engine,attack,BLEED,1,eff_level)
	elif ability_id == "ABI307":
		_apply_effect(engine,attack,BLEED,mini(5,maxi(1,int(attack.payload.get("sword_ap_spent",1)))),eff_level)
	elif ability_id == "ABI308":
		var effect := active_bleeding(target)
		if effect.is_empty():
			return
		var tick_amount := float(Dictionary(effect.get("definition",{})).get("damage",1.0)) * float(effect.get("stacks",1))
		for _tick in range(3):
			var tick := engine.state.create_event(CombatEvent.Kind.DAMAGE,attack.source_id,target.combatant_id,{
				"amount":tick_amount,"damage_type":"physical","source":"effect",
				"effect_id":BLEED,"sword_burst_tick":true
			},attack.event_id)
			engine.state.queue_event(tick)

static func _award_hit_ap(engine: CombatEngine, attack: CombatEvent, source: CombatantState, amount: int) -> void:
	if String(attack.payload.get("sword_abi_id","")) == "ABI301":
		source.gain_action_points(amount)
		return
	for event in engine.state.event_log:
		if event.event_id == attack.parent_event_id and event.kind == CombatEvent.Kind.ACTION:
			if bool(event.result.get("sword_hit_ap_awarded",false)):
				return
			event.set_result("sword_hit_ap_awarded",true)
			event.set_result("ap_gained_on_hit",source.gain_action_points(amount))
			return

static func _apply_effect(engine: CombatEngine, attack: CombatEvent, effect_id: String, stacks: int, eff_level: int) -> void:
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,attack.source_id,attack.target_id,{
		"effect_id":effect_id,"source_type":"ability",
		"ability_id":String(attack.payload.get("sword_abi_id","")),
		"base_chance":100.0,"effect_roll":1,
		"sword_stacks_to_apply":stacks,
		"sword_eff_level":eff_level
	},attack.event_id))

static func active_bleeding(target: CombatantState) -> Dictionary:
	for raw in target.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == BLEED and int(record.get("remaining_rounds",0)) > 0:
			return record
	return {}
