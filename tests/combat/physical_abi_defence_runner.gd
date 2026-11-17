extends SceneTree

## Canonical physical ABI defence policy: dodge chance x0.5, block damage
## x0.5, on-hit effects preserved; ordinary attacks retain full block.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("PHYSICAL_ABI_DEFENCE_FAIL=",label)

func _attack(arena: ArenaCombatSession, ability: bool, block_mode: String, zone: String = "waist") -> CombatEvent:
	var npc := arena.fighter(false)
	npc.combat_stats["manual_block_zones"] = [zone] if block_mode=="manual" else []
	npc.combat_loadout["can_manual_block"] = block_mode=="manual"
	npc.combat_loadout["can_auto_block"] = block_mode=="shield"
	npc.combat_stats["shield_auto_block_rating_percent"] = 100.0 if block_mode=="shield" else 0.0
	var data := {
		"zone":zone,"damage_type":"slashing","raw_damage":200.0,
		"hit_already_resolved":true,
		"rolls":{"hit":1,"dodge":100,"auto_block":1,"block_crush":100,"crit":100,"damage":0.5}
	}
	if ability:
		data["source_kind"] = "ability"
		data["ability_id"] = "ABI401"
		data["combo_abi_id"] = "ABI401"
	var event := arena.state.create_event(CombatEvent.Kind.ATTACK,arena.player_id,ArenaCombatSession.ENEMY_ID,data)
	arena.engine.resolve_event(event)
	arena.engine.resolve_pending_events()
	return event

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("DEFENCE_POLICY_HERO","Defence policy hero",10)
	var sword := {"instance_id":"POLICY_SWORD","equip_slots":["main_hand"],"slot_usage":["main_hand"],"par_stats":{"PAR057":1},"damage":{"min":3.0,"max":4.0,"type":"slashing"}}
	ItemDurabilityService.initialize_item(sword,100)
	_check(repo.add_item(sword),"sword_registered")
	_check(hero.receive_item("POLICY_SWORD",repo),"sword_owned")
	_check(hero.equip("main_hand","POLICY_SWORD",repo),"sword_equipped")
	var arena := ArenaCombatSession.new(hero,repo)
	arena.state.begin_round()
	var npc := arena.fighter(false)
	npc.hp=100000
	npc.max_hp=100000
	npc.combat_stats["dodge_rating_percent"]=40.0
	var baseline := _attack(arena,true,"none")
	var baseline_damage := float(baseline.result.get("after_armour_damage",0.0))
	_check(String(baseline.result.get("outcome",""))=="connected" and baseline_damage>0.0,"unblocked_abi_damage")
	var basic := _attack(arena,false,"none")
	_check(is_equal_approx(float(baseline.result.get("dodge_chance",-1)),float(basic.result.get("dodge_chance",-2))*0.5),"abi_half_calculated_dodge")
	arena.fighter(true).active_effects.clear()
	var manual := _attack(arena,true,"manual")
	_check(String(manual.result.get("partial_block",""))=="manual_block","abi_manual_block_marked")
	_check(String(manual.result.get("outcome",""))=="connected","abi_manual_block_still_hits")
	_check(is_equal_approx(float(manual.result.get("after_armour_damage",0.0)),baseline_damage*0.5),"abi_manual_50pct_postarmour")
	_check(AbilityRuntime.previous_round_trigger_met(arena.state,ArenaCombatSession.ENEMY_ID,"block",arena.state.round_number+1),"abi_block_counts_as_previous_round_block")
	_check(not arena.fighter(true).active_effects.is_empty(),"abi_manual_block_applies_on_hit_eff")
	arena.fighter(true).active_effects.clear()
	var shield := _attack(arena,true,"shield")
	_check(String(shield.result.get("partial_block",""))=="auto_block","abi_shield_block_marked")
	_check(is_equal_approx(float(shield.result.get("after_armour_damage",0.0)),baseline_damage*0.5),"abi_shield_50pct_postarmour")
	# ABI512 is a precise exception: manual and shield blocks must not
	# reduce its damage. Hit/dodge and armour are still processed normally.
	for block_mode in ["manual","shield"]:
		var bypass_npc := arena.fighter(false)
		bypass_npc.combat_stats["manual_block_zones"] = ["waist"] if block_mode=="manual" else []
		bypass_npc.combat_loadout["can_manual_block"] = block_mode=="manual"
		bypass_npc.combat_loadout["can_auto_block"] = block_mode=="shield"
		bypass_npc.combat_stats["shield_auto_block_rating_percent"] = 100.0 if block_mode=="shield" else 0.0
		var bypass := arena.state.create_event(CombatEvent.Kind.ATTACK,arena.player_id,ArenaCombatSession.ENEMY_ID,{
			"zone":"waist","damage_type":"slashing","raw_damage":200.0,
			"source_kind":"ability","ability_id":"ABI512","axe_abi_id":"ABI512",
			"uses_physical_block":false,"hit_already_resolved":true,
			"rolls":{"hit":1,"dodge":100,"auto_block":1,"block_crush":100,"crit":100,"damage":0.5}
		})
		arena.engine.resolve_event(bypass)
		arena.engine.resolve_pending_events()
		_check(String(bypass.result.get("outcome",""))=="connected","abi512_"+block_mode+"_connected")
		_check(not bypass.result.has("partial_block"),"abi512_"+block_mode+"_no_partial_block")
		_check(is_equal_approx(float(bypass.result.get("after_armour_damage",0.0)),baseline_damage),"abi512_"+block_mode+"_full_damage")
	var effects := 0
	for record in arena.fighter(true).active_effects:
		if String(record.get("effect_id",""))=="EFF406":
			effects+=1
	_check(effects>0,"abi_on_hit_effect_survives_block")
	# A successful dodge remains a full avoidance (including on-hit EFF).
	arena.fighter(true).active_effects.clear()
	npc.combat_stats["manual_block_zones"]=[]
	npc.combat_loadout["can_manual_block"]=false
	npc.combat_loadout["can_auto_block"]=false
	var dodge_event := arena.state.create_event(CombatEvent.Kind.ATTACK,arena.player_id,ArenaCombatSession.ENEMY_ID,{
		"zone":"waist","damage_type":"slashing","raw_damage":200.0,
		"source_kind":"ability","ability_id":"ABI401","combo_abi_id":"ABI401",
		"hit_already_resolved":true,
		"rolls":{"hit":1,"dodge":1,"auto_block":100,"block_crush":100,"crit":100,"damage":0.5}
	})
	arena.engine.resolve_event(dodge_event)
	arena.engine.resolve_pending_events()
	_check(String(dodge_event.result.get("outcome",""))=="dodge","abi_successful_dodge_avoids_all_damage")
	_check(not dodge_event.result.has("damage_event_id"),"abi_dodged_no_damage_event")
	_check(arena.fighter(true).active_effects.is_empty(),"abi_dodged_no_on_hit_effect")
	var ordinary := _attack(arena,false,"manual")
	_check(String(ordinary.result.get("outcome",""))=="manual_block","ordinary_manual_block_still_full")
	_check(not ordinary.result.has("damage_event_id"),"ordinary_block_no_damage")
	var ordinary_shield := _attack(arena,false,"shield")
	_check(String(ordinary_shield.result.get("outcome",""))=="auto_block","ordinary_shield_block_still_full")
	_check(not ordinary_shield.result.has("damage_event_id"),"ordinary_shield_no_damage")
	var lines := ArenaCombatLog.lines_for_round(arena.state.event_log,arena.state.round_number,arena.player_id)
	_check(" ".join(PackedStringArray(lines)).contains("50%"),"partial_block_visible_in_journal")
	print("PHYSICAL_ABI_DEFENCE=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)
