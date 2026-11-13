class_name WeaponComboAbiCombatService
extends RefCounted

## Physical dagger archetypes and 2H spear. ABI owns magnitudes, EFF owns
## duration/stacking, CombatEngine owns hit/crit/armour and Tempo owns stun.
const ATTACK := ["ABI401","ABI402","ABI403","ABI404"]
const DEFENCE := ["ABI405","ABI406","ABI407","ABI408"]
const PENETRATION := ["ABI409","ABI410","ABI411","ABI412"]
const SPEAR := ["ABI701","ABI702","ABI703","ABI704"]
const ABILITIES := ["ABI401","ABI402","ABI403","ABI404","ABI405","ABI406","ABI407","ABI408","ABI409","ABI410","ABI411","ABI412","ABI701","ABI702","ABI703","ABI704"]
const ACCURACY := "EFF406"
const FOCUS := "EFF407"
const COUNTER := "EFF408"
const DANCE := "EFF409"
const COUNTER_BUFF := "EFF410"
const WEAKEN := "EFF411"
const SLOW := "EFF412"
const FRACTURE := "EFF413"
const BREACH := "EFF401"

static func is_combo_ability(id: String) -> bool:
	return ABILITIES.has(id)

static func _profile(source: CombatantState, id: String) -> Dictionary:
	var family := "spear" if SPEAR.has(id) else "dagger"
	for raw in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw
		if int(profile.get("weapon_index",-1)) == 0 and String(profile.get("weapon_class","")).to_lower() == family:
			if family == "spear":
				var weapons: Array = source.combat_stats.get("weapon_profiles",[])
				if weapons.is_empty() or not bool(Dictionary(weapons[0]).get("two_handed",false)):
					return {}
			return profile
	return {}

static func _stacks(source: CombatantState, eff_id: String, round_number: int) -> int:
	var amount := 0
	for record in CombatModifierService.active_effects(source,round_number):
		if String(record.get("effect_id","")) == eff_id:
			amount += int(record.get("stacks",1))
	return mini(amount,EffectCatalog.stack_cap(eff_id))

static func _has(source: CombatantState, eff_id: String, round_number: int) -> bool:
	for record in CombatModifierService.active_effects(source,round_number):
		if String(record.get("effect_id","")) == eff_id:
			return true
	return false

static func _remove(source: CombatantState, eff_id: String) -> void:
	for record in source.active_effects.duplicate():
		if String(record.get("effect_id","")) == eff_id:
			source.active_effects.erase(record)

static func _effect(engine: CombatEngine, source_id: String, target_id: String, parent_id: int, eff_id: String, pre: bool = false, context: Dictionary = {}) -> void:
	var payload := {"effect_id":eff_id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	for field in context:
		payload[field] = context[field]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload,parent_id))

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

static func _number(id: String, key: String, action: CombatEvent) -> float:
	return AbilityCatalog.number(id,key,action.payload)

## Flat ABI damage plus physical bonus from the authoritative PAR232 only.
## Do not read the already AP-enhanced weapon range: that would double-count.
static func _damage(source: CombatantState, profile: Dictionary, id: String, action: CombatEvent) -> float:
	var item_level := maxi(1,int(profile.get("item_level",source.level)))
	var base := _number(id,"base_damage",action)
	var step := _number(id,"damage_per_10_levels",action)
	var coefficient := _number(id,"attack_power_coefficient",action)
	var rating := float(Dictionary(source.combat_stats.get("par_totals",{})).get("PAR232",0.0))
	var equipped: Array = source.combat_stats.get("weapon_profiles",[])
	if equipped.is_empty():
		return maxf(0.0,base + float(floori(float(item_level) / 10.0)) * step)
	var weapon: Dictionary = equipped[0]
	var bonus := AttackPowerService.damage_bonus(rating,"main_hand",bool(weapon.get("two_handed",false)))
	return maxf(0.0,base + float(floori(float(item_level) / 10.0)) * step + coefficient * bonus)

static func _queue_attack(engine: CombatEngine, action: CombatEvent, target_id: String, profile: Dictionary, amount: float, extra: Dictionary = {}) -> int:
	var component := {"damage_type":String(profile.get("damage_type","piercing")),"zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,maxf(0.0,amount),1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["combo_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extra:
		payload[key] = extra[key]
	var hit := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
	engine.state.queue_event(hit)
	return hit.event_id

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _profile(source,id)
	if profile.is_empty():
		action.set_result("outcome","matching_mh_required")
		return
	var round_number := engine.state.round_number
	if id in ["ABI402","ABI406"]:
		if id == "ABI402":
			_effect(engine,action.source_id,action.source_id,action.event_id,FOCUS,true,{"combo_accuracy_stacks":_stacks(source,ACCURACY,round_number)})
		else:
			_effect(engine,action.source_id,action.source_id,action.event_id,DANCE,true)
		action.set_result("outcome","buff_dispatched")
		return
	if not _valid_enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var target := engine.state.get_combatant(action.target_id)
	var base := _damage(source,profile,id,action)
	var ids: Array[int] = []
	var extras := {}
	match id:
		"ABI401","ABI409":
			ids.append(_queue_attack(engine,action,action.target_id,profile,base))
		"ABI403":
			for hit_index in range(maxi(1,int(_number(id,"hit_count",action)))):
				ids.append(_queue_attack(engine,action,action.target_id,profile,base,{"combo_strike_index":hit_index}))
		"ABI404":
			var count := _stacks(source,ACCURACY,round_number)
			_remove(source,ACCURACY)
			base += float(count) * _number(id,"damage_per_charge",action)
			if target.max_hp > 0 and float(target.hp) / float(target.max_hp) * 100.0 < _number(id,"low_hp_threshold_pct",action):
				base *= 1.0 + _number(id,"low_hp_bonus_pct",action)/100.0
			ids.append(_queue_attack(engine,action,action.target_id,profile,base))
			action.set_result("charges_consumed",count)
		"ABI405":
			var dodged := AbilityRuntime.previous_round_trigger_met(engine.state,source.combatant_id,"dodge")
			if dodged:
				base *= 1.0 + _number(id,"dodge_bonus_damage_pct",action)/100.0
			extras["combo_bonus_ap"] = int(_number(id,"dodge_bonus_ap",action)) if dodged else 0
			ids.append(_queue_attack(engine,action,action.target_id,profile,base,extras))
		"ABI407":
			var charge_count := _stacks(source,COUNTER,round_number)
			base *= 1.0 + float(charge_count) * _number(id,"damage_bonus_per_charge_pct",action)/100.0
			for target_id in _targets(engine,action,int(_number(id,"max_targets",action))):
				ids.append(_queue_attack(engine,action,target_id,profile,base))
		"ABI408":
			var charge_count := _stacks(source,COUNTER,round_number)
			_remove(source,COUNTER)
			_effect(engine,action.source_id,action.source_id,action.event_id,COUNTER_BUFF,true,{"combo_counter_stacks":charge_count})
			base *= 1.0 + float(charge_count) * _number(id,"damage_bonus_per_charge_pct",action)/100.0
			ids.append(_queue_attack(engine,action,action.target_id,profile,base))
			var oh: Dictionary = {}
			for raw in WeaponAttackProfile.all(source):
				if int(raw.get("weapon_index",-1)) == 1 and String(raw.get("weapon_class","")) == "dagger":
					oh = raw
					break
			if not oh.is_empty():
				ids.append(_queue_attack(engine,action,action.target_id,oh,base*0.5))
			action.set_result("charges_consumed",charge_count)
		"ABI410":
			var n := _stacks(target,BREACH,round_number)
			ids.append(_queue_attack(engine,action,action.target_id,profile,base,{"combo_breach_snapshot":n}))
		"ABI411":
			var n := _stacks(target,BREACH,round_number)
			base *= 1.0 + float(n)*_number(id,"damage_bonus_per_breach_pct",action)/100.0
			ids.append(_queue_attack(engine,action,action.target_id,profile,base,{"combo_breach_snapshot":n}))
		"ABI412":
			var n := _stacks(target,BREACH,round_number)
			ids.append(_queue_attack(engine,action,action.target_id,profile,base,{"dagger_armour_bypass_pct":float(n)*_number(id,"armour_bypass_pct_per_breach_stack",action)}))
		"ABI701":
			if _has(target,SLOW,round_number):
				base *= 1.0 + _number(id,"slow_bonus_damage_pct",action)/100.0
			ids.append(_queue_attack(engine,action,action.target_id,profile,base))
		"ABI702":
			for target_id in _targets(engine,action,int(_number(id,"max_targets",action))):
				ids.append(_queue_attack(engine,action,target_id,profile,base))
		"ABI703","ABI704":
			extras["combo_slow_snapshot"] = _has(target,SLOW,round_number)
			ids.append(_queue_attack(engine,action,action.target_id,profile,base,extras))
	action.set_result("outcome","dispatched" if not ids.is_empty() else "no_available_strikes")
	action.set_result("child_event_ids",ids)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState) -> void:
	var id := String(attack.payload.get("combo_abi_id",""))
	if not ABILITIES.has(id):
		return
	var target := engine.state.get_combatant(attack.target_id)
	if target == null:
		return
	var round_number := engine.state.round_number
	match id:
		"ABI401":
			_effect(engine,attacker.combatant_id,attacker.combatant_id,attack.event_id,ACCURACY)
			if bool(attack.result.get("critical",false)):
				_effect(engine,attacker.combatant_id,attacker.combatant_id,attack.event_id,ACCURACY)
			attacker.gain_action_points(int(AbilityCatalog.number(id,"ap_gain")))
		"ABI403":
			if bool(attack.result.get("critical",false)):
				_effect(engine,attacker.combatant_id,attacker.combatant_id,attack.event_id,ACCURACY)
		"ABI405":
			attacker.gain_action_points(int(AbilityCatalog.number(id,"ap_gain"))+int(attack.payload.get("combo_bonus_ap",0)))
		"ABI409":
			attacker.gain_action_points(int(AbilityCatalog.number(id,"ap_gain")))
			_effect(engine,attacker.combatant_id,target.combatant_id,attack.event_id,BREACH)
		"ABI410":
			if int(attack.payload.get("combo_breach_snapshot",0)) >= int(AbilityCatalog.number(id,"min_breach_stacks")):
				for index in range(int(AbilityCatalog.number(id,"extra_breach_stacks"))):
					_effect(engine,attacker.combatant_id,target.combatant_id,attack.event_id,BREACH)
				attacker.gain_action_points(int(AbilityCatalog.number(id,"bonus_ap_on_condition")))
		"ABI411":
			_effect(engine,attacker.combatant_id,target.combatant_id,attack.event_id,WEAKEN,false,{"combo_breach_stacks":int(attack.payload.get("combo_breach_snapshot",0))})
		"ABI412":
			_remove(target,BREACH)
		"ABI701":
			attacker.gain_action_points(int(AbilityCatalog.number(id,"ap_gain")))
		"ABI702":
			_effect(engine,attacker.combatant_id,target.combatant_id,attack.event_id,SLOW)
		"ABI703":
			if bool(attack.payload.get("combo_slow_snapshot",false)):
				CombatTempoService.apply_control(target,AbilityCatalog.number(id,"control_on_slow"))
				_remove(target,SLOW)
		"ABI704":
			if bool(attack.payload.get("combo_slow_snapshot",false)):
				_effect(engine,attacker.combatant_id,target.combatant_id,attack.event_id,FRACTURE)

static func on_dodge(engine: CombatEngine, attack: CombatEvent, defender: CombatantState) -> void:
	if defender == null or _profile(defender,"ABI405").is_empty():
		return
	if _has(defender,DANCE,engine.state.round_number):
		_effect(engine,defender.combatant_id,defender.combatant_id,attack.event_id,COUNTER)
