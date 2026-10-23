extends SceneTree

## Real encounter -> canonical CombatSimulator verdict -> map NPC death ->
## once-only loot ownership -> persisted pool -> claimed inventory item.
## Negative and repeated outcomes cannot create duplicate rewards.
var failures: Array[String] = []

func _check(value: bool, id: String) -> void:
	if not value:
		failures.append(id)
		print("MAP_REAL_DUEL_REWARD_CASE=FAIL ", id)

func _initialize() -> void:
	_run()
	print("MAP_REAL_DUEL_REWARD_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var data := TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_catalog := NpcRepository.new()
	npc_catalog.load_definitions(data)
	var npc := NpcInstance.new("REAL_REWARD_NPC", npc_catalog.get_npc("NPC003"))
	var map := TacticalMapState.new(12, 12)
	var bridge := MapNpcBridge.new()
	var npc_cell := Vector2i(5, 5)
	_check(bridge.register_npc(map, npc, npc_cell), "npc_spawned_on_map")
	_check(map.place_entity("PLAYER", Vector2i(4, 5)), "player_spawned_nearby")
	var item_repo := ItemRepository.new()
	var loot_item: Dictionary = {
		"instance_id": "REAL_REWARD_DAGGER",
		"generated_from_template": "TEST_DAGGER",
		"quality": "common",
		"durability": {"current": 15, "max": 20}
	}
	_check(item_repo.add_item(loot_item), "npc_possession_added_to_repo")
	_check(npc.receive_item("REAL_REWARD_DAGGER", item_repo), "npc_owns_real_possession")
	var move: Dictionary = map.move_entity("PLAYER", npc_cell)
	_check(bool(move.get("ok", false)), "map_player_contact")
	var encounter: Dictionary = bridge.encounter_at(map, npc_cell)
	_check(bool(encounter.get("ok", false)), "map_detects_encounter")
	if not failures.is_empty():
		return

	var player_character := CharacterState.new("PLAYER", "Artheon Hero", 5)
	var player := TestFixtureLoader.new_combatant("PLAYER", "Artheon Hero", 5, 200)
	TestFixtureLoader.set_weapon_profiles(player, [{
		"damage_min": 500.0, "damage_max": 500.0, "damage_type": "slashing"
	}])
	# CombatantState uses combatant_id, while CharacterState uses
	# character_id. The game must pair the two before awarding rewards.
	_check(player.combatant_id == player_character.character_id, "runtime_and_persistent_player_identity_match")
	if not failures.is_empty():
		return
	var battle: Dictionary = MapEncounterCombatService.begin(encounter, npc_catalog, player)
	_check(bool(battle.get("ok", false)), "encounter_starts_canonical_battle")
	if not bool(battle.get("ok", false)):
		return
	var state: CombatState = battle.get("state")
	_check(state != null and state.get_combatant(npc.instance_id) != null, "actual_npc_instance_bound_to_battle")
	if state == null:
		return
	var sim := CombatSimulator.new(TestFixtureLoader.canonicalize_state(state),
		TestFixtureLoader.load_json("res://data/balance/physical_combat.json"), 6711)
	sim.max_rounds = 25
	var verdict: Dictionary = sim.run_duel(player.combatant_id, npc.instance_id)
	_check(String(verdict.get("winner_id", "")) == player.combatant_id, "engine_declares_player_winner")
	_check(String(verdict.get("loser_id", "")) == npc.instance_id, "engine_declares_correct_npc_loser")
	_check(state.get_combatant(npc.instance_id).is_death_finalized(), "engine_finalized_npc_death")
	_check(state.round_number > 0 and state.event_log.size() > 0, "real_engine_events")
	for round_number in range(1, state.round_number + 1):
		var trace: Dictionary = CombatDiagnostics.round_trace(state, round_number)
		_check(bool(trace.get("valid_event_lineage", false)), "real_duel_lineage_round_%d" % round_number)
	if not failures.is_empty():
		return

	var fake_loss: Dictionary = {"winner_id": npc.instance_id, "loser_id": player.combatant_id}
	var rejected := MapCombatOutcomeService.resolve_victory(fake_loss, map, bridge, npc, player_character,
		item_repo, NpcPossessionLootService.new(1), {"common": 100.0})
	_check(not bool(rejected.get("ok", false)), "npc_victory_cannot_award_player")
	_check(npc.is_alive() and map.entity_positions.has(npc.instance_id), "invalid_outcome_does_not_kill_map_npc")
	var repo_before := item_repo.size()

	var rewarded: Dictionary = MapCombatOutcomeService.resolve_victory(verdict, map, bridge, npc, player_character,
		item_repo, NpcPossessionLootService.new(1), {"common": 100.0})
	_check(bool(rewarded.get("ok", false)), "engine_win_accepted_by_map_outcome")
	if not bool(rewarded.get("ok", false)):
		return
	_check(npc.life_state == "dead" and not map.entity_positions.has(npc.instance_id), "real_npc_removed_from_map")
	_check(bridge.npc_at(map, npc_cell).is_empty(), "dead_npc_cannot_trigger_encounter")
	_check(int(rewarded.get("drop_count", 0)) == 1, "exactly_one_eligible_reward")
	var pool: EncounterLootPool = rewarded.get("loot_pool")
	_check(pool != null, "reward_pool_created")
	if pool == null:
		return
	_check(pool.available_for(player.combatant_id) == ["REAL_REWARD_DAGGER"], "only_winner_sees_reward")
	_check(not player_character.inventory.owns("REAL_REWARD_DAGGER"), "loot_requires_explicit_claim")
	var repo_after := item_repo.size()
	_check(repo_after >= repo_before, "reward_does_not_remove_npc_item")

	# A replayed successful battle verdict must never re-kill or re-roll loot.
	var duplicate := MapCombatOutcomeService.resolve_victory(verdict, map, bridge, npc, player_character,
		item_repo, NpcPossessionLootService.new(1), {"common": 100.0})
	_check(not bool(duplicate.get("ok", false)), "duplicate_verdict_rejected")
	_check(item_repo.size() == repo_after and pool.entries.size() == 1, "duplicate_does_not_create_drops")
	var persisted: Dictionary = pool.to_dict()
	var restored := EncounterLootPool.from_dict(persisted)
	_check(restored.available_for(player.combatant_id) == ["REAL_REWARD_DAGGER"], "loot_survives_pool_serialization")
	_check(restored.claim("REAL_REWARD_DAGGER", player_character, item_repo), "winner_claims_once")
	_check(player_character.inventory.owns("REAL_REWARD_DAGGER"), "item_added_to_real_inventory")
	_check(not restored.claim("REAL_REWARD_DAGGER", player_character, item_repo), "duplicate_claim_refused")
	_check(restored.entries.is_empty(), "claim_removes_pool_entry")
	_check(item_repo.size() == repo_after, "claim_reuses_existing_item_instance")
