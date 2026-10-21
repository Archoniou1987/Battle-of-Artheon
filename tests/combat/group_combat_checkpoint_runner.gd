extends SceneTree

## Deterministic real 1v2 MAP battle: continuous rounds must match interrupted
## and resumed rounds, including RNG, ABI, DoT/HoT, event IDs, Tempo and
## automatic per-round checkpoint writes. No Arena training session involved.
const PATH := "user://boa_test_group_checkpoint_v1.json"
const ENCOUNTER := "location_42:bandit_patrol:cohort_001"
var failures: Array[String] = []

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("GROUP_CHECKPOINT_CASE=FAIL ",label)

func _initialize() -> void:
	_execute()
	print("GROUP_CHECKPOINT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _encounter() -> Dictionary:
	var npc_data := TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var catalog := NpcRepository.new()
	catalog.load_definitions(npc_data)
	var map := TacticalMapState.new(12,12)
	var bridge := MapNpcBridge.new()
	var members: Array[NpcInstance] = []
	for i in range(2):
		var id := "PATROL_%02d" % (i + 1)
		var npc := NpcInstance.new(id,catalog.get_npc("NPC003"))
		if not bridge.register_npc(map,npc,Vector2i(5,5)):
			return {}
		members.append(npc)
	var encounter := bridge.encounter_at(map,Vector2i(5,5))
	return {"catalog":catalog,"encounter":encounter,"map":map,"bridge":bridge,"npcs":members}

func _player() -> CombatantState:
	var combatant := TestFixtureLoader.new_combatant("PLAYER", "Player", 10, 12000, 500)
	TestFixtureLoader.set_weapon_profiles(combatant,[{"damage_min":2.0,"damage_max":3.0,"damage_type":"slashing"}])
	return combatant

func _configure(sim: GroupCombatSimulator) -> void:
	sim.engine.combat_rng.seed = 20261021
	var p := sim.state.get_combatant("PLAYER")
	p.hp = 8000
	p.max_hp = 12000
	p.mana = 500
	p.max_mana = 500
	p.combat_stats["hp_regen_round"] = 0.0
	p.combat_stats["mana_regen_round"] = 0.0
	for raw_id in ["PATROL_01","PATROL_02"]:
		var npc := sim.state.get_combatant(raw_id)
		npc.max_hp = 12000
		npc.hp = 8000
		npc.max_mana = 500
		npc.mana = 500
		npc.combat_stats["hp_regen_round"] = 0.0
		npc.combat_stats["mana_regen_round"] = 0.0
	sim.attack_pipeline.ability_scheduler = AbilityScheduler.new(
		AbilityCatalog.load_json("res://data/abilities/catalog.json"),
		{"PLAYER":["ABI003","ABI004"],"PATROL_01":["ABI004"],"PATROL_02":[]})
	# Force deterministic magic hits, not artificial direct EFF mutations.
	var fireball := AbilityCatalog.definition(sim.attack_pipeline.ability_scheduler.definitions,"ABI003").duplicate(true)
	fireball["magic_hit_roll"] = 1
	sim.attack_pipeline.ability_scheduler.definitions["ABI003"] = fireball

func _signature(sim: GroupCombatSimulator, encounter_key: String, fingerprint: String) -> String:
	var captured := GroupCombatCheckpointService.capture(sim,encounter_key,fingerprint)
	if not bool(captured.get("ok",false)):
		_check(false, "signature_capture_" + String(captured.get("reason","")))
		return ""
	# Normalize number representations through the exact JSON serialization
	# boundary used by the disk codec before comparing both simulations.
	var normalized: Variant = JSON.parse_string(JSON.stringify(captured["payload"]))
	return JSON.stringify(normalized)

func _read_original() -> String:
	return FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""

func _write_raw(data: String) -> void:
	var f := FileAccess.open(PATH,FileAccess.WRITE)
	if f != null:
		f.store_string(data)
		f.close()

func _execute() -> void:
	GroupCombatCheckpointService.clear(PATH)
	var seed_a := _encounter()
	var seed_b := _encounter()
	_check(not seed_a.is_empty() and not seed_b.is_empty(), "two_world_encounters")
	if seed_a.is_empty() or seed_b.is_empty():
		GroupCombatCheckpointService.clear(PATH)
		return
	var baseline_open := MapEncounterCombatService.begin(seed_a["encounter"],seed_a["catalog"],_player())
	var checkpoint_open := MapEncounterCombatService.begin_resumable(seed_b["encounter"],seed_b["catalog"],_player(),ENCOUNTER,PATH)
	_check(bool(baseline_open.get("ok",false)) and bool(checkpoint_open.get("ok",false)), "group_battles_created")
	if not bool(baseline_open.get("ok",false)) or not bool(checkpoint_open.get("ok",false)):
		GroupCombatCheckpointService.clear(PATH)
		return
	var fingerprint := GroupCombatCheckpointService.initial_roster_fingerprint(baseline_open["state"])
	var baseline := GroupCombatSimulator.new(baseline_open["state"],baseline_open["group"])
	var paused: GroupCombatSimulator = checkpoint_open["simulator"]
	_check(fingerprint == paused.checkpoint_roster_fingerprint, "baseline_and_suspended_roster_fingerprints_match")
	_configure(baseline)
	_configure(paused)
	_check(baseline.group.active_opponent("PLAYER") == "PATROL_01", "group_primary_target")
	_check(not bool(checkpoint_open.get("resumed",true)), "first_open_starts_new_battle")
	_check(not fingerprint.is_empty(), "fingerprint_generated")

	for i in range(3):
		var continuous: Dictionary = baseline.run_round()
		var checkpointed: Dictionary = paused.run_round()
		_check(bool(continuous.get("ok",false)) and bool(checkpointed.get("ok",false)), "initial_round_%d" % (i+1))
		_check(bool(checkpointed.get("checkpoint_ok",false)), "automatic_save_after_round_%d" % (i+1))
		_check(FileAccess.file_exists(PATH), "save_file_after_round_%d" % (i+1))
		_check(_signature(baseline,ENCOUNTER,fingerprint) == _signature(paused,ENCOUNTER,fingerprint), "identical_before_interrupt_%d" % (i+1))
		if not bool(checkpointed.get("ok",false)) or not bool(checkpointed.get("checkpoint_ok",false)):
			GroupCombatCheckpointService.clear(PATH)
			return
	_check(paused.state.round_number == 3, "three_rounds_checkpointed")
	var frozen_rng_state := paused.engine.combat_rng.state
	var frozen_effect_counter := paused.engine._next_effect_stack_id
	var frozen_event_id := paused.state.next_event_id
	var frozen_casts: Dictionary = paused.attack_pipeline.ability_scheduler.cast_round_by_combatant.duplicate(true)
	var frozen_cooldowns: Dictionary = paused.attack_pipeline.ability_scheduler.cooldowns_by_combatant.duplicate(true)
	var frozen_effects: Dictionary = {}
	for raw_id in paused.state.combatants.keys():
		var fighter := paused.state.get_combatant(String(raw_id))
		frozen_effects[String(raw_id)] = fighter.active_effects.duplicate(true)
	var saved_contents := _read_original()
	_check(saved_contents.length() > 100, "serialized_checkpoint_nonempty")

	# Bad checksum never instantiates a simulator, and the MAP adapter must
	# not silently start a new encounter on a damaged checkpoint.
	var corrupted := JSON.parse_string(saved_contents)
	if corrupted is Dictionary:
		corrupted["sha256"] = "bad"
		_write_raw(JSON.stringify(corrupted))
		var invalid := GroupCombatCheckpointService.read(PATH,ENCOUNTER,fingerprint)
		_check(not bool(invalid.get("ok",false)) and String(invalid.get("reason","")) == "checkpoint_integrity_failed", "checksum_rejects_tamper")
		var blocked := MapEncounterCombatService.begin_resumable(seed_b["encounter"],seed_b["catalog"],_player(),ENCOUNTER,PATH)
		_check(not bool(blocked.get("ok",false)), "invalid_save_prevents_silent_restart")
		_write_raw(saved_contents)

	_check(not bool(GroupCombatCheckpointService.read(PATH,"different_map:patrol",fingerprint).get("ok",false)), "different_encounter_rejected")
	_check(not bool(GroupCombatCheckpointService.read(PATH,ENCOUNTER,"f".repeat(64)).get("ok",false)), "outdated_equipment_signature_rejected")
	# Emulate process death: drop the old simulator and encounter build,
	# instantiate a completely new world encounter using the same NPC cohort.
	paused = null
	var seed_c := _encounter()
	var resumed_open := MapEncounterCombatService.begin_resumable(seed_c["encounter"],seed_c["catalog"],_player(),ENCOUNTER,PATH)
	_check(bool(resumed_open.get("ok",false)) and bool(resumed_open.get("resumed",false)), "reopened_from_real_map_encounter")
	if not bool(resumed_open.get("ok",false)):
		GroupCombatCheckpointService.clear(PATH)
		return
	var resumed: GroupCombatSimulator = resumed_open["simulator"]
	_check(resumed.state.round_number == 3, "resume_starts_at_next_round")
	_check(resumed.engine.combat_rng.state == frozen_rng_state and resumed.engine._next_effect_stack_id == frozen_effect_counter, "restore_rng_and_eff_sequence")
	_check(resumed.state.next_event_id == frozen_event_id, "restore_next_canonical_event_id")
	_check(resumed.attack_pipeline.ability_scheduler.cast_round_by_combatant == frozen_casts and resumed.attack_pipeline.ability_scheduler.cooldowns_by_combatant == frozen_cooldowns, "restore_cooldowns_and_abi_round_budget")
	for raw_id in frozen_effects:
		_check(resumed.state.get_combatant(String(raw_id)).active_effects == frozen_effects[raw_id], "restore_real_effects_" + String(raw_id))
	_check(_signature(baseline,ENCOUNTER,fingerprint) == _signature(resumed,ENCOUNTER,fingerprint), "full_snapshot_exactly_restored")

	for i in range(3,9):
		var continuous: Dictionary = baseline.run_round()
		var restarted: Dictionary = resumed.run_round()
		_check(bool(continuous.get("ok",false)) and bool(restarted.get("ok",false)), "continuation_round_%d" % (i+1))
		_check(bool(restarted.get("checkpoint_ok",false)), "continuation_saved_%d" % (i+1))
		_check(_signature(baseline,ENCOUNTER,fingerprint) == _signature(resumed,ENCOUNTER,fingerprint), "uninterrupted_equals_resumed_round_%d" % (i+1))
		_check(resumed.state.pending_events.is_empty() and resumed.orchestrator.deferred_events.is_empty(), "round_boundary_empty_queues_%d" % (i+1))
		if not bool(restarted.get("ok",false)) or not bool(restarted.get("checkpoint_ok",false)):
			break
	var abi_events := 0
	var periodic_events := 0
	for event in resumed.state.event_log:
		if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("source_kind","")) == "ability":
			abi_events += 1
		if String(event.payload.get("source","")) == "effect":
			periodic_events += 1
	_check(abi_events > 0 and periodic_events > 0, "actual_abi_and_eff_through_checkpoint")
	_check(resumed.state.round_number == 9, "nine_rounds_completed")
	_check(GroupCombatCheckpointService.clear(PATH) and not FileAccess.file_exists(PATH), "checkpoint_explicit_cleanup")
