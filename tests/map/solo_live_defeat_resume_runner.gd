extends SceneTree

## Defeat must be a separate durable outcome: no NPC tombstones, no loot,
## no stale checkpoint reuse; terminal retry and crash gaps are idempotent.
const EXP := "user://test_live_defeat_exp.json"
const TOWN := "user://test_live_defeat_town.json"
const MANIFEST := "user://test_live_defeat_manifest.json"
const ID := "solo_exp_defeat_player"
const PLAYER := "player"
const BANDIT := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_DEFEAT_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("LIVE_DEFEAT_RESUME_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _terminal_loss(combat: SoloLiveNpcCombat, label: String) -> bool:
	var simulator: GroupCombatSimulator = combat.battle["simulator"]
	simulator.engine.combat_rng.seed = 20261021
	for n in range(80):
		if simulator.controller.combat_finished():
			break
		var result: Dictionary = simulator.run_round()
		if not bool(result.get("ok",false)) or not bool(result.get("checkpoint_ok",false)):
			check(false,label+"_round_failed_"+str(n+1)+"_"+String(result.get("reason",result.get("checkpoint_reason","unknown"))))
			return false
	var hero: CombatantState = simulator.state.get_combatant(PLAYER)
	var loss := simulator.controller.combat_finished() and simulator.controller.winning_team() != "players" and hero != null and hero.is_death_finalized()
	check(loss,label+"_real_engine_terminal_defeat")
	check(FileAccess.file_exists(combat.checkpoint_path),label+"_checkpoint_kept")
	return loss

func _run() -> void:
	var attempt1 := SoloLiveNpcCombat._paths(ID,BANDIT)
	var attempt2 := SoloLiveNpcCombat._paths(ID,BANDIT,2)
	for path in [EXP,TOWN,MANIFEST,
		String(attempt1["checkpoint"]),String(attempt1["receipt"]),String(attempt1["terminal"]),
		String(attempt2["checkpoint"]),String(attempt2["receipt"]),String(attempt2["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Defeat Hero",1)
	hero.current_hp = 1
	var repo := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,789,START,hero,repo,MANIFEST).get("ok",false)),"expedition_created")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(opened.get("ok",false)),"map_opened")
	if not bool(opened.get("ok",false)):
		return
	var session: SoloLiveMapSession = opened["session"]
	check(session.expedition.world_state.get(SoloTownExpeditionBridge.START_CELL_KEY,[]) == [START.x,START.y],"starting_cell_persisted")
	var started := SoloLiveNpcCombat.start(session,TARGET)
	check(bool(started.get("ok",false)),"real_npc_contact_started")
	if not bool(started.get("ok",false)):
		print("LIVE_DEFEAT_START_REASON=",started.get("reason","unknown"))
		return
	var combat: SoloLiveNpcCombat = started["combat"]
	check(combat.encounter_key == String(attempt1["encounter_key"]),"first_attempt_identity")
	if not _terminal_loss(combat,"first"):
		return
	var before := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	check(FileAccess.file_exists(MANIFEST) and not FileAccess.file_exists(combat.terminal_path),"loss_not_yet_published")
	var locked := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(locked.get("ok",false)),"reopen_world_for_terminal_loss")
	if not bool(locked.get("ok",false)):
		return
	var resume := SoloLiveNpcCombat.resume(locked["session"])
	check(bool(resume.get("ok",false)),"losing_checkpoint_restored")
	if not bool(resume.get("ok",false)):
		print("LIVE_DEFEAT_RESTORE_REASON=",resume.get("reason","unknown"),":",resume.get("detail",""))
		return
	var recovered: SoloLiveNpcCombat = resume["combat"]
	var prior_round: int = int(recovered.battle["simulator"].state.round_number)
	var prior_event: int = int(recovered.battle["simulator"].state.next_event_id)
	var resolved := recovered.play_round()
	check(bool(resolved.get("ok",false)) and String(resolved.get("state",""))=="defeat","terminal_defeat_published")
	if not bool(resolved.get("ok",false)):
		print("LIVE_DEFEAT_SETTLEMENT_REASON=",resolved.get("reason","unknown"),":",resolved.get("detail",""))
		return
	check(recovered.battle["simulator"].state.round_number==prior_round and recovered.battle["simulator"].state.next_event_id==prior_event,"defeat_cannot_replay_terminal_round")
	check(not FileAccess.file_exists(MANIFEST),"defeat_manifest_cleared")
	var published := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(published.get("ok",false)),"canonical_defeat_save_valid")
	if not bool(published.get("ok",false)):
		return
	var exp1: ExpeditionState = published["expedition"]
	var ledger1: Dictionary = exp1.world_state.get(SoloCombatDefeatService.LEDGER_KEY,{})
	check(ledger1.size()==1 and ledger1.has(combat.encounter_key),"defeat_ledger_published_once")
	check(exp1.player_position==START,"retreated_to_saved_start")
	check(published["character"].current_hp>0,"hero_revived_after_retreat")
	check(published["repository"].size()==0 and published["character"].inventory.size()==0,"inventory_and_repository_unchanged")
	check(Dictionary(exp1.world_state.get(MapCombatSettlementService.MARKER_KEY,{})).is_empty(),"no_victory_receipt_on_loss")
	check(Dictionary(exp1.world_state.get(MapWorldCommitService.TOMBSTONES_KEY,{})).is_empty(),"no_enemy_tombstones_on_loss")
	check(GroundLootService.items_at(exp1,TARGET,PLAYER).is_empty(),"no_ground_reward_on_loss")
	var once_sha := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var manifest_one := {
		"expedition_path":EXP,"terminal_path":combat.terminal_path,"checkpoint_path":combat.checkpoint_path,
		"encounter_key":combat.encounter_key,"expedition_id":ID,"player_id":PLAYER,"base_sha256":before
	}
	var again := SoloCombatDefeatService.recover(manifest_one)
	check(bool(again.get("ok",false)) and bool(again.get("already_published",false)),"defeat_publish_idempotent")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==once_sha,"no_second_defeat_write")
	var fresh := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(fresh.get("ok",false)),"live_map_reopened_after_defeat")
	if not bool(fresh.get("ok",false)):
		return
	var fresh_session: SoloLiveMapSession = fresh["session"]
	check(fresh_session.npc_bridge.instances.has(BANDIT),"living_bandit_still_on_map")
	# Simulate a badly injured player for the SECOND real attempt.
	fresh_session.character.current_hp = 1
	check(bool(ExpeditionSaveService.save(EXP,fresh_session.expedition,fresh_session.character,fresh_session.repository).get("ok",false)),"second_attempt_injury_saved")
	var newer := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(newer.get("ok",false)),"second_attempt_world_opened")
	if not bool(newer.get("ok",false)):
		return
	var second := SoloLiveNpcCombat.start(newer["session"],TARGET)
	check(bool(second.get("ok",false)),"second_fight_against_same_npc_started")
	if not bool(second.get("ok",false)):
		print("SECOND_DEFEAT_START_REASON=",second.get("reason","unknown"))
		return
	var second_combat: SoloLiveNpcCombat = second["combat"]
	check(second_combat.encounter_key==String(attempt2["encounter_key"]) and second_combat.checkpoint_path!=combat.checkpoint_path,"second_attempt_distinct_checkpoint")
	if not _terminal_loss(second_combat,"second"):
		return
	var durable := SoloCombatDefeatService.stage(second_combat.owner,second_combat.battle,second_combat.encounter_key,second_combat.checkpoint_path,second_combat.terminal_path)
	check(bool(durable.get("ok",false)) and FileAccess.file_exists(second_combat.terminal_path),"second_terminal_staged_before_crash")
	if not bool(durable.get("ok",false)):
		print("SECOND_DEFEAT_STAGE_REASON=",durable.get("reason","unknown"),":",durable.get("detail",""))
		return
	var crash_gap := SoloExpeditionLaunchGate.inspect(EXP,MANIFEST,ID,PLAYER)
	check(bool(crash_gap.get("ok",false)) and String(crash_gap.get("state",""))=="ready_after_recovery","restart_publishes_durable_defeat")
	check(not FileAccess.file_exists(MANIFEST),"restart_clears_pending_manifest")
	var world2 := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(world2.get("ok",false)),"second_published_world_valid")
	if bool(world2.get("ok",false)):
		var losses: Dictionary = world2["expedition"].world_state.get(SoloCombatDefeatService.LEDGER_KEY,{})
		check(losses.size()==2 and losses.has(combat.encounter_key) and losses.has(second_combat.encounter_key),"both_attempt_receipts_preserved")
		check(world2["expedition"].player_position==START,"second_defeat_retreat_persisted")
		check(Dictionary(world2["expedition"].world_state.get(MapWorldCommitService.TOMBSTONES_KEY,{})).is_empty(),"second_loss_does_not_kill_enemy")
		check(Dictionary(world2["expedition"].world_state.get(MapCombatSettlementService.MARKER_KEY,{})).is_empty(),"second_loss_does_not_roll_loot")
	for path in [EXP,TOWN,MANIFEST,
		String(attempt1["checkpoint"]),String(attempt1["receipt"]),String(attempt1["terminal"]),
		String(attempt2["checkpoint"]),String(attempt2["receipt"]),String(attempt2["terminal"])]:
		wipe(path)
