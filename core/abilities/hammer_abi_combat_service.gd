class_name HammerAbiCombatService
extends RefCounted

## PHY 1H hammers: charge-based defence/attack ABIs. CHARGE is a permanent
## per-combatant EFF; no parallel damage pipeline or unconditional stun logic.
const HEAVY := "ABI601"
const REFLECT_ABI := "ABI602"
const HEAL := "ABI603"
const FRACTURE := "ABI604"
const SURGE := "ABI605"
const CRUSH := "ABI606"
const ABILITIES := [HEAVY,REFLECT_ABI,HEAL,FRACTURE,SURGE,CRUSH]
const CHARGE := "EFF601"
const REFLECT_EFF := "EFF602"
const FRACTURE_EFF := "EFF603"
const SURGE_EFF := "EFF604"

static func is_hammer_ability(ability_id: String) -> bool:
	return ABILITIES.has(ability_id)

static func _weapon(source: CombatantState) -> Dictionary:
	for raw in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw
		if int(profile.get("weapon_index",-1))==0 and String(profile.get("weapon_class","")).to_lower()=="hammer":
			return profile
	return {}

static func _average(profile: Dictionary) -> float:
	return (float(profile.get("damage_min",0.0))+float(profile.get("damage_max",0.0)))*0.5

static func charges(source: CombatantState, round_number: int) -> int:
	var n := 0
	var cap := 0
	for record in CombatModifierService.active_effects(source,round_number):
		if String(record.get("effect_id","")) == CHARGE:
			cap = EffectCatalog.stack_cap(CHARGE,Dictionary(record.get("definition",{})))
			n += int(record.get("stacks",0))
	return mini(cap,n)

static func _charge_record(source: CombatantState) -> Dictionary:
	for raw in source.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == CHARGE:
			return record
	return {}

static func gain_charges(engine: CombatEngine, source: CombatantState, n: int) -> void:
	if n <= 0 or source == null or source.is_death_finalized() or _weapon(source).is_empty():
		return
	var record := _charge_record(source)
	var current_definition: Dictionary = Dictionary(engine.canonical_effects.get(CHARGE,{})) if record.is_empty() else Dictionary(record.get("definition",{}))
	var cap := EffectCatalog.stack_cap(CHARGE,current_definition)
	if record.is_empty():
		source.active_effects.append({
			"effect_id":CHARGE,
			"definition":current_definition.duplicate(true),
			"source_id":source.combatant_id,
			"source_type":"hammer_passive",
			"start_round":engine.state.round_number,
			"remaining_rounds":1,
			"stacks":mini(n,cap),
			"revealed":true
		})
	else:
		record["stacks"] = mini(cap,int(record.get("stacks",0))+n)

static func _consume(source: CombatantState, n: int) -> void:
	if source == null or n <= 0:
		return
	var record := _charge_record(source)
	if record.is_empty():
		return
	var rest := maxi(0,int(record.get("stacks",0))-n)
	if rest <= 0:
		source.active_effects.erase(record)
	else:
		record["stacks"] = rest

static func _effect(engine: CombatEngine, source_id: String, target_id: String, parent_id: int, eff_id: String, pre: bool = false, extras: Dictionary = {}) -> void:
	var payload := {"effect_id":eff_id,"source_type":"ability","base_chance":100.0,"effect_roll":1,"preparation_effect":pre}
	for key in extras:
		payload[key] = extras[key]
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload,parent_id))

static func _queue_attack(engine: CombatEngine, action: CombatEvent, profile: Dictionary, multiplier: float, extras: Dictionary = {}) -> void:
	var component := {"damage_type":String(profile.get("damage_type","blunt")),"zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,_average(profile)*multiplier,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["hammer_abi_id"] = String(action.payload.get("ability_id",""))
	for key in extras:
		payload[key] = extras[key]
	var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,action.target_id,payload,action.event_id)
	engine.state.queue_event(attack)
	action.set_result("child_event_ids",[attack.event_id])

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var profile := _weapon(source)
	if profile.is_empty():
		action.set_result("outcome","hammer_mh_required")
		return
	if id == HEAVY:
		# 20% MH is attached to its ordinary locked attack in CombatRound.
		action.set_result("outcome","linked_to_existing_mh")
		return
	if id == REFLECT_ABI:
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(REFLECT_ABI),true)
		action.set_result("outcome","reflect_active")
		return
	var n := charges(source,engine.state.round_number)
	if id == HEAL:
		var spent := roundi(float(n)*0.50)
		_consume(source,spent)
		var heal_value := roundi(float(source.max_hp)*float(spent)/200.0)
		engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,action.source_id,action.source_id,{
			"inline_heal":heal_value,"clamp_heal_to_max":true,
			"source_type":"ability","ability_id":id
		},action.event_id))
		action.set_result("charges_consumed",spent)
		action.set_result("outcome","healing")
		return
	if id == SURGE:
		var spent := roundi(float(n)*0.25)
		_consume(source,spent)
		_effect(engine,action.source_id,action.source_id,action.event_id,AbilityCatalog.effect_id(SURGE),true,{"hammer_surge_pct":float(spent)})
		action.set_result("charges_consumed",spent)
		action.set_result("outcome","surge_active")
		return
	var target := engine.state.get_combatant(action.target_id)
	if target == null or target.is_death_finalized() or target == source:
		action.set_result("outcome","invalid_target")
		return
	if engine.group_state != null and engine.group_state.team_of(action.source_id)==engine.group_state.team_of(action.target_id):
		action.set_result("outcome","friendly_target")
		return
	if engine.zone_state != null and engine.zone_state.distance(action.source_id,action.target_id)!=0:
		action.set_result("outcome","out_of_range")
		return
	if id == FRACTURE:
		_consume(source,n)
		_queue_attack(engine,action,profile,2.0,{
			"hammer_fracture_charges":n,
			"hammer_fracture_zone":String(action.payload.get("zone","chest"))
		})
		# Charges are spent even if attack fails or produces no armour debuff.
		action.set_result("charges_consumed",n)
		action.set_result("outcome","dispatched")
	elif id == CRUSH:
		_consume(source,n)
		_queue_attack(engine,action,profile,minf(3.0,float(n)*0.03),{
			"hammer_formal_tempo_delta":-mini(200,n*2)
		})
		action.set_result("charges_consumed",n)
		action.set_result("outcome","dispatched")

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState) -> void:
	var abi := String(attack.payload.get("hammer_abi_id",""))
	if abi == HEAVY or abi == CRUSH:
		# A connected hammer hit applies real Tempo debt; no control on misses,
		# dodges or blocks. CombatTempoService owns delayed stun and immunity.
		var target := engine.state.get_combatant(attack.target_id)
		var control := 25.0 if abi == HEAVY else float(-int(attack.payload.get("hammer_formal_tempo_delta",0)))
		if target != null and control > 0.0:
			CombatTempoService.apply_control(target,control)
			attack.set_result("tempo_control_applied",control)
	elif abi == FRACTURE:
		var effect_id := AbilityCatalog.effect_id(FRACTURE,"on_hit")
		var spent := int(attack.payload.get("hammer_fracture_charges",0))
		var context := {"hammer_fracture_charges":spent}
		if EffectCatalog.application_duration_rounds(EffectCatalog.definition(engine.canonical_effects,effect_id),context) > 0:
			_effect(engine,attack.source_id,attack.target_id,attack.event_id,effect_id,false,{
				"hammer_fracture_charges":spent,
				"hammer_fracture_pct":spent,
				"hammer_fracture_zone":String(attack.payload.get("hammer_fracture_zone","chest"))
			})
	# Ordinary MH autoattack is a source of charges, regardless of which ABI
	# was activated in the same round. Never count standalone ABI attacks.
	if bool(attack.payload.get("is_weapon_attack",false)) and String(attack.payload.get("source_kind","")) != "ability" and int(attack.payload.get("weapon_index",-1))==0 and String(attacker.combat_loadout.get("weapon_class","")).to_lower()=="hammer" and not _weapon(attacker).is_empty():
		gain_charges(engine,attacker,5+(5 if bool(attack.result.get("critical",false)) else 0))

static func on_damage(engine: CombatEngine, event: CombatEvent, target: CombatantState) -> void:
	var dealt := int(event.result.get("final_damage",0))
	if dealt <= 0:
		return
	# Passive: 1 charge per nonzero damage EVENT. 5 separate DoTs = 5.
	if String(target.combat_loadout.get("weapon_class","")).to_lower()=="hammer":
		gain_charges(engine,target,1)
	var attacker := engine.state.get_combatant(event.source_id)
	if attacker != null and attacker.combatant_id != target.combatant_id:
		var lifesteal := CombatModifierService.modifier(attacker,"damage_lifesteal_pct",engine.state.round_number)
		var heal := int(floor(float(dealt)*maxf(0.0,lifesteal)/100.0))
		if heal > 0:
			engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,attacker.combatant_id,attacker.combatant_id,{
				"inline_heal":heal,"clamp_heal_to_max":true,
				"source_type":"ability","ability_id":SURGE
			},event.event_id))
	if String(event.payload.get("source","")) == "hammer_reflection" or attacker == null or attacker.combatant_id == target.combatant_id:
		return # No reflection chain.
	var reflect := CombatModifierService.modifier(target,"reflection_pct",engine.state.round_number)
	if reflect > 0.0:
		engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.DAMAGE,target.combatant_id,attacker.combatant_id,{
			"amount":float(dealt)*reflect/100.0,
			"damage_type":String(event.payload.get("damage_type","physical")),
			"source":"hammer_reflection"
		},event.event_id))
