extends SceneTree

## Regression: physical dagger v1.2 equipment + actual ABI/EFF integration.
## Manual headless execution; no hidden CI trigger.
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, name: String) -> void:
	if not value:
		problems.append(name)
		print("DAGGER_V12_FAIL=",name)

func _active(target: CombatantState, effect_id: String) -> Dictionary:
	for raw in target.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}

func _count_abi_attacks(session: ArenaCombatSession, abi_id: String) -> int:
	var total := 0
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("dagger_abi_id","")) == abi_id:
			total += 1
	return total

func _make_session(archetype: String, seed_value: int, dual_wield: bool = false) -> ArenaCombatSession:
	var hero := CharacterState.new("DAGGER_"+archetype,"Dagger Test",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[par_id] = 90
	var repository := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repository,archetype,40,"purple",seed_value)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	_check(hero.equip("main_hand",String(item.get("instance_id","")),repository),archetype+"_equipped")
	if dual_wield:
		var secondary := ItemV12InstanceFactory.grant_weapon(hero,repository,archetype,40,"purple",seed_value+10000)
		_check(not secondary.is_empty(),archetype+"_offhand_generated")
		if secondary.is_empty():
			return null
		_check(hero.equip("off_hand",String(secondary.get("instance_id","")),repository),archetype+"_offhand_equipped")
		if String(hero.equipment.get_equipped_instance_id("off_hand")) != String(secondary.get("instance_id","")):
			return null
	var ability_sets := {
		"DAGGER_DEF":["ABI401","ABI402","ABI403","ABI404"],
		"DAGGER_ATTACK":["ABI401","ABI402","ABI405","ABI406"],
		"DAGGER_PEN":["ABI401","ABI402","ABI407","ABI408"]
	}
	var expected: Array = ability_sets.get(archetype,[])
	_check(item.get("abilities",[]) == expected,archetype+"_ability_loadout")
	var restored := ItemRepository.from_dict(repository.to_dict())
	_check(restored.get_item(String(item.get("instance_id",""))).get("abilities",[]) == expected,archetype+"_persisted")
	var session := ArenaCombatSession.new(hero,repository)
	var actor := session.fighter(true)
	var victim := session.fighter(false)
	if actor == null or victim == null:
		_check(false,archetype+"_fighters")
		return null
	actor.hp = 100000
	actor.max_hp = 100000
	victim.hp = 100000
	victim.max_hp = 100000
	actor.combat_stats["hit_chance_rating_percent"] = 100.0
	victim.combat_stats["hit_chance_rating_percent"] = 100.0
	victim.combat_stats["dodge_rating_percent"] = 0.0
	victim.combat_stats["shield_auto_block_rating_percent"] = 0.0
	victim.combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	var options := session.player_ability_options()
	for i in range(4):
		_check(i < options.size() and String(options[i].get("id","")) == String(expected[i]),archetype+"_slot_"+str(i))
	for id in expected:
		session.ability_scheduler.definitions[id]["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _cast(session: ArenaCombatSession, abi: String) -> bool:
	session.fighter(true).action_points = 8
	var outcome := session.play_round(["chest"],["head","arms"],abi)
	_check(bool(outcome.get("ok",false)),abi+"_cast")
	return bool(outcome.get("ok",false))

func _run() -> void:
	var catalog := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	for id in DaggerAbiCombatService.ABILITIES:
		_check(catalog.has(id),"catalog_"+id)
		if catalog.has(id):
			_check(AbilityRuntime.validate_definition(id,catalog[id]).is_empty(),"ability_valid_"+id)
	for id in ["EFF401","EFF402","EFF403","EFF404","EFF405"]:
		_check(effects.has(id),"effect_catalog_"+id)
	_check(String(catalog.get("ABI403",{}).get("trigger_previous_round","")) == "dodge","fan_requires_dodge")
	# Arena validates before begin_round; the planned round must be used
	# to read the immediately preceding successful dodge.
	var trigger_state := CombatState.new()
	trigger_state.begin_round()
	var dodge_event := trigger_state.create_event(CombatEvent.Kind.ATTACK,"enemy","player",{"round":1})
	dodge_event.set_result("outcome","dodge")
	trigger_state.record_event(dodge_event)
	_check(AbilityRuntime.previous_round_trigger_met(trigger_state,"player","dodge",2),"planned_round_dodge_true")
	_check(not AbilityRuntime.previous_round_trigger_met(trigger_state,"player","dodge",1),"wrong_round_not_eligible")

	# Regression: the Arena button must use the intended NEXT round,
	# not stale triggers from the round before the last finished round.
	var fan_preview := _make_session("DAGGER_DEF",202611074)
	if fan_preview != null:
		fan_preview.fighter(true).action_points = 8
		fan_preview.state.begin_round() # Round 1: player dodges.
		var previous_dodge := fan_preview.state.create_event(CombatEvent.Kind.ATTACK,ArenaCombatSession.ENEMY_ID,fan_preview.player_id)
		previous_dodge.set_result("outcome","dodge")
		fan_preview.state.record_event(previous_dodge)
		var options_after_dodge := fan_preview.player_ability_options()
		_check(options_after_dodge.size() > 2 and bool(Dictionary(options_after_dodge[2]).get("available",false)),"fan_available_after_last_round_dodge")
		fan_preview.state.begin_round() # Round 2: enemy connects; no dodge.
		var previous_hit := fan_preview.state.create_event(CombatEvent.Kind.ATTACK,ArenaCombatSession.ENEMY_ID,fan_preview.player_id)
		previous_hit.set_result("outcome","connected")
		fan_preview.state.record_event(previous_hit)
		var options_after_hit := fan_preview.player_ability_options()
		_check(options_after_hit.size() > 2 and not bool(Dictionary(options_after_hit[2]).get("available",false)),"fan_unavailable_after_stale_dodge")
		_check(not AbilityRuntime.previous_round_trigger_met(fan_preview.state,fan_preview.player_id,"dodge",3),"fan_cast_guard_no_stale_dodge")


	_check(int(catalog.get("ABI408",{}).get("ap_cost",-1)) == 5,"absolute_cost_five")

	var defensive := _make_session("DAGGER_DEF",202611071)
	if defensive != null:
		if _cast(defensive,"ABI401"):
			_check(_count_abi_attacks(defensive,"ABI401") == 1,"def_quick_extra_attack")
			_check(int(_active(defensive.fighter(false),"EFF401").get("stacks",0)) >= 1,"def_breach_on_hit")
		if _cast(defensive,"ABI404"):
			_check(not _active(defensive.fighter(true),"EFF404").is_empty(),"def_combo_dodge_buff")
			_check(_count_abi_attacks(defensive,"ABI404") == 1,"def_combo_mh_without_oh")
		_check(_cast(defensive,"ABI402"),"def_poison_coating_cast")
		_check(not _active(defensive.fighter(false),"EFF403").is_empty(),"def_autoattack_poison")

	var attacking := _make_session("DAGGER_ATTACK",202611072)
	if attacking != null:
		if _cast(attacking,"ABI402"):
			_check(not _active(attacking.fighter(false),"EFF403").is_empty(),"attack_coating_poison")
		if _cast(attacking,"ABI405"):
			_check(not _active(attacking.fighter(false),"EFF405").is_empty(),"attack_pre_weakening")
			_check(_count_abi_attacks(attacking,"ABI405") == 1,"attack_heavy_no_oh")
		if _cast(attacking,"ABI406"):
			_check(_count_abi_attacks(attacking,"ABI406") >= 1,"attack_flurry_from_poison_stacks")

	var penetration := _make_session("DAGGER_PEN",202611073)
	if penetration != null:
		if _cast(penetration,"ABI401"):
			_check(int(_active(penetration.fighter(false),"EFF401").get("stacks",0)) >= 1,"pen_breach_first")
		if _cast(penetration,"ABI407"):
			_check(int(_active(penetration.fighter(false),"EFF401").get("stacks",0)) >= 1,"pen_deep_preserves_existing_breach_without_poison")
		if _cast(penetration,"ABI408"):
			_check(_active(penetration.fighter(false),"EFF401").is_empty(),"pen_absolute_consumes_after_hit")
			_check(_count_abi_attacks(penetration,"ABI408") == 1,"pen_absolute_mh_only")


	# Preparation effects are active immediately; ordinary on-hit EFF would activate next round.
	# Burst skills consume poison on cast, but DEF_COMBO must preserve breach.
	# The cast snapshot still determines damage and the number of strikes.
	var consume_def := _make_session("DAGGER_DEF",202611075)
	if consume_def != null:
		consume_def.state.begin_round()
		var def_target := consume_def.fighter(false)
		var poison_event := consume_def.state.create_event(CombatEvent.Kind.EFFECT,consume_def.player_id,ArenaCombatSession.ENEMY_ID,{"effect_id":"EFF403","base_chance":100.0,"effect_roll":1,"preparation_effect":true})
		consume_def.engine.resolve_event(poison_event)
		var breach_event := consume_def.state.create_event(CombatEvent.Kind.EFFECT,consume_def.player_id,ArenaCombatSession.ENEMY_ID,{"effect_id":"EFF401","base_chance":100.0,"effect_roll":1,"preparation_effect":true})
		consume_def.engine.resolve_event(breach_event)
		_check(not _active(def_target,"EFF403").is_empty(),"def_consume_poison_setup")
		_check(not _active(def_target,"EFF401").is_empty(),"def_preserve_breach_setup")
		var def_cast := consume_def.state.create_event(CombatEvent.Kind.ACTION,consume_def.player_id,ArenaCombatSession.ENEMY_ID,{"source_kind":"ability","ability_id":"ABI404","zone":"chest"})
		DaggerAbiCombatService.dispatch(consume_def.engine,def_cast)
		_check(int(def_cast.result.get("poison_stacks_consumed",0))==1,"def_consumed_count")
		_check(_active(def_target,"EFF403").is_empty(),"def_consumes_poison_at_cast")
		_check(not _active(def_target,"EFF401").is_empty(),"def_preserves_breach")
		consume_def.engine.resolve_pending_events()
		_check(_active(def_target,"EFF403").is_empty(),"def_poison_not_restored_by_abi_hits")

	var consume_attack := _make_session("DAGGER_ATTACK",202611076,true)
	if consume_attack != null:
		consume_attack.state.begin_round()
		var attack_target := consume_attack.fighter(false)
		for i in range(4):
			var add_poison := consume_attack.state.create_event(CombatEvent.Kind.EFFECT,consume_attack.player_id,ArenaCombatSession.ENEMY_ID,{"effect_id":"EFF403","base_chance":100.0,"effect_roll":1,"preparation_effect":true})
			consume_attack.engine.resolve_event(add_poison)
		_check(int(_active(attack_target,"EFF403").get("stacks",0))==4,"flurry_consume_poison_setup")
		var poison_record := _active(attack_target,"EFF403")
		var original_poison_definition: Dictionary = poison_record.get("definition",{})
		var capped_poison_definition: Dictionary = original_poison_definition.duplicate(true)
		capped_poison_definition["max_stacks"] = 2
		poison_record["definition"] = capped_poison_definition
		_check(DaggerAbiCombatService._active_stacks(attack_target,"EFF403",consume_attack.state.round_number)==2,"poison_stack_cap_from_eff_snapshot")
		poison_record["definition"] = original_poison_definition
		var flurry_cast := consume_attack.state.create_event(CombatEvent.Kind.ACTION,consume_attack.player_id,ArenaCombatSession.ENEMY_ID,{"source_kind":"ability","ability_id":"ABI406","zone":"chest"})
		DaggerAbiCombatService.dispatch(consume_attack.engine,flurry_cast)
		_check(int(flurry_cast.result.get("poison_stacks_consumed",0))==4,"flurry_consumed_count")
		_check(Array(flurry_cast.result.get("child_event_ids",[])).size()==4,"flurry_snapshot_four_strikes")
		_check(_active(attack_target,"EFF403").is_empty(),"flurry_consumes_poison_at_cast")
		consume_attack.engine.resolve_pending_events()
		_check(_active(attack_target,"EFF403").is_empty(),"flurry_poison_not_restored_by_abi_hits")


	# PEN_DEEP converts consumed poison into breach ONLY on connected hits.
	# Test odd rounding, maximum five stacks and a failed strike.
	for poison_count in [1, 5, 10]:
		var convert_session := _make_session("DAGGER_PEN",202611080+poison_count)
		if convert_session == null:
			continue
		convert_session.state.begin_round()
		var convert_target := convert_session.fighter(false)
		for index in range(poison_count):
			var poison_add := convert_session.state.create_event(CombatEvent.Kind.EFFECT,convert_session.player_id,ArenaCombatSession.ENEMY_ID,{"effect_id":"EFF403","base_chance":100.0,"effect_roll":1,"preparation_effect":true})
			convert_session.engine.resolve_event(poison_add)
		_check(int(_active(convert_target,"EFF403").get("stacks",0))==poison_count,"pen_conversion_poison_setup_"+str(poison_count))
		var convert_action := convert_session.state.create_event(CombatEvent.Kind.ACTION,convert_session.player_id,ArenaCombatSession.ENEMY_ID,{"source_kind":"ability","ability_id":"ABI407","zone":"chest","rolls":{"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}})
		DaggerAbiCombatService.dispatch(convert_session.engine,convert_action)
		var expected_breach := mini(5,poison_count / 2)
		_check(int(convert_action.result.get("poison_stacks_consumed",-1))==poison_count,"pen_conversion_consumed_"+str(poison_count))
		_check(_active(convert_target,"EFF403").is_empty(),"pen_conversion_poison_removed_"+str(poison_count))
		_check(int(convert_action.result.get("breach_stacks_to_apply",-1))==expected_breach,"pen_conversion_expected_"+str(poison_count))
		convert_session.engine.resolve_pending_events()
		_check(int(_active(convert_target,"EFF401").get("stacks",0))==expected_breach,"pen_conversion_breach_after_hit_"+str(poison_count))

	var missed_conversion := _make_session("DAGGER_PEN",202611099)
	if missed_conversion != null:
		missed_conversion.state.begin_round()
		var missed_target := missed_conversion.fighter(false)
		for index in range(4):
			var poison_miss := missed_conversion.state.create_event(CombatEvent.Kind.EFFECT,missed_conversion.player_id,ArenaCombatSession.ENEMY_ID,{"effect_id":"EFF403","base_chance":100.0,"effect_roll":1,"preparation_effect":true})
			missed_conversion.engine.resolve_event(poison_miss)
		# Force a true miss regardless of initial hit bonuses.
		missed_conversion.fighter(true).combat_stats["hit_chance_rating_percent"] = -1000.0
		var miss_action := missed_conversion.state.create_event(CombatEvent.Kind.ACTION,missed_conversion.player_id,ArenaCombatSession.ENEMY_ID,{"source_kind":"ability","ability_id":"ABI407","zone":"chest","rolls":{"hit":100,"dodge":100,"auto_block":100,"crit":100}})
		DaggerAbiCombatService.dispatch(missed_conversion.engine,miss_action)
		_check(_active(missed_target,"EFF403").is_empty(),"pen_miss_consumes_poison")
		missed_conversion.engine.resolve_pending_events()
		_check(_active(missed_target,"EFF401").is_empty(),"pen_miss_no_breach")

	print("DAGGER_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)
