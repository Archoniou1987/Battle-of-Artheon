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

func _make_session(archetype: String, seed_value: int) -> ArenaCombatSession:
	var hero := CharacterState.new("DAGGER_"+archetype,"Dagger Test",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[par_id] = 90
	var repository := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repository,archetype,40,"purple",seed_value)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	_check(hero.equip("main_hand",String(item.get("instance_id","")),repository),archetype+"_equipped")
	var expected: Array = {
		"DAGGER_DEF":["ABI401","ABI402","ABI403","ABI404"],
		"DAGGER_ATTACK":["ABI401","ABI402","ABI405","ABI406"],
		"DAGGER_PEN":["ABI401","ABI402","ABI407","ABI408"]
	}.get(archetype,[])
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
			_check(int(_active(penetration.fighter(false),"EFF401").get("stacks",0)) >= 2,"pen_deep_adds_stack")
		if _cast(penetration,"ABI408"):
			_check(_active(penetration.fighter(false),"EFF401").is_empty(),"pen_absolute_consumes_after_hit")
			_check(_count_abi_attacks(penetration,"ABI408") == 1,"pen_absolute_mh_only")

	print("DAGGER_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)
