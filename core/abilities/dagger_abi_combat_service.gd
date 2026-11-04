class_name DaggerAbiCombatService
extends RefCounted

## Physical dagger ABI401-402 only. Follow the shared ACTION -> ATTACK ->
## DAMAGE/EFFECT chain; do not bypass hit, dodge, block, crit or armour.
const QUICK := "ABI401"
const COATING := "ABI402"
const BREACH := "EFF401"
const COATING_EFF := "EFF402"
const POISON := "EFF403"

static func is_dagger_ability(ability_id: String) -> bool:
	return ability_id in [QUICK, COATING]

static func dispatch(engine: CombatEngine, action: CombatEvent) -> void:
	var id := String(action.payload.get("ability_id",""))
	if id == COATING:
		# Instant EFF applies before ordinary MH/OH attacks of this round.
		var eff := engine.state.create_event(CombatEvent.Kind.EFFECT,action.source_id,action.source_id,{
			"effect_id":COATING_EFF,"base_chance":100.0,"effect_roll":1,
			"source_type":"ability","ability_id":COATING,
			"preparation_effect":true
		},action.event_id)
		engine.state.queue_event(eff)
		action.set_result("outcome","coating_applied")
		return
	if id != QUICK:
		action.set_result("outcome","unknown_dagger_ability")
		return
	var source := engine.state.get_combatant(action.source_id)
	if source == null or source.is_death_finalized():
		action.set_result("outcome","invalid_combatant")
		return
	var mh := {}
	for raw_profile in WeaponAttackProfile.all(source):
		var profile: Dictionary = raw_profile
		if int(profile.get("weapon_index",-1)) == 0 and String(profile.get("weapon_class","")).to_lower() == "dagger":
			mh = profile
			break
	if mh.is_empty():
		action.set_result("outcome","dagger_mh_required")
		return
	var defender := engine.state.get_combatant(action.target_id)
	if defender == null or defender.is_death_finalized():
		action.set_result("outcome","invalid_target")
		return
	if engine.group_state != null and engine.group_state.team_of(action.source_id) == engine.group_state.team_of(action.target_id):
		action.set_result("outcome","friendly_target")
		return
	if engine.zone_state != null and engine.zone_state.distance(action.source_id,action.target_id) != 0:
		action.set_result("outcome","out_of_range")
		return
	var base := CombatMath.roll_damage(float(mh.get("damage_min",0.0)),float(mh.get("damage_max",0.0)),engine.combat_rng.randf()) * 0.20
	var component := {"damage_type":String(mh.get("damage_type","piercing")),"zone":String(action.payload.get("zone","chest"))}
	var payload := CombatDamagePayload.ability_attack_payload(action,component,base,1.0)
	payload["rolls"] = engine.complete_attack_rolls(Dictionary(action.payload.get("rolls",{})))
	payload["dagger_abi_id"] = QUICK
	var attack := engine.state.create_event(CombatEvent.Kind.ATTACK,action.source_id,action.target_id,payload,action.event_id)
	engine.state.queue_event(attack)
	action.set_result("outcome","dispatched")
	action.set_result("child_event_ids",[attack.event_id])

static func on_connected_attack(engine: CombatEngine, attack: CombatEvent, attacker: CombatantState) -> void:
	if String(attack.payload.get("dagger_abi_id","")) == QUICK:
		# No AP for a missed, dodged or blocked quick attack.
		attacker.gain_action_points(1)
		_apply_effect(engine,attack,BREACH)
		return
	# Coating applies to ordinary weapon MH/OH hits, not to ABI hits.
	if not bool(attack.payload.get("is_weapon_attack",false)):
		return
	if String(attack.payload.get("source_kind","")) == "ability":
		return
	var index := int(attack.payload.get("weapon_index",-1))
	var has_dagger := false
	for raw_profile in WeaponAttackProfile.all(attacker):
		var profile: Dictionary = raw_profile
		if int(profile.get("weapon_index",-1)) == index and String(profile.get("weapon_class","")).to_lower() == "dagger":
			has_dagger = true
			break
	if not has_dagger:
		return
	var active := false
	for record in CombatModifierService.active_effects(attacker,engine.state.round_number):
		if String(record.get("effect_id","")) == COATING_EFF:
			active = true
			break
	if not active:
		return
	_apply_effect(engine,attack,POISON)

static func on_effect_applied(engine: CombatEngine, event: CombatEvent) -> void:
	# The optional AP roll occurs ONLY when poison was actually applied.
	if String(event.payload.get("effect_id","")) != POISON or not bool(event.result.get("resolved",false)):
		return
	var source := engine.state.get_combatant(event.source_id)
	if source != null and engine.combat_rng.randf() < 0.05:
		source.gain_action_points(1)

static func _apply_effect(engine: CombatEngine, attack: CombatEvent, effect_id: String) -> void:
	engine.state.queue_event(engine.state.create_event(CombatEvent.Kind.EFFECT,attack.source_id,attack.target_id,{
		"effect_id":effect_id,"source_type":"ability",
		"ability_id":String(attack.payload.get("dagger_abi_id",COATING)),
		"base_chance":100.0,"effect_roll":1
	},attack.event_id))
