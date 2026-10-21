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

func _initialize() -> void:
	for path in [EXP,TOWN,MANIFEST]:
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
	check(not bool(SoloLiveMapSession.open(EXP,MANIFEST,ID,"player").get("ok",false)),"normal_map_entry_blocks_pending")
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
	var world := ExpeditionSaveService.read(EXP,ID,"player")
	check(bool(world.get("ok",false)) and world["expedition"].player_position==Vector2i(6,5),"prebattle_position_remains_authoritative")
	for path in [EXP,TOWN,MANIFEST,combat.checkpoint_path,combat.receipt_path,combat.terminal_path]:
		wipe(path)
	print("LIVE_COMBAT_RESUME_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
