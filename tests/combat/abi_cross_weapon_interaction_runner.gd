extends SceneTree

## Deterministic cross-weapon integration: use the production CombatEngine,
## canonical PAR fixtures, real EFF catalog and the common event queue.
## No artificial damage modifiers or alternate attack resolution.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ABI_CROSS_WEAPON_CASE=FAIL ",label)

func _initialize() -> void:
	_sword_cripple_versus_axe_damage()
	_dagger_breach_versus_hammer_armour()
	_hammer_charge_magic_resist_versus_penetration()
	_dagger_poison_versus_hammer_reflection()
	_axe_counter_versus_dagger_dodge()
	_hammer_tempo_versus_axe_immunity()
	print("ABI_CROSS_WEAPON_INTERACTION_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _damage_type(weapon_class: String) -> String:
	match weapon_class:
		"sword": return "slashing"
		"dagger": return "piercing"
		"axe": return "chopping"
		_: return "blunt"

func _fighter(id: String, weapon_class: String) -> CombatantState:
	var fighter := TestFixtureLoader.new_combatant(id,id,10,10000,200)
	var weapon: Dictionary = {
		"slot":"main_hand","instance_id":id+"_mh","weapon_class":weapon_class,
		"damage_min":100.0,"damage_max":100.0,"damage_type":_damage_type(weapon_class)
	}
	var profiles: Array = [weapon]
	if weapon_class == "dagger":
		profiles.append({
			"slot":"off_hand","instance_id":id+"_oh","weapon_class":"dagger",
			"damage_min":75.0,"damage_max":75.0,"damage_type":"piercing"
		})
	TestFixtureLoader.set_weapon_profiles(fighter,profiles)
	fighter.combat_loadout["weapon_class"] = weapon_class
	fighter.combat_stats["manual_block_zones"] = []
	fighter.combat_stats["dodge_rating_percent"] = 0.0
	fighter.combat_stats["shield_auto_block_rating_percent"] = 0.0
	CombatTempoService.initialize(fighter,0.0,100.0,0.0)
	return fighter

func _pair(left_class: String, right_class: String) -> Dictionary:
	var state := CombatState.new()
	state.add_combatant(_fighter("left",left_class))
	state.add_combatant(_fighter("right",right_class))
	state.begin_round()
	var engine := CombatEngine.new(state)
	engine.combat_rng.seed = 20261106
	return {"state":state,"engine":engine}

func _effect(ctx: Dictionary, source_id: String, target_id: String, effect_id: String, extra: Dictionary = {}, instant: bool = false) -> CombatEvent:
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var payload: Dictionary = {
		"effect_id":effect_id, "source_type":"ability", "base_chance":100.0,
		"effect_roll":1, "preparation_effect":instant
	}
	for key in extra:
		payload[key] = extra[key]
	var event := state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload)
	engine.resolve_event(event)
	_check(bool(event.result.get("resolved",false)),effect_id+":resolved")
	return event

func _attack(ctx: Dictionary, source_id: String, target_id: String, index: int = 0, extra: Dictionary = {}, hit_roll: int = 1, dodge_roll: int = 100) -> CombatEvent:
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var source := state.get_combatant(source_id)
	var profiles := WeaponAttackProfile.all(source)
	var profile: Dictionary = profiles[index]
	var rolls := {
		"hit":hit_roll,"reaction":100,"dodge":dodge_roll,"auto_block":100,
		"block_crush":100,"crit":100,"on_hit_effect":100,"damage":0.5
	}
	var payload := WeaponAttackProfile.attack_payload(profile,rolls,"chest")
	for key in extra:
		payload[key] = extra[key]
	var event := state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,payload)
	state.queue_event(event)
	engine.resolve_pending_events()
	return event

func _effects_count(fighter: CombatantState, effect_id: String) -> int:
	var n := 0
	for raw in fighter.active_effects:
		if String(Dictionary(raw).get("effect_id","")) == effect_id:
			n += 1
	return n

func _effect_stacks(fighter: CombatantState, effect_id: String) -> int:
	var n := 0
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			n += int(record.get("stacks",0))
	return n

func _sword_cripple_versus_axe_damage() -> void:
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var axe := state.get_combatant("right")
	_effect(ctx,"left","right","EFF301",{"sword_stacks_to_apply":4,"sword_eff_level":2})
	var cripple := _effect(ctx,"left","right","EFF302",{"sword_eff_level":1})
	_check(int(cripple.result.get("sword_bleed_snapshot",-1)) == 4,"sword:bleed_snapshot_four")
	state.begin_round()
	_check(is_equal_approx(CombatModifierService.modifier(axe,"physical_damage_outgoing_direct_pct",state.round_number),-20.0),"sword:cripple_reduces_axe_outgoing_by_20pct")
	var hit := _attack(ctx,"right","left")
	_check(String(hit.result.get("outcome","")) == "connected","sword:axe_hit_connected")
	_check(is_equal_approx(float(hit.result.get("raw_damage",-1.0)),80.0),"sword:cripple_applies_to_real_axe_attack")
	print("ABI_CROSS_WEAPON_CASE=CHECKED sword_bleed_cripple_vs_axe")

func _dagger_breach_versus_hammer_armour() -> void:
	var ctx := _pair("dagger","hammer")
	var state: CombatState = ctx["state"]
	var hammer := state.get_combatant("right")
	hammer.armour["chest"] = {"piercing":150.0}
	var charge_definition := EffectCatalog.definition(EffectCatalog.load_json(),"EFF601")
	hammer.active_effects.append({
		"effect_id":"EFF601","definition":charge_definition,"source_id":"right",
		"start_round":1,"remaining_rounds":1,"stacks":40
	})
	var base_hit := _attack(ctx,"left","right")
	_check(String(base_hit.result.get("outcome","")) == "connected","dagger:baseline_hit_connected")
	var base_reduction := float(base_hit.result.get("armour_reduction",-1.0))
	for i in range(5):
		_effect(ctx,"left","right","EFF401")
	_check(_effects_count(hammer,"EFF401") == 1 and _effect_stacks(hammer,"EFF401") == 5,"dagger:five_breach_stacks_in_one_record")
	state.begin_round()
	var breached_hit := _attack(ctx,"left","right")
	var breached_reduction := float(breached_hit.result.get("armour_reduction",-1.0))
	_check(String(breached_hit.result.get("outcome","")) == "connected","dagger:breached_hit_connected")
	_check(int(breached_hit.result.get("dagger_breach_stacks",-1)) == 5,"dagger:five_stacks_visible_to_damage")
	_check(base_reduction > 0.0 and breached_reduction < base_reduction,"dagger:breach_counters_hammer_charge_armour")
	_check(HammerAbiCombatService.charges(hammer,state.round_number) >= 40,"hammer:charges_survive_armour_breach")
	print("ABI_CROSS_WEAPON_CASE=CHECKED dagger_breach_vs_hammer_armour")

func _dagger_poison_versus_hammer_reflection() -> void:
	var ctx := _pair("dagger","hammer")
	var state: CombatState = ctx["state"]
	var hammer := state.get_combatant("right")
	_effect(ctx,"left","left","EFF402",{},true)
	_effect(ctx,"right","right","EFF602",{},true)
	_check(is_equal_approx(CombatModifierService.modifier(hammer,"reflection_pct",1),20.0),"hammer:reflection_effect_active")
	var mh := _attack(ctx,"left","right",0)
	var oh := _attack(ctx,"left","right",1)
	_check(String(mh.result.get("outcome","")) == "connected" and String(oh.result.get("outcome","")) == "connected","dagger:mh_oh_both_connected")
	_check(_effects_count(hammer,"EFF403") == 1 and _effect_stacks(hammer,"EFF403") == 2,"dagger:coating_applies_two_poison_stacks")
	var reflected := 0
	var own_hits := 0
	for event in state.event_log:
		if event.kind != CombatEvent.Kind.DAMAGE:
			continue
		if String(event.payload.get("source","")) == "hammer_reflection":
			reflected += 1
			_check(event.source_id == "right" and event.target_id == "left","hammer:reflection_hits_attacker")
		elif event.source_id == "left" and event.target_id == "right":
			own_hits += 1
	_check(own_hits == 2 and reflected == 2,"hammer:one_reflection_per_dagger_hit_no_recursive_chain")
	_check(HammerAbiCombatService.charges(hammer,1) == 2,"hammer:one_charge_per_taken_damage_event")
	print("ABI_CROSS_WEAPON_CASE=CHECKED dagger_poison_vs_hammer_reflection")

func _axe_counter_versus_dagger_dodge() -> void:
	var ctx := _pair("dagger","axe")
	var state: CombatState = ctx["state"]
	var axe := state.get_combatant("right")
	axe.combat_stats["dodge_rating_percent"] = 100.0
	_effect(ctx,"right","right","EFF503",{"axe_stance_dodge_pct":0.0},true)
	var dodges := 0
	for i in range(6):
		var incoming := _attack(ctx,"left","right",i%2,{},1,1)
		if String(incoming.result.get("outcome","")) == "dodge":
			dodges += 1
	var counters := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "right" and bool(event.payload.get("is_counterattack_abi",false)):
			counters += 1
			_check(String(event.result.get("outcome","")) == "connected","axe:counterattack_connected")
	_check(dodges == 6,"axe:all_six_incoming_attacks_dodged")
	_check(counters == 5,"axe:retaliation_capped_at_five")
	print("ABI_CROSS_WEAPON_CASE=CHECKED axe_retaliation_vs_dagger_dodge")

func _hammer_tempo_versus_axe_immunity() -> void:
	var ctx := _pair("hammer","axe")
	var state: CombatState = ctx["state"]
	var axe := state.get_combatant("right")
	var miss := _attack(ctx,"left","right",0,{"hammer_abi_id":"ABI606","hammer_formal_tempo_delta":-200},100)
	_check(String(miss.result.get("outcome","")) == "miss" and is_equal_approx(axe.tempo,0.0),"hammer:miss_does_not_control_tempo")
	var hit := _attack(ctx,"left","right",0,{"hammer_abi_id":"ABI606","hammer_formal_tempo_delta":-200})
	_check(String(hit.result.get("outcome","")) == "connected" and is_equal_approx(float(hit.result.get("tempo_control_applied",0.0)),200.0),"hammer:connected_hit_applies_200_tempo_debt")
	CombatTempoService.end_round(state)
	_check(axe.tempo_stun_round == 2,"hammer:stun_scheduled_for_round_two")
	state.begin_round()
	_check(CombatTempoService.is_stunned(axe,2),"hammer:next_round_stunned")
	CombatTempoService.end_round(state)
	_check(axe.tempo_immunity_until_round == 4,"hammer:two_rounds_immunity")
	state.begin_round()
	var second_hit := _attack(ctx,"left","right",0,{"hammer_abi_id":"ABI601"})
	_check(is_equal_approx(float(second_hit.result.get("tempo_control_applied",0.0)),25.0),"hammer:control_still_accumulates_during_immunity")
	CombatTempoService.end_round(state)
	_check(axe.tempo_stun_round == 2 and CombatTempoService.is_immune(axe,3),"hammer:immune_round_three_no_rechain")
	state.begin_round()
	CombatTempoService.end_round(state)
	_check(axe.tempo_stun_round == 2 and CombatTempoService.is_immune(axe,4),"hammer:immune_round_four_no_rechain")
	state.begin_round()
	CombatTempoService.end_round(state)
	_check(axe.tempo_stun_round == 6,"hammer:accumulated_debt_stuns_after_immunity")
	print("ABI_CROSS_WEAPON_CASE=CHECKED hammer_tempo_vs_axe_immunity")

func _hammer_charge_magic_resist_versus_penetration() -> void:
	var ctx := _pair("dagger","hammer")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var attacker := state.get_combatant("left")
	var hammer := state.get_combatant("right")
	var baseline := CombatModifierService.magic_resist(hammer,"fire",1,attacker)
	HammerAbiCombatService.gain_charges(engine,hammer,80)
	var fortified := CombatModifierService.magic_resist(hammer,"fire",1,attacker)
	_check(HammerAbiCombatService.charges(hammer,1) == 80,"hammer:charge_cap_preserves_eighty")
	_check(fortified > baseline,"hammer:charges_raise_magic_resist")
	var first := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"fire","source":"ability"
	})
	engine.resolve_event(first)
	_check(is_equal_approx(float(first.result.get("magic_resist",-1.0)),fortified),"hammer:fire_damage_uses_charge_resistance")
	var totals: Dictionary = attacker.combat_stats["par_totals"]
	totals["PAR164"] = 10000.0
	attacker.combat_stats["par_totals"] = totals
	var penetrated := CombatModifierService.magic_resist(hammer,"fire",1,attacker)
	_check(penetrated < fortified,"dagger:magic_pen_rating_counters_hammer_resist")
	var second := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"fire","source":"ability"
	})
	engine.resolve_event(second)
	_check(int(second.result.get("final_damage",0)) > int(first.result.get("final_damage",0)),"dagger:penetration_increases_real_magic_damage")
	print("ABI_CROSS_WEAPON_CASE=CHECKED hammer_magic_resist_vs_penetration")
