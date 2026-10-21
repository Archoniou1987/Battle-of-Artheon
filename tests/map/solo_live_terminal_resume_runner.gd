extends SceneTree

## Real CharacterCombatBuilder + NPC fight. Complete the final combat
## round, stop BEFORE world publication, restart and publish it exactly once.
const EXP := "user://test_live_terminal_exp.json"
const TOWN := "user://test_live_terminal_town.json"
const MANIFEST := "user://test_live_terminal_manifest.json"
const ID := "solo_exp_terminal_player"
const PLAYER := "player"
const BANDIT := "solo_npc_bandit_01"
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		print("LIVE_TERMINAL_RESUME_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("LIVE_TERMINAL_RESUME_TEST=", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	quit(0 if errors.is_empty() else 1)

func _run() -> void:
	var artifacts := SoloLiveNpcCombat._paths(ID,BANDIT)
	var checkpoint := String(artifacts["checkpoint"])
	var receipt := String(artifacts["receipt"])
	var terminal := String(artifacts["terminal"])
	for path in [EXP,TOWN,MANIFEST,checkpoint,receipt,terminal]:
		wipe(path)
	var player := CharacterState.new(PLAYER,"Terminal Hero",30)
	var repo := ItemRepository.new()
	# Equip a real canonical item template, not an injected combat override.
	var sword := {"instance_id":"terminal_resume_sword","template_id":"audit_sword_100","rarity":"green"}
	ItemDurabilityService.initialize_item(sword,100)
	check(repo.add_item(sword),"sword_added")
	check(player.receive_item("terminal_resume_sword",repo),"sword_owned")
	check(player.equip("main_hand","terminal_resume_sword",repo),"sword_equipped")
	check(bool(SoloTownSaveService.save(TOWN,player,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,456,Vector2i(6,5),player,repo,MANIFEST).get("ok",false)),"expedition_created")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(opened.get("ok",false)),"live_map_opened")
	if not bool(opened.get("ok",false)):
		return
	var session: SoloLiveMapSession = opened["session"]
	var base_sha := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var began := SoloLiveNpcCombat.start(session,Vector2i(7,5))
	check(bool(began.get("ok",false)),"actual_fight_started")
	if not bool(began.get("ok",false)):
		print("LIVE_TERMINAL_START_REASON=",began.get("reason","unknown"))
		return
	var live: SoloLiveNpcCombat = began["combat"]
	var simulator: GroupCombatSimulator = live.battle["simulator"]
	simulator.engine.combat_rng.seed = 20261021
	var rounds := 0
	while not simulator.controller.combat_finished() and rounds < 40:
		var round_result := simulator.run_round()
		check(bool(round_result.get("ok",false)) and bool(round_result.get("checkpoint_ok",false)),"real_round_checkpoint_"+str(rounds+1))
		if not bool(round_result.get("ok",false)) or not bool(round_result.get("checkpoint_ok",false)):
			return
		rounds += 1
	check(simulator.controller.combat_finished() and simulator.controller.winning_team()=="players","real_player_victory")
	if simulator.controller.winning_team() != "players":
		return
	check(FileAccess.file_exists(checkpoint) and FileAccess.file_exists(MANIFEST),"terminal_round_persisted_before_publish")
	check(not FileAccess.file_exists(receipt) and not FileAccess.file_exists(terminal),"no_premature_reward_publication")
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"reopen_prebattle_world_for_terminal_resume")
	if not bool(pending.get("ok",false)):
		return
	var resumed := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(resumed.get("ok",false)),"terminal_fight_recovered")
	if not bool(resumed.get("ok",false)):
		print("LIVE_TERMINAL_RESUME_REASON=",resumed.get("reason","unknown"),":",resumed.get("detail",""))
		return
	var recovered: SoloLiveNpcCombat = resumed["combat"]
	var old_round := recovered.battle["simulator"].state.round_number
	var old_event_id := recovered.battle["simulator"].state.next_event_id
	check(recovered.battle["simulator"].controller.combat_finished(),"terminal_state_preserved")
	check(old_round==rounds,"terminal_round_number_identical")
	check(not bool(pending["session"].move_one_step(Vector2i(5,5)).get("ok",false)),"terminal_pending_still_blocks_move")
	var settled := recovered.play_round()
	check(bool(settled.get("ok",false)) and String(settled.get("state",""))=="victory","terminal_resume_publishes_winner")
	if not bool(settled.get("ok",false)):
		print("LIVE_TERMINAL_SETTLEMENT_REASON=",settled.get("reason","unknown"),":",settled.get("detail",""))
		return
	check(recovered.battle["simulator"].state.round_number==old_round and recovered.battle["simulator"].state.next_event_id==old_event_id,"terminal_publication_does_not_replay_round")
	check(not FileAccess.file_exists(MANIFEST),"manifest_cleared_after_publish")
	var world := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(world.get("ok",false)),"published_world_readable")
	if not bool(world.get("ok",false)):
		return
	var expedition: ExpeditionState = world["expedition"]
	var markers: Dictionary = expedition.world_state.get(MapCombatSettlementService.MARKER_KEY,{})
	check(markers.size()==1 and markers.has(live.encounter_key),"exactly_one_world_settlement")
	check(MapWorldCommitService.is_defeated_spawn(expedition,BANDIT),"bandit_defeat_is_persistent")
	var ground_before := GroundLootService.items_at(expedition,Vector2i(7,5),PLAYER)
	var repository_before: int = world["repository"].size()
	var canonical_sha := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var repeat := ExpeditionSaveService.recover_pending_combat(EXP,terminal,live.encounter_key,ID,PLAYER,base_sha)
	check(bool(repeat.get("ok",false)) and bool(repeat.get("already_published",false)),"second_publish_idempotent")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==canonical_sha,"duplicate_publish_cannot_rewrite_world")
	var repeated_world := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(repeated_world.get("ok",false)),"world_readable_after_duplicate_publish")
	if bool(repeated_world.get("ok",false)):
		check(repeated_world["repository"].size()==repository_before,"repository_has_no_duplicate_items")
		check(GroundLootService.items_at(repeated_world["expedition"],Vector2i(7,5),PLAYER)==ground_before,"ground_loot_not_duplicated")
	var playable := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(playable.get("ok",false)),"normal_map_reopens_after_terminal_recovery")
	if bool(playable.get("ok",false)):
		check(not playable["session"].npc_bridge.instances.has(BANDIT),"defeated_bandit_not_respawned")
		check(not bool(SoloLiveNpcCombat.start(playable["session"],Vector2i(7,5)).get("ok",false)),"same_encounter_cannot_restart")
	for path in [EXP,TOWN,MANIFEST,checkpoint,receipt,terminal]:
		wipe(path)
