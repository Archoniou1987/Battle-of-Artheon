class_name DaggerAbiCombatService
extends RefCounted

## PHY dagger ABI401–408. All damage stays in CombatEngine ATTACK/DAMAGE,
## including individual crit, hit, dodge, block and physical mitigation.
const QUICK := "ABI401"
const COATING := "ABI402"
const DEF_FAN := "ABI403"
const DEF_COMBO := "ABI404"
const ATTACK_HEAVY := "ABI405"
const ATTACK_FLURRY := "ABI406"
const PEN_DEEP := "ABI407"
const PEN_ABSOLUTE := "ABI408"
const ABILITIES := [QUICK, COATING, DEF_FAN, DEF_COMBO, ATTACK_HEAVY, ATTACK_FLURRY, PEN_DEEP, PEN_ABSOLUTE]
const BREACH := "EFF401"
const COATING_EFF := "EFF402"
const POISON := "EFF403"
const DODGE_BUFF := "EFF404"
const OPEN_GUARD := "EFF405"

static func is_dagger_ability(ability_id: String) -> bool:
	return ABILITIES.has(ability_id)

static func _weapon(source: CombatantState, index: int) -> Dictionary:
	for raw_profile in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw_profile
		if int(profile.get("weapon_index",-1)) == index and String(profile.get("weapon_class","")).to_lower() == "dagger":
			return profile
	return {}

static func _average(profile: Dictionary) -> float:
	if profile.is_empty():
		return 0.0
	return (float(profile.get("damage_min",0.0)) + float(profile.get("damage_max",0.0))) * 0.5

static func _active_stacks(target: CombatantState, effect_id: String, round_number: int, cap: int) -> int:
	var total := 0
	for record in CombatModifierService.active_effects(target, round_number):
		if String(record.get("effect_id","")) == effect_id:
			total += int(record.get("stacks",1))
	return mini(cap, total)

static func _remove_effect(target: CombatantState, effect_id: String) -> void:
	for record in target.active_effects.duplicate():
		if String(record.get("effect_id","")) == effect_id:
			target.active_effects.erase(record)

static func _valid_enemy(engine: CombatEngine, source_id: String, target_id: String) -> bool:
	var source := engine.state.get_combatant(source_id)
	var target := engine.state.get_combatant(target_id)
	if source == null or target == null or source.is_death_finalized() or target.is_death_finalized() or source_id == target_id:
		return false
	if engine.group_state != null and engine.group_state.team_of(source_id) == engine.group_state.team_of(target_id):
		return false
	if engine.zone_state != null and engine.zone_state.distance(source_id,target_id) != 0:
		return false
	return true

static func _targets(engine: CombatEngine, action: CombatEvent, count: int) -> Array[String]:
	var ids: Array[String] = []
	if _valid_enemy(engine,action.source_id,action.target_id):
		ids.append(action.target_id)
	var rest: Array[String] = []
	for raw_id in engine.state.combatants.keys():
		var id := String(raw_id)
		if ids.has(id) or not _valid_enemy(engine,action.source_id,id):
			continue
		rest.append(id)
	rest.sort()
	while ids.size() < count and not rest.is_empty():
		var index := engine.combat_rng.randi_range(0,rest.size()-1)
		ids.append(rest[index])
		rest.remove_at(index)
	return ids

static func _effect(engine: CombatEngine, source_id: String, target_id: String, parent_id: int, effect_id: String, pre: bool = false, additional: Dictionary = {}) -> void:
	var payload := {"effect_id":effect_id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	for key in additional:
		payload[key] = additional[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload,parent_id))

## A pre-attack EFF must modify the SAME round, even if the ordinary MH
## attack is earlier in the sealed round than this standard-timing ABI.
static func prepare_action(engine: CombatEngine, action: CombatEvent) -> void:
	var ability_id := String(action.payload.get("ability_id",""))
	if not ability_id in [DEF_COMBO, ATTACK_HEAVY]:
		return
	var source := engine.state.get_combatant(action.source_id)
	if source == null or _weapon(source,0).is_empty() or not _valid_enemy(engine,action.source_id,action.target_id):
		return
	if ability_id == ATTACK_HEAVY:
		_effect(engine,action.source_id,action.target_id,action.event_id,OPEN_GUARD,true)
	else:
		var target := engine.state.get_combatant(action.target_id)
		var breach := _active_stacks(target,BREACH,engine.state.round_number,5)
		_effect(engine,action.source_id,action.source_id,action.event_id,DODGE_BUFF,true,{"dagger_dodge_pct":5.0 * float(breach)})

static func _queue_attack(engine: CombatEngine, action: CombatEvent, target_id: String, profile: Dictionary, damage: float, extras: Dictionary = {}) -> int:
	if profile.is_empty() or damage <= 0.0:
		return -1
	var component := {"damage_type":String(profile.get("damage_type","piercing")),"zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,damage,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["dagger_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extras:
		payload[key] = extras[key]
	var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
	engine.state.queue_event(attack)
	return attack.event_id

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var mh := _weapon(source,0)
	if mh.is_empty():
		action.set_result("outcome","dagger_mh_required")
		return
	if id == COATING:
		_effect(engine,action.source_id,action.source_id,action.event_id,COATING_EFF,true)
		action.set_result("outcome","coating_applied")
		return
	if not _valid_enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var target := engine.state.get_combatant(action.target_id)
	var oh := _weapon(source,1)
	var mh_average := _average(mh)
	var oh_average := _average(oh)
	var poison_stacks := _active_stacks(target,POISON,engine.state.round_number,10)
	var breach_stacks := _active_stacks(target,BREACH,engine.state.round_number,5)
	var ids: Array[int] = []
	if id == QUICK:
		var damage := CombatMath.roll_damage(float(mh.get("damage_min",0.0)),float(mh.get("damage_max",0.0)),engine.combat_rng.randf()) * 0.20
		var hit := _queue_attack(engine,action,action.target_id,mh,damage)
		if hit > 0: ids.append(hit)
	elif id == DEF_FAN:
		for enemy_id in _targets(engine,action,5):
			var fan_hit := _queue_attack(engine,action,enemy_id,mh,mh_average+oh_average)
			if fan_hit > 0: ids.append(fan_hit)
	elif id == DEF_COMBO or id == ATTACK_HEAVY:
		var multiplier := 1.0 + 0.10 * float(poison_stacks) if id == DEF_COMBO else 1.0
		var mh_hit := _queue_attack(engine,action,action.target_id,mh,mh_average*multiplier)
		if mh_hit > 0: ids.append(mh_hit)
		var oh_hit := _queue_attack(engine,action,action.target_id,oh,oh_average*multiplier)
		if oh_hit > 0: ids.append(oh_hit)
	elif id == ATTACK_FLURRY:
		for i in range(poison_stacks):
			var current := mh if i % 2 == 0 else oh
			var strike := _queue_attack(engine,action,action.target_id,current,_average(current)*0.60,{"dagger_strike_index":i})
			if strike > 0: ids.append(strike)
	elif id == PEN_DEEP:
		var pierce := _queue_attack(engine,action,action.target_id,mh,mh_average*0.50*float(breach_stacks))
		if pierce > 0: ids.append(pierce)
	elif id == PEN_ABSOLUTE:
		var extras := {"dagger_armour_bypass_pct":20.0*float(breach_stacks)}
		var mh_pierce := _queue_attack(engine,action,action.target_id,mh,mh_average,extras)
		if mh_pierce > 0: ids.append(mh_pierce)
		var oh_pierce := _queue_attack(engine,action,action.target_id,oh,oh_average,extras)
		if oh_pierce > 0: ids.append(oh_pierce)
	action.set_result("outcome","dispatched" if not ids.is_empty() else "no_available_strikes")
	action.set_result("child_event_ids",ids)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState) -> void:
	var abi := String(attack.payload.get("dagger_abi_id",""))
	if abi == QUICK:
		attacker.gain_action_points(1)
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,BREACH)
		return
	if abi == PEN_DEEP:
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,BREACH)
		return
	if abi == PEN_ABSOLUTE:
		# All hits read one cast-time snapshot; consume only after at least one
		# successful hit (not after miss/dodge/block).
		var target := engine.state.get_combatant(attack.target_id)
		if target != null:
			_remove_effect(target,BREACH)
		return
	# Coating is applied only by successful ORDINARY MH/OH dagger attacks.
	if not bool(attack.payload.get("is_weapon_attack",false)) or String(attack.payload.get("source_kind","")) == "ability":
		return
	if _weapon(attacker,int(attack.payload.get("weapon_index",-1))).is_empty():
		return
	var coating_active := false
	for record in CombatModifierService.active_effects(attacker,engine.state.round_number):
		if String(record.get("effect_id","")) == COATING_EFF:
			coating_active = true
			break
	if coating_active:
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,POISON)

static func on_effect_applied(engine: CombatEngine, event: CombatEvent) -> void:
	if String(event.payload.get("effect_id","")) != POISON or not bool(event.result.get("resolved",false)):
		return
	var source := engine.state.get_combatant(event.source_id)
	if source != null and engine.combat_rng.randf() < 0.05:
		source.gain_action_points(1)
