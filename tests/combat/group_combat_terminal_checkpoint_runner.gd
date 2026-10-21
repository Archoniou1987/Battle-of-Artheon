extends SceneTree

## A terminal checkpoint must stay terminal after restore: no duplicate round,
## no additional event IDs, no automatic deletion before world rewards commit.
## Version mismatches and unsupported snapshots are rejected, never replayed.
const PATH := "user://boa_test_group_terminal_checkpoint_v1.json"
const ENCOUNTER := "world_1:location_9:npc_BOSS"
var errors: Array[String] = []

func _check(ok: bool, reason: String) -> void:
	if not ok:
		errors.append(reason)
		print("GROUP_TERMINAL_CHECKPOINT_CASE=FAIL ",reason)

func _initialize() -> void:
	_run()
	print("GROUP_TERMINAL_CHECKPOINT_TEST=", "PASS" if errors.is_empty() else "FAIL", " errors=",errors)
	quit(0 if errors.is_empty() else 1)

func _write_checkpoint_text(value: String) -> void:
	var file := FileAccess.open(PATH,FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()

func _run() -> void:
	GroupCombatCheckpointService.clear(PATH)
	var state := CombatState.new()
	var hero := TestFixtureLoader.new_combatant("PLAYER","Player",30,10000,100)
	TestFixtureLoader.set_weapon_profiles(hero,[{"damage_min":10000.0,"damage_max":10000.0,"damage_type":"slashing"}])
	hero.combat_stats["hit_chance_rating_percent"] = 100.0
	var enemy := TestFixtureLoader.new_combatant("BOSS","Boss",1,15,0)
	TestFixtureLoader.set_weapon_profiles(enemy,[{"damage_min":0.0,"damage_max":0.0,"damage_type":"slashing"}])
	enemy.combat_stats["shield_auto_block_rating_percent"] = 0.0
	enemy.combat_stats["dodge_rating_percent"] = 0.0
	enemy.combat_stats["damage_reduction_pct"] = 0.0
	state.add_combatant(hero)
	state.add_combatant(enemy)
	var group := GroupCombatState.new(state)
	group.add_member("players","PLAYER")
	group.add_member("enemies","BOSS")
	var signature := GroupCombatCheckpointService.initial_roster_fingerprint(state)
	var sim := GroupCombatSimulator.new(state,group)
	sim.engine.combat_rng.seed = 20261021
	_check(bool(sim.enable_checkpoint(ENCOUNTER,signature,PATH).get("ok",false)), "checkpoint_enabled")
	_check(not bool(GroupCombatCheckpointService.capture(sim,ENCOUNTER,signature).get("ok",false)), "cannot_checkpoint_before_first_round")
	var result: Dictionary = {}
	for i in range(1,11):
		result = sim.run_round()
		_check(bool(result.get("ok",false)) and bool(result.get("checkpoint_ok",false)), "end_round_checkpoint_%d" % i)
		if i == 1:
			sim.round_in_progress = true
			_check(String(GroupCombatCheckpointService.capture(sim,ENCOUNTER,signature).get("reason","")) == "round_not_fully_resolved", "cannot_save_partial_round")
			sim.round_in_progress = false
		if sim.controller.combat_finished() or not bool(result.get("ok",false)):
			break
	_check(sim.controller.combat_finished() and sim.controller.winning_team() == "players", "actual_engine_boss_defeat")
	_check(FileAccess.file_exists(PATH), "terminal_checkpoint_kept_for_world_commit")
	if not sim.controller.combat_finished() or not FileAccess.file_exists(PATH):
		GroupCombatCheckpointService.clear(PATH)
		return
	_check(bool(result.get("battle_outcome","") == "winner:players"), "terminal_round_result")
	var terminal_state := GroupCombatCheckpointService.read(PATH,ENCOUNTER,signature)
	_check(bool(terminal_state.get("ok",false)) and bool(terminal_state.get("terminal",false)), "terminal_snapshot_restores_as_terminal")
	if not bool(terminal_state.get("ok",false)):
		GroupCombatCheckpointService.clear(PATH)
		return
	var restored: GroupCombatSimulator = terminal_state["simulator"]
	_check(restored.state.get_combatant("BOSS").is_death_finalized(), "defeated_boss_is_finalized")
	var before_round := restored.state.round_number
	var before_events := restored.state.event_log.size()
	var before_next_id := restored.state.next_event_id
	var denied := restored.run_round()
	_check(not bool(denied.get("ok",true)) and String(denied.get("reason","")) == "combat_finished", "terminal_round_cannot_replay")
	_check(restored.state.round_number == before_round and restored.state.next_event_id == before_next_id and restored.state.event_log.size() == before_events, "terminal_retry_does_not_mutate_history")
	_check(FileAccess.file_exists(PATH), "terminal_checkpoint_not_cleared_on_restore")
	var original := FileAccess.get_file_as_string(PATH)
	var wrapper: Variant = JSON.parse_string(original)
	if wrapper is Dictionary:
		var payload: Variant = JSON.parse_string(String(wrapper["payload_json"]))
		if payload is Dictionary:
			payload["schema_version"] = 99
			var inner := JSON.stringify(payload)
			wrapper["payload_json"] = inner
			wrapper["sha256"] = inner.sha256_text()
			_write_checkpoint_text(JSON.stringify(wrapper))
			var obsolete := GroupCombatCheckpointService.read(PATH,ENCOUNTER,signature)
			_check(not bool(obsolete.get("ok",false)) and String(obsolete.get("reason","")) == "checkpoint_schema_mismatch", "changed_schema_is_rejected_even_with_matching_checksum")
	_write_checkpoint_text(original)
	# A structurally altered payload with a freshly computed checksum must
	# still be rejected. SHA-256 is corruption detection, not validation.
	var duplicate_outer: Variant = JSON.parse_string(original)
	if duplicate_outer is Dictionary:
		var duplicate_payload: Variant = JSON.parse_string(String(duplicate_outer["payload_json"]))
		if duplicate_payload is Dictionary:
			var logged_events: Array = duplicate_payload["state"]["events"]
			if logged_events.size() > 1:
				logged_events[1]["id"] = logged_events[0]["id"]
				var unsafe_payload := JSON.stringify(duplicate_payload)
				duplicate_outer["payload_json"] = unsafe_payload
				duplicate_outer["sha256"] = unsafe_payload.sha256_text()
				_write_checkpoint_text(JSON.stringify(duplicate_outer))
				var duplicates := GroupCombatCheckpointService.read(PATH,ENCOUNTER,signature)
				_check(not bool(duplicates.get("ok",false)) and String(duplicates.get("reason","")) == "checkpoint_invalid_event_payload", "duplicate_event_ids_rejected_even_with_valid_hash")
	_write_checkpoint_text(original)
	# An attacker cannot change terminal=true to terminal=false to replay the
	# last round. The restored group and snapshot must agree on finality.
	var terminal_outer: Variant = JSON.parse_string(original)
	if terminal_outer is Dictionary:
		var terminal_payload: Variant = JSON.parse_string(String(terminal_outer["payload_json"]))
		if terminal_payload is Dictionary:
			terminal_payload["terminal"] = false
			var unsafe_terminal := JSON.stringify(terminal_payload)
			terminal_outer["payload_json"] = unsafe_terminal
			terminal_outer["sha256"] = unsafe_terminal.sha256_text()
			_write_checkpoint_text(JSON.stringify(terminal_outer))
			var false_terminal := GroupCombatCheckpointService.read(PATH,ENCOUNTER,signature)
			_check(not bool(false_terminal.get("ok",false)) and String(false_terminal.get("reason","")) == "checkpoint_terminal_state_mismatch", "terminal_flag_cannot_be_cleared")
	_write_checkpoint_text(original)
	_check(bool(GroupCombatCheckpointService.read(PATH,ENCOUNTER,signature).get("ok",false)), "valid_checkpoint_untouched_after_negative_tests")
	_check(GroupCombatCheckpointService.clear(PATH), "acknowledgement_can_clear_terminal_checkpoint")
	_check(not FileAccess.file_exists(PATH), "cleared_checkpoint_cannot_replay")
