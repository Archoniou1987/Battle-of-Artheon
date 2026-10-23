extends SceneTree

## A real three-round ArenaCombatSession integration chain. No manually
## inserted active_effects: equipped ABI003 applies EFF003 to the NPC, then
## equipped ABI004 applies EFF004 to the hero. Engine-generated periodic
## events must agree with live EFF view and the resolved Arena combat log.
var failures: Array[String] = []

func _check(condition: bool, code: String) -> void:
	if not condition:
		failures.append(code)
		print("ARENA_REAL_EFF_CHAIN_CASE=FAIL ", code)

func _init() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("REAL_EFF_CHAIN_HERO", "EFF Chain Hero", 10)
	var sword: Dictionary = {
		"instance_id":"REAL_EFF_CHAIN_MH",
		"equip_slots":["main_hand"],
		"slot_usage":["main_hand"],
		"abilities":["ABI003"],
		"par_stats":{"PAR057":1},
		"damage":{"min":3.0,"max":4.0,"type":"slashing"}
	}
	var chest: Dictionary = {
		"instance_id":"REAL_EFF_CHAIN_CHEST",
		"equip_slots":["chest"],
		"slot_usage":["chest"],
		"abilities":["ABI004"]
	}
	for item in [sword,chest]:
		ItemDurabilityService.initialize_item(item,100)
		_check(repo.add_item(item), "fixture_repository")
		_check(hero.receive_item(String(item["instance_id"]),repo), "fixture_ownership")
	_check(hero.equip("main_hand","REAL_EFF_CHAIN_MH",repo), "fixture_weapon")
	_check(hero.equip("chest","REAL_EFF_CHAIN_CHEST",repo), "fixture_chest")
	if not failures.is_empty():
		_finish()
		return

	var session := ArenaCombatSession.new(hero,repo)
	var player := session.fighter(true)
	var enemy := session.fighter(false)
	player.max_hp = 2000
	player.hp = 1000
	player.max_mana = 100
	player.mana = 100
	# Keep the NPC as a normal armed training opponent, but eliminate
	# unrelated automatic abilities from this controlled EFF lifecycle case.
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	session.engine.combat_rng.seed = 20261020
	# Fix hit randomness only. Both ABI definitions, damage/EFF components,
	# cooldowns and timing remain the canonical production catalog.
	var fireball: Dictionary = AbilityCatalog.definition(session.ability_scheduler.definitions,"ABI003").duplicate(true)
	fireball["magic_hit_roll"] = 1
	session.ability_scheduler.definitions["ABI003"] = fireball
	var options: Array[Dictionary] = session.player_ability_options()
	_check(options.size() == 5, "five_real_abi_slots")
	_check(String(options[0].get("id","")) == "ABI003", "weapon_abi003")
	_check(String(options[3].get("id","")) == "ABI004", "chest_abi004")
	_check(bool(options[0].get("available",false)), "fireball_available")
	_check(bool(options[3].get("available",false)), "healing_available")
	if not failures.is_empty():
		_finish()
		return

	var block_zones: Array[String] = []
	for zone in ["chest","arms","waist","legs"]:
		if block_zones.size() < CombatModifierService.manual_block_zone_capacity(player):
			block_zones.append(String(zone))

	# ROUND 1: sword strike, manual defence and real ABI003 -> EFF003.
	var first: Dictionary = session.play_round(["head"],block_zones,"ABI003")
	_check(bool(first.get("ok",false)), "round1_accepted_" + String(first.get("reason","")))
	if not bool(first.get("ok",false)):
		_finish()
		return
	_check(session.state.round_number == 1, "round1_number")
	_audit_round(session,1,1,0)
	_check(_abi_casts(session,1,"ABI003") == 1, "round1_fireball_cast_once")
	_check(_effect_applications(session,1,"EFF003") == 1, "round1_burning_applied_by_engine")
	_check(_periodic_tick(session,1,"EFF003",false)["count"] == 0, "round1_no_early_dot")
	_check(_record_count(enemy,"EFF003") == 1, "round1_one_real_burning_record")
	var burning_view: Dictionary = session.effect_view(false)
	_check(_contains_effect(Array(burning_view.get("debuffs",[])),"EFF003",true), "round1_burning_visible_pending")
	_check(_lines_contain(first,"EFF003"), "round1_burning_in_combat_journal")
	_check(not CombatDiagnostics.combatant_trace(player,1).is_empty(), "round1_par_diagnostics")

	# ROUND 2: a cooldown-rejected recast is atomic; the legal choice is
	# ABI004, which heals the hero and attaches EFF004. EFF003 begins ticking.
	var before_mana := player.mana
	var before_hp := player.hp
	var npc_before_hp := enemy.hp
	var npc_before_mana := enemy.mana
	var before_event_count := session.state.event_log.size()
	var before_next_event_id := session.state.next_event_id
	var before_burning: Array = enemy.active_effects.duplicate(true)
	var rejected: Dictionary = session.play_round(["head"],block_zones,"ABI003")
	_check(not bool(rejected.get("ok",false)), "round2_abi003_cooldown_rejected")
	_check(session.state.round_number == 1 and player.mana == before_mana and player.hp == before_hp, "round2_reject_is_atomic")
	_check(enemy.hp == npc_before_hp and enemy.mana == npc_before_mana, "round2_reject_does_not_mutate_npc")
	_check(session.state.event_log.size() == before_event_count and session.state.next_event_id == before_next_event_id, "round2_reject_does_not_allocate_or_record_events")
	_check(enemy.active_effects == before_burning, "round2_reject_preserves_real_eff_lifecycle")
	_check(session.state.pending_events.is_empty(), "round2_reject_has_no_events")
	var second: Dictionary = session.play_round(["head"],block_zones,"ABI004")
	_check(bool(second.get("ok",false)), "round2_accepted_" + String(second.get("reason","")))
	if not bool(second.get("ok",false)):
		_finish()
		return
	_check(session.state.round_number == 2, "round2_number")
	_audit_round(session,2,1,1)
	_check(_abi_casts(session,2,"ABI004") == 1, "round2_healing_cast_once")
	_check(_effect_applications(session,2,"EFF004") == 1, "round2_regeneration_applied_by_engine")
	var dot: Dictionary = _periodic_tick(session,2,"EFF003",false)
	_check(int(dot.get("count",0)) == 1 and int(dot.get("amount",0)) > 0, "round2_real_burning_damage")
	_check(_lines_contain(second,"EFF EFF003"), "round2_dot_in_journal")
	_check(_record_count(player,"EFF004") == 1, "round2_one_real_regeneration_record")
	_check(_contains_effect(Array(session.effect_view(true).get("buffs",[])),"EFF004",true), "round2_regeneration_visible_pending")
	_check(_lines_contain(second,"EFF004"), "round2_regeneration_in_journal")
	_check(_periodic_tick(session,2,"EFF004",true)["count"] == 0, "round2_no_early_hot")

	# ROUND 3: no ABI. Both independently authored real effects should
	# now tick and be reported by the same Arena combat journal.
	var third: Dictionary = session.play_round(["head"],block_zones)
	_check(bool(third.get("ok",false)), "round3_accepted_" + String(third.get("reason","")))
	if not bool(third.get("ok",false)):
		_finish()
		return
	_check(session.state.round_number == 3, "round3_number")
	_audit_round(session,3,0,2)
	_check(_abi_casts(session,3,"ABI003") == 0 and _abi_casts(session,3,"ABI004") == 0, "round3_no_unselected_abi")
	var second_dot: Dictionary = _periodic_tick(session,3,"EFF003",false)
	var hot: Dictionary = _periodic_tick(session,3,"EFF004",true)
	_check(int(second_dot.get("count",0)) == 1 and int(second_dot.get("amount",0)) > 0, "round3_real_dot")
	_check(int(hot.get("count",0)) == 1 and int(hot.get("amount",0)) > 0, "round3_real_hot")
	_check(_lines_contain(third,"EFF EFF003") and _lines_contain(third,"EFF EFF004"), "round3_both_effects_in_journal")
	_check(_contains_effect(Array(session.effect_view(false).get("debuffs",[])),"EFF003",false), "round3_burning_still_visible")
	_check(_contains_effect(Array(session.effect_view(true).get("buffs",[])),"EFF004",false), "round3_regeneration_still_visible")
	_check(session.orchestrator.battle_outcome() == "ongoing", "three_rounds_stay_active")
	_finish()

func _audit_round(session: ArenaCombatSession, round_number: int, expected_abi: int, expected_ticks: int) -> void:
	var audit: Dictionary = CombatDiagnostics.round_trace(session.state,round_number)
	print("ARENA_REAL_EFF_AUDIT_ROUND=",round_number,
		" weapon=",audit.get("weapon_attacks",0),
		" abi=",audit.get("abi_casts",0),
		" periodic=",audit.get("periodic_ticks",0),
		" applied=",audit.get("applied_effects",0),
		" orphan=",audit.get("missing_parent_event_ids",[]))
	_check(bool(audit.get("valid_event_lineage",false)), "round%d_event_lineage" % round_number)
	_check(int(audit.get("event_count",0)) > 0, "round%d_engine_events" % round_number)
	_check(int(Dictionary(audit.get("weapon_attacks_by_source",{})).get(session.player_id,0)) == 1, "round%d_real_weapon_action" % round_number)
	_check(int(Dictionary(audit.get("abi_casts_by_source",{})).get(session.player_id,0)) == expected_abi, "round%d_real_abi_dispatch" % round_number)
	_check(int(audit.get("periodic_ticks",0)) == expected_ticks, "round%d_periodic_event_count" % round_number)
	# Count the specific engine-authored EFF instead of assuming no other
	# passive weapon/NPC effects could also be present in the same round.
	if round_number <= 2:
		var expected_id := "EFF003" if round_number == 1 else "EFF004"
		var applications: Dictionary = audit.get("applied_effects_by_id", {})
		_check(int(applications.get(expected_id,0)) == 1, "round%d_real_eff_application_count" % round_number)
	# Diagnostics exposes detached dictionaries. Mutating this projection must
	# never alter the canonical, resolved engine events.
	var projection: Array = audit.get("events",[])
	if not projection.is_empty():
		var projected: Dictionary = projection[0]
		var projected_result: Dictionary = projected.get("result",{})
		projected_result["__test_read_only_probe"] = true
		var original_id := int(projected.get("id",-1))
		for event in session.state.event_log:
			if event.event_id == original_id:
				_check(not event.result.has("__test_read_only_probe"), "round%d_diagnostics_are_detached" % round_number)
				break

func _record_count(target: CombatantState, effect_id: String) -> int:
	var count := 0
	for record in target.active_effects:
		if String(record.get("effect_id","")) == effect_id:
			count += 1
	return count

func _contains_effect(entries: Array, id: String, pending: bool) -> bool:
	for raw in entries:
		var entry: Dictionary = Dictionary(raw)
		if String(entry.get("id","")) == id:
			return bool(entry.get("pending",not pending)) == pending
	return false

func _abi_casts(session: ArenaCombatSession, round_number: int, id: String) -> int:
	var count := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) == round_number and event.kind == CombatEvent.Kind.ACTION and event.source_id == session.player_id and String(event.payload.get("ability_id","")) == id:
			count += 1
	return count

func _effect_applications(session: ArenaCombatSession, round_number: int, id: String) -> int:
	var count := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) == round_number and event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id","")) == id and bool(event.result.get("resolved",false)) and String(event.payload.get("source","")) != "effect":
			count += 1
	return count

func _periodic_tick(session: ArenaCombatSession, round_number: int, id: String, healing: bool) -> Dictionary:
	var count := 0
	var amount := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) != round_number or String(event.payload.get("effect_id","")) != id or String(event.payload.get("source","")) != "effect":
			continue
		if healing and event.kind == CombatEvent.Kind.EFFECT:
			count += 1
			amount += int(event.result.get("healed",0))
		elif not healing and event.kind == CombatEvent.Kind.DAMAGE:
			count += 1
			amount += int(event.result.get("hp_removed",0))
	return {"count":count,"amount":amount}

func _lines_contain(result: Dictionary, fragment: String) -> bool:
	for raw in Array(result.get("lines",[])):
		if String(raw).contains(fragment):
			return true
	return false

func _finish() -> void:
	print("ARENA_REAL_EFF_CHAIN_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)
