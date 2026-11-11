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
	_abi_to_eff_references()
	_abi_mh_bonus_ownership()
	_dagger_abi_coefficients_from_catalog()
	_dagger_legacy_action_uses_canonical_bonus()
	_dagger_poison_proc_from_eff()
	_abi_target_limits_from_catalog()
	_legacy_abi_target_cap_fallback()
	_sword_cripple_versus_axe_damage()
	_sword_effect_strength_from_catalog()
	_sword_hit_ap_and_critical_numbers_from_catalog()
	_dynamic_effects_from_catalog()
	_dagger_breach_versus_hammer_armour()
	_hammer_charge_magic_resist_versus_penetration()
	_axe_rage_value_comes_from_eff()
	_axe_abi_coefficients_from_catalog()
	_hammer_abi_coefficients_from_catalog()
	_hammer_eff601_charge_generation()
	_dagger_poison_versus_hammer_reflection()
	_axe_counter_versus_dagger_dodge()
	_hammer_tempo_versus_axe_immunity()
	print("ABI_CROSS_WEAPON_INTERACTION_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _abi_to_eff_references() -> void:
	var abilities := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	for abi_id in abilities:
		var abi: Dictionary = abilities[abi_id]
		_check(not abi.has("eff") and not abi.has("effect_level"),String(abi_id)+":no_duplicate_eff_aliases")
		var primary := AbilityCatalog.effect_id(String(abi_id))
		for raw in abi.get("components", []):
			if raw is Dictionary and String(raw.get("kind", "")) == "effect":
				var expected := String(raw.get("effect_id", ""))
				_check(primary == expected and effects.has(expected), String(abi_id) + ":primary_eff_reference")
		if abi.has("sword_eff_id"):
			_check(primary == String(abi["sword_eff_id"]) and effects.has(primary), String(abi_id) + ":sword_eff_reference")
		var roles: Dictionary = abi.get("effect_refs", {})
		for role in roles:
			var expected := String(roles[role])
			_check(AbilityCatalog.effect_id(String(abi_id),String(role)) == expected and effects.has(expected), String(abi_id) + ":" + String(role) + "_eff_reference")

## ABI owns target caps, including unscheduled/custom action snapshots.
func _abi_target_limits_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	for spec in [
		{"abi":"ABI302","class":"sword","expected":3},
		{"abi":"ABI307","class":"sword","expected":5},
		{"abi":"ABI403","class":"dagger","expected":5},
		{"abi":"ABI508","class":"axe","expected":3}
	]:
		var id := String(spec["abi"])
		var authored: Dictionary = defs.get(id,{})
		_check(int(authored.get("max_targets",-1)) == int(spec["expected"]),id+":canonical_target_cap")
		var ctx := _pair(String(spec["class"]),"hammer")
		var state: CombatState = ctx["state"]
		var action_definition: Dictionary = authored.duplicate(true)
		var intent := AbilityRuntime.build_action_event(state,"left","right",id,action_definition)
		_check(int(intent.payload.get("max_targets",-1)) == int(spec["expected"]),id+":target_cap_in_event")
		if id == "ABI307":
			continue
		# Lower cap in a test-only event, with more than two valid enemies.
		action_definition["max_targets"] = 2
		state.add_combatant(_fighter("extra_1","hammer"))
		state.add_combatant(_fighter("extra_2","hammer"))
		var limited := AbilityRuntime.build_action_event(state,"left","right",id,action_definition)
		var engine: CombatEngine = ctx["engine"]
		if id == "ABI302":
			SwordAbiCombatService.dispatch(engine,limited)
		elif id == "ABI403":
			DaggerAbiCombatService.dispatch(engine,limited)
		else:
			AxeAbiCombatService.dispatch(engine,limited)
		_check(Array(limited.result.get("child_event_ids",[])).size() == 2,id+":target_cap_dispatch")

## Queued combat ACTIONs from before the max_targets field existed
## must retain the authored AoE size, not silently fall back to one target.
func _legacy_abi_target_cap_fallback() -> void:
	for spec in [
		{"abi":"ABI302","class":"sword","mode":"aoe_3","count":3},
		{"abi":"ABI307","class":"sword","mode":"dodge_ultimate","count":5},
		{"abi":"ABI403","class":"dagger","mode":"","count":5},
		{"abi":"ABI508","class":"axe","mode":"","count":3}
	]:
		var ctx := _pair(String(spec["class"]),"hammer")
		var state: CombatState = ctx["state"]
		var engine: CombatEngine = ctx["engine"]
		for i in range(4):
			state.add_combatant(_fighter("legacy_extra_"+str(i),"hammer"))
		var id := String(spec["abi"])
		var action := state.create_event(CombatEvent.Kind.ACTION,"left","right",{
			"ability_id":id,"source_kind":"ability","zone":"chest",
			"sword_ability_mode":String(spec["mode"]),"ap_spent":1
		})
		if String(spec["class"]) == "sword":
			SwordAbiCombatService.dispatch(engine,action)
		elif String(spec["class"]) == "dagger":
			DaggerAbiCombatService.dispatch(engine,action)
		else:
			AxeAbiCombatService.dispatch(engine,action)
		_check(Array(action.result.get("child_event_ids",[])).size()==int(spec["count"]),id+":legacy_target_cap_from_catalog")


## Changed test-only ABI501/ABI601 bonuses must reach the first ordinary
## MH attack and real CombatEngine damage without any repeated +20 constant.
func _abi_mh_bonus_ownership() -> void:
	var abilities := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	for case in [
		{"ability_id":"ABI501","weapon_class":"axe","bonus":37.0,"payload_key":"axe_mh_damage_bonus_pct"},
		{"ability_id":"ABI601","weapon_class":"hammer","bonus":43.0,"payload_key":"hammer_mh_damage_bonus_pct"}
	]:
		var id := String(case["ability_id"])
		var abi_definition: Dictionary = Dictionary(abilities[id]).duplicate(true)
		_check(is_equal_approx(float(abi_definition.get("mh_damage_bonus_pct",-1.0)),20.0),id+":catalog_ordinary_mh_bonus")
		abi_definition["mh_damage_bonus_pct"] = float(case["bonus"])
		var ctx := _pair(String(case["weapon_class"]),"dagger")
		var state: CombatState = ctx["state"]
		var engine: CombatEngine = ctx["engine"]
		var source := state.get_combatant("left")
		var profile: Dictionary = WeaponAttackProfile.all(source)[0]
		var rolls := {"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
		var mh := state.create_event(CombatEvent.Kind.ATTACK,"left","right",WeaponAttackProfile.attack_payload(profile,rolls,"chest"))
		var ability_action := AbilityRuntime.build_action_event(state,"left","right",id,abi_definition)
		var round := CombatRound.new(state.round_number)
		round.lock_action(mh)
		round.lock_action(ability_action)
		round.resolve(engine)
		var payload_key := String(case["payload_key"])
		_check(is_equal_approx(float(mh.payload.get(payload_key,-1.0)),float(case["bonus"])),id+":MH_bonus_attached_from_ABI")
		_check(String(mh.result.get("outcome","")) == "connected",id+":MH_hit_connected")
		_check(is_equal_approx(float(mh.result.get("raw_damage",-1.0)),100.0*(1.0+float(case["bonus"])/100.0)),id+":MH_damage_follows_ABI_bonus")

## The production dagger dispatch must obey changed test-only ABI values,
## including old events which did not yet carry their ABI numeric fields.
## Sword ABI301 links to the ordinary MH; ABI302 grants AP only once
## after an actual connected AoE hit. Neither value belongs to Combat.
func _sword_hit_ap_and_critical_numbers_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var actor := state.get_combatant("left")
	actor.action_points = 0
	var profile: Dictionary = WeaponAttackProfile.all(actor)[0]
	var rolls := {"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
	var mh := state.create_event(CombatEvent.Kind.ATTACK,"left","right",WeaponAttackProfile.attack_payload(profile,rolls,"chest"))
	var definition: Dictionary = Dictionary(defs["ABI301"]).duplicate(true)
	definition["ap_gain"] = 3
	var action := AbilityRuntime.build_action_event(state,"left","right","ABI301",definition)
	var round := CombatRound.new(state.round_number)
	round.lock_action(mh)
	round.lock_action(action)
	round.resolve(engine)
	_check(String(mh.result.get("outcome",""))=="connected","ABI301:MH_hit_connected")
	_check(int(mh.payload.get("sword_ap_gain_on_hit",-1))==3,"ABI301:action_AP_snapshot_attached")
	_check(actor.action_points==3,"ABI301:AP_from_authored_snapshot")

	var aoe_ctx := _pair("sword","axe")
	var aoe_state: CombatState = aoe_ctx["state"]
	var aoe_engine: CombatEngine = aoe_ctx["engine"]
	var aoe_actor := aoe_state.get_combatant("left")
	aoe_actor.action_points = 0
	var aoe_def: Dictionary = Dictionary(defs["ABI302"]).duplicate(true)
	aoe_def["ap_gain"] = 4
	aoe_def["rolls"] = rolls
	var aoe_action := AbilityRuntime.build_action_event(aoe_state,"left","right","ABI302",aoe_def)
	aoe_state.queue_event(aoe_action)
	aoe_engine.resolve_pending_events()
	_check(int(aoe_action.result.get("ap_gained_on_hit",-1))==4,"ABI302:AP_from_authored_snapshot")
	_check(aoe_actor.action_points==4,"ABI302:AP_awarded_once")

	var legacy_ctx := _pair("sword","axe")
	var legacy_actor := legacy_ctx["state"].get_combatant("left")
	legacy_actor.action_points = 0
	var legacy_hit := _attack(legacy_ctx,"left","right",0,{"sword_abi_id":"ABI301"})
	_check(String(legacy_hit.result.get("outcome",""))=="connected","ABI301:legacy_MH_connected")
	_check(legacy_actor.action_points==1,"ABI301:legacy_hit_uses_canonical_AP")

	var crit_ctx := _pair("sword","axe")
	var crit_state: CombatState = crit_ctx["state"]
	var crit_engine: CombatEngine = crit_ctx["engine"]
	var crit_def: Dictionary = Dictionary(defs["ABI308"]).duplicate(true)
	crit_def["crit_pct_per_ap"] = 17
	crit_def["crit_damage_pct_per_ap"] = 31
	var crit_action := AbilityRuntime.build_action_event(crit_state,"left","right","ABI308",crit_def)
	crit_action.payload["ap_spent"] = 2
	SwordAbiCombatService.dispatch(crit_engine,crit_action)
	for pending in crit_state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("sword_abi_id",""))=="ABI308":
			_check(is_equal_approx(float(pending.payload.get("sword_crit_chance_pct",-1.0)),34.0),"ABI308:crit_chance_from_authored_snapshot")
			_check(is_equal_approx(float(pending.payload.get("sword_crit_damage_pct",-1.0)),62.0),"ABI308:crit_damage_from_authored_snapshot")
	var old_crit_ctx := _pair("sword","axe")
	var old_crit_state: CombatState = old_crit_ctx["state"]
	var old_crit_engine: CombatEngine = old_crit_ctx["engine"]
	var old_crit_action := old_crit_state.create_event(CombatEvent.Kind.ACTION,"left","right",{
		"ability_id":"ABI308","sword_ability_mode":"crit_ultimate","ap_spent":2,"source_kind":"ability"
	})
	SwordAbiCombatService.dispatch(old_crit_engine,old_crit_action)
	for pending in old_crit_state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("sword_abi_id",""))=="ABI308":
			_check(is_equal_approx(float(pending.payload.get("sword_crit_chance_pct",-1.0)),20.0),"ABI308:legacy_crit_chance_from_catalog")
			_check(is_equal_approx(float(pending.payload.get("sword_crit_damage_pct",-1.0)),50.0),"ABI308:legacy_crit_damage_from_catalog")


func _dagger_abi_coefficients_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	for scenario in [
		{"abi":"ABI401","overrides":{"damage_multiplier":0.37,"ap_gain":3},"poison":0,"breach":0,"expected_damage":[37.0]},
		{"abi":"ABI403","overrides":{"damage_multiplier":0.80},"poison":0,"breach":0,"expected_damage":[140.0]},
		{"abi":"ABI404","overrides":{"poison_damage_bonus_per_stack":0.27},"poison":2,"breach":0,"expected_damage":[154.0,115.5]},
		{"abi":"ABI405","overrides":{"damage_multiplier":1.25},"poison":0,"breach":0,"expected_damage":[125.0,93.75]},
		{"abi":"ABI406","overrides":{"strike_damage_multiplier":0.42},"poison":3,"breach":0,"expected_damage":[42.0,31.5,42.0]},
		{"abi":"ABI407","overrides":{"breach_damage_multiplier":0.80,"poison_stacks_per_breach":3},"poison":5,"breach":2,"expected_damage":[160.0]},
		{"abi":"ABI408","overrides":{"armour_bypass_pct_per_breach_stack":11.0},"poison":0,"breach":3,"expected_damage":[100.0,75.0]}
	]:
		var id := String(scenario["abi"])
		var ctx := _pair("dagger","axe")
		var state: CombatState = ctx["state"]
		var engine: CombatEngine = ctx["engine"]
		var defender := state.get_combatant("right")
		for spec in [
			{"eff":"EFF403","count":int(scenario["poison"])},
			{"eff":"EFF401","count":int(scenario["breach"])}
		]:
			if int(spec["count"]) <= 0:
				continue
			var eff_id := String(spec["eff"])
			defender.active_effects.append({
				"effect_id":eff_id,"definition":EffectCatalog.definition(engine.canonical_effects,eff_id).duplicate(true),
				"source_id":"left","start_round":1,"remaining_rounds":5,"stacks":int(spec["count"])
			})
		var definition: Dictionary = Dictionary(defs[id]).duplicate(true)
		if id == "ABI403" or id == "ABI405":
			_check(is_equal_approx(float(definition.get("damage_multiplier",-1.0)),1.0),id+":authored_base_multiplier")
		for field in Dictionary(scenario["overrides"]):
			definition[field] = scenario["overrides"][field]
		definition["rolls"] = {"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
		var action := AbilityRuntime.build_action_event(state,"left","right",id,definition)
		DaggerAbiCombatService.dispatch(engine,action)
		var attack_events: Array[CombatEvent] = []
		for pending in state.pending_events:
			if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("dagger_abi_id","")) == id:
				attack_events.append(pending)
		var expected: Array = scenario["expected_damage"]
		_check(attack_events.size()==expected.size(),id+":custom_attack_count")
		for i in range(mini(attack_events.size(),expected.size())):
			_check(is_equal_approx(float(attack_events[i].payload.get("raw_damage",-1.0)),float(expected[i])),id+":custom_damage_"+str(i))
		if id == "ABI401" and not attack_events.is_empty():
			_check(int(attack_events[0].payload.get("dagger_ap_gain_on_hit",-1))==3,"ABI401:custom_AP_in_attack_snapshot")
			var attacker := state.get_combatant("left")
			attacker.action_points = 0
			engine.resolve_pending_events()
			_check(attacker.action_points==3,"ABI401:custom_AP_awarded_after_hit")
		if id == "ABI407":
			_check(int(action.result.get("breach_stacks_to_apply",-1))==1,"ABI407:poison_conversion_ratio_from_abi")
		if id == "ABI408" and not attack_events.is_empty():
			_check(is_equal_approx(float(attack_events[0].payload.get("dagger_armour_bypass_pct",-1.0)),33.0),"ABI408:armour_bypass_from_abi")

## Older ACTION events never carried the new numeric fields.
func _dagger_legacy_action_uses_canonical_bonus() -> void:
	var ctx := _pair("dagger","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var legacy := state.create_event(CombatEvent.Kind.ACTION,"left","right",{"ability_id":"ABI401","source_kind":"ability","zone":"chest"})
	DaggerAbiCombatService.dispatch(engine,legacy)
	for event in state.pending_events:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("dagger_abi_id","")) == "ABI401":
			_check(is_equal_approx(float(event.payload.get("raw_damage",-1.0)),20.0),"ABI401:legacy_action_uses_canonical_multiplier")
			_check(int(event.payload.get("dagger_ap_gain_on_hit",-1))==1,"ABI401:legacy_action_uses_canonical_AP")
			return
	_check(false,"ABI401:legacy_action_queued_attack")

func _dagger_poison_proc_from_eff() -> void:
	var ctx := _pair("dagger","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var source := state.get_combatant("left")
	source.action_points = 0
	engine.canonical_effects["EFF403"]["ap_gain_on_apply_chance_pct"] = 100.0
	engine.canonical_effects["EFF403"]["ap_gain_on_apply"] = 2
	_effect(ctx,"left","right","EFF403")
	_check(source.action_points==2,"EFF403:poison_AP_proc_uses_effect_chance_and_amount")
	source.action_points = 0
	engine.canonical_effects["EFF403"]["ap_gain_on_apply_chance_pct"] = 0.0
	_effect(ctx,"left","right","EFF403")
	_check(source.action_points==0,"EFF403:zero_proc_chance_prevents_AP")

## The canonical EFF rage cap and ABI requirements are independent.
## All changed values are test-only and must survive action snapshots.
func _axe_abi_coefficients_from_catalog() -> void:
	var definitions := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	for scenario in [
		{"abi":"ABI502","overrides":{"attack_damage_pct":135.0},"rage":0,"expected":135.0},
		{"abi":"ABI503","overrides":{"attack_damage_pct":137.0},"rage":0,"expected":137.0},
		{"abi":"ABI505","overrides":{"attack_damage_pct":139.0},"rage":0,"expected":139.0},
		{"abi":"ABI506","overrides":{"execute_hp_threshold_fraction":0.35,"min_rage_stacks":2,"damage_pct_per_rage_stack":91.0},"rage":4,"expected":364.0},
		{"abi":"ABI508","overrides":{"single_target_damage_pct":170.0,"multi_target_damage_pct":65.0,"damage_pct_per_rage_stack":13.0},"rage":2,"expected":196.0}
	]:
		var id := String(scenario["abi"])
		var ctx := _pair("axe","dagger")
		var state: CombatState = ctx["state"]
		var engine: CombatEngine = ctx["engine"]
		var actor := state.get_combatant("left")
		var target := state.get_combatant("right")
		var rage_count := int(scenario["rage"])
		if rage_count > 0:
			actor.active_effects.append({
				"effect_id":"EFF501","definition":EffectCatalog.definition(engine.canonical_effects,"EFF501").duplicate(true),
				"source_id":"left","start_round":1,"remaining_rounds":5,"stacks":rage_count
			})
		if id == "ABI506":
			target.hp = 3000
			_check(not AxeAbiCombatService.can_cast(state,"left","right",id),"axe:canonical_execute_threshold_remains_20pct")
		var definition: Dictionary = Dictionary(definitions[id]).duplicate(true)
		for raw_field in Dictionary(scenario["overrides"]):
			definition[raw_field] = scenario["overrides"][raw_field]
		definition["rolls"] = {"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
		var action := AbilityRuntime.build_action_event(state,"left","right",id,definition)
		AxeAbiCombatService.dispatch(engine,action)
		var attacks: Array[CombatEvent] = []
		for pending in state.pending_events:
			if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("axe_abi_id","")) == id:
				attacks.append(pending)
		_check(attacks.size()==1,id+":single_attack_created")
		if not attacks.is_empty():
			_check(is_equal_approx(float(attacks[0].payload.get("raw_damage",-1.0)),float(scenario["expected"])),id+":custom_damage_from_abi")
		if id == "ABI508":
			var group_ctx := _pair("axe","dagger")
			var group_state: CombatState = group_ctx["state"]
			var group_engine: CombatEngine = group_ctx["engine"]
			var group_actor := group_state.get_combatant("left")
			group_actor.active_effects.append({
				"effect_id":"EFF501","definition":EffectCatalog.definition(group_engine.canonical_effects,"EFF501").duplicate(true),
				"source_id":"left","start_round":1,"remaining_rounds":5,"stacks":rage_count
			})
			group_state.add_combatant(_fighter("extra_axe1","dagger"))
			group_state.add_combatant(_fighter("extra_axe2","dagger"))
			var group_action := AbilityRuntime.build_action_event(group_state,"left","right",id,definition)
			AxeAbiCombatService.dispatch(group_engine,group_action)
			var group_attacks: Array[CombatEvent] = []
			for pending in group_state.pending_events:
				if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("axe_abi_id","")) == id:
					group_attacks.append(pending)
			_check(group_attacks.size()==3,"ABI508:group_three_targets")
			for attack in group_attacks:
				_check(is_equal_approx(float(attack.payload.get("raw_damage",-1.0)),91.0),"ABI508:group_damage_from_abi")
	# An ABI requirement is not the EFF stack cap, even when tuned to four.
	var crusher_ctx := _pair("axe","dagger")
	var crusher_state: CombatState = crusher_ctx["state"]
	var crusher_engine: CombatEngine = crusher_ctx["engine"]
	var crusher_actor := crusher_state.get_combatant("left")
	crusher_actor.active_effects.append({
		"effect_id":"EFF501","definition":EffectCatalog.definition(crusher_engine.canonical_effects,"EFF501").duplicate(true),
		"source_id":"left","start_round":1,"remaining_rounds":5,"stacks":4
	})
	_check(not AxeAbiCombatService.can_cast(crusher_state,"left","right","ABI507"),"ABI507:canonical_requires_five_rage")
	var crusher_def: Dictionary = Dictionary(definitions["ABI507"]).duplicate(true)
	crusher_def["required_rage_stacks"] = 4
	var crusher_action := AbilityRuntime.build_action_event(crusher_state,"left","left","ABI507",crusher_def)
	AxeAbiCombatService.dispatch(crusher_engine,crusher_action)
	_check(String(crusher_action.result.get("outcome",""))=="crusher_applied","ABI507:custom_requirement_from_abi")
	_check(AxeAbiCombatService.rage_stacks(crusher_actor,crusher_state.round_number)==0,"ABI507:consumes_rage_on_activation")

## Production hammer dispatch must honor changed test-only ABI coefficients.
## EFF601 stacks, EFF603 duration and EFF604 magnitude stay in their catalogs.
func _hammer_abi_coefficients_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var heavy_ctx := _pair("hammer","axe")
	var heavy_state: CombatState = heavy_ctx["state"]
	var heavy_engine: CombatEngine = heavy_ctx["engine"]
	var heavy_actor := heavy_state.get_combatant("left")
	var heavy_profile: Dictionary = WeaponAttackProfile.all(heavy_actor)[0]
	var rolls := {"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
	var mh := heavy_state.create_event(CombatEvent.Kind.ATTACK,"left","right",WeaponAttackProfile.attack_payload(heavy_profile,rolls,"chest"))
	var heavy_def: Dictionary = Dictionary(defs["ABI601"]).duplicate(true)
	heavy_def["tempo_control_on_hit"] = 39
	var heavy_action := AbilityRuntime.build_action_event(heavy_state,"left","right","ABI601",heavy_def)
	var heavy_round := CombatRound.new(heavy_state.round_number)
	heavy_round.lock_action(mh)
	heavy_round.lock_action(heavy_action)
	heavy_round.resolve(heavy_engine)
	_check(is_equal_approx(float(mh.payload.get("hammer_tempo_control_on_hit",-1.0)),39.0),"ABI601:tempo_value_from_action_snapshot")
	_check(String(mh.result.get("outcome",""))=="connected","ABI601:tempo_fixture_hit_connected")
	_check(is_equal_approx(float(mh.result.get("tempo_control_applied",-1.0)),39.0),"ABI601:tempo_39_on_hit")

	var heal_ctx := _pair("hammer","axe")
	var heal_state: CombatState = heal_ctx["state"]
	var heal_engine: CombatEngine = heal_ctx["engine"]
	var healer := heal_state.get_combatant("left")
	HammerAbiCombatService.gain_charges(heal_engine,healer,80)
	healer.hp = 6000
	var heal_def: Dictionary = Dictionary(defs["ABI603"]).duplicate(true)
	heal_def["charge_spend_fraction"] = 0.30
	heal_def["heal_hp_pct_per_spent_charge"] = 0.70
	var heal_action := AbilityRuntime.build_action_event(heal_state,"left","left","ABI603",heal_def)
	HammerAbiCombatService.dispatch(heal_engine,heal_action)
	heal_engine.resolve_pending_events()
	_check(int(heal_action.result.get("charges_consumed",-1))==24,"ABI603:custom_charge_spend")
	_check(healer.hp==7680,"ABI603:custom_heal_per_spent_charge")
	_check(HammerAbiCombatService.charges(healer,heal_state.round_number)==56,"ABI603:spent_only_24_charges")

	var surge_ctx := _pair("hammer","axe")
	var surge_state: CombatState = surge_ctx["state"]
	var surge_engine: CombatEngine = surge_ctx["engine"]
	var surger := surge_state.get_combatant("left")
	HammerAbiCombatService.gain_charges(surge_engine,surger,80)
	var surge_def: Dictionary = Dictionary(defs["ABI605"]).duplicate(true)
	surge_def["charge_spend_fraction"] = 0.40
	var surge_action := AbilityRuntime.build_action_event(surge_state,"left","left","ABI605",surge_def)
	HammerAbiCombatService.dispatch(surge_engine,surge_action)
	surge_engine.resolve_pending_events()
	_check(int(surge_action.result.get("charges_consumed",-1))==32,"ABI605:custom_charge_spend")
	_check(HammerAbiCombatService.charges(surger,surge_state.round_number)==48,"ABI605:spent_32_charges")
	var surge_record := _active_effect(surger,"EFF604")
	var surge_effect: Dictionary = surge_record.get("definition",{})
	_check(is_equal_approx(float(surge_effect.get("physical_damage_outgoing_direct_pct",-1.0)),25.0),"EFF604:surge_strength_cap_independent_from_abi_spend")
	_check(is_equal_approx(float(surge_effect.get("damage_lifesteal_pct",-1.0)),20.0),"EFF604:lifesteal_unchanged")

	var fracture_ctx := _pair("hammer","axe")
	var fracture_state: CombatState = fracture_ctx["state"]
	var fracture_engine: CombatEngine = fracture_ctx["engine"]
	var fracturer := fracture_state.get_combatant("left")
	HammerAbiCombatService.gain_charges(fracture_engine,fracturer,40)
	var fracture_def: Dictionary = Dictionary(defs["ABI604"]).duplicate(true)
	fracture_def["damage_multiplier"] = 1.8
	var fracture_action := AbilityRuntime.build_action_event(fracture_state,"left","right","ABI604",fracture_def)
	HammerAbiCombatService.dispatch(fracture_engine,fracture_action)
	var fracture_attacks: Array[CombatEvent] = []
	for pending in fracture_state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("hammer_abi_id",""))=="ABI604":
			fracture_attacks.append(pending)
	_check(fracture_attacks.size()==1,"ABI604:one_fracture_attack")
	if not fracture_attacks.is_empty():
		_check(is_equal_approx(float(fracture_attacks[0].payload.get("raw_damage",-1.0)),180.0),"ABI604:custom_multiplier_from_abi")
		_check(int(fracture_attacks[0].payload.get("hammer_fracture_charges",-1))==40,"ABI604:charge_count_sent_to_eff")
	_check(HammerAbiCombatService.charges(fracturer,fracture_state.round_number)==0,"ABI604:all_charges_consumed")

	var crush_ctx := _pair("hammer","axe")
	var crush_state: CombatState = crush_ctx["state"]
	var crush_engine: CombatEngine = crush_ctx["engine"]
	var crusher := crush_state.get_combatant("left")
	HammerAbiCombatService.gain_charges(crush_engine,crusher,80)
	var crush_def: Dictionary = Dictionary(defs["ABI606"]).duplicate(true)
	crush_def["damage_multiplier_per_charge"] = 0.04
	crush_def["max_damage_multiplier"] = 2.2
	crush_def["tempo_control_per_charge"] = 3
	crush_def["max_tempo_control"] = 160
	var crush_action := AbilityRuntime.build_action_event(crush_state,"left","right","ABI606",crush_def)
	HammerAbiCombatService.dispatch(crush_engine,crush_action)
	var crush_attacks: Array[CombatEvent] = []
	for pending in crush_state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("hammer_abi_id",""))=="ABI606":
			crush_attacks.append(pending)
	_check(crush_attacks.size()==1,"ABI606:one_crush_attack")
	if not crush_attacks.is_empty():
		_check(is_equal_approx(float(crush_attacks[0].payload.get("raw_damage",-1.0)),220.0),"ABI606:custom_damage_multiplier_and_cap")
		_check(int(crush_attacks[0].payload.get("hammer_formal_tempo_delta",0))==-160,"ABI606:custom_tempo_per_charge_and_cap")
	_check(HammerAbiCombatService.charges(crusher,crush_state.round_number)==0,"ABI606:all_charges_consumed")


## EFF601, not ABI, owns passive generation numbers and active snapshots.
func _hammer_eff601_charge_generation() -> void:
	var ctx := _pair("hammer","axe")
	var engine: CombatEngine = ctx["engine"]
	var state: CombatState = ctx["state"]
	var hammer := state.get_combatant("left")
	engine.canonical_effects["EFF601"]["charges_per_ordinary_mh_hit"] = 7
	engine.canonical_effects["EFF601"]["charges_per_positive_damage_event_taken"] = 4
	var first := _attack(ctx,"left","right")
	_check(String(first.result.get("outcome",""))=="connected","EFF601:ordinary_mh_connected")
	_check(HammerAbiCombatService.charges(hammer,state.round_number)==7,"EFF601:initial_charges_from_catalog")
	var charge_record := _active_effect(hammer,"EFF601")
	_check(not charge_record.is_empty(),"EFF601:charge_record_created")
	if charge_record.is_empty():
		return
	var existing: Dictionary = Dictionary(charge_record.get("definition",{})).duplicate(true)
	existing["charges_per_ordinary_mh_hit"] = 2
	existing["charges_per_positive_damage_event_taken"] = 4
	charge_record["definition"] = existing
	var second := _attack(ctx,"left","right")
	_check(String(second.result.get("outcome",""))=="connected","EFF601:second_mh_connected")
	_check(HammerAbiCombatService.charges(hammer,state.round_number)==9,"EFF601:active_snapshot_controls_next_hit")
	var damage_event := state.create_event(CombatEvent.Kind.DAMAGE,"right","left",{
		"amount":1000.0,"damage_type":"physical","source":"charge_generation_test"
	})
	engine.resolve_event(damage_event)
	_check(int(damage_event.result.get("final_damage",0))>0,"EFF601:positive_incoming_damage_fixture")
	_check(HammerAbiCombatService.charges(hammer,state.round_number)==13,"EFF601:active_snapshot_controls_damage_taken")
	# Direct service callback exercises the critical branch deterministically,
	# without relying on the fixture's PAR-derived critical chance.
	existing["bonus_charges_on_ordinary_mh_crit"] = 3
	charge_record["definition"] = existing
	var critical_hit := state.create_event(CombatEvent.Kind.ATTACK,"left","right",{
		"is_weapon_attack":true,"weapon_index":0,"source_kind":"weapon"
	})
	critical_hit.set_result("critical",true)
	HammerAbiCombatService.on_connected_attack(engine,critical_hit,hammer)
	_check(HammerAbiCombatService.charges(hammer,state.round_number)==18,"EFF601:active_snapshot_controls_critical_charge_bonus")


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

## Test-only changed EFF definitions prove COMBAT never keeps base numbers.
func _sword_effect_strength_from_catalog() -> void:
	var ctx := _pair("sword","axe")
	var engine: CombatEngine = ctx["engine"]
	var state: CombatState = ctx["state"]
	engine.canonical_effects["EFF301"]["damage"] = 2.0
	engine.canonical_effects["EFF302"]["physical_damage_outgoing_direct_pct"] = -7.0
	engine.canonical_effects["EFF303"]["anti_dodge_direct_pct"] = -2.0
	engine.canonical_effects["EFF304"]["anti_crit_direct_pct"] = -3.0
	_effect(ctx,"left","right","EFF301",{"sword_stacks_to_apply":3,"sword_eff_level":20})
	var target := state.get_combatant("right")
	for record in target.active_effects:
		if String(record.get("effect_id","")) == "EFF301":
			_check(is_equal_approx(float(Dictionary(record.get("definition",{})).get("damage",-1.0)),20.0),"sword:bleed_strength_from_eff_and_level_cap")
	_effect(ctx,"left","right","EFF302",{"sword_eff_level":20})
	_effect(ctx,"left","right","EFF303",{"sword_eff_level":20})
	_effect(ctx,"left","right","EFF304",{"sword_eff_level":20})
	state.begin_round()
	_check(is_equal_approx(CombatModifierService.modifier(target,"physical_damage_outgoing_direct_pct",state.round_number),-21.0),"sword:cripple_strength_from_eff")
	_check(is_equal_approx(CombatModifierService.modifier(target,"anti_dodge_direct_pct",state.round_number),-30.0),"sword:slow_strength_from_eff_and_level_cap")
	_check(is_equal_approx(CombatModifierService.modifier(target,"anti_crit_direct_pct",state.round_number),-45.0),"sword:lost_strength_from_eff_and_level_cap")

## Real ABI paths must pass raw counts; EFF decides the % and its cap.
## Per-unit and max values are changed in fixture only, leaving balance intact.
func _dynamic_effects_from_catalog() -> void:
	var abilities := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)

	var dagger_ctx := _pair("dagger","axe")
	var dagger_state: CombatState = dagger_ctx["state"]
	var dagger_engine: CombatEngine = dagger_ctx["engine"]
	dagger_engine.canonical_effects["EFF404"]["contextual_modifier"]["per_unit"] = 7
	dagger_engine.canonical_effects["EFF404"]["contextual_modifier"]["maximum"] = 18
	_effect(dagger_ctx,"left","right","EFF401",{"sword_stacks_to_apply":3},true)
	var combo_action := AbilityRuntime.build_action_event(dagger_state,"left","right","ABI404",abilities["ABI404"])
	DaggerAbiCombatService.prepare_action(dagger_engine,combo_action)
	dagger_engine.resolve_pending_events()
	var dagger_buff := _active_effect(dagger_state.get_combatant("left"),"EFF404")
	_check(not dagger_buff.is_empty(),"dagger:contextual_dodge_applied")
	_check(is_equal_approx(float(Dictionary(dagger_buff.get("definition",{})).get("dodge_direct_pct",-1)),18.0),"dagger:contextual_dodge_per_stack_and_cap")

	var axe_ctx := _pair("axe","hammer")
	var axe_state: CombatState = axe_ctx["state"]
	var axe_engine: CombatEngine = axe_ctx["engine"]
	axe_engine.canonical_effects["EFF503"]["contextual_modifier"]["per_unit"] = 8
	axe_engine.canonical_effects["EFF503"]["contextual_modifier"]["maximum"] = 22
	_effect(axe_ctx,"left","left","EFF501",{"sword_stacks_to_apply":3},true)
	var stance_action := AbilityRuntime.build_action_event(axe_state,"left","left","ABI504",abilities["ABI504"])
	AxeAbiCombatService.dispatch(axe_engine,stance_action)
	axe_engine.resolve_pending_events()
	var stance := _active_effect(axe_state.get_combatant("left"),"EFF503")
	_check(is_equal_approx(float(Dictionary(stance.get("definition",{})).get("dodge_direct_pct",-1)),22.0),"axe:contextual_dodge_per_rage_and_cap")
	_check(int(Dictionary(stance.get("definition",{})).get("counterattack_cap",-1))==5,"axe:counter_cap_unmodified")

	var hammer_ctx := _pair("hammer","axe")
	var hammer_state: CombatState = hammer_ctx["state"]
	var hammer_engine: CombatEngine = hammer_ctx["engine"]
	hammer_engine.canonical_effects["EFF604"]["contextual_modifier"]["per_unit"] = 1.5
	hammer_engine.canonical_effects["EFF604"]["contextual_modifier"]["maximum"] = 24
	HammerAbiCombatService.gain_charges(hammer_engine,hammer_state.get_combatant("left"),80)
	var surge_action := AbilityRuntime.build_action_event(hammer_state,"left","left","ABI605",abilities["ABI605"])
	HammerAbiCombatService.dispatch(hammer_engine,surge_action)
	hammer_engine.resolve_pending_events()
	var surge := _active_effect(hammer_state.get_combatant("left"),"EFF604")
	var surge_definition: Dictionary = surge.get("definition",{})
	_check(is_equal_approx(float(surge_definition.get("physical_damage_outgoing_direct_pct",-1)),24.0),"hammer:contextual_physical_surge_and_cap")
	_check(is_equal_approx(float(surge_definition.get("magic_damage_direct_pct",-1)),24.0),"hammer:contextual_magic_surge_and_cap")
	_check(is_equal_approx(float(surge_definition.get("damage_lifesteal_pct",-1)),20.0),"hammer:lifesteal_unchanged")

	# Fracture's magnitude and bounds belong to EFF603 as well.
	hammer_engine.canonical_effects["EFF603"]["contextual_modifier"]["per_unit"] = 0.5
	hammer_engine.canonical_effects["EFF603"]["contextual_modifier"]["maximum"] = 40
	_effect(hammer_ctx,"left","right","EFF603",{"hammer_fracture_charges":100,"hammer_fracture_zone":"legs"},true)
	var fracture := _active_effect(hammer_state.get_combatant("right"),"EFF603")
	var fracture_definition: Dictionary = fracture.get("definition",{})
	_check(is_equal_approx(float(fracture_definition.get("armour_reduction_pct",-1)),40.0),"hammer:fracture_magnitude_from_eff_and_cap")
	_check(int(fracture_definition.get("duration_rounds",-1))==10,"hammer:fracture_duration_unchanged")
	_check(String(fracture_definition.get("armour_zone",""))=="legs","hammer:fracture_zone_unchanged")

	# A queued pre-migration event keeps its already-computed application value.
	var old_event := _effect(hammer_ctx,"left","left","EFF604",{"hammer_surge_pct":11.0},true)
	_check(bool(old_event.result.get("resolved",false)),"hammer:legacy_event_resolved")
	var old_surge := _active_effect(hammer_state.get_combatant("left"),"EFF604")
	_check(is_equal_approx(float(Dictionary(old_surge.get("definition",{})).get("physical_damage_outgoing_direct_pct",-1)),11.0),"hammer:legacy_event_kept_value")


func _active_effect(fighter: CombatantState, effect_id: String) -> Dictionary:
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}


func _dagger_breach_versus_hammer_armour() -> void:
	var ctx := _pair("dagger","hammer")
	var state: CombatState = ctx["state"]
	var hammer := state.get_combatant("right")
	hammer.armour["chest"] = {"piercing":150.0}
	var charge_definition: Dictionary = EffectCatalog.definition(EffectCatalog.load_json(),"EFF601").duplicate(true)
	# Change the test-only EFF value; Combat must never keep a hardcoded 0.25.
	charge_definition["armour_and_resistance_direct_pct_per_stack"] = 0.5
	hammer.active_effects.append({
		"effect_id":"EFF601","definition":charge_definition,"source_id":"right",
		"start_round":1,"remaining_rounds":1,"stacks":40
	})
	var base_hit := _attack(ctx,"left","right")
	_check(String(base_hit.result.get("outcome","")) == "connected","dagger:baseline_hit_connected")
	var base_reduction := float(base_hit.result.get("armour_reduction",-1.0))
	_check(is_equal_approx(float(base_hit.result.get("armour_before_dr_percent",-1.0)),float(base_hit.result.get("armour_raw_percent",-1.0))+20.0),"hammer:armour_reads_test_only_eff601_rate")
	for i in range(5):
		_effect(ctx,"left","right","EFF401")
	_check(_effects_count(hammer,"EFF401") == 1 and _effect_stacks(hammer,"EFF401") == 5,"dagger:five_breach_stacks_in_one_record")
	# Change only the active EFF snapshot, not CombatEngine: 5 stacks x 4 p.p.
	for record in hammer.active_effects:
		if String(record.get("effect_id","")) == "EFF401":
			var active_definition: Dictionary = record["definition"]
			active_definition["armour_reduction_pct_per_stack"] = 4.0
	state.begin_round()
	var breached_hit := _attack(ctx,"left","right")
	var breached_reduction := float(breached_hit.result.get("armour_reduction",-1.0))
	_check(String(breached_hit.result.get("outcome","")) == "connected","dagger:breached_hit_connected")
	_check(int(breached_hit.result.get("dagger_breach_stacks",-1)) == 5,"dagger:five_stacks_visible_to_damage")
	_check(is_equal_approx(float(breached_hit.result.get("armour_after_breach_percent",-1)),maxf(0.0,float(breached_hit.result.get("armour_raw_percent",-1))-20.0)),"dagger:armour_reads_test_only_eff401_rate")
	_check(base_reduction > 0.0 and breached_reduction < base_reduction,"dagger:breach_counters_hammer_charge_armour")
	_check(HammerAbiCombatService.charges(hammer,state.round_number) >= 40,"hammer:charges_survive_armour_breach")
	print("ABI_CROSS_WEAPON_CASE=CHECKED dagger_breach_vs_hammer_armour")

func _axe_rage_value_comes_from_eff() -> void:
	var ctx := _pair("axe","dagger")
	var state: CombatState = ctx["state"]
	var axe := state.get_combatant("left")
	var rage_definition: Dictionary = EffectCatalog.definition(EffectCatalog.load_json(),"EFF501").duplicate(true)
	rage_definition["block_crush_per_stack"] = 3.5
	axe.active_effects.append({
		"effect_id":"EFF501", "definition":rage_definition, "source_id":"left",
		"start_round":1, "remaining_rounds":5, "stacks":3
	})
	_check(is_equal_approx(CombatModifierService.block_crush_chance(axe,1),10.5),"axe:rage_reads_test_only_eff501_rate")

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
	# Changing only the EFF snapshot cap must change the number of counters.
	var limited := _pair("dagger","axe")
	var limited_state: CombatState = limited["state"]
	var limited_axe := limited_state.get_combatant("right")
	limited_axe.combat_stats["dodge_rating_percent"] = 100.0
	_effect(limited,"right","right","EFF503",{"axe_stance_dodge_pct":0.0},true)
	for record in limited_axe.active_effects:
		if String(record.get("effect_id","")) == "EFF503":
			var changed: Dictionary = Dictionary(record.get("definition",{})).duplicate(true)
			changed["counterattack_cap"] = 2
			record["definition"] = changed
	for i in range(4):
		_attack(limited,"left","right",i%2,{},1,1)
	var limited_counters := 0
	for event in limited_state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == "right" and bool(event.payload.get("is_counterattack_abi",false)):
			limited_counters += 1
	_check(limited_counters == 2,"axe:counter_limit_from_eff503_snapshot")

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
