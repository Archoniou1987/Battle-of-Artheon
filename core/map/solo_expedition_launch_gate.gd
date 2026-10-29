class_name SoloExpeditionLaunchGate
extends RefCounted

## Authoritative Solo map entry gate. Never load a generated debug map
## or start movement until the expedition and pending combat agree.
## No UI scene dependencies, so real map startup can reuse this unchanged.
static func inspect(expedition_path: String = ExpeditionSaveService.DEFAULT_PATH, manifest_path: String = SoloCombatSessionManifest.PATH, expedition_id: String = "", player_id: String = "") -> Dictionary:
	if not MapWorldCommitService._valid_path(expedition_path) or not MapWorldCommitService._valid_path(manifest_path):
		return {"ok":false,"state":"blocked","reason":"invalid_entry_path"}
	if not FileAccess.file_exists(expedition_path):
		if FileAccess.file_exists(manifest_path):
			return {"ok":false,"state":"blocked","reason":"pending_combat_without_expedition"}
		return {"ok":true,"state":"new_expedition_required"}
	if expedition_id.is_empty() or player_id.is_empty():
		return {"ok":false,"state":"blocked","reason":"missing_player_identity"}
	# The expedition snapshot must be valid even if the manifest happens
	# to be absent. A bad file is NEVER silently replaced with a new game.
	var saved: Dictionary = ExpeditionSaveService.read(expedition_path,expedition_id,player_id)
	if not bool(saved.get("ok",false)):
		return {"ok":false,"state":"blocked","reason":"expedition_invalid","detail":String(saved.get("reason","unknown"))}
	var expedition: ExpeditionState = saved["expedition"]
	if not expedition.is_active():
		return {"ok":false,"state":"expedition_closed","reason":expedition.status}
	if FileAccess.file_exists(manifest_path):
		var pending: Dictionary = SoloCombatSessionManifest.read(manifest_path)
		if not bool(pending.get("ok",false)):
			return {"ok":false,"state":"blocked","reason":"invalid_pending_manifest"}
		var data: Dictionary = pending["data"]
		if String(data.get("expedition_path","")) != expedition_path or String(data.get("expedition_id","")) != expedition_id or String(data.get("player_id","")) != player_id:
			return {"ok":false,"state":"blocked","reason":"pending_manifest_owner_mismatch"}
		var recovery: Dictionary = SoloCombatSessionManifest.recover_on_launch(manifest_path)
		if not bool(recovery.get("ok",false)):
			return {"ok":false,"state":String(recovery.get("state","blocked")),"reason":String(recovery.get("reason","unknown")),"checkpoint_path":String(recovery.get("checkpoint_path","")),"encounter_key":String(recovery.get("encounter_key",""))}
		# Re-open after recovery: no cached pre-battle items or resources.
		saved = ExpeditionSaveService.read(expedition_path,expedition_id,player_id)
		if not bool(saved.get("ok",false)):
			return {"ok":false,"state":"blocked","reason":"recovered_world_invalid"}
		expedition = saved["expedition"]
		if not expedition.is_active():
			return {"ok":false,"state":"expedition_closed","reason":expedition.status}
		return {"ok":true,"state":"ready_after_recovery","expedition":expedition,"character":saved["character"],"repository":saved["repository"]}
	return {"ok":true,"state":"ready","expedition":expedition,"character":saved["character"],"repository":saved["repository"]}
