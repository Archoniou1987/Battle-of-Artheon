class_name AxeAbiCombatService
extends RefCounted

## Four approved axe families. ABI owns attacks, EFF501 owns wounds/DoT.
## Physical hit, block, damage, mitigation and death remain with CombatEngine.
const ABILITIES := ["ABI501","ABI502","ABI503","ABI504","ABI505","ABI506","ABI507","ABI508","ABI509","ABI510","ABI511","ABI512","ABI513","ABI514","ABI515","ABI516"]
const WOUND := "EFF501"

static func is_axe_ability(id: String) -> bool:
	return ABILITIES.has(id)

static func _profile(source: CombatantState, id: String) -> Dictionary:
	var two_handed := id in ["ABI505","ABI506","ABI507","ABI508","ABI509","ABI510","ABI511","ABI512","ABI513","ABI514","ABI515","ABI516"]
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	if weapons.is_empty() or bool(Dictionary(weapons[0]).get("two_handed",false)) != two_handed:
		return {}
	for raw in WeaponAttackProfile.all(source):
		var p: Dictionary = raw
		if int(p.get("weapon_index",-1)) == 0 and String(p.get("weapon_class","")).to_lower()=="axe":
			return p
	return {}

static func _valid_enemy(engine: CombatEngine, source_id: String, target_id: String) -> bool:
	var target := engine.state.get_combatant(target_id)
	if source_id == target_id or target == null or target.is_death_finalized():
		return false
	if engine.group_state != null and engine.group_state.team_of(source_id)==engine.group_state.team_of(target_id):
		return false
	if engine.zone_state != null and engine.zone_state.distance(source_id,target_id)!=0:
		return false
	return true

static func can_cast(state: CombatState, source_id: String, _target_id: String, abi: String, _planned_round: int = -1) -> bool:
	if not is_axe_ability(abi):
		return true
	var source := state.get_combatant(source_id)
	return source != null and not _profile(source,abi).is_empty()

static func _effect(engine: CombatEngine, source: String, target: String, parent: int, id: String, extras: Dictionary = {}) -> void:
	var payload := {"effect_id":id,"source_type":"ability","base_chance":100.0,"effect_roll":1}
	var fighter := engine.state.get_combatant(source)
	if fighter != null:
		var weapons: Array = fighter.combat_stats.get("weapon_profiles",[])
		if not weapons.is_empty():
			payload["effect_rank"] = AbilityCatalog.rank_for_item_level(int(Dictionary(weapons[0]).get("item_level",fighter.level)))+1
	for key in extras:
		payload[key] = extras[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source,target,payload,parent))

static func _wounds(target: CombatantState, source_id: String, round_number: int) -> int:
	var result := 0
	for record in CombatModifierService.active_effects(target,round_number):
		if String(record.get("effect_id","")) == WOUND and String(record.get("source_id","")) == source_id:
			result += int(record.get("stacks",1))
	return mini(EffectCatalog.stack_cap(WOUND),result)

static func _consume_wounds(target: CombatantState, source_id: String, n: int) -> void:
	var remaining := n
	for record in target.active_effects.duplicate():
		if remaining <= 0:
			break
		if String(record.get("effect_id","")) != WOUND or String(record.get("source_id","")) != source_id:
			continue
		var count := mini(remaining,int(record.get("stacks",1)))
		remaining -= count
		var rest := int(record.get("stacks",1))-count
		if rest <= 0:
			target.active_effects.erase(record)
		else:
			record["stacks"] = rest
			record["active_stacks"] = mini(rest,int(record.get("active_stacks",0)))

static func _targets(engine: CombatEngine, action: CombatEvent, limit: int) -> Array[String]:
	var result: Array[String] = []
	if _valid_enemy(engine,action.source_id,action.target_id):
		result.append(action.target_id)
	var others: Array[String] = []
	for raw in engine.state.combatants.keys():
		var id := String(raw)
		if not result.has(id) and _valid_enemy(engine,action.source_id,id):
			others.append(id)
	others.sort()
	while result.size() < limit and not others.is_empty():
		var index := engine.combat_rng.randi_range(0,others.size()-1)
		result.append(others[index])
		others.remove_at(index)
	return result

static func _damage(source: CombatantState, profile: Dictionary, id: String, multiplier: float) -> float:
	var base := AbilityCatalog.ranked_damage(id,int(profile.get("item_level",source.level)))
	var attack_power := float(Dictionary(source.combat_stats.get("par_totals",{})).get("PAR232",0))
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	var two_handed := not weapons.is_empty() and bool(Dictionary(weapons[0]).get("two_handed",false))
	var bonus := AttackPowerService.damage_bonus(attack_power,"main_hand",two_handed)
	return maxf(0.0,(base+AbilityCatalog.number(id,"attack_power_coefficient")*bonus)*multiplier)

static func _queue_attack(engine: CombatEngine, action: CombatEvent, target_id: String, profile: Dictionary, damage: float, extras: Dictionary = {}) -> int:
	var component := {"damage_type":"chopping","zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,damage,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["axe_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extras:
		payload[key]=extras[key]
	var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
	engine.state.queue_event(attack)
	return attack.event_id

static func prepare_action(_engine: CombatEngine, _action: CombatEvent) -> void:
	pass

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var actor := engine.state.get_combatant(action.source_id)
	if actor == null or actor.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _profile(actor,id)
	if profile.is_empty():
		action.set_result("outcome","wrong_axe_hand")
		return
	if id == "ABI506":
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(id))
		action.set_result("outcome","berserk")
		return
	if not _valid_enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var limit := maxi(1,int(action.payload.get("max_targets",AbilityCatalog.number(id,"max_targets"))))
	var ids: Array[int] = []
	for target_id in _targets(engine,action,limit):
		var target := engine.state.get_combatant(target_id)
		var wounds := _wounds(target,action.source_id,engine.state.round_number)
		var mult := 1.0
		var extra := {"axe_wounds_snapshot":wounds}
		if id == "ABI508" or id == "ABI512" or id == "ABI516":
			var values: Array = Array(AbilityCatalog.definition(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),id).get("bonus_damage_pct_by_wounds",[]))
			if values.size()==4:
				mult += float(values[clampi(wounds,0,3)])/100.0
			extra["axe_consume_wounds"] = wounds
		if id == "ABI508" and target.max_hp > 0 and float(target.hp)/float(target.max_hp)<AbilityCatalog.number(id,"execute_hp_threshold_fraction",action.payload):
			mult *= AbilityCatalog.number(id,"execute_multiplier",action.payload)
		if id == "ABI511" or id == "ABI512":
			if target.can_auto_block():
				mult += AbilityCatalog.number(id,"shield_damage_bonus_pct",action.payload)/100.0
		if id == "ABI515":
			mult += float(wounds)*AbilityCatalog.number(id,"bonus_damage_pct_per_wound",action.payload)/100.0
		if id == "ABI510":
			extra["axe_block_crush_bonus_pct"] = AbilityCatalog.number(id,"block_crush_bonus_pct",action.payload)
		if id == "ABI512":
			extra["uses_physical_block"] = not bool(AbilityCatalog.definition(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),id).get("ignore_all_blocks",false))
		if id == "ABI504":
			var heal_values: Array = Array(AbilityCatalog.definition(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),id).get("heal_from_damage_pct_by_wounds",[]))
			if heal_values.size()==4:
				extra["axe_heal_from_damage_pct"]=float(heal_values[clampi(wounds,0,3)])
			extra["axe_consume_wounds"] = wounds
		ids.append(_queue_attack(engine,action,target_id,profile,_damage(actor,profile,id,mult),extra))
	action.set_result("outcome","dispatched" if not ids.is_empty() else "no_targets")
	action.set_result("child_event_ids",ids)

static func _gain_once(engine: CombatEngine, attack: CombatEvent, actor: CombatantState) -> void:
	var ap_amount := 1
	if String(attack.payload.get("axe_abi_id","")) == "ABI501" and int(attack.payload.get("axe_wounds_snapshot",0)) >= 3:
		ap_amount += int(AbilityCatalog.number("ABI501","bonus_ap_at_three_wounds"))
	for event in engine.state.event_log:
		if event.event_id == attack.parent_event_id and event.kind == CombatEvent.Kind.ACTION:
			if bool(event.result.get("axe_ap_done",false)):
				return
			event.set_result("axe_ap_done",true)
			event.set_result("ap_gained_on_hit",actor.gain_action_points(ap_amount))
			return
	actor.gain_action_points(ap_amount)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent) -> void:
	var id := String(attack.payload.get("axe_abi_id",""))
	if not is_axe_ability(id):
		return
	var actor := engine.state.get_combatant(attack.source_id)
	var target := engine.state.get_combatant(attack.target_id)
	if actor == null or target == null:
		return
	if id in ["ABI501","ABI505","ABI509","ABI513"]:
		_gain_once(engine,attack,actor)
	if id in ["ABI501","ABI503","ABI505","ABI507","ABI509","ABI511","ABI513","ABI514"]:
		var stacks := 2 if id=="ABI507" or (id=="ABI514" and int(attack.payload.get("axe_wounds_snapshot",0))>0) else 1
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,WOUND,{"stacks_to_apply":stacks})
	if id == "ABI502":
		var pct := AbilityCatalog.number(id,"heal_hp_pct_per_wound")
		var healing := roundi(float(actor.max_hp)*float(int(attack.payload.get("axe_wounds_snapshot",0)))*pct/100.0)
		if healing>0:
			engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,actor.combatant_id,actor.combatant_id,{"inline_heal":healing,"clamp_heal_to_max":true,"source_type":"ability","ability_id":id},attack.event_id))
	if int(attack.payload.get("axe_consume_wounds",0))>0:
		_consume_wounds(target,attack.source_id,int(attack.payload["axe_consume_wounds"]))

static func on_damage(engine: CombatEngine, damage_event: CombatEvent, target: CombatantState) -> void:
	if int(damage_event.result.get("final_damage",0))<=0:
		return
	for parent in engine.state.event_log:
		if parent.event_id != damage_event.parent_event_id or parent.kind != CombatEvent.Kind.ATTACK:
			continue
		if String(parent.payload.get("axe_abi_id",""))!="ABI504":
			return
		var source := engine.state.get_combatant(damage_event.source_id)
		if source == null or source.combatant_id == target.combatant_id:
			return
		var pct := float(parent.payload.get("axe_heal_from_damage_pct",0))
		# CombatEngine has already calculated armour, damage reduction and actual damage.
		# No arbitrary HP-% cap: a stronger final hit legitimately heals more.
		var heal := maxi(0,roundi(float(int(damage_event.result.get("final_damage",0)))*pct/100.0))
		if heal>0:
			engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source.combatant_id,source.combatant_id,{"inline_heal":heal,"clamp_heal_to_max":true,"source_type":"ability","ability_id":"ABI504"},damage_event.event_id))
		return

static func on_dodge(_engine: CombatEngine, _incoming: CombatEvent, _defender: CombatantState) -> void:
	pass
