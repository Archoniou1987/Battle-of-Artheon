class_name AxeAbiCombatService
extends RefCounted

## Approved PHY axe ABI501–508. Uses CombatEngine ATTACK and EFFECT events:
## hit/miss and armour persist even where dodge/block are explicitly bypassed.
const RAGE_ABI := "ABI501"
const CUT_ABI := "ABI502"
const DEF_SWEEP := "ABI503"
const DEF_STANCE := "ABI504"
const ATTACK_BREAKER := "ABI505"
const EXECUTE := "ABI506"
const CRUSHER := "ABI507"
const SHIELD_BREAK := "ABI508"
const ABILITIES := [RAGE_ABI,CUT_ABI,DEF_SWEEP,DEF_STANCE,ATTACK_BREAKER,EXECUTE,CRUSHER,SHIELD_BREAK]
const RAGE := "EFF501"
const SWEEP_EFF := "EFF502"
const STANCE_EFF := "EFF503"
const BREAK_EFF := "EFF504"
const CRUSHER_EFF := "EFF505"

static func is_axe_ability(ability_id: String) -> bool:
	return ABILITIES.has(ability_id)

static func _weapon(source: CombatantState) -> Dictionary:
	for raw_profile in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw_profile
		if int(profile.get("weapon_index",-1))==0 and String(profile.get("weapon_class","")).to_lower()=="axe":
			return profile
	return {}

static func _average(profile: Dictionary) -> float:
	return (float(profile.get("damage_min",0.0))+float(profile.get("damage_max",0.0)))*0.5

static func rage_stacks(source: CombatantState, round_number: int) -> int:
	var total := 0
	var cap := 0
	var effect_id := AbilityCatalog.effect_id(RAGE_ABI)
	for record in CombatModifierService.active_effects(source,round_number):
		if String(record.get("effect_id","")) == effect_id:
			cap = EffectCatalog.stack_cap(effect_id,Dictionary(record.get("definition",{})))
			total += int(record.get("stacks",1))
	return mini(cap,total)

static func _consume_rage(source: CombatantState) -> void:
	for record in source.active_effects.duplicate():
		if String(record.get("effect_id","")) == AbilityCatalog.effect_id(RAGE_ABI):
			source.active_effects.erase(record)

static func _enemy(engine: CombatEngine, source_id: String, target_id: String) -> bool:
	var a := engine.state.get_combatant(source_id)
	var b := engine.state.get_combatant(target_id)
	if a == null or b == null or source_id == target_id or a.is_death_finalized() or b.is_death_finalized():
		return false
	if engine.group_state != null and engine.group_state.team_of(source_id) == engine.group_state.team_of(target_id):
		return false
	if engine.zone_state != null and engine.zone_state.distance(source_id,target_id) != 0:
		return false
	return true

## Checked by all manual/automatic Scheduler entry points BEFORE AP/CD spend.
static func can_cast(state: CombatState, source_id: String, target_id: String, abi: String, planned_round: int = -1) -> bool:
	if not is_axe_ability(abi):
		return true
	var source := state.get_combatant(source_id)
	if source == null or _weapon(source).is_empty():
		return false
	# UI preflight checks the upcoming round; committed casts use the live round.
	var evaluating_round := state.round_number if planned_round < 0 else planned_round
	var n := rage_stacks(source,evaluating_round)
	if abi == CRUSHER:
		return n == int(AbilityCatalog.number(CRUSHER,"required_rage_stacks"))
	if abi == EXECUTE:
		var target := state.get_combatant(target_id)
		return target != null and target.max_hp > 0 and float(target.hp) < AbilityCatalog.number(EXECUTE,"execute_hp_threshold_fraction") * float(target.max_hp) and n >= int(AbilityCatalog.number(EXECUTE,"min_rage_stacks"))
	return true

static func _effect(engine: CombatEngine, source_id: String, target_id: String, parent_id: int, effect_id: String, pre: bool = false, extras: Dictionary = {}) -> void:
	var payload := {"effect_id":effect_id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	for key in extras:
		payload[key] = extras[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload,parent_id))

## The attacker-breaking debuff affects all attacks of the current round,
## independent of action ordering, like approved dagger pre-attack effects.
static func prepare_action(engine: CombatEngine, action: CombatEvent) -> void:
	if String(action.payload.get("ability_id","")) != ATTACK_BREAKER:
		return
	var source := engine.state.get_combatant(action.source_id)
	if source == null or _weapon(source).is_empty() or not _enemy(engine,action.source_id,action.target_id):
		return
	_effect(engine,action.source_id,action.target_id,action.event_id,AbilityCatalog.effect_id(ATTACK_BREAKER,"pre_attack"),true)

static func _queue_attack(engine: CombatEngine, action: CombatEvent, target_id: String, profile: Dictionary, percent: float, extras: Dictionary = {}) -> int:
	var component := {"damage_type":String(profile.get("damage_type","chopping")),"zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,_average(profile)*percent/100.0,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["axe_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extras:
		payload[key] = extras[key]
	var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
	engine.state.queue_event(attack)
	return attack.event_id

static func _targets(engine: CombatEngine, action: CombatEvent, limit: int) -> Array[String]:
	var ids: Array[String] = []
	if _enemy(engine,action.source_id,action.target_id):
		ids.append(action.target_id)
	var others: Array[String] = []
	for raw_id in engine.state.combatants:
		var id := String(raw_id)
		if ids.has(id) or not _enemy(engine,action.source_id,id):
			continue
		others.append(id)
	others.sort()
	while ids.size() < limit and not others.is_empty():
		var index := engine.combat_rng.randi_range(0,others.size()-1)
		ids.append(others[index])
		others.remove_at(index)
	return ids

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _weapon(source)
	if profile.is_empty():
		action.set_result("outcome","axe_mh_required")
		return
	if id == RAGE_ABI:
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(RAGE_ABI))
		action.set_result("outcome","rage_added")
		return
	if id == DEF_STANCE:
		var rage_count := rage_stacks(source,engine.state.round_number)
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(DEF_STANCE),true,{"axe_rage_stacks":rage_count})
		action.set_result("outcome","retaliation_stance")
		return
	if id == CRUSHER:
		if rage_stacks(source,engine.state.round_number) != int(AbilityCatalog.number(CRUSHER,"required_rage_stacks",action.payload)):
			action.set_result("outcome","needs_five_rage")
			return
		_consume_rage(source)
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(CRUSHER),true)
		action.set_result("outcome","crusher_applied")
		return
	if not _enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var rage := rage_stacks(source,engine.state.round_number)
	var ids: Array[int] = []
	if id == CUT_ABI:
		ids.append(_queue_attack(engine,action,action.target_id,profile,AbilityCatalog.number(id,"attack_damage_pct",action.payload),{"skip_dodge_block":true}))
	elif id == DEF_SWEEP or id == ATTACK_BREAKER:
		ids.append(_queue_attack(engine,action,action.target_id,profile,AbilityCatalog.number(id,"attack_damage_pct",action.payload)))
	elif id == EXECUTE:
		var victim := engine.state.get_combatant(action.target_id)
		if victim != null and victim.max_hp>0 and float(victim.hp)<AbilityCatalog.number(EXECUTE,"execute_hp_threshold_fraction",action.payload)*float(victim.max_hp) and rage>=int(AbilityCatalog.number(EXECUTE,"min_rage_stacks",action.payload)):
			ids.append(_queue_attack(engine,action,action.target_id,profile,AbilityCatalog.number(EXECUTE,"damage_pct_per_rage_stack",action.payload)*float(rage)))
	elif id == SHIELD_BREAK:
		var targets := _targets(engine,action,maxi(1,int(action.payload.get("max_targets",1))))
		var base := AbilityCatalog.number(SHIELD_BREAK,"single_target_damage_pct",action.payload) if targets.size() == 1 else AbilityCatalog.number(SHIELD_BREAK,"multi_target_damage_pct",action.payload)
		for target_id in targets:
			ids.append(_queue_attack(engine,action,target_id,profile,base+AbilityCatalog.number(SHIELD_BREAK,"damage_pct_per_rage_stack",action.payload)*float(rage),{"skip_dodge_block":true}))
	action.set_result("outcome","dispatched" if not ids.is_empty() else "unavailable")
	action.set_result("child_event_ids",ids)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent) -> void:
	var abi := String(attack.payload.get("axe_abi_id",""))
	if abi == DEF_SWEEP:
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,AbilityCatalog.effect_id(DEF_SWEEP,"on_hit"))
	elif abi == EXECUTE or abi == SHIELD_BREAK:
		# Miss/dodge/block never consume rage; any connected strike does.
		var source := engine.state.get_combatant(attack.source_id)
		if source != null:
			_consume_rage(source)

static func on_dodge(engine: CombatEngine, incoming: CombatEvent, defender: CombatantState) -> void:
	var stance: Dictionary = {}
	for raw in CombatModifierService.active_effects(defender,engine.state.round_number):
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == STANCE_EFF:
			stance = record
			break
	if stance.is_empty():
		return
	var counter_cap := maxi(0,int(Dictionary(stance.get("definition",{})).get("counterattack_cap",0)))
	if int(stance.get("axe_counter_count",0)) >= counter_cap:
		return
	var profile := _weapon(defender)
	if profile.is_empty() or not _enemy(engine,defender.combatant_id,incoming.source_id):
		return
	stance["axe_counter_count"] = int(stance.get("axe_counter_count",0)) + 1
	var base := CombatMath.roll_damage(float(profile.get("damage_min",0.0)),float(profile.get("damage_max",0.0)),engine.combat_rng.randf())
	var payload := {
		"raw_damage":base,
		"damage_type":String(profile.get("damage_type","chopping")),
		"zone":"chest",
		"rolls":engine.complete_attack_rolls({}),
		"hit_already_resolved":true,
		"is_counterattack_abi":true,
		"source_kind":"ability",
		"uses_physical_block":false,
		"axe_abi_id":DEF_STANCE
	}
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.ATTACK,defender.combatant_id,incoming.source_id,payload,incoming.event_id))
