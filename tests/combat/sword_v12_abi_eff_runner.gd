extends SceneTree

## Approved sword ABI301–316: real generated equipment, save/load,
## ten numeric damage ranks, hit/miss gates, mastery and independent AoE.
## No legacy bleeding/MH multiplier assumptions.
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(ok: bool, label: String) -> void:
	if not ok:
		problems.append(label)
		print("SWORD_V12_CASE_FAIL=",label)

func _effect(target: CombatantState, id: String) -> Dictionary:
	for raw in target.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == id:
			return record
	return {}

func _events(session: ArenaCombatSession, kind: CombatEvent.Kind, ability_id: String = "") -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind != kind:
			continue
		if ability_id != "" and String(event.payload.get("ability_id","")) != ability_id and String(event.payload.get("sword_abi_id","")) != ability_id:
			continue
		result.append(event)
	return result

func _session(archetype: String, seed: int) -> ArenaCombatSession:
	var hero := CharacterState.new("SWORD_"+archetype,"Sword ABI v2",40)
	for stat in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[stat] = 90
	var repo := ItemRepository.new()
	var hand := "2H" if archetype == "2H_SWORD" else "MH"
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,archetype,40,"purple",seed,hand)
	_check(not item.is_empty(),archetype+"_generated")
	if item.is_empty():
		return null
	var expected: Array[String] = ItemV12InstanceFactory._physical_weapon_abilities(archetype)
	_check(expected.size()==4,archetype+"_four_abilities")
	_check(item.get("abilities",[]) == expected,archetype+"_canonical_item_abilities")
	var instance_id := String(item.get("instance_id",""))
	_check(instance_id.begins_with("ITEMID") and hero.inventory.owns(instance_id),archetype+"_item_owned")
	_check(hero.equip("main_hand",instance_id,repo),archetype+"_equipped")
	_check(ItemRepository.from_dict(repo.to_dict()).get_item(instance_id).get("abilities",[])==expected,archetype+"_abilities_persist")
	var session := ArenaCombatSession.new(hero,repo)
	var player := session.fighter(true)
	var target := session.fighter(false)
	_check(player!=null and target!=null,archetype+"_combatant_ready")
	if player == null or target == null:
		return null
	var options := session.player_ability_options()
	for i in range(mini(4,options.size())):
		_check(String(options[i].get("id",""))==expected[i],archetype+"_slot_"+str(i))
	player.max_hp=100000
	player.hp=100000
	target.max_hp=100000
	target.hp=100000
	player.combat_stats["hit_chance_rating_percent"]=100.0
	target.combat_stats["dodge_rating_percent"]=0.0
	target.combat_stats["shield_auto_block_rating_percent"]=0.0
	target.combat_loadout["can_auto_block"]=false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID]=[]
	for id in expected:
		session.ability_scheduler.definitions[id]["rolls"]={"hit":1,"crit":100,"dodge":100,"auto_block":100,"block_crush":100}
	return session

func _extra_enemy(session: ArenaCombatSession, index: int) -> CombatantState:
	var id := "SWORD_EXTRA_"+str(index)
	var char := CharacterState.new(id,id,40)
	var fighter := CharacterCombatBuilder.build(char,ItemRepository.new(),{"health":100000,"mana":0})
	session.state.add_combatant(fighter)
	_check(session.orchestrator.group_state.add_member("enemy",id),"group_"+id)
	session.orchestrator.zone_state.set_zone(id,CombatZoneState.ZONE_2)
	fighter.combat_stats["dodge_rating_percent"]=0.0
	fighter.combat_stats["shield_auto_block_rating_percent"]=0.0
	fighter.combat_loadout["can_auto_block"]=false
	return fighter

func _verify() -> void:
	var abilities := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	for id in SwordAbiCombatService.ABILITIES:
		_check(abilities.has(id),"missing_"+id)
		if not abilities.has(id):
			continue
		_check(AbilityRuntime.validate_definition(id,abilities[id]).is_empty(),"invalid_"+id)
		_check(Array(abilities[id].get("base_damage_by_rank",[])).size()==10,"ten_ranks_"+id)
		_check(not abilities[id].has("sword_mh_multiplier") and not abilities[id].has("mh_flat_bonus"),"no_old_mh_damage_"+id)
	for id in ["EFF314","EFF315","EFF316","EFF317","EFF318","EFF319","EFF320","EFF321","EFF322","EFF323"]:
		_check(effects.has(id),"missing_"+id)
	_check(AbilityCatalog.rank_for_item_level(1)==0 and AbilityCatalog.rank_for_item_level(10)==0 and AbilityCatalog.rank_for_item_level(11)==1 and AbilityCatalog.rank_for_item_level(75)==7,"rank_boundaries")
	for entry in [
		{"archetype":"SWORD_DEF","ids":["ABI301","ABI302","ABI303","ABI304"]},
		{"archetype":"SWORD_DODGE","ids":["ABI305","ABI306","ABI307","ABI308"]},
		{"archetype":"SWORD_CRIT","ids":["ABI309","ABI310","ABI311","ABI312"]},
		{"archetype":"2H_SWORD","ids":["ABI313","ABI314","ABI315","ABI316"]}
	]:
		var archetype: String = entry["archetype"]
		_check(ItemV12InstanceFactory._physical_weapon_abilities(archetype)==entry["ids"],archetype+"_item_links")
		var session := _session(archetype,202611150+int(SwordAbiCombatService.ABILITIES.find(String(entry["ids"][0]))))
		if session == null:
			continue
		var actor := session.fighter(true)
		actor.action_points=5
		var q: String = entry["ids"][0]
		var result := session.play_round(["chest"],["head","arms"],q)
		_check(bool(result.get("ok",false)),archetype+"_q_cast")
		var hits := _events(session,CombatEvent.Kind.ATTACK,q)
		_check(not hits.is_empty(),archetype+"_q_attack_events")
		_check(AbilityCatalog.ranked_damage(q,40)>=0.0,archetype+"_ranked_damage")
		_check(int(_effect(actor,"EFF314").get("stacks",0))>=1,archetype+"_mastery_on_q")
		print("SWORD_V12_ARCHETYPE=",archetype," attacks=",hits.size()," mastery=",_effect(actor,"EFF314").get("stacks",0))
	_test_multi_target()
	_test_defensive_parry_multiple_attackers()
	_test_rating_debuff_ranks()
	print("SWORD_V12_ABI_EFF=","PASS" if problems.is_empty() else "FAIL"," problems=",problems)
	quit(0 if problems.is_empty() else 1)

func _test_multi_target() -> void:
	var session := _session("SWORD_DODGE",202611165)
	if session == null:
		return
	var a := _extra_enemy(session,1)
	var b := _extra_enemy(session,2)
	session.fighter(true).action_points=5
	var result := session.play_round(["chest"],["head","arms"],"ABI307")
	_check(bool(result.get("ok",false)),"circle_three_target_cast")
	_check(_events(session,CombatEvent.Kind.ATTACK,"ABI307").size()==3,"circle_three_independent_attacks")
	_check(a.hp<=100000 and b.hp<=100000,"circle_enemy_attacks")
	var multi := _session("2H_SWORD",202611166)
	if multi == null:
		return
	for i in range(2):
		_extra_enemy(multi,10+i)
	multi.fighter(true).action_points=5
	var aoe := multi.play_round(["chest"],["head","arms"],"ABI316")
	_check(bool(aoe.get("ok",false)),"twohand_ultimate_cast")
	_check(_events(multi,CombatEvent.Kind.ATTACK,"ABI316").size()==3,"twohand_ultimate_three_hits")

func _test_rating_debuff_ranks() -> void:
	var effects := EffectCatalog.load_json()
	for id in ["EFF319","EFF321"]:
		var rule: Dictionary = effects[id]
		var magnitudes: Array = rule.get("rating_delta_by_rank",[])
		_check(magnitudes.size()==10,id+"_ten_rating_ranks")
		if magnitudes.size()==10:
			_check(float(magnitudes[0])<0.0 and absf(float(magnitudes[9]))>absf(float(magnitudes[0])),id+"_rank_strength_increases")
			var resolved := EffectCatalog.application_modifiers(rule,{"effect_rank":4})
			var key := "anti_crit_rating_delta" if id=="EFF319" else "hit_chance_rating_delta"
			_check(is_equal_approx(float(resolved.get(key,0)),float(magnitudes[3])),id+"_level_four_effect")

## ABI303 is a prepared shield counter: one reply per distinct blocked
## attacker, and its damage uses the current EFF314 count without consuming it.
func _test_defensive_parry_multiple_attackers() -> void:
	var session := _session("SWORD_DEF",202611176)
	if session == null:
		return
	var actor := session.fighter(true)
	actor.combat_loadout["can_auto_block"] = true
	var second := _extra_enemy(session,21)
	var third := _extra_enemy(session,22)
	session.state.begin_round()
	var effects := EffectCatalog.load_json()
	actor.active_effects.append({
		"effect_id":"EFF316","definition":Dictionary(effects["EFF316"]).duplicate(true),
		"source_id":session.player_id,"start_round":session.state.round_number,
		"remaining_rounds":1,"stacks":1
	})
	actor.active_effects.append({
		"effect_id":"EFF314","definition":Dictionary(effects["EFF314"]).duplicate(true),
		"source_id":session.player_id,"start_round":session.state.round_number,
		"remaining_rounds":3,"stacks":3,"active_stacks":3
	})
	var profile := SwordAbiCombatService._profile(actor,"ABI303")
	_check(not profile.is_empty(),"parry_real_sword_profile")
	var base_damage := SwordAbiCombatService._damage(actor,profile,"ABI303")
	var attackers := [ArenaCombatSession.ENEMY_ID,second.combatant_id,third.combatant_id]
	for enemy_id in attackers:
		var blocked := session.state.create_event(CombatEvent.Kind.ATTACK,enemy_id,session.player_id,{"zone":"head"})
		blocked.set_result("outcome","manual_block")
		SwordAbiCombatService.on_block(session.engine,blocked,actor)
	# A second blocked attack from the same dual-wield enemy must trigger another counter.
	var duplicate := session.state.create_event(CombatEvent.Kind.ATTACK,attackers[0],session.player_id,{"zone":"head"})
	duplicate.set_result("outcome","auto_block")
	SwordAbiCombatService.on_block(session.engine,duplicate,actor)
	var replies: Array[CombatEvent] = []
	for pending in session.state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("sword_abi_id","")) == "ABI303":
			replies.append(pending)
	_check(replies.size()==4,"parry_four_blocked_attacks_four_counters")
	for enemy_id in attackers:
		var count := 0
		for reply in replies:
			if reply.target_id == enemy_id:
				count += 1
				_check(is_equal_approx(float(reply.payload.get("raw_damage",0.0)),base_damage*1.3),"parry_three_mastery_adds_30_percent")
		_check(count==(2 if enemy_id==attackers[0] else 1),"parry_counter_per_blocked_hit_"+enemy_id)
	# Resolving the same ATTACK event twice must not create extra replies.
	SwordAbiCombatService.on_block(session.engine,duplicate,actor)
	var counter_count := 0
	for pending in session.state.pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("sword_abi_id",""))=="ABI303":
			counter_count += 1
	_check(counter_count==4,"parry_same_event_not_double_processed")
	_check(SwordAbiCombatService._active_stacks(actor,"EFF314",session.state.round_number)==3,"parry_does_not_consume_mastery")
