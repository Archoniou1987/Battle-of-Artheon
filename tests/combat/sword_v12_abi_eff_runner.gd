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
		var second := session.play_round(["chest"],["head","arms"],third_abi)
		_check(bool(second.get("ok",false)),archetype+"_abi03_round")
		var debuff := _eff(target,String(entry["third"]))
		_check(not debuff.is_empty(),archetype+"_debuff_applied")
		if not debuff.is_empty():
			var effect_definition: Dictionary = debuff.get("definition",{})
			var key := "physical_damage_outgoing_direct_pct" if archetype=="SWORD_DEF" else ("anti_dodge_direct_pct" if archetype=="SWORD_DODGE" else "anti_crit_direct_pct")
			var expected := -5.0 if archetype=="SWORD_DEF" else -1.0
			_check(float(effect_definition.get(key,0.0)) == expected,archetype+"_debuff_snapshot")
		_check(int(_eff(target,"EFF301").get("stacks",0)) == 1,archetype+"_bleed_not_consumed")
		# Round 3: all-AP ability must operate on the same target and effect.
		player.action_points = 5
		if archetype == "SWORD_DEF":
			for zone in CombatEngine.HIT_ZONES:
				player.armour[zone] = {"slashing":100.0,"piercing":100.0,"chopping":100.0,"blunt":100.0}
		var last := session.play_round(["chest"],["head","arms"],String(entry["fourth"]))
		_check(bool(last.get("ok",false)),archetype+"_abi04_round")
		_check(player.action_points == 0,archetype+"_abi04_all_ap_spent")
		if archetype == "SWORD_DODGE":
			_check(int(_eff(target,"EFF301").get("stacks",0)) == 5,"dodge_ult_five_stacks")
		elif archetype == "SWORD_CRIT":
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
	print("SWORD_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)
