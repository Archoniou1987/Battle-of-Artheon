class_name SwordAbiCombatService
extends RefCounted

## Sword ABI301–316. ABI owns damage, EFF owns timed state; CombatEngine
## alone resolves physical hit/crit/armour, block and Tempo.
const ABILITIES := ["ABI301","ABI302","ABI303","ABI304","ABI305","ABI306","ABI307","ABI308","ABI309","ABI310","ABI311","ABI312","ABI313","ABI314","ABI315","ABI316"]
const MASTERY := "EFF314"
const PARRY := "EFF316"

static func is_sword_ability(id: String) -> bool:
	return ABILITIES.has(id)

static func _effect(engine: CombatEngine, source: String, target: String, parent: int, id: String, pre: bool = false, extra: Dictionary = {}) -> void:
	var payload := {"effect_id":id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	var caster := engine.state.get_combatant(source)
	if caster != null:
		var weapons: Array = caster.combat_stats.get("weapon_profiles",[])
		if not weapons.is_empty():
			payload["effect_rank"] = AbilityCatalog.rank_for_item_level(int(Dictionary(weapons[0]).get("item_level",caster.level)))+1
	for key in extra:
		payload[key] = extra[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source,target,payload,parent))

static func _active_stacks(source: CombatantState, id: String, round_number: int) -> int:
	var n := 0
	for record in CombatModifierService.active_effects(source,round_number):
		if String(record.get("effect_id","")) == id:
			n += int(record.get("stacks",1))
	return mini(n,EffectCatalog.stack_cap(id))

static func _remove(source: CombatantState, id: String) -> void:
	for record in source.active_effects.duplicate():
		if String(record.get("effect_id","")) == id:
			source.active_effects.erase(record)

static func _profile(source: CombatantState, id: String) -> Dictionary:
	var expected_2h := id in ["ABI313","ABI314","ABI315","ABI316"]
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	if weapons.is_empty() or bool(Dictionary(weapons[0]).get("two_handed",false)) != expected_2h:
		return {}
	for raw in WeaponAttackProfile.all(source):
		var p: Dictionary = raw
		if int(p.get("weapon_index",-1)) == 0 and String(p.get("weapon_class","")).to_lower() == "sword":
			return p
	return {}

static func _valid_enemy(engine: CombatEngine, source: String, target_id: String) -> bool:
	var target := engine.state.get_combatant(target_id)
	if source == target_id or target == null or target.is_death_finalized():
		return false
	if engine.group_state != null and engine.group_state.team_of(source) == engine.group_state.team_of(target_id):
		return false
	if engine.zone_state != null and engine.zone_state.distance(source,target_id) != 0:
		return false
	return true

static func _targets(engine: CombatEngine, action: CombatEvent, amount: int) -> Array[String]:
	var ids: Array[String] = []
	if _valid_enemy(engine,action.source_id,action.target_id):
		ids.append(action.target_id)
	var other: Array[String] = []
	for key in engine.state.combatants.keys():
		var id := String(key)
		if not ids.has(id) and _valid_enemy(engine,action.source_id,id):
			other.append(id)
	other.sort()
	while ids.size() < amount and not other.is_empty():
		var index := engine.combat_rng.randi_range(0,other.size()-1)
		ids.append(other[index])
		other.remove_at(index)
	return ids

static func _damage(source: CombatantState, profile: Dictionary, id: String, bonus_multiplier: float = 1.0) -> float:
	var level := int(profile.get("item_level",source.level))
	var base := AbilityCatalog.ranked_damage(id,level)
	var rating := float(Dictionary(source.combat_stats.get("par_totals",{})).get("PAR232",0.0))
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	var two_handed := not weapons.is_empty() and bool(Dictionary(weapons[0]).get("two_handed",false))
	var ap_bonus := AttackPowerService.damage_bonus(rating,"main_hand",two_handed)
	return maxf(0.0,(base+AbilityCatalog.number(id,"attack_power_coefficient")*ap_bonus)*bonus_multiplier)

static func _attack(engine: CombatEngine, action: CombatEvent, target: String, profile: Dictionary, damage: float, extra: Dictionary = {}) -> int:
	var component := {"damage_type":"slashing","zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,damage,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["sword_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extra:
		payload[key] = extra[key]
	var event := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target,payload,action.event_id)
	engine.state.queue_event(event)
	return event.event_id

## Parry applies before the ordinary sealed attacks in this round.
static func prepare_action(engine: CombatEngine, action: CombatEvent) -> void:
	if String(action.payload.get("ability_id","")) != "ABI303":
		return
	var source := engine.state.get_combatant(action.source_id)
	if source != null and not source.is_death_finalized() and source.can_auto_block() and not _profile(source,"ABI303").is_empty():
		_effect(engine,action.source_id,action.source_id,action.event_id,PARRY,true)

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _profile(source,id)
	if profile.is_empty():
		action.set_result("outcome","sword_mh_required")
		return
	if id in ["ABI302","ABI303"] and not source.can_auto_block():
		action.set_result("outcome","shield_required")
		return
	if id in ["ABI302","ABI306","ABI310"]:
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(id))
		action.set_result("outcome","buff_dispatched")
		return
	if id == "ABI303":
		action.set_result("outcome","parry_armed")
		return
	if not _valid_enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var mastery := _active_stacks(source,MASTERY,engine.state.round_number)
	var damage := _damage(source,profile,id)
	var bonus := 0.0
	if id in ["ABI304","ABI308","ABI312","ABI316"]:
		_remove(source,MASTERY)
		action.set_result("mastery_consumed",mastery)
		if id == "ABI316":
			bonus = float(mastery)*0.15
		else:
			bonus = float(mastery)*0.15
		damage *= 1.0+bonus
		if id == "ABI308":
			# Dodge is another defence type: no more single-target damage than defensive E.
			var max_damage := _damage(source,profile,"ABI304",1.0+float(mastery)*0.15)
			if AbilityRuntime.previous_round_trigger_met(engine.state,source.combatant_id,"dodge"):
				damage *= 1.15
			damage = minf(damage,max_damage)
	var extra := {}
	if id == "ABI312":
		extra["sword_crit_chance_pct"] = 40.0
	if id == "ABI316":
		extra["sword_mastery_snapshot"] = mastery
	var ids: Array[int] = []
	for target in _targets(engine,action,maxi(1,int(action.payload.get("max_targets",AbilityCatalog.number(id,"max_targets"))))):
		ids.append(_attack(engine,action,target,profile,damage,extra))
	action.set_result("outcome","dispatched" if not ids.is_empty() else "no_targets")
	action.set_result("child_event_ids",ids)

static func _gain_once(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState, amount: int) -> void:
	if amount <= 0:
		return
	for event in engine.state.event_log:
		if event.event_id == attack.parent_event_id and event.kind == CombatEvent.Kind.ACTION:
			if bool(event.result.get("sword_gain_done",false)):
				return
			event.set_result("sword_gain_done",true)
			event.set_result("ap_gained_on_hit",attacker.gain_action_points(amount))
			return
	attacker.gain_action_points(amount)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState, defender: CombatantState) -> void:
	var id := String(attack.payload.get("sword_abi_id",""))
	if not ABILITIES.has(id):
		return
	var eff := AbilityCatalog.effect_id(id)
	if id in ["ABI301","ABI305","ABI309","ABI313"]:
		_gain_once(engine,attack,attacker,1)
		# One mastery charge per cast, not per target.
		if not (id == "ABI313" and _already_awarded_mastery(engine,attack)):
			_effect(engine,attacker.combatant_id,attacker.combatant_id,attack.event_id,MASTERY)
		if id == "ABI309" and bool(attack.result.get("critical",false)):
			attacker.gain_action_points(1)
	elif id == "ABI307":
		_gain_once(engine,attack,attacker,2)
	elif id in ["ABI311","ABI314"]:
		_effect(engine,attacker.combatant_id,defender.combatant_id,attack.event_id,eff,false,{"effect_rank":_rank_for_attack(attacker,id)})
	elif id == "ABI312":
		if bool(attack.result.get("critical",false)):
			_effect(engine,attacker.combatant_id,defender.combatant_id,attack.event_id,eff)
	elif id == "ABI315":
		_effect(engine,attacker.combatant_id,defender.combatant_id,attack.event_id,eff)
	elif id == "ABI316" and int(attack.payload.get("sword_mastery_snapshot",0)) == 3:
		_effect(engine,attacker.combatant_id,defender.combatant_id,attack.event_id,eff)

static func _rank_for_attack(source: CombatantState, id: String) -> int:
	var profile := _profile(source,id)
	return AbilityCatalog.rank_for_item_level(int(profile.get("item_level",source.level)))+1

static func _already_awarded_mastery(engine: CombatEngine, attack: CombatEvent) -> bool:
	for event in engine.state.event_log:
		if event.event_id == attack.parent_event_id and event.kind == CombatEvent.Kind.ACTION:
			if bool(event.result.get("sword_mastery_done",false)):
				return true
			event.set_result("sword_mastery_done",true)
			return false
	return false

## Invoked only after a successful (not crushed) shield block.
static func on_block(engine: CombatEngine, blocked: CombatEvent, defender: CombatantState) -> void:
	if not defender.can_auto_block() or _profile(defender,"ABI303").is_empty():
		return
	for record in CombatModifierService.active_effects(defender,engine.state.round_number):
		if String(record.get("effect_id","")) != PARRY or int(record.get("counter_used_round",-1)) == engine.state.round_number:
			continue
		record["counter_used_round"] = engine.state.round_number
		var profile := _profile(defender,"ABI303")
		var payload := CombatDamagePayload.ability_attack_payload(blocked,{"damage_type":"slashing","zone":String(blocked.payload.get("zone","chest"))},_damage(defender,profile,"ABI303"),1.0)
		payload["rolls"] = engine.complete_attack_rolls({})
		payload["sword_abi_id"] = "ABI303"
		payload["is_counterattack_abi"] = true
		var reply := engine.state.create_event(CombatEvent.Kind.ATTACK,defender.combatant_id,blocked.source_id,payload,blocked.event_id)
		engine.state.queue_event(reply)
		return
