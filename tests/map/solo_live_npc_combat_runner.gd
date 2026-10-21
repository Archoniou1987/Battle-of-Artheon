extends SceneTree

const EXP := "user://test_live_npc_combat_exp.json"
const TOWN := "user://test_live_npc_combat_town.json"
const MANIFEST := "user://test_live_npc_combat_manifest.json"
const ID := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		errors.append(name)
		print("LIVE_NPC_COMBAT_CASE=FAIL ",name)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
	var town := CharacterState.new("player","Hero",20)
	var items := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,town,items).get("ok",false)),"canonical_town_created")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,123,Vector2i(6,5),town,items,MANIFEST).get("ok",false)),"expedition_created_adjacent_to_bandit")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(bool(opened.get("ok",false)),"live_session_open")
	if not bool(opened.get("ok",false)):
		quit(1)
		return
	var session: SoloLiveMapSession = opened["session"]
	check(not bool(SoloLiveNpcCombat.start(session,Vector2i(8,8)).get("ok",false)),"distant_enemy_cannot_start_fight")
	var began := SoloLiveNpcCombat.start(session,Vector2i(7,5))
	check(bool(began.get("ok",false)),"actual_character_builder_and_npc_combat_started")
	if not bool(began.get("ok",false)):
		print("LIVE_COMBAT_START_REASON=",began.get("reason",""))
		quit(1)
		return
	var combat: SoloLiveNpcCombat = began["combat"]
	check(FileAccess.file_exists(MANIFEST),"manifest_written_before_round")
	check(not bool(SoloLiveNpcCombat.start(session,Vector2i(7,5)).get("ok",false)),"second_battle_blocked_by_manifest")
	check(not bool(session.move_one_step(Vector2i(5,5)).get("ok",false)),"movement_locked_while_in_combat")
	check(not bool(session.return_to_town(TOWN).get("ok",false)),"return_locked_while_in_combat")
	var sim: GroupCombatSimulator = combat.battle["simulator"]
	check(sim.state.get_combatant("player") != null and sim.state.get_combatant("solo_npc_bandit_01") != null,"real_roster_ids")
	var step := combat.play_round()
	check(bool(step.get("ok",false)) or String(step.get("state",""))=="defeat_pending_resolution","round_or_terminal_defeat_processed")
	if bool(step.get("ok",false)):
		check(sim.state.round_number >= 1,"combat_engine_advanced")
		if String(step.get("state",""))=="ongoing":
			check(FileAccess.file_exists(combat.checkpoint_path),"round_checkpoint_durable")
	# Save remains last pre-fight state while manifest holds ownership.
	var saved := ExpeditionSaveService.read(EXP,ID,"player")
	check(bool(saved.get("ok",false)),"expedition_remains_readable_during_battle")
	# Tests must not leave abandoned manifests in the next CI script.
	wipe(MANIFEST)
	wipe(combat.checkpoint_path)
	wipe(combat.receipt_path)
	wipe(combat.terminal_path)
	for path in [EXP,TOWN]:
		wipe(path)
	print("LIVE_NPC_COMBAT_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
