extends SceneTree

## World encounter -> canonical group simulator -> durable terminal round ->
## immutable reward staging -> idempotent map/ExpeditionState replay.
## Covers crash windows before world mutation, after world mutation, after
## expedition snapshot reload, and after an item has already been claimed.
const CHECKPOINT := "user://boa_test_world_settlement_round_v1.json"
const RECEIPT := "user://boa_test_world_settlement_receipt_v1.json"
const ENCOUNTER := "test_expedition:bandit_cohort_02"
const EXPEDITION := "EXPEDITION_SETTLEMENT_001"
const CELL := Vector2i(5,5)
var failures: Array[String] = []

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		print("MAP_SETTLEMENT_CASE=FAIL ",label)

func _initialize() -> void:
	_run()
	print("MAP_SETTLEMENT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _world(with_items: bool = true) -> Dictionary:
	var catalog := NpcRepository.new()
	catalog.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map := TacticalMapState.new(12,12)
	var bridge := MapNpcBridge.new()
	var repo := ItemRepository.new()
	var npcs: Array[NpcInstance] = []
	map.place_entity("PLAYER",Vector2i(4,5))
	for i in range(2):
		var npc_id := "WORLD_BANDIT_%02d" % (i+1)
		var item_id := "WORLD_DAGGER_%02d" % (i+1)
		var npc := NpcInstance.new(npc_id,catalog.get_npc("NPC003"))
		if not bridge.register_npc(map,npc,CELL):
			return {}
		if with_items:
			if not repo.add_item({"instance_id":item_id,"generated_from_template":"TEST_DAGGER","quality":"common","durability":{"current":15,"max":20}}):
				return {}
			if not npc.receive_item(item_id,repo):
				return {}
		npcs.append(npc)
	return {"catalog":catalog,"map":map,"bridge":bridge,"repo":repo,"npcs":npcs}

func _hero() -> CombatantState:
	var p := TestFixtureLoader.new_combatant("PLAYER","Map Hero",30,12000,500)
	TestFixtureLoader.set_weapon_profiles(p,[{"damage_min":5000.0,"damage_max":5000.0,"damage_type":"slashing"}])
	p.combat_stats["hit_chance_rating_percent"] = 100.0
	return p

func _expedition() -> ExpeditionState:
	return ExpeditionState.new(EXPEDITION)

func _check_dead(world: Dictionary,label: String) -> void:
	for npc in world["npcs"]:
		_check(npc.life_state == "dead" and not world["map"].entity_positions.has(npc.instance_id),label+"_"+npc.instance_id)
	_check(world["bridge"].npc_at(world["map"],CELL).is_empty(),label+"_cannot_retrigger")

func _run() -> void:
	GroupCombatCheckpointService.clear(CHECKPOINT)
	if FileAccess.file_exists(RECEIPT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECEIPT))
	var world := _world()
	_check(not world.is_empty(),"world_exists")
	if world.is_empty():
		return
	var character := CharacterState.new("PLAYER","Map Hero",30)
	var expedition := _expedition()
	var turns := HexMapTurnService.new()
	var moved: Dictionary = turns.move_player(world["map"],world["bridge"],"PLAYER",CELL,RandomNumberGenerator.new())
	_check(bool(moved.get("ok",false)) and moved.has("encounter"),"real_map_contact_opens_encounter")
	_check(turns.coordinator.combat_active,"map_paused_during_active_encounter")
	if not moved.has("encounter"):
		return
	var session := turns.begin_resumable_group_combat(moved["encounter"],world["catalog"],_hero(),ENCOUNTER,CHECKPOINT)
	_check(bool(session.get("ok",false)),"battle_opens_resumable")
	if not bool(session.get("ok",false)):
		return
	var premature := MapCombatSettlementService.stage(session,expedition,world["map"],world["bridge"],character,world["repo"],NpcPossessionLootService.new(11),{"common":100.0},ENCOUNTER,RECEIPT,1000)
	_check(not bool(premature.get("ok",false)) and not FileAccess.file_exists(RECEIPT),"nonterminal_cannot_stage_reward")
	var sim: GroupCombatSimulator = session["simulator"]
	var battle_result: Dictionary = sim.run()
	_check(String(battle_result.get("winning_team","")) == "players","real_engine_player_win")
	_check(sim.controller.combat_finished() and sim.state.round_number > 0 and FileAccess.file_exists(CHECKPOINT),"durable_terminal_checkpoint")
	if not sim.controller.combat_finished() or not FileAccess.file_exists(CHECKPOINT):
		return
	# Crash window A: prepare a durable result WITHOUT killing a single NPC.
	var staged := MapCombatSettlementService.stage(session,expedition,world["map"],world["bridge"],character,world["repo"],NpcPossessionLootService.new(11),{"common":100.0},ENCOUNTER,RECEIPT,1000)
	_check(bool(staged.get("ok",false)),"reward_receipt_staged")
	if not bool(staged.get("ok",false)):
		_check(false,"stage_reason_"+String(staged.get("reason","unknown")))
		return
	_check(FileAccess.file_exists(RECEIPT) and not bool(staged.get("already_staged",true)),"receipt_precedes_world_mutation")
	_check(world["npcs"][0].is_alive() and world["npcs"][1].is_alive(),"stage_does_not_kill_npcs")
	_check(expedition.restore_loot_pool(ENCOUNTER) == null,"stage_does_not_spawn_loot")
	var staged_again := MapCombatSettlementService.stage(session,expedition,world["map"],world["bridge"],character,world["repo"],NpcPossessionLootService.new(9999),{"common":0.0},ENCOUNTER,RECEIPT,2000)
	_check(bool(staged_again.get("ok",false)) and bool(staged_again.get("already_staged",false)),"staged_result_cannot_reroll")

	# Crash window A: reconstructed world uses ONLY the durable receipt.
	var after_crash := _world(false)
	var blank_expedition := _expedition()
	var recovered_turns := HexMapTurnService.new()
	var replay := recovered_turns.recover_settled_group_victory(RECEIPT,ENCOUNTER,blank_expedition,after_crash["map"],after_crash["bridge"],character,after_crash["repo"])
	_check(bool(replay.get("ok",false)) and not bool(replay.get("already_applied",true)),"replay_preapply_crash")
	if not bool(replay.get("ok",false)):
		_check(false,"replay_reason_"+String(replay.get("reason","unknown")))
		return
	_check_dead(after_crash,"replay_death")
	_check(not recovered_turns.coordinator.combat_active,"recovery_releases_map_pause")
	# Normal caller can also settle the already staged outcome without
	# rerolling, and releases the same map's encounter pause.
	var normal_commit := turns.resolve_group_victory_durable(session,expedition,world["map"],world["bridge"],character,world["repo"],NpcPossessionLootService.new(9999),{"common":0.0},ENCOUNTER,RECEIPT,2000)
	_check(bool(normal_commit.get("ok",false)) and bool(normal_commit.get("already_staged",false)) and not turns.coordinator.combat_active,"real_hex_turn_lifecycle_finishes_after_durable_receipt")
	_check_dead(world,"normal_flow_death")
	_check(expedition.restore_loot_pool(ENCOUNTER) != null and expedition.restore_loot_pool(ENCOUNTER).item_ids().size() == 2,"normal_flow_reward_reuses_staged_roll")
	_check(after_crash["repo"].has_item("WORLD_DAGGER_01") and after_crash["repo"].has_item("WORLD_DAGGER_02"),"restore_missing_reward_item_instances")
	var recovered_pool := blank_expedition.restore_loot_pool(ENCOUNTER)
	_check(recovered_pool != null,"replay_restores_claimable_pool")
	if recovered_pool == null:
		return
	_check(recovered_pool.available_for("PLAYER").size() == 2,"two_rewards_exactly_once")
	var replay_twice := MapCombatSettlementService.apply(RECEIPT,ENCOUNTER,blank_expedition,after_crash["map"],after_crash["bridge"],character,after_crash["repo"])
	_check(bool(replay_twice.get("ok",false)) and bool(replay_twice.get("already_applied",false)),"same_world_apply_is_idempotent")
	_check(blank_expedition.restore_loot_pool(ENCOUNTER).entries.size() == 2,"duplicate_apply_never_doubles_loot")

	# Crash window B: expedition and repository survive restart, whereas
	# the map is regenerated and all NPCs initially appear alive again.
	var saved_expedition: Variant = JSON.parse_string(JSON.stringify(blank_expedition.to_dict()))
	var saved_repo: Variant = JSON.parse_string(JSON.stringify(after_crash["repo"].to_dict()))
	var after_reload := _world(false)
	var continued_exp := ExpeditionState.from_dict(saved_expedition)
	var continued_repo := ItemRepository.from_dict(saved_repo)
	var restarted_turns := HexMapTurnService.new()
	var replay_again := restarted_turns.recover_settled_group_victory(RECEIPT,ENCOUNTER,continued_exp,after_reload["map"],after_reload["bridge"],character,continued_repo)
	_check(bool(replay_again.get("ok",false)) and bool(replay_again.get("already_applied",false)),"restore_after_world_snapshot")
	_check_dead(after_reload,"reloaded_map_suppresses_npcs")
	_check(continued_exp.restore_loot_pool(ENCOUNTER).available_for("PLAYER").size()==2,"persisted_rewards_are_not_rerolled")

	# Loot claimed once must NOT be resurrected by a later receipt replay.
	_check(continued_exp.claim_loot_at_hex(character,CELL,"WORLD_DAGGER_01",continued_repo,1100),"first_item_claimed")
	_check(character.inventory.owns("WORLD_DAGGER_01"),"claim_in_real_player_inventory")
	var after_claim := MapCombatSettlementService.apply(RECEIPT,ENCOUNTER,continued_exp,after_reload["map"],after_reload["bridge"],character,continued_repo)
	_check(bool(after_claim.get("ok",false)) and bool(after_claim.get("already_applied",false)),"after_claim_replay_allowed")
	_check(continued_exp.restore_loot_pool(ENCOUNTER).available_for("PLAYER") == ["WORLD_DAGGER_02"],"claimed_loot_never_recreated")
	_check(continued_repo.size() == 2,"no_duplicate_item_instances")
	_check(not continued_exp.claim_loot_at_hex(character,CELL,"WORLD_DAGGER_01",continued_repo,1100),"same_item_claim_twice_denied")

	# A journal is bound to one expedition / encounter / winner.
	_check(not bool(MapCombatSettlementService.read(RECEIPT,"other_cohort",EXPEDITION,"PLAYER").get("ok",false)),"wrong_encounter_rejected")
	_check(not bool(MapCombatSettlementService.read(RECEIPT,ENCOUNTER,"other_expedition","PLAYER").get("ok",false)),"wrong_expedition_rejected")
	_check(not bool(MapCombatSettlementService.read(RECEIPT,ENCOUNTER,EXPEDITION,"OTHER").get("ok",false)),"wrong_player_rejected")
	_check(FileAccess.file_exists(CHECKPOINT) and FileAccess.file_exists(RECEIPT),"checkpoint_and_receipt_retained_until_world_durable")

	var original_receipt := FileAccess.get_file_as_string(RECEIPT)
	var tampered: Variant = JSON.parse_string(original_receipt)
	if tampered is Dictionary:
		tampered["sha256"] = "bad"
		var out := FileAccess.open(RECEIPT,FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify(tampered))
			out.close()
		var bad := MapCombatSettlementService.read(RECEIPT,ENCOUNTER,EXPEDITION,"PLAYER")
		_check(not bool(bad.get("ok",false)) and String(bad.get("reason","")) == "settlement_integrity_failed","tampered_receipt_rejected")
		out = FileAccess.open(RECEIPT,FileAccess.WRITE)
		if out != null:
			out.store_string(original_receipt)
			out.close()
	_check(bool(MapCombatSettlementService.read(RECEIPT,ENCOUNTER,EXPEDITION,"PLAYER").get("ok",false)),"untampered_receipt_recovered")
	GroupCombatCheckpointService.clear(CHECKPOINT)
	if FileAccess.file_exists(RECEIPT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECEIPT))
