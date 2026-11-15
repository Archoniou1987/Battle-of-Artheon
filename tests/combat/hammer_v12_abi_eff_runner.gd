extends SceneTree

## Approved 1H defensive and 2H concussion mace packs: runtime catalogue,
## real ITEM v1.2 / saved ABI / combat events / EFF / Tempo.
var failures: Array[String] = []
const KITS := {
	"HAMMER_DEF":["ABI601","ABI602","ABI603","ABI604"],
	"HAMMER_ATTACK":["ABI605","ABI606","ABI607","ABI608"],
	"2H_HAMMER":["ABI605","ABI606","ABI607","ABI608"]
}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("HAMMER_V12_FAIL=",label)

func _effect(fighter: CombatantState, id: String) -> Dictionary:
	for raw in fighter.active_effects:
		if String(Dictionary(raw).get("effect_id",""))==id:
			return raw
	return {}

func _attacks(session: ArenaCombatSession, abi: String) -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK and String(event.payload.get("hammer_abi_id",""))==abi:
			result.append(event)
	return result

func _make_session(archetype: String, seed: int) -> ArenaCombatSession:
	var hero := CharacterState.new("HAMMER_"+archetype,"Mace Tester",40)
	for id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[id]=90
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,40,"purple",seed,"MH" if archetype=="HAMMER_DEF" else "2H")
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	var expected: Array = KITS[archetype]
	_check(item.get("abilities",[])==expected,archetype+"_four_abilities")
	_check(Array(item.get("slot_usage",[])).size()==(0 if archetype=="HAMMER_DEF" else 2),archetype+"_hand_reservation")
	_check(hero.equip("main_hand",String(item.get("instance_id","")),repo),archetype+"_equipped")
	var saved := ItemRepository.from_dict(repo.to_dict())
	_check(saved.get_item(String(item.get("instance_id",""))).get("abilities",[])==expected,archetype+"_save_load")
	var session := ArenaCombatSession.new(hero,repo)
	var actor := session.fighter(true)
	var target := session.fighter(false)
	_check(actor!=null and target!=null,archetype+"_combatants")
	if actor == null or target == null:
		return null
	actor.max_hp=100000
	actor.hp=100000
	target.max_hp=100000
	target.hp=100000
	actor.combat_stats["hit_chance_rating_percent"]=100.0
	target.combat_stats["dodge_rating_percent"]=0.0
	target.combat_stats["shield_auto_block_rating_percent"]=0.0
	target.combat_loadout["can_auto_block"]=false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID]=[]
	var options := session.player_ability_options()
	for i in range(4):
		_check(i<options.size() and String(options[i].get("id",""))==String(expected[i]),archetype+"_slot_"+str(i))
	for id in expected:
		session.ability_scheduler.definitions[String(id)]["rolls"]={"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _cast(session: ArenaCombatSession, id: String) -> bool:
	session.fighter(true).action_points=8
	var result := session.play_round(["chest"],["head","arms"],id)
	_check(bool(result.get("ok",false)),id+"_round")
	return bool(result.get("ok",false))

func _give_concussion(session: ArenaCombatSession, stacks: int) -> void:
	session.fighter(false).active_effects.append({
		"effect_id":"EFF601",
		"definition":Dictionary(EffectCatalog.load_json()["EFF601"]).duplicate(true),
		"source_id":session.player_id,
		"start_round":0,"remaining_rounds":4,
		"stacks":stacks,"active_stacks":stacks
	})

func _run() -> void:
	var catalog := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	_check(HammerAbiCombatService.ABILITIES.size()==8,"eight_mace_ABI")
	for n in range(601,609):
		var id := "ABI%d" % n
		_check(catalog.has(id),id+"_catalog")
		if catalog.has(id):
			_check(AbilityRuntime.validate_definition(id,catalog[id]).is_empty(),id+"_valid")
			_check(Array(Dictionary(catalog[id]).get("base_damage_by_rank",[])).size()==10,id+"_ten_ranks")
	for id in ["EFF601","EFF602","EFF603","EFF604","EFF605","EFF606"]:
		_check(effects.has(id),id+"_catalog")
	_check(int(Dictionary(effects["EFF601"]).get("max_stacks",0))==3,"concussion_max3")
	_check(int(Dictionary(effects["EFF601"]).get("duration_rounds",0))==4,"concussion_duration4")
	_check(not Dictionary(effects["EFF601"]).has("charges_per_ordinary_mh_hit"),"retired_100_charge_mechanic")
	_check(Array(Dictionary(catalog["ABI608"]).get("bonus_damage_pct_by_concussion",[])).size()==4,"finisher_four_damage_steps")
	_check(Array(Dictionary(catalog["ABI608"]).get("tempo_control_by_concussion",[])).size()==4,"finisher_four_tempo_steps")
	var trigger := CombatState.new()
	trigger.begin_round()
	var block_event := trigger.create_event(CombatEvent.Kind.ATTACK,"enemy","player",{"round":1})
	block_event.set_result("outcome","manual_block")
	trigger.record_event(block_event)
	_check(AbilityRuntime.previous_round_trigger_met(trigger,"player","block",2),"counter_requires_previous_block")
	_check(not AbilityRuntime.previous_round_trigger_met(trigger,"player","block",1),"counter_not_first_round")

	var defence := _make_session("HAMMER_DEF",202611180)
	if defence != null:
		if _cast(defence,"ABI601"):
			_check(_attacks(defence,"ABI601").size()==1,"def_q_single_ability_hit")
			_check(_effect(defence.fighter(false),"EFF601").is_empty(),"def_no_concussion")
		if _cast(defence,"ABI602"):
			_check(not _effect(defence.fighter(true),"EFF602").is_empty(),"guard_buff_applied")
		if _cast(defence,"ABI604"):
			_check(_attacks(defence,"ABI604").size()==1,"def_finisher_one_hit")
			_check(not _effect(defence.fighter(true),"EFF605").is_empty(),"finisher_self_attack_buff")
			_check(not _effect(defence.fighter(false),"EFF604").is_empty(),"finisher_enemy_weakening")
	var attack := _make_session("HAMMER_ATTACK",202611181)
	if attack != null:
		if _cast(attack,"ABI605"):
			_check(_attacks(attack,"ABI605").size()==1,"attack_q_one_hit")
			# On-hit effects start next round; the snapshot is queued, not active yet.
			var concussion := _effect(attack.fighter(false),"EFF601")
			_check(not concussion.is_empty() and int(concussion.get("stacks",0))>=1,"attack_q_concussion")
			if not concussion.is_empty():
				_check(int(concussion.get("start_round",-1))==attack.state.round_number+1,"attack_q_concussion_next_round")
		if _cast(attack,"ABI606"):
			_check(not _effect(attack.fighter(false),"EFF606").is_empty(),"armour_debuff_on_hit")
	var execute := _make_session("HAMMER_ATTACK",202611182)
	if execute != null:
		_give_concussion(execute,3)
		if _cast(execute,"ABI608"):
			var hits := _attacks(execute,"ABI608")
			_check(hits.size()==1,"earthquake_one_target_hit")
			if not hits.is_empty():
				_check(int(hits[0].payload.get("hammer_concussion_snapshot",-1))==3,"earthquake_three_charges_snapshot")
				_check(is_equal_approx(float(hits[0].payload.get("hammer_tempo_control_on_hit",0)),75.0),"earthquake_75_tempo")
			_check(HammerAbiCombatService._concussion(execute.fighter(false),execute.player_id,execute.state.round_number)==0,"earthquake_consumes_concussion")
	var legacy := _make_session("2H_HAMMER",202611183)
	if legacy != null:
		# Arena may show other ability cards: inspect the weapon's first four slots.
		var choices := legacy.player_ability_options()
		var matches := choices.size()>=4
		for i in range(4):
			if i>=choices.size() or String(choices[i].get("id",""))!=String(KITS["2H_HAMMER"][i]):
				matches=false
		_check(matches,"old_2h_template_uses_offensive_kit")
	print("HAMMER_V12_ABI_EFF=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
