class_name SoloTownSaveService
extends RefCounted

## One canonical atomic town snapshot. Legacy city files are NOT written
## here, and the expedition archive remains the evidence of return.
const FORMAT := "BOA_SOLO_TOWN_SAVE_V1"
const VERSION := 1
const DEFAULT_PATH := "user://solo_town_save_v1.json"

static func _read_payload(path: String) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not FileAccess.file_exists(path):
		return {"ok":false,"reason":"town_snapshot_not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"town_snapshot_open_failed"}
	if file.get_length() < 16 or file.get_length() > ExpeditionSaveService.MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"town_snapshot_size_invalid"}
	var raw := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(raw)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT or not envelope.get("payload_json") is String:
		return {"ok":false,"reason":"town_snapshot_format_invalid"}
	var encoded := String(envelope["payload_json"])
	if encoded.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"town_snapshot_integrity_failed"}
	var payload: Variant = JSON.parse_string(encoded)
	if not payload is Dictionary or int(payload.get("version",-1)) != VERSION:
		return {"ok":false,"reason":"town_snapshot_schema_invalid"}
	return {"ok":true,"payload":payload,"sha256":encoded.sha256_text()}

static func read(path: String, player_id: String) -> Dictionary:
	var raw := _read_payload(path)
	if not bool(raw.get("ok",false)):
		return raw
	var payload: Dictionary = raw["payload"]
	if String(payload.get("player_id","")) != player_id or not payload.get("character") is Dictionary or not payload.get("repository") is Dictionary or not payload.get("return_origin") is Dictionary:
		return {"ok":false,"reason":"town_snapshot_owner_or_shape_invalid"}
	var repository_data: Dictionary = payload["repository"]
	if not repository_data.get("items") is Dictionary:
		return {"ok":false,"reason":"town_snapshot_repository_invalid"}
	var repository := ItemRepository.from_dict(repository_data)
	if repository.size() != Dictionary(repository_data["items"]).size():
		return {"ok":false,"reason":"town_snapshot_repository_rejected"}
	var restored := MapWorldCommitService._restore_character(payload["character"],repository)
	if not bool(restored.get("ok",false)):
		return {"ok":false,"reason":"town_snapshot_character_invalid","detail":String(restored.get("reason","unknown"))}
	var owner: CharacterState = restored["character"]
	if owner.character_id != player_id or repository.size() != owner.inventory.size():
		return {"ok":false,"reason":"town_snapshot_unowned_items"}
	var source: Dictionary = payload["return_origin"]
	if not source.is_empty():
		if String(source.get("expedition_id","")).is_empty() or String(source.get("snapshot_sha256","")).length() != 64:
			return {"ok":false,"reason":"town_return_origin_invalid"}
	return {"ok":true,"character":owner,"repository":repository,"return_origin":source,"sha256":String(raw["sha256"])}

## Migration only: legacy repositories sometimes contain item records not
## referenced by the character inventory. Preserve the original legacy file;
## copy only provably owned items into the new canonical town snapshot.
## Never use this to "repair" an existing canonical save.
static func prepare_legacy_inventory_migration(player: CharacterState, repository: ItemRepository) -> Dictionary:
	if player == null or repository == null or player.inventory == null:
		return {"ok":false,"reason":"legacy_migration_missing_owner"}
	var source: Dictionary = repository.to_dict().get("items", {})
	var owned_ids: Array = player.inventory.instance_ids()
	var owned: ItemRepository = ItemRepository.new()
	for raw_id in owned_ids:
		var id := String(raw_id)
		if not source.has(id) or not source[id] is Dictionary:
			return {"ok":false,"reason":"legacy_owned_item_missing","item_id":id}
		if not owned.add_item(source[id]):
			return {"ok":false,"reason":"legacy_owned_item_invalid","item_id":id}
	if owned.size() != owned_ids.size():
		return {"ok":false,"reason":"legacy_inventory_count_mismatch"}
	return {"ok":true,"repository":owned,"orphan_count":maxi(0,repository.size()-owned.size())}


static func _write(path: String, player: CharacterState, repository: ItemRepository, source: Dictionary) -> Dictionary:
	# Diagnose orphan instances BEFORE touching the durable town snapshot.
	# This check is intentionally strict: never silently delete inventory.
	var raw_instances: Dictionary = repository.to_dict().get("items",{})
	var orphan_ids: Array[String] = []
	for raw_id in raw_instances.keys():
		var instance_id := String(raw_id)
		if not player.inventory.owns(instance_id):
			orphan_ids.append(instance_id)
	if not orphan_ids.is_empty():
		orphan_ids.sort()
		return {"ok":false,"reason":"town_snapshot_unowned_items","detail":", ".join(PackedStringArray(orphan_ids.slice(0,8))),"orphan_count":orphan_ids.size()}
	var payload := {"version":VERSION,"player_id":player.character_id,"character":MapWorldCommitService._character_to_dict(player),"repository":repository.to_dict(),"return_origin":source.duplicate(true)}
	var encoded := JSON.stringify(payload)
	var wrapper := JSON.stringify({"format":FORMAT,"payload_json":encoded,"sha256":encoded.sha256_text()})
	if wrapper.to_utf8_buffer().size() > ExpeditionSaveService.MAX_BYTES:
		return {"ok":false,"reason":"town_snapshot_too_large"}
	var temp := path+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"town_snapshot_temp_failed"}
	file.store_string(wrapper)
	file.flush()
	file.close()
	var checked := read(temp,player.character_id)
	if not bool(checked.get("ok",false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return {"ok":false,"reason":"town_snapshot_verify_failed","detail":String(checked.get("reason","unknown"))}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path)) != OK:
		return {"ok":false,"reason":"town_snapshot_replace_failed"}
	return {"ok":true,"sha256":encoded.sha256_text()}

static func save(path: String, player: CharacterState, repository: ItemRepository, expected_sha256: String = "", allow_town_arena_combat: bool = false) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or player == null or repository == null or (player.in_combat and not allow_town_arena_combat):
		return {"ok":false,"reason":"invalid_town_save_context"}
	if FileAccess.file_exists(path):
		var existing := read(path,player.character_id)
		if not bool(existing.get("ok",false)):
			return existing
		if String(existing["sha256"]) != expected_sha256:
			return {"ok":false,"reason":"stale_town_revision"}
		return _write(path,player,repository,existing["return_origin"])
	if not expected_sha256.is_empty():
		return {"ok":false,"reason":"town_save_not_initialized"}
	return _write(path,player,repository,{})

static func adopt_closed_expedition(town_path: String, expedition_path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if not MapWorldCommitService._valid_path(town_path):
		return {"ok":false,"reason":"invalid_town_path"}
	var returned := SoloTownReturnService.load_returned_owner(expedition_path,expedition_id,player_id,manifest_path)
	if not bool(returned.get("ok",false)):
		return returned
	var source := ExpeditionSaveService._read_payload_envelope(expedition_path)
	if not bool(source.get("ok",false)):
		return source
	var source_hash := String(source["sha256"])
	if FileAccess.file_exists(town_path):
		var existing := read(town_path,player_id)
		if not bool(existing.get("ok",false)):
			return existing
		var origin: Dictionary = existing["return_origin"]
		if String(origin.get("expedition_id","")) == expedition_id and String(origin.get("snapshot_sha256","")) == source_hash:
			return {"ok":true,"already_adopted":true}
		# A city save normally already exists before the expedition.
		# It may be replaced ONLY when it still equals the verified
		# departure snapshot. Never silently merge divergent owners.
		if not SoloTownExpeditionBridge.town_matches_origin(returned["expedition"],existing["character"],existing["repository"]):
			return {"ok":false,"reason":"town_snapshot_conflict"}
	var receipt := {"expedition_id":expedition_id,"snapshot_sha256":source_hash}
	var done := _write(town_path,returned["character"],returned["repository"],receipt)
	if not bool(done.get("ok",false)):
		return done
	return {"ok":true,"already_adopted":false}

## Explicit conflict recovery, NEVER the ordinary automatic return.
## Archive the exact pre-existing town bytes before accepting the closed
## expedition. The archive stays readable with the same canonical contract.
## The user must explicitly opt into expedition ownership in the UI.
static func adopt_closed_expedition_preserving_town(town_path: String, expedition_path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	var normal := adopt_closed_expedition(town_path,expedition_path,expedition_id,player_id,manifest_path)
	if bool(normal.get("ok",false)) or String(normal.get("reason","")) != "town_snapshot_conflict":
		return normal
	var town_before := read(town_path,player_id)
	if not bool(town_before.get("ok",false)):
		return town_before
	var returned := SoloTownReturnService.load_returned_owner(expedition_path,expedition_id,player_id,manifest_path)
	if not bool(returned.get("ok",false)):
		return returned
	var closed := ExpeditionSaveService._read_payload_envelope(expedition_path)
	if not bool(closed.get("ok",false)):
		return closed
	var raw := FileAccess.get_file_as_string(town_path)
	var town_hash := String(town_before["sha256"])
	var backup_path := town_path + ".conflict_" + town_hash.substr(0,24)
	if FileAccess.file_exists(backup_path):
		if FileAccess.get_file_as_string(backup_path) != raw:
			return {"ok":false,"reason":"town_conflict_backup_collision"}
	else:
		var backup := FileAccess.open(backup_path,FileAccess.WRITE)
		if backup == null:
			return {"ok":false,"reason":"town_conflict_backup_unwritable"}
		backup.store_string(raw)
		backup.flush()
		backup.close()
		if FileAccess.get_file_as_string(backup_path) != raw:
			return {"ok":false,"reason":"town_conflict_backup_unverified"}
	var backup_checked := read(backup_path,player_id)
	if not bool(backup_checked.get("ok",false)) or String(backup_checked.get("sha256","")) != town_hash:
		return {"ok":false,"reason":"town_conflict_backup_invalid"}
	# Recheck the original revision before any change. Never overwrite a
	# concurrent update made while the conflict was being diagnosed.
	var latest := read(town_path,player_id)
	if not bool(latest.get("ok",false)) or String(latest.get("sha256","")) != town_hash:
		return {"ok":false,"reason":"town_conflict_changed_during_recovery"}
	var receipt := {"expedition_id":expedition_id,"snapshot_sha256":String(closed["sha256"])}
	var published := _write(town_path,returned["character"],returned["repository"],receipt)
	if not bool(published.get("ok",false)):
		return published
	return {"ok":true,"conflict_recovered":true,"city_backup_path":backup_path,"already_adopted":false}


