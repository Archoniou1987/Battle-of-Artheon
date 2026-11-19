class_name HammerAbiCombatService
extends RefCounted

## One family, two independent kits: 1H defensive mace ABI601–604,
## 2H heavy mace ABI605–608. EFF601 is target-owned concussion.
## CombatEngine alone resolves hit, block, armour, Tempo, and end-of-round death.
const ABILITIES := ["ABI601","ABI602","ABI603","ABI604","ABI605","ABI606","ABI607","ABI608"]
const CONCUSSION := "EFF601"

static func is_hammer_ability(ability_id: String) -> bool:
	return ABILITIES.has(ability_id)

static func _weapon(source: CombatantState, id: String) -> Dictionary:
	var two_handed := id in ["ABI605","ABI606","ABI607","ABI608"]
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	if weapons.is_empty() or bool(Dictionary(weapons[0]).get("two_handed",false)) != two_handed:
		return {}
	for raw in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw
		if int(profile.get("weapon_index",-1))==0 and String(profile.get("weapon_class","")).to_lower()=="hammer":
			return profile
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
	if not is_hammer_ability(abi):
		return true
	var source := state.get_combatant(source_id)
	return source != null and not _weapon(source,abi).is_empty()

static func _effect(engine: CombatEngine, source_id: String, target_id: String, parent_id: int, eff_id: String, pre: bool = false, extras: Dictionary = {}) -> void:
	if eff_id.is_empty():
		return
	var payload := {"effect_id":eff_id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	for key in extras:
		payload[key] = extras[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload,parent_id))

## Apply ABI601 defence before sealed attacks resolve; AP generation on hit
## remains separate and continues through normal CombatEngine attack results.
static func prepare_action(engine: CombatEngine, action: CombatEvent) -> void:
	if String(action.payload.get("ability_id","")) != "ABI601":
		return
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized() or _weapon(source,"ABI601").is_empty():
		return
	var effect_id := AbilityCatalog.effect_id("ABI601","on_cast")
	_effect(engine,action.source_id,action.source_id,action.event_id,effect_id,true)

## The shared engine invokes this only for an actual, uncrushed manual or
## shield auto-block. Merely selecting a protected zone never awards AP.
static func on_block(engine: CombatEngine, blocked: CombatEvent, defender: CombatantState) -> void:
	for record in CombatModifierService.active_effects(defender,engine.state.round_number):
		if String(record.get("effect_id","")) != "EFF607":
			continue
		var definition: Dictionary = record.get("definition",{})
		var max_awards := maxi(0,int(definition.get("max_ap_from_blocks_per_round",0)))
		var reward := maxi(0,int(definition.get("ap_per_successful_block",0)))
		var spent := int(record.get("block_ap_awarded",0))
		if spent >= max_awards or reward <= 0:
			continue
		var amount := mini(reward,max_awards-spent)
		record["block_ap_awarded"] = spent+amount
		var gained := defender.gain_action_points(amount)
		blocked.set_result("hammer_block_ap_gained",gained)
		return

static func _concussion(target: CombatantState, source_id: String, round_number: int) -> int:
	var n := 0
	for record in CombatModifierService.active_effects(target,round_number):
		if String(record.get("effect_id",""))==CONCUSSION and String(record.get("source_id",""))==source_id:
			n += int(record.get("stacks",1))
	return mini(n,EffectCatalog.stack_cap(CONCUSSION))

static func _consume_concussion(target: CombatantState, source_id: String, amount: int) -> void:
	var remaining := amount
	for record in target.active_effects.duplicate():
		if remaining <= 0:
			break
		if String(record.get("effect_id",""))!=CONCUSSION or String(record.get("source_id",""))!=source_id:
			continue
		var spent := mini(remaining,int(record.get("stacks",1)))
		remaining -= spent
		var count := int(record.get("stacks",1))-spent
		if count <= 0:
			target.active_effects.erase(record)
		else:
			record["stacks"]=count
			record["active_stacks"]=mini(count,int(record.get("active_stacks",0)))

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

static func _damage(source: CombatantState, profile: Dictionary, abi: String, multiplier: float) -> float:
	var base := AbilityCatalog.ranked_damage(abi,int(profile.get("item_level",source.level)))
	var rating := float(Dictionary(source.combat_stats.get("par_totals",{})).get("PAR232",0.0))
	var weapons: Array = source.combat_stats.get("weapon_profiles",[])
	var two_handed := not weapons.is_empty() and bool(Dictionary(weapons[0]).get("two_handed",false))
	var ap_bonus := AttackPowerService.damage_bonus(rating,"main_hand",two_handed)
	var item_balance_factor := maxf(0.0,float(profile.get("abi_damage_balance_factor",1.0)))
	return maxf(0.0,(base+AbilityCatalog.number(abi,"attack_power_coefficient")*ap_bonus)*multiplier*item_balance_factor)

static func _attack(engine: CombatEngine, action: CombatEvent, target_id: String, profile: Dictionary, damage: float, extras: Dictionary = {}) -> int:
	var component := {"damage_type":"blunt","zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,damage,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["hammer_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extras:
		payload[key] = extras[key]
	var event := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,target_id,payload,action.event_id)
	engine.state.queue_event(event)
	return event.event_id

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _weapon(source,id)
	if profile.is_empty():
		action.set_result("outcome","wrong_hammer_hand")
		return
	if id == "ABI602":
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(id),true)
		action.set_result("outcome","guard_active")
		return
	if not _valid_enemy(engine,action.source_id,action.target_id):
		action.set_result("outcome","invalid_target")
		return
	var ids: Array[int] = []
	var count := maxi(1,int(action.payload.get("max_targets",AbilityCatalog.number(id,"max_targets"))))
	for target_id in _targets(engine,action,count):
		var target := engine.state.get_combatant(target_id)
		var stacks := _concussion(target,action.source_id,engine.state.round_number)
		var multiplier := 1.0
		var extras := {"hammer_concussion_snapshot":stacks}
		if id == "ABI608":
			var definition := AbilityCatalog.definition(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),id)
			var damage_bonus: Array = definition.get("bonus_damage_pct_by_concussion",[])
			var tempo: Array = definition.get("tempo_control_by_concussion",[])
			if damage_bonus.size()==4:
				var bonus_pct := float(damage_bonus[clampi(stacks,0,3)])
				multiplier += bonus_pct/100.0
				extras["hammer_bonus_damage_pct"]=bonus_pct
			if tempo.size()==4:
				extras["hammer_tempo_control_on_hit"]=float(tempo[clampi(stacks,0,3)])
			extras["hammer_consume_concussion"]=stacks
		if id == "ABI607":
			extras["hammer_tempo_control_on_hit"]=AbilityCatalog.number(id,"tempo_control_on_hit",action.payload)
		ids.append(_attack(engine,action,target_id,profile,_damage(source,profile,id,multiplier),extras))
	action.set_result("outcome","dispatched" if not ids.is_empty() else "no_targets")
	action.set_result("child_event_ids",ids)

static func _gain_once(engine: CombatEngine, attack: CombatEvent, source: CombatantState) -> void:
	for event in engine.state.event_log:
		if event.kind==CombatEvent.Kind.ACTION and event.event_id==attack.parent_event_id:
			if bool(event.result.get("hammer_ap_done",false)):
				return
			event.set_result("hammer_ap_done",true)
			event.set_result("ap_gained_on_hit",source.gain_action_points(1))
			return
	source.gain_action_points(1)

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState) -> void:
	var id := String(attack.payload.get("hammer_abi_id",""))
	if not is_hammer_ability(id):
		return
	var target := engine.state.get_combatant(attack.target_id)
	if target == null:
		return
	if id in ["ABI601","ABI605"]:
		_gain_once(engine,attack,attacker)
	if id == "ABI607":
		# One AP per actual connected target, once per attack event.
		# The parent action tracks the shared per-cast cap, not the targets.
		for parent in engine.state.event_log:
			if parent.event_id != attack.parent_event_id or parent.kind != CombatEvent.Kind.ACTION:
				continue
			var already := int(parent.result.get("hammer_wave_ap_awarded",0))
			var cap := maxi(0,int(AbilityCatalog.number("ABI607","ap_gain")))
			var per_hit := maxi(0,int(AbilityCatalog.number("ABI607","ap_gain_per_connected_target")))
			if already < cap and per_hit > 0:
				var eligible := mini(per_hit,cap-already)
				parent.set_result("hammer_wave_ap_awarded",already+eligible)
				var gained := attacker.gain_action_points(eligible)
				parent.set_result("ap_gained_on_hit",int(parent.result.get("ap_gained_on_hit",0))+gained)
				attack.set_result("hammer_wave_ap_gained",gained)
			break
	if id in ["ABI605","ABI607"]:
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,CONCUSSION)
	if id == "ABI603":
		_effect(engine,attack.source_id,attack.source_id,attack.event_id,AbilityCatalog.effect_id(id,"on_hit"))
	if id == "ABI604":
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,AbilityCatalog.effect_id(id,"on_hit"))
		_effect(engine,attack.source_id,attack.source_id,attack.event_id,AbilityCatalog.effect_id(id,"self_on_hit"))
	if id == "ABI606":
		_effect(engine,attack.source_id,attack.target_id,attack.event_id,AbilityCatalog.effect_id(id,"on_hit"))
	if id in ["ABI607","ABI608"]:
		var tempo := float(attack.payload.get("hammer_tempo_control_on_hit",0.0))
		if tempo>0.0:
			CombatTempoService.apply_control(target,tempo)
			attack.set_result("tempo_control_applied",tempo)
	if id == "ABI608" and int(attack.payload.get("hammer_consume_concussion",0))>0:
		_consume_concussion(target,attack.source_id,int(attack.payload["hammer_consume_concussion"]))

static func on_damage(_engine: CombatEngine, _event: CombatEvent, _target: CombatantState) -> void:
	# No passive healing, reflection or permanent charge generation.
	pass
