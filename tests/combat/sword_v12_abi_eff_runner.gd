extends SceneTree

## Full chain: v1.2 roll -> real ITEMID -> bag -> equip -> 4 ABI ->
## canonical ArenaCombatSession -> physical hit -> EFF -> round ticks.
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		problems.append(msg)
		print("SWORD_V12_CASE_FAIL=",msg)

func _eff(target: CombatantState, effect_id: String) -> Dictionary:
	for record in target.active_effects:
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}

func _events(session: ArenaCombatSession, kind: CombatEvent.Kind, ability_id: String = "", effect_id: String = "") -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind != kind:
			continue
		if not ability_id.is_empty() and String(event.payload.get("ability_id","")) != ability_id and String(event.payload.get("sword_abi_id","")) != ability_id:
			continue
		if not effect_id.is_empty() and String(event.payload.get("effect_id","")) != effect_id:
			continue
		result.append(event)
	return result

func _verify() -> void:
	var catalog := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var effects := EffectCatalog.load_json()
	for ability_id in SwordAbiCombatService.ABILITIES:
		_check(catalog.has(ability_id),"missing_ability_"+ability_id)
		if catalog.has(ability_id):
			_check(AbilityRuntime.validate_definition(ability_id,catalog[ability_id]).is_empty(),"invalid_ability_"+ability_id)
	for effect_id in ["EFF301","EFF302","EFF303","EFF304"]:
		_check(effects.has(effect_id),"missing_effect_"+effect_id)
	for entry in [
		{"id":"SWORD_DEF","seed":202611041,"abis":["ABI301","ABI302","ABI303","ABI306"],"third":"EFF302","fourth":"ABI306"},
		{"id":"SWORD_DODGE","seed":202611042,"abis":["ABI301","ABI302","ABI304","ABI307"],"third":"EFF303","fourth":"ABI307"},
		{"id":"SWORD_CRIT","seed":202611043,"abis":["ABI301","ABI302","ABI305","ABI308"],"third":"EFF304","fourth":"ABI308"}
	]:
		var archetype := String(entry["id"])
		var hero := CharacterState.new("SWORD_"+archetype,"Sword Test",40)
		# High enough to equip Lv40 by its real attribute requirements.
		for key in ["PAR001","PAR002","PAR003"]:
			hero.progression.base_stats[key] = 50
		var repo := ItemRepository.new()
		var item := ItemV12InstanceFactory.grant_sword(hero,repo,archetype,40,"purple",int(entry["seed"]))
		_check(not item.is_empty(),archetype+"_generated")
		if item.is_empty():
			continue
		var id := String(item["instance_id"])
		_check(id.begins_with("ITEMID") and hero.inventory.owns(id),archetype+"_real_instance")
		_check(item.get("abilities",[]) == entry["abis"],archetype+"_four_abilities")
		_check(hero.equip("main_hand",id,repo),archetype+"_equipped")
		var restored := ItemRepository.from_dict(repo.to_dict())
		_check(restored.get_item(id).get("abilities",[]) == entry["abis"],archetype+"_abi_persist")
		var session := ArenaCombatSession.new(hero,repo)
		var player := session.fighter(true)
		var target := session.fighter(false)
		_check(player != null and target != null,archetype+"_fighter_built")
		if player == null or target == null:
			continue
		var options := session.player_ability_options()
		for index in range(4):
			_check(String(options[index].get("id","")) == String(entry["abis"][index]),archetype+"_slot_"+str(index))
		target.max_hp = 100000
		target.hp = 100000
		player.max_hp = 100000
		player.hp = 100000
		# Remove unrelated enemy defence randomness from deterministic ABI tests.
		player.combat_stats["hit_chance_rating_percent"] = 100.0
		target.combat_stats["dodge_rating_percent"] = 0.0
		target.combat_stats["shield_auto_block_rating_percent"] = 0.0
		target.combat_loadout["can_auto_block"] = false
		session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
		player.action_points = 5
		for ability_id in entry["abis"]:
			var authored: Dictionary = session.ability_scheduler.definitions[String(ability_id)]
			authored["rolls"] = {"hit":1,"crit":100,"dodge":100,"auto_block":100,"block_crush":100}
		# Round 1: ABI301 must NOT add an extra ATTACK event.
		var first := session.play_round(["chest"],["head","arms"],"ABI301")
		_check(bool(first.get("ok",false)),archetype+"_abi01_round")
		if not bool(first.get("ok",false)):
			continue
		_check(_events(session,CombatEvent.Kind.ATTACK).filter(func(ev):return ev.source_id == player.combatant_id).size() == 1,archetype+"_abi01_no_extra_mh")
		_check(int(_eff(target,"EFF301").get("stacks",0)) == 1,archetype+"_first_bleed")
		_check(player.action_points >= 5,archetype+"_abi01_gain_on_hit_capped")
		# Round 2: separately delivered ABI03 uses existing bleed stack
		# without consuming it and snapshots its strength for two rounds.
		player.action_points = 5
		var third_abi := String(entry["abis"][2])
		# Effect level is NOT character level. A Lv40 item may carry Lv5 EFF.
		if archetype != "SWORD_DEF":
			session.ability_scheduler.definitions[third_abi]["sword_eff_level"] = 5
		var second := session.play_round(["chest"],["head","arms"],third_abi)
		_check(bool(second.get("ok",false)),archetype+"_abi03_round")
		var debuff := _eff(target,String(entry["third"]))
		_check(not debuff.is_empty(),archetype+"_debuff_applied")
		if not debuff.is_empty():
			var effect_definition: Dictionary = debuff.get("definition",{})
			var key := "physical_damage_outgoing_direct_pct" if archetype=="SWORD_DEF" else ("anti_dodge_direct_pct" if archetype=="SWORD_DODGE" else "anti_crit_direct_pct")
			var expected := -5.0
			_check(float(effect_definition.get(key,0.0)) == expected,archetype+"_debuff_snapshot")
		_check(int(_eff(target,"EFF301").get("stacks",0)) == 1,archetype+"_bleed_not_consumed")
		var effect_key := "physical_damage_outgoing_direct_pct" if archetype=="SWORD_DEF" else ("anti_dodge_direct_pct" if archetype=="SWORD_DODGE" else "anti_crit_direct_pct")
		_check(CombatModifierService.modifier(target,effect_key,3) == -5.0,archetype+"_debuff_runtime_modifier")
		# Round 3: all-AP ability must operate on the same target and effect.
		player.action_points = 5
		if archetype == "SWORD_CRIT":
			session.ability_scheduler.definitions["ABI308"]["rolls"]["crit"] = 1
		if archetype == "SWORD_DEF":
			for zone in CombatEngine.HIT_ZONES:
				player.armour[zone] = {"slashing":100.0,"piercing":100.0,"chopping":100.0,"blunt":100.0}
		var last := session.play_round(["chest"],["head","arms"],String(entry["fourth"]))
		_check(bool(last.get("ok",false)),archetype+"_abi04_round")
		_check(player.action_points == 0,archetype+"_abi04_all_ap_spent")
		if archetype == "SWORD_DODGE":
			_check(int(_eff(target,"EFF301").get("stacks",0)) == 5,"dodge_ult_five_stacks")
		elif archetype == "SWORD_CRIT":
			var bonus_recorded := false
			for attack in _events(session,CombatEvent.Kind.ATTACK,"ABI308"):
				if float(attack.payload.get("sword_crit_chance_pct",0)) == 50.0 and float(attack.payload.get("sword_crit_damage_pct",0)) == 125.0 and bool(attack.result.get("critical",false)):
					bonus_recorded = true
			_check(bonus_recorded,"crit_ult_five_ap_bonus_and_critical")
			var bursts := 0
			for event in _events(session,CombatEvent.Kind.DAMAGE,"","EFF301"):
				if bool(event.payload.get("sword_burst_tick",false)):
					bursts += 1
			_check(bursts == 3,"crit_ult_three_bleed_ticks")
			_check(not _eff(target,"EFF301").is_empty(),"crit_ult_does_not_consume_bleed")
		else:
			var ult_attack := false
			for event in _events(session,CombatEvent.Kind.ATTACK,"ABI306"):
				if float(event.result.get("raw_damage",0.0)) > 50.0:
					ult_attack = true
			_check(ult_attack,"def_ult_uses_all_5_zone_armour")
		print("SWORD_V12_ARCHETYPE=",archetype," final_bleed=",_eff(target,"EFF301").get("stacks",0)," ap=",player.action_points)
	_test_aoe_and_hit_gates()
	print("SWORD_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)

func _test_session(archetype: String, seed_value: int) -> ArenaCombatSession:
	var hero := CharacterState.new("AOE_"+archetype,"AOE Hero",40)
	for key in ["PAR001","PAR002","PAR003"]:
		hero.progression.base_stats[key] = 50
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_sword(hero,repo,archetype,40,"purple",seed_value)
	if item.is_empty() or not hero.equip("main_hand",String(item.get("instance_id","")),repo):
		_check(false,"aoe_fixture_"+archetype)
		return null
	var session := ArenaCombatSession.new(hero,repo)
	session.fighter(true).hp = 100000
	session.fighter(true).max_hp = 100000
	session.fighter(true).combat_stats["hit_chance_rating_percent"] = 100.0
	session.fighter(false).hp = 100000
	session.fighter(false).max_hp = 100000
	session.fighter(false).combat_stats["dodge_rating_percent"] = 0.0
	session.fighter(false).combat_stats["shield_auto_block_rating_percent"] = 0.0
	session.fighter(false).combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	return session

func _extra_enemy(session: ArenaCombatSession, index: int) -> CombatantState:
	var id := "SWORD_EXTRA_"+str(index)
	var character := CharacterState.new(id,id,40)
	var fighter := CharacterCombatBuilder.build(character,ItemRepository.new(),{"health":100000,"mana":0})
	session.state.add_combatant(fighter)
	_check(session.orchestrator.group_state.add_member("enemy",id),"aoe_group_"+id)
	session.orchestrator.zone_state.set_zone(id,CombatZoneState.ZONE_2)
	fighter.combat_stats["dodge_rating_percent"] = 0.0
	fighter.combat_stats["shield_auto_block_rating_percent"] = 0.0
	fighter.combat_loadout["can_auto_block"] = false
	return fighter

func _test_aoe_and_hit_gates() -> void:
	var session := _test_session("SWORD_DEF",202611041)
	if session == null:
		return
	var other1 := _extra_enemy(session,1)
	var other2 := _extra_enemy(session,2)
	var target := session.fighter(false)
	# A 0-HP target remains selectable until end-of-round death finalization.
	other2.hp = 0
	var actor := session.fighter(true)
	actor.action_points = 0
	var ability: Dictionary = session.ability_scheduler.definitions["ABI302"]
	ability["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"crit":100,"block_crush":100}
	var result := session.play_round(["chest"],["head","arms"],"ABI302")
	_check(bool(result.get("ok",false)),"abi02_3_target_cast")
	var hits := _events(session,CombatEvent.Kind.ATTACK,"ABI302")
	_check(hits.size()==3,"abi02_3_independent_attack_events")
	for enemy in [target,other1,other2]:
		_check(int(_eff(enemy,"EFF301").get("stacks",0))==1,"abi02_bleed_each_"+enemy.combatant_id)
	_check(other2.is_death_finalized(),"abi02_zero_hp_death_at_end_of_round")
	var rewarded := false
	for event in _events(session,CombatEvent.Kind.ACTION,"ABI302"):
		if bool(event.result.get("sword_hit_ap_awarded",false)) and int(event.result.get("ap_gained_on_hit",-1)) == 2:
			rewarded = true
	_check(rewarded,"abi02_exactly_two_ap_total")
	# CD 3 means no re-cast in the following round, even with available AP.
	session.orchestrator.begin_round()
	_check(session.ability_scheduler.cast_event(session.state,session.player_id,ArenaCombatSession.ENEMY_ID,"ABI302")==null,"abi02_cooldown")
	var miss := _test_session("SWORD_DEF",202611041)
	if miss == null:
		return
	miss.fighter(true).action_points = 0
	miss.fighter(true).combat_stats["hit_chance_rating_percent"] = -100.0
	var ability_miss: Dictionary = miss.ability_scheduler.definitions["ABI302"]
	ability_miss["rolls"] = {"hit":100,"dodge":100,"auto_block":100,"crit":100}
	var missed := miss.play_round(["chest"],["head","arms"],"ABI302")
	_check(bool(missed.get("ok",false)),"abi02_miss_cast_processed")
	_check(_eff(miss.fighter(false),"EFF301").is_empty(),"abi02_miss_no_eff")
	_check(miss.fighter(true).action_points == 0,"abi02_miss_no_ap")
	# Up to five targets for the AP-based dodge finisher; each receives
	# exactly min(AP, max_stacks) bleeding stacks on successful hit.
	var dodge := _test_session("SWORD_DODGE",202611042)
	if dodge == null:
		return
	var all_targets: Array[CombatantState] = [dodge.fighter(false)]
	for i in range(4):
		all_targets.append(_extra_enemy(dodge,10+i))
	dodge.fighter(true).action_points = 5
	var dodge_ability: Dictionary = dodge.ability_scheduler.definitions["ABI307"]
	dodge_ability["rolls"] = {"hit":1,"dodge":100,"auto_block":100,"crit":100}
	var aoe := dodge.play_round(["chest"],["head","arms"],"ABI307")
	_check(bool(aoe.get("ok",false)),"abi04_dodge_5target_cast")
	_check(_events(dodge,CombatEvent.Kind.ATTACK,"ABI307").size()==5,"abi04_dodge_5_independent_hits")
	for enemy in all_targets:
		_check(int(_eff(enemy,"EFF301").get("stacks",0))==5,"abi04_dodge_5stacks_"+enemy.combatant_id)
	print("SWORD_V12_AOE_TEST=",("PASS" if problems.is_empty() else "FAIL"))
