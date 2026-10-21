extends SceneTree

const EXP := "user://test_live_resume_expedition.json"
const TOWN := "user://test_live_resume_town.json"
const MANIFEST := "user://test_live_resume_manifest.json"
const ID := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		print("LIVE_COMBAT_RESUME_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true

func _initialize() -> void:
	var artifacts := SoloLiveNpcCombat._paths(ID,"solo_npc_bandit_01")
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
	var player := CharacterState.new("player","Hero",20)
	var repo := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,player,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,123,Vector2i(6,5),player,repo,MANIFEST).get("ok",false)),"world_saved")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(bool(opened.get("ok",false)),"world_opened")
	if not bool(opened.get("ok",false)):
		quit(1)
		return
	var session: SoloLiveMapSession = opened["session"]
	var begun := SoloLiveNpcCombat.start(session,Vector2i(7,5))
	check(bool(begun.get("ok",false)),"combat_begun")
	if not bool(begun.get("ok",false)):
		print("LIVE_RESUME_START_REASON=",begun.get("reason",""))
		quit(1)
		return
	var combat: SoloLiveNpcCombat = begun["combat"]
	var progressed := combat.play_round()
	check(bool(progressed.get("ok",false)),"first_combat_round_checkpointed")
	var last_round := combat.battle["simulator"].state.round_number
	check(last_round == 1,"first_round_number")
	check(FileAccess.file_exists(combat.checkpoint_path),"round_checkpoint_exists")
	var checkpoint_text := FileAccess.get_file_as_string(combat.checkpoint_path)
	var revision := ExpeditionSaveService._read_payload_envelope(EXP)
	check(bool(revision.get("ok",false)),"prebattle_revision_readable")
	var base_sha := String(revision.get("sha256",""))
	check(not bool(SoloLiveMapSession.open(EXP,MANIFEST,ID,"player").get("ok",false)),"normal_map_entry_blocks_pending")
	# A missing checkpoint must never turn the manifest into a new combat.
	wipe(combat.checkpoint_path)
	var missing_session := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,"player")
	check(bool(missing_session.get("ok",false)),"missing_checkpoint_still_mounts_locked_world")
	if bool(missing_session.get("ok",false)):
		var missing := SoloLiveNpcCombat.resume(missing_session["session"])
		check(not bool(missing.get("ok",false)) and String(missing.get("reason",""))=="resume_checkpoint_missing_or_terminal","missing_checkpoint_fails_closed")
		check(not bool(missing_session["session"].move_one_step(Vector2i(5,5)).get("ok",false)),"missing_checkpoint_cannot_move")
	check(FileAccess.file_exists(MANIFEST),"missing_checkpoint_keeps_manifest")
	check(write_text(combat.checkpoint_path,"{corrupt checkpoint"),"corrupt_checkpoint_written")
	var broken_session := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,"player")
	check(bool(broken_session.get("ok",false)),"corrupt_checkpoint_still_mounts_locked_world")
	if bool(broken_session.get("ok",false)):
		var broken := SoloLiveNpcCombat.resume(broken_session["session"])
		check(not bool(broken.get("ok",false)) and String(broken.get("reason",""))=="resume_checkpoint_rejected","corrupt_checkpoint_fails_closed")
	check(FileAccess.file_exists(MANIFEST),"corrupt_checkpoint_keeps_manifest")
	check(not FileAccess.file_exists(combat.receipt_path) and not FileAccess.file_exists(combat.terminal_path),"invalid_resume_never_mints_rewards")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==base_sha,"invalid_resume_does_not_mutate_world")
	check(write_text(combat.checkpoint_path,checkpoint_text),"original_checkpoint_restored_for_test")
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,"player")
	check(bool(pending.get("ok",false)),"prebattle_world_restored")
	if bool(pending.get("ok",false)):
		var pending_session: SoloLiveMapSession = pending["session"]
		check(not bool(pending_session.move_one_step(Vector2i(5,5)).get("ok",false)),"pending_map_cannot_move")
		check(not bool(pending_session.return_to_town(TOWN).get("ok",false)),"pending_map_cannot_exit")
		var resumed := SoloLiveNpcCombat.resume(pending_session)
		check(bool(resumed.get("ok",false)),"real_checkpoint_resumed")
		if not bool(resumed.get("ok",false)):
			print("LIVE_RESUME_REASON=",resumed.get("reason",""),":",resumed.get("detail",""))
		else:
			var resumed_combat: SoloLiveNpcCombat = resumed["combat"]
			check(bool(resumed_combat.battle.get("resumed",false)),"old_combat_reused")
			check(resumed_combat.battle["simulator"].state.round_number==last_round,"round_not_replayed")
			check(resumed_combat.target_cell==Vector2i(7,5),"npc_contact_restored")
			check(Array(resumed_combat.battle.get("npc_instance_ids",[]))==Array(combat.battle.get("npc_instance_ids",[])),"npc_roster_identical")
			var original_sim: GroupCombatSimulator = combat.battle["simulator"]
			var restored_sim: GroupCombatSimulator = resumed_combat.battle["simulator"]
			check(restored_sim.state.next_event_id==original_sim.state.next_event_id and restored_sim.state.event_log.size()==original_sim.state.event_log.size(),"event_history_not_replayed")
			check(restored_sim.state.get_combatant("player").hp==original_sim.state.get_combatant("player").hp and restored_sim.state.get_combatant("solo_npc_bandit_01").hp==original_sim.state.get_combatant("solo_npc_bandit_01").hp,"combatant_hp_restored_exactly")
			check(FileAccess.get_file_as_string(combat.checkpoint_path)==checkpoint_text,"resume_does_not_rewrite_checkpoint")
			check(not FileAccess.file_exists(combat.receipt_path) and not FileAccess.file_exists(combat.terminal_path),"resume_does_not_generate_rewards")
			var next := resumed_combat.play_round()
			var state := String(next.get("state",""))
			check((bool(next.get("ok",false)) and state in ["ongoing","victory"]) or state=="defeat_pending_resolution","resumed_combat_advances_or_finalizes")
			check(restored_sim.state.round_number==last_round+1,"resumed_round_advances_once")
			if state=="victory":
				check(not FileAccess.file_exists(MANIFEST),"victory_published_once")
				var winner_world := ExpeditionSaveService.read(EXP,ID,"player")
				check(bool(winner_world.get("ok",false)),"published_winner_can_reload")
				if bool(winner_world.get("ok",false)):
					var markers: Dictionary = winner_world["expedition"].world_state.get(MapCombatSettlementService.MARKER_KEY,{})
					check(markers.has(combat.encounter_key) and markers.size()==1,"victory_has_single_settlement_marker")
					var saved_revision := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
					var repeat := ExpeditionSaveService.recover_pending_combat(EXP,combat.terminal_path,combat.encounter_key,ID,"player",base_sha)
					check(bool(repeat.get("ok",false)) and bool(repeat.get("already_published",false)),"duplicate_publication_idempotent")
					check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==saved_revision,"repeated_publication_does_not_write_rewards")
			elif state in ["ongoing","defeat_pending_resolution"]:
				check(FileAccess.file_exists(MANIFEST) and FileAccess.file_exists(combat.checkpoint_path),"unfinished_result_retains_manifest_and_checkpoint")
	var world := ExpeditionSaveService.read(EXP,ID,"player")
	check(bool(world.get("ok",false)),"world_remains_readable_after_resume")
	if bool(world.get("ok",false)) and FileAccess.file_exists(MANIFEST):
		check(world["expedition"].player_position==Vector2i(6,5),"prebattle_position_remains_authoritative")
	for path in [EXP,TOWN,MANIFEST,combat.checkpoint_path,combat.receipt_path,combat.terminal_path]:
		wipe(path)
	print("LIVE_COMBAT_RESUME_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
