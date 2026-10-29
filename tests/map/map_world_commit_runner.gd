extends SceneTree

## Real hex contact -> terminal group combat -> immutable settlement ->
## one atomic expedition/items/character snapshot -> receipt acknowledgement.
## Then reconstruct a fresh process, suppress defeated NPC respawn, claim,
## expire and persist loot without reintroducing previously completed rewards.
const CHECKPOINT := "user://boa_test_world_commit_fight.json"
const RECEIPT := "user://boa_test_world_commit_receipt.json"
const SNAPSHOT := "user://boa_test_world_commit_snapshot.json"
const ENCOUNTER := "test:world_commit:bandits_02"
const EXPEDITION_ID := "WORLD_COMMIT_TEST_EXPEDITION"
const CELL := Vector2i(5,5)
var failures: Array[String] = []

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		print("MAP_WORLD_COMMIT_CASE=FAIL ",label)

func _initialize() -> void:
	_run()
	print("MAP_WORLD_COMMIT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _world(with_items: bool = true) -> Dictionary:
	var catalog := NpcRepository.new()
	catalog.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map := TacticalMapState.new(12,12)
	var bridge := MapNpcBridge.new()
	var repo := ItemRepository.new()
	var npcs: Array[NpcInstance] = []
	if not map.place_entity("PLAYER",Vector2i(4,5)):
		return {}
	for i in range(2):
		var npc_id := "PERSIST_BANDIT_%02d" % (i+1)
		var item_id := "PERSIST_DAGGER_%02d" % (i+1)
		var npc := NpcInstance.new(npc_id,catalog.get_npc("NPC003"))
		if not bridge.register_npc(map,npc,CELL):
			return {}
		if with_items:
			if not repo.add_item({"instance_id":item_id,"generated_from_template":"TEST_DAGGER","quality":"common","durability":{"current":12,"max":20}}) or not npc.receive_item(item_id,repo):
				return {}
		npcs.append(npc)
	return {"map":map,"bridge":bridge,"catalog":catalog,"repository":repo,"npcs":npcs}

func _fighter(character: CharacterState, repo: ItemRepository) -> CombatantState:
	var pools: Dictionary = character.resource_snapshot(repo)
	var hero := TestFixtureLoader.new_combatant(character.character_id,"Map Hero",character.level,int(pools["max_hp"]),int(pools["max_mana"]))
	TestFixtureLoader.set_weapon_profiles(hero,[{"damage_min":10000.0,"damage_max":10000.0,"damage_type":"slashing"}])
	hero.combat_stats["hit_chance_rating_percent"] = 100.0
	hero.combat_stats["dodge_rating_percent"] = 100.0
	return hero

func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Public runtime entry point: settlement, HP/Mana, atomic bundle and
## journal acknowledgement must all finish BEFORE movement is released.
func _test_atomic_finish() -> void:
	var fight_path := "user://boa_test_atomic_finish_fight.json"
	var receipt_path := "user://boa_test_atomic_finish_receipt.json"
	var bundle_path := "user://boa_test_atomic_finish_bundle.json"
	var cohort_key := ENCOUNTER + ":atomic"
	var expedition_id := EXPEDITION_ID + "_ATOMIC"
	GroupCombatCheckpointService.clear(fight_path)
	_delete(receipt_path)
	_delete(bundle_path)
	var world := _world()
	_check(not world.is_empty(),"atomic_public_world_ready")
	if world.is_empty():
		return
	var character := CharacterState.new("PLAYER","Map Hero",20)
	var expedition := ExpeditionState.new(expedition_id)
	var turns := HexMapTurnService.new()
	var contact := turns.move_player(world["map"],world["bridge"],"PLAYER",CELL,RandomNumberGenerator.new())
	_check(bool(contact.get("ok",false)) and contact.has("encounter"),"atomic_public_map_contact")
	if not contact.has("encounter"):
		return
	var opened := turns.begin_resumable_group_combat(contact["encounter"],world["catalog"],_fighter(character,world["repository"]),cohort_key,fight_path)
	_check(bool(opened.get("ok",false)),"atomic_public_checkpointed_battle")
	if not bool(opened.get("ok",false)):
		return
	var simulator: GroupCombatSimulator = opened["simulator"]
	var outcome := simulator.run()
	_check(String(outcome.get("winning_team",""))=="players","atomic_public_real_fight_won")
	if String(outcome.get("winning_team",""))!="players":
		return
	_check(turns.coordinator.combat_active,"atomic_public_map_still_frozen_before_commit")
	var final := turns.finalize_group_victory_atomic(opened,cohort_key,expedition,world["map"],world["bridge"],character,world["repository"],NpcPossessionLootService.new(1),{"common":100.0},receipt_path,fight_path,bundle_path,1000)
	_check(bool(final.get("ok",false)),"atomic_public_finalize_success")
	if not bool(final.get("ok",false)):
		_check(false,"atomic_public_reason_"+String(final.get("reason","unknown"))+"_"+String(final.get("detail","")))
		return
	_check(not turns.coordinator.combat_active,"atomic_public_map_only_unpaused_after_commit")
	_check(FileAccess.file_exists(bundle_path) and not FileAccess.file_exists(receipt_path) and not FileAccess.file_exists(fight_path),"atomic_public_journals_acknowledged")
	_check(character.current_hp == simulator.state.get_combatant("PLAYER").visible_hp(),"atomic_public_hp_committed")
	var recovered := MapWorldCommitService.read(bundle_path,cohort_key,expedition_id,"PLAYER")
	_check(bool(recovered.get("ok",false)),"atomic_public_reboot_restores")
	if bool(recovered.get("ok",false)):
		var fresh_map := _world(false)
		var suppressed := MapWorldCommitService.reconcile_map(recovered["expedition"],fresh_map["map"],fresh_map["bridge"])
		_check(bool(suppressed.get("ok",false)) and int(suppressed.get("deaths_applied",-1)) == 2,"atomic_public_no_respawn_after_ack")
		_check(recovered["expedition"].restore_loot_pool(cohort_key).item_ids().size() == 2,"atomic_public_two_claimable_items")
	_check(not bool(turns.finalize_group_victory_atomic(opened,cohort_key,expedition,world["map"],world["bridge"],character,world["repository"],NpcPossessionLootService.new(1),{"common":100.0},receipt_path,fight_path,bundle_path,1000).get("ok",false)),"atomic_public_no_double_completion")
	_delete(bundle_path)
	GroupCombatCheckpointService.clear(fight_path)
	_delete(receipt_path)

func _run() -> void:
	GroupCombatCheckpointService.clear(CHECKPOINT)
	_delete(RECEIPT)
	_delete(SNAPSHOT)
	var world := _world()
	_check(not world.is_empty(),"world_ready")
	if world.is_empty():
		return
	var character := CharacterState.new("PLAYER","Map Hero",20)
	var expedition := ExpeditionState.new(EXPEDITION_ID)
	var turns := HexMapTurnService.new()
	var contact := turns.move_player(world["map"],world["bridge"],"PLAYER",CELL,RandomNumberGenerator.new())
	_check(bool(contact.get("ok",false)) and contact.has("encounter"),"map_encounter_contact")
	if not contact.has("encounter"):
		return
	var session := turns.begin_resumable_group_combat(contact["encounter"],world["catalog"],_fighter(character,world["repository"]),ENCOUNTER,CHECKPOINT)
	_check(bool(session.get("ok",false)),"resumable_session_open")
	if not bool(session.get("ok",false)):
		return
	var simulator: GroupCombatSimulator = session["simulator"]
	var verdict := simulator.run()
	_check(String(verdict.get("winning_team","")) == "players","canonical_player_victory")
	_check(simulator.controller.combat_finished() and FileAccess.file_exists(CHECKPOINT),"committed_terminal_checkpoint")
	if String(verdict.get("winning_team","")) != "players":
		return
	var world_result := turns.resolve_group_victory_durable(session,expedition,world["map"],world["bridge"],character,world["repository"],NpcPossessionLootService.new(1),{"common":100.0},ENCOUNTER,RECEIPT,1000)
	_check(bool(world_result.get("ok",false)),"durable_world_outcome")
	_check(FileAccess.file_exists(RECEIPT) and FileAccess.file_exists(CHECKPOINT),"journal_survives_until_world_commit")
	if not bool(world_result.get("ok",false)):
		_check(false,"outcome_reason_"+String(world_result.get("reason","unknown")))
		return
	_check(not bool(MapWorldCommitService.acknowledge(SNAPSHOT,RECEIPT,CHECKPOINT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"ack_without_snapshot_denied")
	_check(FileAccess.file_exists(RECEIPT) and FileAccess.file_exists(CHECKPOINT),"early_ack_never_deletes_journals")

	# A combatant and a persistent CharacterState have different ownership;
	# stale character HP/Mana may not be written as a successful world commit.
	character.current_mana = -1
	var premature := MapWorldCommitService.commit(session,ENCOUNTER,expedition,world["map"],world["bridge"],character,world["repository"],RECEIPT,CHECKPOINT,SNAPSHOT)
	_check(not bool(premature.get("ok",false)) and String(premature.get("reason","")) == "world_commit_combat_resources_not_committed","prebattle_character_resources_rejected")
	_check(not FileAccess.file_exists(SNAPSHOT),"no_snapshot_for_stale_combat_resources")
	var won: CombatantState = simulator.state.get_combatant("PLAYER")
	_check(character.commit_combat_resources(won,world["repository"]),"canonical_combat_resources_committed")
	var committed := MapWorldCommitService.commit(session,ENCOUNTER,expedition,world["map"],world["bridge"],character,world["repository"],RECEIPT,CHECKPOINT,SNAPSHOT)
	_check(bool(committed.get("ok",false)),"atomic_world_snapshot_committed")
	if not bool(committed.get("ok",false)):
		_check(false,"snapshot_reason_"+String(committed.get("reason","unknown"))+"_"+String(committed.get("detail","")))
		return
	_check(FileAccess.file_exists(SNAPSHOT) and FileAccess.file_exists(RECEIPT) and FileAccess.file_exists(CHECKPOINT),"verified_snapshot_precedes_cleanup")
	var decoded := MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER")
	_check(bool(decoded.get("ok",false)),"snapshot_reloads_all_owners")
	if not bool(decoded.get("ok",false)):
		_check(false,"read_reason_"+String(decoded.get("reason","unknown")))
		return
	_check(decoded["repository"].size() == 2 and decoded["character"].inventory.size() == 0,"repository_and_inventory_stored_atomically")
	_check(decoded["character"].current_hp == character.current_hp and decoded["character"].current_mana == character.current_mana,"combat_hp_and_mana_survive_restart")
	_check(decoded["expedition"].restore_loot_pool(ENCOUNTER).available_for("PLAYER").size() == 2,"loot_entitlements_stored_atomically")
	_check(not bool(MapWorldCommitService.read(SNAPSHOT,"different_encounter",EXPEDITION_ID,"PLAYER").get("ok",false)),"wrong_encounter_cannot_reuse_snapshot")
	_check(not bool(MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"OTHER").get("ok",false)),"wrong_character_cannot_reuse_snapshot")

	# A truncated/modified world snapshot must never authorize cleanup,
	# even if both old combat journals are still perfectly valid.
	var unmodified_world := FileAccess.get_file_as_string(SNAPSHOT)
	var before_ack_bad: Variant = JSON.parse_string(unmodified_world)
	if before_ack_bad is Dictionary:
		before_ack_bad["sha256"] = "corrupted"
		var bad_writer := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
		if bad_writer != null:
			bad_writer.store_string(JSON.stringify(before_ack_bad))
			bad_writer.close()
		_check(not bool(MapWorldCommitService.acknowledge(SNAPSHOT,RECEIPT,CHECKPOINT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"corrupted_bundle_cannot_acknowledge")
		_check(FileAccess.file_exists(RECEIPT) and FileAccess.file_exists(CHECKPOINT),"failed_ack_preserves_source_journals")
		var restored_writer := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
		if restored_writer != null:
			restored_writer.store_string(unmodified_world)
			restored_writer.close()

	# Acknowledge only after a FULL independent disk read.
	var ack := MapWorldCommitService.acknowledge(SNAPSHOT,RECEIPT,CHECKPOINT,ENCOUNTER,EXPEDITION_ID,"PLAYER")
	_check(bool(ack.get("ok",false)),"verified_world_allows_ack")
	_check(not FileAccess.file_exists(RECEIPT) and not FileAccess.file_exists(CHECKPOINT) and FileAccess.file_exists(SNAPSHOT),"only_redundant_journals_removed")
	_check(bool(MapWorldCommitService.acknowledge(SNAPSHOT,RECEIPT,CHECKPOINT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"ack_replay_safe")

	# Recovery MUST use the authoritative world bundle after journals clear.
	# A regenerated map starts with both bandits alive.
	var new_world := _world(false)
	_check(not new_world.is_empty(),"fresh_world_rebuilt")
	if new_world.is_empty():
		return
	var restored: Dictionary = MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER")
	if not bool(restored.get("ok",false)):
		_check(false,"snapshot_unavailable_after_ack")
		return
	var persisted_expedition: ExpeditionState = restored["expedition"]
	var persisted_character: CharacterState = restored["character"]
	var persisted_repo: ItemRepository = restored["repository"]
	_check(MapWorldCommitService.is_defeated_spawn(persisted_expedition,"PERSIST_BANDIT_01") and MapWorldCommitService.is_defeated_spawn(persisted_expedition,"PERSIST_BANDIT_02"),"spawn_guard_remembers_completed_cohort")
	_check(not MapWorldCommitService.is_defeated_spawn(persisted_expedition,"OTHER_NPC"),"unrelated_npc_still_spawnable")
	# A wrong NPC location must reject ALL mutations, not half-kill a group.
	new_world["map"].entity_positions["PERSIST_BANDIT_02"] = Vector2i(6,5)
	var wrong_location := MapWorldCommitService.reconcile_map(persisted_expedition,new_world["map"],new_world["bridge"])
	_check(not bool(wrong_location.get("ok",false)),"relocated_npc_rejected")
	_check(new_world["npcs"][0].is_alive() and new_world["npcs"][1].is_alive(),"failed_reconcile_never_partially_kills")
	new_world["map"].entity_positions["PERSIST_BANDIT_02"] = CELL
	var recovered := MapWorldCommitService.reconcile_map(persisted_expedition,new_world["map"],new_world["bridge"])
	_check(bool(recovered.get("ok",false)) and int(recovered.get("deaths_applied",-1)) == 2,"regenerated_npcs_killed_from_snapshot")
	_check(new_world["bridge"].npc_at(new_world["map"],CELL).is_empty(),"dead_npcs_never_retrigger")
	var second_recovery := MapWorldCommitService.reconcile_map(persisted_expedition,new_world["map"],new_world["bridge"])
	_check(bool(second_recovery.get("ok",false)) and int(second_recovery.get("deaths_applied",-1)) == 0,"map_replay_no_duplicate_deaths")

	# A claim after acknowledgement still needs its own atomic update.
	_check(persisted_expedition.claim_loot_at_hex(persisted_character,CELL,"PERSIST_DAGGER_01",persisted_repo,1100),"first_coin_claim")
	_check(persisted_character.inventory.owns("PERSIST_DAGGER_01"),"claimed_item_in_real_inventory")
	var claim_commit := MapWorldCommitService.save_progress(SNAPSHOT,ENCOUNTER,persisted_expedition,persisted_character,persisted_repo)
	_check(bool(claim_commit.get("ok",false)),"claimed_loot_durably_saved")
	_check(not bool(MapWorldCommitService.save_progress(SNAPSHOT,ENCOUNTER,decoded["expedition"],decoded["character"],decoded["repository"]).get("ok",false)),"old_snapshot_cannot_resurrect_claimed_coin")
	var after_claim := MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER")
	_check(bool(after_claim.get("ok",false)) and after_claim["character"].inventory.owns("PERSIST_DAGGER_01"),"claim_survives_full_process_restart")
	_check(after_claim["expedition"].restore_loot_pool(ENCOUNTER).available_for("PLAYER") == ["PERSIST_DAGGER_02"],"claim_not_duplicated")
	_check(after_claim["repository"].size() == 2,"claim_retains_original_item_instances")
	var before_expiry_expedition := ExpeditionState.from_dict(after_claim["expedition"].to_dict())
	var before_expiry_repository := ItemRepository.from_dict(after_claim["repository"].to_dict())

	# The remaining coin expires (15-minute TTL), and the permanent marker
	# survives even when the pool disappears from the expedition entirely.
	_check(after_claim["expedition"].cleanup_expired_loot(2000,after_claim["repository"]) == 1,"unclaimed_coin_expires")
	var expiry_commit := MapWorldCommitService.save_progress(SNAPSHOT,ENCOUNTER,after_claim["expedition"],after_claim["character"],after_claim["repository"])
	_check(bool(expiry_commit.get("ok",false)),"expiry_cleanup_durably_saved")
	var after_expiry := MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER")
	_check(bool(after_expiry.get("ok",false)) and after_expiry["expedition"].restore_loot_pool(ENCOUNTER) == null,"expired_reward_not_recreated")
	_check(after_expiry["character"].inventory.owns("PERSIST_DAGGER_01") and after_expiry["repository"].size() == 1,"claimed_item_survives_expired_coin")
	_check(not bool(MapWorldCommitService.save_progress(SNAPSHOT,ENCOUNTER,before_expiry_expedition,after_claim["character"],before_expiry_repository).get("ok",false)),"expired_pool_cannot_return")

	# An altered snapshot is rejected; it never silently creates a new world.
	var original := FileAccess.get_file_as_string(SNAPSHOT)
	var corrupt: Variant = JSON.parse_string(original)
	if corrupt is Dictionary:
		corrupt["sha256"] = "invalid"
		var file := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(corrupt))
			file.close()
		_check(not bool(MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"corrupted_snapshot_rejected")
		var repaired := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
		if repaired != null:
			repaired.store_string(original)
			repaired.close()
	_check(bool(MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"valid_snapshot_restored")
	# Recomputing an envelope checksum must not bypass structure checks:
	# a malformed receipt roster is rejected before any map is loaded.
	var rewritten: Variant = JSON.parse_string(original)
	if rewritten is Dictionary:
		var altered_payload: Variant = JSON.parse_string(String(rewritten["payload_json"]))
		if altered_payload is Dictionary:
			altered_payload["receipt"]["npc_ids"] = "not_an_array"
			var new_raw := JSON.stringify(altered_payload)
			rewritten["payload_json"] = new_raw
			rewritten["sha256"] = new_raw.sha256_text()
			var mutation := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
			if mutation != null:
				mutation.store_string(JSON.stringify(rewritten))
				mutation.close()
			_check(not bool(MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"rehashed_malformed_roster_rejected")
			var rollback := FileAccess.open(SNAPSHOT,FileAccess.WRITE)
			if rollback != null:
				rollback.store_string(original)
				rollback.close()
	_check(bool(MapWorldCommitService.read(SNAPSHOT,ENCOUNTER,EXPEDITION_ID,"PLAYER").get("ok",false)),"valid_snapshot_survives_negative_tests")
	_test_atomic_finish()
	_delete(SNAPSHOT)
	GroupCombatCheckpointService.clear(CHECKPOINT)
	_delete(RECEIPT)
