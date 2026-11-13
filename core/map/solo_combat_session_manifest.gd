class_name SoloCombatSessionManifest
extends RefCounted

## One pending combat per local Solo expedition. Must be written BEFORE
## opening the combat checkpoint. The terminal snapshot is never deleted
## until the outcome has been published into the canonical expedition save.
const FORMAT := "BOA_SOLO_COMBAT_MANIFEST_V1"
const PATH := "user://solo_pending_combat_v1.json"

static func begin(path: String, expedition_path: String, terminal_path: String, checkpoint_path: String, encounter_key: String, expedition_id: String, player_id: String) -> Dictionary:
	for p in [path,expedition_path,terminal_path,checkpoint_path]:
		if not MapWorldCommitService._valid_path(p):
			return {"ok":false,"reason":"manifest_invalid_path"}
	if path == expedition_path or path == terminal_path or path == checkpoint_path or expedition_path == terminal_path or expedition_path == checkpoint_path or terminal_path == checkpoint_path:
		return {"ok":false,"reason":"manifest_paths_conflict"}
	if FileAccess.file_exists(path):
		return {"ok":false,"reason":"manifest_pending_combat_exists"}
	var saved := ExpeditionSaveService.read(expedition_path,expedition_id,player_id)
	if not bool(saved.get("ok",false)):
		return {"ok":false,"reason":"manifest_expedition_not_verified"}
	var current: ExpeditionState = saved["expedition"]
	if not current.is_active() or Dictionary(current.world_state.get(ExpeditionSaveService.MARKERS_KEY,{})).has(encounter_key):
		return {"ok":false,"reason":"manifest_encounter_not_available"}
	var revision := ExpeditionSaveService._read_payload_envelope(expedition_path)
	if not bool(revision.get("ok",false)):
		return revision
	if not MapWorldCommitService._valid_id(encounter_key):
		return {"ok":false,"reason":"manifest_invalid_encounter"}
	var payload := {"encounter_key":encounter_key,"expedition_id":expedition_id,"player_id":player_id,"expedition_path":expedition_path,"terminal_path":terminal_path,"checkpoint_path":checkpoint_path,"base_sha256":String(revision["sha256"])}
	var encoded := JSON.stringify(payload)
	var envelope := JSON.stringify({"format":FORMAT,"payload_json":encoded,"sha256":encoded.sha256_text()})
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"manifest_write_failed"}
	file.store_string(envelope)
	file.flush()
	file.close()
	var checked := read(tmp)
	if not bool(checked.get("ok",false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return {"ok":false,"reason":"manifest_verify_failed"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),ProjectSettings.globalize_path(path)) != OK:
		return {"ok":false,"reason":"manifest_replace_failed"}
	return {"ok":true,"base_sha256":String(revision["sha256"])}

static func read(path: String = PATH) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not FileAccess.file_exists(path):
		return {"ok":false,"reason":"manifest_missing"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"manifest_read_failed"}
	if file.get_length() > 8192 or file.get_length() < 16:
		file.close()
		return {"ok":false,"reason":"manifest_invalid_size"}
	var raw := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(raw)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT or not envelope.get("payload_json") is String:
		return {"ok":false,"reason":"manifest_invalid_format"}
	var encoded := String(envelope["payload_json"])
	if encoded.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"manifest_integrity_failed"}
	var data: Variant = JSON.parse_string(encoded)
	if not data is Dictionary:
		return {"ok":false,"reason":"manifest_invalid_payload"}
	for key in ["encounter_key","expedition_id","player_id","expedition_path","terminal_path","checkpoint_path","base_sha256"]:
		if not data.get(key) is String or String(data[key]).is_empty():
			return {"ok":false,"reason":"manifest_missing_"+key}
	for key in ["expedition_path","terminal_path","checkpoint_path"]:
		if not MapWorldCommitService._valid_path(String(data[key])):
			return {"ok":false,"reason":"manifest_invalid_"+key}
	if not MapWorldCommitService._valid_id(String(data["encounter_key"])) or not MapWorldCommitService._valid_id(String(data["expedition_id"])) or not MapWorldCommitService._valid_id(String(data["player_id"])) or String(data["base_sha256"]).length() != 64:
		return {"ok":false,"reason":"manifest_invalid_identity"}
	return {"ok":true,"data":data}

## Call when loading a Solo expedition, BEFORE allowing map movement or
## any new encounter. An unfinished battle must resume from its checkpoint.
static func recover_on_launch(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok":true,"state":"no_pending_combat"}
	var loaded := read(path)
	if not bool(loaded.get("ok",false)):
		return loaded
	var data: Dictionary = loaded["data"]
	var terminal_path := String(data["terminal_path"])
	if not FileAccess.file_exists(terminal_path):
		return {"ok":false,"state":"resume_combat_checkpoint","checkpoint_path":String(data["checkpoint_path"]),"encounter_key":String(data["encounter_key"]),"reason":"terminal_snapshot_missing"}
	# Victory uses a map combat world receipt; defeat uses a verified full
	# expedition snapshot and never grants NPC tombstones or reward rolls.
	var typed := SoloCombatDefeatService.inspect_terminal_type(terminal_path)
	if not bool(typed.get("ok",false)):
		return {"ok":false,"state":"manual_reconciliation_required","reason":String(typed.get("reason","unknown"))}
	var terminal_format := String(typed["format"])
	var outcome: Dictionary
	if terminal_format == MapWorldCommitService.FORMAT:
		outcome = ExpeditionSaveService.recover_pending_combat(String(data["expedition_path"]),terminal_path,String(data["encounter_key"]),String(data["expedition_id"]),String(data["player_id"]),String(data["base_sha256"]))
	elif terminal_format == ExpeditionSaveService.FORMAT:
		outcome = SoloCombatDefeatService.recover(data)
	else:
		return {"ok":false,"state":"manual_reconciliation_required","reason":"unknown_combat_terminal_format"}
	if not bool(outcome.get("ok",false)):
		return {"ok":false,"state":"manual_reconciliation_required","reason":String(outcome.get("reason","unknown")),"detail":String(outcome.get("detail",""))}
	# A completed recovery can be replayed if deletion fails, so never
	# delete the terminal snapshot before the manifest is cleared.
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		return {"ok":false,"state":"published_manifest_cleanup_failed"}
	return {"ok":true,"state":"recovered","outcome":"defeat" if terminal_format == ExpeditionSaveService.FORMAT else "victory","recovered":bool(outcome.get("recovered",false)),"already_published":bool(outcome.get("already_published",false)),"terminal_path":terminal_path}
