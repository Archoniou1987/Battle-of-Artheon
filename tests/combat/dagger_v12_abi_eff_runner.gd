extends SceneTree

## Current physical dagger / 2H spear ABI v2 canonical loadout and combat smoke.
## The previous dagger ABI implementations are retired; only canonical ABI401-412 are active.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ABI_V2_FAIL=",label)

func _active(target: CombatantState, effect_id: String) -> Dictionary:
	for raw in target.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}

func _session(archetype: String, seed_value: int) -> ArenaCombatSession:
	var hero := CharacterState.new("V2_"+archetype,"Archetype Test",40)
	for id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[id] = 90
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,40,"purple",seed_value)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	_check(hero.equip("main_hand",String(item["instance_id"]),repo),archetype+"_equipped")
	var sets := {
		"DAGGER_ATTACK": ["ABI401","ABI402","ABI403","ABI404"],
		"DAGGER_DEF": ["ABI405","ABI406","ABI407","ABI408"],
		"DAGGER_PEN": ["ABI409","ABI410","ABI411","ABI412"],
		"2H_SPEAR": ["ABI701","ABI702","ABI703","ABI704"]
	}
	var expected: Array = sets[archetype]
	_check(item.get("abilities",[]) == expected,archetype+"_canonical_ABI_order")
	_check(ItemRepository.from_dict(repo.to_dict()).get_item(String(item["instance_id"])).get("abilities",[]) == expected,archetype+"_persistent_ids")
	var session := ArenaCombatSession.new(hero,repo)
	var attacker := session.fighter(true)
	var target := session.fighter(false)
	if attacker == null or target == null:
		_check(false,archetype+"_combatants")
		return null
	attacker.hp = 100000
	attacker.max_hp = 100000
	target.hp = 100000
	target.max_hp = 100000
	attacker.combat_stats["hit_chance_rating_percent"] = 100.0
	target.combat_stats["dodge_rating_percent"] = 0.0
	target.combat_stats["shield_auto_block_rating_percent"] = 0.0
	target.combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	var options := session.player_ability_options()
	for index in range(4):
		_check(index < options.size() and String(Dictionary(options[index]).get("id","")) == String(expected[index]),archetype+"_slot_"+str(index))
	for id in expected:
		session.ability_scheduler.definitions[id]["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _cast(session: ArenaCombatSession, id: String) -> bool:
	session.fighter(true).action_points = 8
	var result := session.play_round(["chest"],["head","arms"],id)
	_check(bool(result.get("ok",false)),id+"_cast")
	return bool(result.get("ok",false))

func _count(session: ArenaCombatSession, id: String) -> int:
	var n := 0
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("combo_abi_id","")) == id:
			n += 1
	return n

func _apply(session: ArenaCombatSession, id: String, to_self: bool = false) -> void:
	var target_id := session.player_id if to_self else ArenaCombatSession.ENEMY_ID
	var event := session.state.create_event(CombatEvent.Kind.EFFECT,session.player_id,target_id,{"effect_id":id,"base_chance":100.0,"effect_roll":1,"preparation_effect":true})
	session.engine.resolve_event(event)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	for id in WeaponComboAbiCombatService.ABILITIES:
		_check(catalog.has(id),"catalog_"+id)
		if catalog.has(id):
			_check(AbilityRuntime.validate_definition(id,catalog[id]).is_empty(),"valid_"+id)
	for id in ["EFF406","EFF407","EFF408","EFF409","EFF410","EFF411","EFF412","EFF413"]:
		_check(effects.has(id),"effect_"+id)
	var attack := _session("DAGGER_ATTACK",202611131)
	if attack != null:
		if _cast(attack,"ABI401"):
			_check(_count(attack,"ABI401")==1,"attack_quick_one_hit")
			_check(not _active(attack.fighter(true),"EFF406").is_empty(),"attack_accuracy_on_hit")
		if _cast(attack,"ABI402"):
			_check(not _active(attack.fighter(true),"EFF407").is_empty(),"attack_focus_buff")
		if _cast(attack,"ABI403"):
			_check(_count(attack,"ABI403")==3,"attack_flurry_three_hits")
		if _cast(attack,"ABI404"):
			_check(_count(attack,"ABI404")==1,"attack_finisher")
	var defensive := _session("DAGGER_DEF",202611132)
	if defensive != null:
		if _cast(defensive,"ABI406"):
			_check(not _active(defensive.fighter(true),"EFF409").is_empty(),"def_dodge_buff")
		if _cast(defensive,"ABI405"):
			_check(_count(defensive,"ABI405")==1,"def_lunge")
		if _cast(defensive,"ABI407"):
			_check(_count(defensive,"ABI407")>=1,"def_fan")
		if _cast(defensive,"ABI408"):
			_check(not _active(defensive.fighter(true),"EFF410").is_empty(),"def_combo_buff")
	var pen := _session("DAGGER_PEN",202611133)
	if pen != null:
		if _cast(pen,"ABI409"):
			_check(not _active(pen.fighter(false),"EFF401").is_empty(),"pen_breach_on_hit")
		_apply(pen,"EFF401")
		if _cast(pen,"ABI410"):
			_check(int(_active(pen.fighter(false),"EFF401").get("stacks",0))>=3,"pen_weakspot_adds_stacks")
		if _cast(pen,"ABI411"):
			_check(not _active(pen.fighter(false),"EFF411").is_empty(),"pen_damage_weakening")
		if _cast(pen,"ABI412"):
			_check(_active(pen.fighter(false),"EFF401").is_empty(),"pen_finish_consumes_breach")
	var spear := _session("2H_SPEAR",202611134)
	if spear != null:
		_check(String(spear.fighter(true).combat_stats.weapon_profiles[0].weapon_class)=="spear","spear_combat_class")
		if _cast(spear,"ABI702"):
			_check(not _active(spear.fighter(false),"EFF412").is_empty(),"spear_slow")
		if _cast(spear,"ABI704"):
			_check(not _active(spear.fighter(false),"EFF413").is_empty(),"spear_armour_fracture")
		if _cast(spear,"ABI703"):
			_check(_active(spear.fighter(false),"EFF412").is_empty(),"spear_impale_consumes_slow")
		_check(_cast(spear,"ABI701"),"spear_thrust")
	print("DAGGER_V12_ABI_EFF=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
