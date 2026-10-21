extends SceneTree

## Live Arena tests: a control ABI creates actual Tempo debt and scheduled
## stun, then the same Arena command path rejects all stunned NPC actions.
## A separate one-shot Arena duel validates terminal-state atomicity.
const CONTROL_ABI := "ABI_TEST_ARENA_TEMPO_CONTROL"
const CONTROL_EFF := "EFF_TEST_ARENA_TEMPO_DEBT"
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ARENA_TEMPO_DEATH_FAIL=", label)

func _init() -> void:
	_tempo_cycle()
	_terminal_battle()
	print("ARENA_TEMPO_DEATH_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _fixture(id: String, damage: float) -> ArenaCombatSession:
	var repository := ItemRepository.new()
	var hero := CharacterState.new(id, "Arena Tempo Test Hero", 10)
	var weapon: Dictionary = {
		"instance_id": id + "_weapon",
		"equip_slots": ["main_hand"],
		"slot_usage": ["main_hand"],
		"par_stats": {"PAR057": 1},
		"damage": {"min": damage, "max": damage, "type": "slashing"}
	}
	ItemDurabilityService.initialize_item(weapon, 100)
	_check(repository.add_item(weapon), id + "_weapon_added")
	_check(hero.receive_item(String(weapon["instance_id"]), repository), id + "_weapon_owned")
	_check(hero.equip("main_hand", String(weapon["instance_id"]), repository), id + "_weapon_equipped")
	if not failures.is_empty():
		return null
	var session := ArenaCombatSession.new(hero, repository)
	var player := session.fighter(true)
	var npc := session.fighter(false)
	player.max_hp = 30000
	player.hp = 15000
	player.max_mana = 250
	player.mana = 250
	npc.max_hp = 30000
	npc.hp = 15000
	npc.max_mana = 250
	npc.mana = 250
	session.engine.combat_rng.seed = 20261021
	return session

func _blocks(player: CombatantState) -> Array[String]:
	var blocks: Array[String] = []
	for zone in ["chest", "arms", "waist", "legs"]:
		if blocks.size() < CombatModifierService.manual_block_zone_capacity(player):
			blocks.append(zone)
	return blocks

func _npc_attack_count(session: ArenaCombatSession, round_number: int) -> int:
	var count := 0
	for event in session.state.event_log:
		if int(event.payload.get("round", -1)) == round_number and event.kind == CombatEvent.Kind.ATTACK and event.source_id == ArenaCombatSession.ENEMY_ID and bool(event.payload.get("is_weapon_attack", false)) and not bool(event.payload.get("is_counterattack", false)):
			count += 1
	return count

func _npc_abi_count(session: ArenaCombatSession, round_number: int) -> int:
	var trace: Dictionary = CombatDiagnostics.round_trace(session.state, round_number)
	return int(Dictionary(trace.get("abi_casts_by_source", {})).get(ArenaCombatSession.ENEMY_ID, 0))

func _tempo_cycle() -> void:
	var session := _fixture("ARENA_TEMPO_CYCLE", 3.0)
	if session == null:
		return
	var player := session.fighter(true)
	var npc := session.fighter(false)
	CombatTempoService.initialize(npc, 0.0, 100.0, 0.0)
	# Fixture only: the actual ACTION->EFF->CombatTempoService chain is used.
	# No direct calls to apply_control or manually planted active_effects.
	session.engine.physical_balance["effects"] = {
		CONTROL_EFF: {
			"name": "Temporary Arena control",
			"kind": "debuff",
			"tempo_modifier": -220.0,
			"duration_rounds": 2,
			"stacking": "unique"
		}
	}
	session.ability_scheduler.definitions[CONTROL_ABI] = {
		"name": "Arena Tempo Control",
		"application_timing": "standard",
		"delivery_type": "DIRECT",
		"target_team": "ENEMY",
		"components": [{"kind": "effect", "effect_id": CONTROL_EFF, "base_chance": 100.0}],
		"mana_cost": 5,
		"cooldown_rounds": 1
	}
	session.ability_scheduler.loadouts[session.player_id] = [CONTROL_ABI]
	session.player_ability_slots = [CONTROL_ABI, "", "", "", ""]
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = ["ABI004"]
	_check(AbilityRuntime.validate_definition(CONTROL_ABI, session.ability_scheduler.definitions[CONTROL_ABI]).is_empty(), "tempo_ability_fixture_valid")
	_check(bool(session.player_ability_options()[0].get("available", false)), "tempo_ability_available_round_one")
	if not failures.is_empty():
		return
	var blocks := _blocks(player)
	for round_number in range(1, 7):
		var selected := CONTROL_ABI if round_number in [1, 3] else ""
		var was_stunned := CombatTempoService.is_stunned(npc, round_number)
		var result: Dictionary = session.play_round(["chest"], blocks, selected)
		_check(bool(result.get("ok", false)), "tempo_round_%d_accepted_%s" % [round_number, String(result.get("reason", ""))])
		if not bool(result.get("ok", false)):
			return
		_check(session.state.round_number == round_number, "tempo_round_%d_number" % round_number)
		var trace: Dictionary = CombatDiagnostics.round_trace(session.state, round_number)
		_check(bool(trace.get("valid_event_lineage", false)), "tempo_round_%d_lineage" % round_number)
		_check(int(trace.get("abi_casts", 0)) <= 2, "tempo_round_%d_actor_abi_limits" % round_number)
		if was_stunned:
			_check(_npc_attack_count(session, round_number) == 0, "stun_prevents_npc_weapon_round_%d" % round_number)
			_check(_npc_abi_count(session, round_number) == 0, "stun_prevents_npc_abi_round_%d" % round_number)
		else:
			_check(_npc_attack_count(session, round_number) >= 1, "npc_recovers_weapon_round_%d" % round_number)
		if selected == CONTROL_ABI:
			_check(int(Dictionary(trace.get("applied_effects_by_id", {})).get(CONTROL_EFF, 0)) == 1, "real_control_effect_cast_round_%d" % round_number)
		if round_number == 1:
			_check(npc.tempo_stun_round == 2, "control_schedules_next_round_stun")
			_check(not CombatTempoService.is_stunned(npc, 1), "same_round_not_stunned")
		elif round_number == 2:
			_check(npc.tempo_immunity_until_round == 4, "two_round_immunity_begins")
		elif round_number == 3:
			_check(CombatTempoService.is_immune(npc, 3) and npc.tempo_stun_round == 2, "control_during_immunity_does_not_chain_stun")
			_check(npc.tempo < -100.0, "control_debt_accumulates_while_immune")
		elif round_number == 4:
			_check(CombatTempoService.is_immune(npc, 4) and npc.tempo_stun_round == 2, "second_immune_round_blocks_stun")
		elif round_number == 5:
			_check(npc.tempo_stun_round == 6, "control_debt_schedules_fresh_stun_after_immunity")
		elif round_number == 6:
			_check(npc.tempo_immunity_until_round == 8, "second_stun_rearms_two_round_immunity")
		_check(not npc.is_death_finalized() and not player.is_death_finalized(), "tempo_both_alive_round_%d" % round_number)
	print("ARENA_TEMPO_CYCLE=6_REAL_ROUNDS")

func _terminal_battle() -> void:
	var session := _fixture("ARENA_TERMINAL_DUEL", 40000.0)
	if session == null:
		return
	var player := session.fighter(true)
	var npc := session.fighter(false)
	npc.max_hp = 10000
	npc.hp = 10000
	npc.armour.clear()
	npc.combat_stats["dodge_rating_percent"] = 0.0
	npc.combat_stats["shield_auto_block_rating_percent"] = 0.0
	npc.combat_stats["manual_block_zones"] = []
	npc.combat_loadout["can_manual_block"] = false
	npc.combat_loadout["can_auto_block"] = false
	npc.combat_stats["damage_reduction_pct"] = 0.0
	npc.combat_stats["damage_reduction"] = 0.0
	# Force the seed-independent physical hit, but keep all following
	# physical stages in the production engine, including one-shot damage.
	player.combat_stats["hit_chance_rating_percent"] = 100.0
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = ["ABI004"]
	var blocks := _blocks(player)
	var result: Dictionary = session.play_round(["chest"], blocks)
	_check(bool(result.get("ok", false)), "terminal_round_accepted")
	if not bool(result.get("ok", false)):
		return
	_check(session.state.round_number == 1, "terminal_round_one")
	_check(npc.one_shot_kill and npc.is_death_finalized(), "one_shot_finalized_only_by_end_round")
	_check(String(result.get("outcome", "")) == "winner:player", "canonical_arena_winner")
	_check(session.orchestrator.battle_outcome() == "winner:player", "outcome_matches_orchestrator")
	_check(_npc_abi_count(session, 1) == 1, "lethally_hit_npc_still_resolves_locked_heal")
	var trace: Dictionary = CombatDiagnostics.round_trace(session.state, 1)
	_check(bool(trace.get("valid_event_lineage", false)), "terminal_canonical_event_lineage")
	var hp_before := player.hp
	var mana_before := player.mana
	var enemy_hp_before := npc.hp
	var round_before := session.state.round_number
	var event_count_before := session.state.event_log.size()
	var next_id_before := session.state.next_event_id
	var denied: Dictionary = session.play_round(["chest"], blocks)
	_check(not bool(denied.get("ok", false)), "finished_battle_rejects_new_round")
	_check(session.state.round_number == round_before and session.state.event_log.size() == event_count_before and session.state.next_event_id == next_id_before, "finished_battle_no_new_events")
	_check(player.hp == hp_before and player.mana == mana_before and npc.hp == enemy_hp_before, "finished_battle_no_resource_mutation")
	_check(session.state.pending_events.is_empty(), "finished_battle_empty_queue")
