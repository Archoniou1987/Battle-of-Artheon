extends SceneTree

const SAVE := "user://test_solo_entry_save.json"
const MANIFEST := "user://test_solo_entry_manifest.json"
const TERMINAL := "user://test_solo_entry_terminal.json"
const CHECKPOINT := "user://test_solo_entry_checkpoint.json"
const EXP := "SOLO_ENTRY_TEST"
const PLAYER := "PLAYER"
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("SOLO_ENTRY_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [SAVE,MANIFEST,TERMINAL,CHECKPOINT]:
		wipe(path)
	var empty: Dictionary = SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,PLAYER)
	check(bool(empty.get("ok",false)) and String(empty.get("state",""))=="new_expedition_required","fresh_entry_needs_world_creation")
	var expedition := ExpeditionState.new(EXP)
	var player := CharacterState.new(PLAYER,"Explorer",5)
	var repository := ItemRepository.new()
	expedition.player_position=Vector2i(2,2)
	check(bool(ExpeditionSaveService.save(SAVE,expedition,player,repository).get("ok",false)),"initial_save")
	var ready: Dictionary = SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,PLAYER)
	check(bool(ready.get("ok",false)) and String(ready.get("state",""))=="ready","valid_existing_expedition")
	check(not bool(SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,"OTHER").get("ok",false)),"wrong_player_blocked")
	var pending: Dictionary = SoloCombatSessionManifest.begin(MANIFEST,SAVE,TERMINAL,CHECKPOINT,"entry:test:npc",EXP,PLAYER)
	check(bool(pending.get("ok",false)),"manifest_pre_registered")
	var halt: Dictionary = SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,PLAYER)
	check(not bool(halt.get("ok",false)) and String(halt.get("state",""))=="resume_combat_checkpoint","checkpoint_blocks_map_entry")
	check(FileAccess.file_exists(MANIFEST),"checkpoint_manifest_kept")
	check(not bool(SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,"OTHER").get("ok",false)),"pending_manifest_cannot_cross_players")
	wipe(MANIFEST)
	var terminal_only := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if terminal_only != null:
		terminal_only.store_string("broken")
		terminal_only.close()
	var corrupt: Dictionary = SoloExpeditionLaunchGate.inspect(SAVE,MANIFEST,EXP,PLAYER)
	check(not bool(corrupt.get("ok",false)) and String(corrupt.get("reason",""))=="invalid_pending_manifest","invalid_manifest_denies_entry")
	for path in [SAVE,MANIFEST,TERMINAL,CHECKPOINT]:
		wipe(path)
	print("SOLO_LAUNCH_GATE_TEST="+("PASS" if failures.is_empty() else "FAIL")+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
