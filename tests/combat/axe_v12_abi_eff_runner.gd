extends SceneTree

## Physical axe v1.2: one MH ABI pack, rage cap, conditional casts and
## combat damage/effect events. Run manually via Combat Integration Gate.
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		problems.append(label)
		print("AXE_V12_FAIL=",label)

func _effect(fighter: CombatantState, effect_id: String) -> Dictionary:
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}

func _attacks(session: ArenaCombatSession, abi_id: String) -> Array[CombatEvent]:
	var found: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("axe_abi_id","")) == abi_id:
			found.append(event)
	return found

func _make_session(archetype: String, seed_value: int) -> ArenaCombatSession:
	var hero := CharacterState.new("AXE_"+archetype,"Axe Test",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[par_id] = 90
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,40,"purple",seed_value)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	_check(hero.equip("main_hand",String(item.get("instance_id","")),repo),archetype+"_equipped")
	var ability_sets := {
		"AXE_DEF":["ABI501","ABI502","ABI503","ABI504"],
		"AXE_ATTACK":["ABI501","ABI502","ABI505","ABI506"],
		"AXE_SHIELD":["ABI501","ABI502","ABI507","ABI508"]
	}
	var expected: Array = ability_sets.get(archetype,[])
	_check(item.get("abilities",[]) == expected,archetype+"_loadout")
	var session := ArenaCombatSession.new(hero,repo)
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
	actor.combat_stats["crit_chance_rating_percent"] = 100.0
	victim.combat_stats["anti_crit_rating_percent"] = 0.0
	victim.combat_stats["dodge_rating_percent"] = 0.0
	victim.combat_stats["shield_auto_block_rating_percent"] = 0.0
	victim.combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	var options := session.player_ability_options()
	for i in range(4):
		_check(i < options.size() and String(options[i].get("id",""))==String(expected[i]),archetype+"_abi_slot_"+str(i))
	for id in expected:
		session.ability_scheduler.definitions[id]["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":1}
	return session

func _cast(session: ArenaCombatSession, ability_id: String) -> bool:
	session.fighter(true).action_points = 8
	var result := session.play_round(["chest"],["head","arms"],ability_id)
	_check(bool(result.get("ok",false)),ability_id+"_cast")
	return bool(result.get("ok",false))

func _give_rage(fighter: CombatantState, stacks: int) -> void:
	for raw in fighter.active_effects.duplicate():
		if String(raw.get("effect_id","")) == "EFF501":
			fighter.active_effects.erase(raw)
	fighter.active_effects.append({
		"effect_id":"EFF501","definition":EffectCatalog.load_json()["EFF501"],
		"source_id":fighter.combatant_id,"start_round":0,
		"remaining_rounds":5,"stacks":stacks,"active_stacks":stacks
	})

func _run() -> void:
	var catalog := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	for id in AxeAbiCombatService.ABILITIES:
		_check(catalog.has(id),"catalog_"+id)
		if catalog.has(id):
			_check(AbilityRuntime.validate_definition(id,catalog[id]).is_empty(),"definition_"+id)
	for id in ["EFF501","EFF502","EFF503","EFF504","EFF505"]:
		_check(effects.has(id),"effect_catalog_"+id)
	_check(String(catalog.get("ABI502",{}).get("trigger_previous_round",""))=="crit_or_block_crush","cut_previous_crit_or_crush")
	_check(int(catalog.get("ABI507",{}).get("cooldown_rounds",-1))==5,"crusher_cd5")

	var defence := _make_session("AXE_DEF",202611081)
	if defence != null:
		if _cast(defence,"ABI501"):
			_check(int(_effect(defence.fighter(true),"EFF501").get("stacks",0))==1,"def_one_rage")
			_check(_attacks(defence,"ABI501").size()==1,"rage_ordinary_mh_not_extra")
		_check(_cast(defence,"ABI503"),"def_sweep")
		_check(not _effect(defence.fighter(false),"EFF502").is_empty(),"def_sweep_debuff")
		_give_rage(defence.fighter(true),5)
		_check(_cast(defence,"ABI504"),"def_stance")
		var saw_stance := false
		for event in defence.state.event_log:
			if event.kind==CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id",""))=="EFF503" and bool(event.result.get("resolved",false)):
				saw_stance = true
		_check(saw_stance,"def_stance_prepared")

	var attack := _make_session("AXE_ATTACK",202611082)
	if attack != null:
		_check(not AxeAbiCombatService.can_cast(attack.state,attack.player_id,ArenaCombatSession.ENEMY_ID,"ABI506"),"execute_rejects_full_hp")
		_give_rage(attack.fighter(true),5)
		if _cast(attack,"ABI505"):
			var saw_breaker := false
			for event in attack.state.event_log:
				if event.kind==CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id",""))=="EFF504":
					saw_breaker = true
			_check(saw_breaker,"attack_breaker_early_effect")
		attack.fighter(false).hp = 19999
		_check(AxeAbiCombatService.can_cast(attack.state,attack.player_id,ArenaCombatSession.ENEMY_ID,"ABI506"),"execute_eligible")
		if _cast(attack,"ABI506"):
			_check(_attacks(attack,"ABI506").size()==1,"execute_one_attack")
			_check(_effect(attack.fighter(true),"EFF501").is_empty(),"execute_consumes_rage_on_hit")

	var shield := _make_session("AXE_SHIELD",202611083)
	if shield != null:
		_check(not AxeAbiCombatService.can_cast(shield.state,shield.player_id,ArenaCombatSession.ENEMY_ID,"ABI507"),"crusher_requires_rage")
		_give_rage(shield.fighter(true),5)
		_check(_cast(shield,"ABI507"),"shield_crusher")
		_check(_effect(shield.fighter(true),"EFF501").is_empty(),"crusher_spends_rage")
		_check(not _effect(shield.fighter(true),"EFF505").is_empty(),"crusher_twenty_round_buff")
		_give_rage(shield.fighter(true),5)
		if _cast(shield,"ABI508"):
			_check(_attacks(shield,"ABI508").size()==1,"shieldbreaker_single_target")
			_check(_effect(shield.fighter(true),"EFF501").is_empty(),"shieldbreaker_spends_rage")

	print("AXE_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)
