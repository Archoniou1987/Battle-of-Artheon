class_name ExpeditionSaveService
extends RefCounted

## Solo expedition's independent save container. Unlike the combat-receipt
## checkpoint V1, this exists BEFORE the first encounter and can be updated
## after any number of completed encounters. Combat receipts are still
## responsible for battle outcome verification and idempotent rewards.
const FORMAT := "BOA_SOLO_EXPEDITION_SAVE_V1"
const VERSION := 1
const DEFAULT_PATH := "user://solo_expedition_save_v1.json"
const MAX_BYTES := 8 * 1024 * 1024
const TOMBSTONES_KEY := MapWorldCommitService.TOMBSTONES_KEY
const MARKERS_KEY := MapCombatSettlementService.MARKER_KEY

static func _valid_identity(expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> bool:
	return expedition != null and player != null and repository != null and MapWorldCommitService._valid_id(expedition.expedition_id) and MapWorldCommitService._valid_id(player.character_id) and not player.in_combat

static func _snapshot(expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> Dictionary:
	return {"schema":VERSION,"expedition_id":expedition.expedition_id,"player_id":player.character_id,"expedition":expedition.to_dict(),"character":MapWorldCommitService._character_to_dict(player),"repository":repository.to_dict()}

static func _validate_locations(expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> String:
	var world := expedition.world_state
	var ground: Variant = world.get(GroundLootService.WORLD_KEY,{})
	if not ground is Dictionary:
		return "invalid_ground_registry"
	var owned: Dictionary = {}
	for id in player.inventory.instance_ids():
		var item_id := String(id)
		if item_id.is_empty() or owned.has(item_id) or not repository.has_item(item_id):
			return "invalid_owned_item"
		owned[item_id] = true
	for id in ground:
		var item_id := String(id)
		var entry: Variant = ground[id]
		if item_id.is_empty() or not repository.has_item(item_id) or owned.has(item_id) or not entry is Dictionary or String(entry.get("instance_id","")) != item_id:
			return "duplicate_or_missing_ground_item"
		var pos: Variant = entry.get("cell",null)
		if not pos is Array or Array(pos).size() != 2:
			return "invalid_ground_coordinates"
		for v in pos:
			if not CharacterProgression._is_whole_number(v):
				return "invalid_ground_coordinates"
		var policy := String(entry.get("policy",""))
		if policy != GroundLootService.POLICY_EXPEDITION and policy != GroundLootService.POLICY_TIMED:
			return "invalid_ground_policy"
		if policy == GroundLootService.POLICY_TIMED and int(entry.get("expires_at_unix",0)) <= 0:
			return "invalid_ground_expiration"
	var pools: Variant = world.get("encounter_loot_pools",{})
	if not pools is Dictionary:
		return "invalid_loot_pools"
	for key in pools:
		if not pools[key] is Dictionary:
			return "invalid_loot_pool"
		var pool := EncounterLootPool.from_dict(pools[key])
		for id in pool.item_ids():
			if not repository.has_item(id) or owned.has(id) or ground.has(id):
				return "duplicate_pool_item"
	var tombstones: Variant = world.get(TOMBSTONES_KEY,{})
	var markers: Variant = world.get(MARKERS_KEY,{})
	if not tombstones is Dictionary or not markers is Dictionary:
		return "invalid_combat_ledgers"
	for encounter_key in tombstones:
		var tombstone: Variant = tombstones[encounter_key]
		if not tombstone is Dictionary or String(tombstone.get("receipt_sha256","")).length() != 64:
			return "invalid_combat_tombstone"
		if String(markers.get(encounter_key,"")) != String(tombstone["receipt_sha256"]):
			return "combat_marker_tombstone_mismatch"
	return ""

static func _restore(payload: Dictionary, expedition_id: String, player_id: String) -> Dictionary:
	if int(payload.get("schema",-1)) != VERSION or String(payload.get("expedition_id","")) != expedition_id or String(payload.get("player_id","")) != player_id:
		return {"ok":false,"reason":"expedition_save_identity_mismatch"}
	for key in ["expedition","character","repository"]:
		if not payload.get(key) is Dictionary:
			return {"ok":false,"reason":"expedition_save_missing_" + key}
	var expedition := ExpeditionState.from_dict(payload["expedition"])
	if expedition.expedition_id != expedition_id:
		return {"ok":false,"reason":"expedition_save_owner_mismatch"}
	var items: Dictionary = payload["repository"]
	if not items.get("items") is Dictionary:
		return {"ok":false,"reason":"expedition_save_items_invalid"}
	var repository := ItemRepository.from_dict(items)
	if repository.size() != Dictionary(items["items"]).size():
		return {"ok":false,"reason":"expedition_save_item_rejected"}
	var restored := MapWorldCommitService._restore_character(payload["character"],repository)
	if not bool(restored.get("ok",false)):
		return restored
	var player: CharacterState = restored["character"]
	if player.character_id != player_id:
		return {"ok":false,"reason":"expedition_save_character_mismatch"}
	var issue := _validate_locations(expedition,player,repository)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	return {"ok":true,"expedition":expedition,"character":player,"repository":repository}

static func read(path: String, expedition_id: String, player_id: String) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not MapWorldCommitService._valid_id(expedition_id) or not MapWorldCommitService._valid_id(player_id):
		return {"ok":false,"reason":"expedition_save_invalid_path_or_owner"}
	if not FileAccess.file_exists(path):
		return {"ok":false,"reason":"expedition_save_not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"expedition_save_open_failed"}
	if file.get_length() < 16 or file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"expedition_save_size_rejected"}
	var raw := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(raw)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT or not envelope.get("payload_json") is String:
		return {"ok":false,"reason":"expedition_save_invalid_envelope"}
	var payload_json := String(envelope["payload_json"])
	if payload_json.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"expedition_save_integrity_failed"}
	var payload: Variant = JSON.parse_string(payload_json)
	if not payload is Dictionary:
		return {"ok":false,"reason":"expedition_save_parse_failed"}
	return _restore(payload,expedition_id,player_id)

static func _write(path: String, expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> Dictionary:
	var payload_json := JSON.stringify(_snapshot(expedition,player,repository))
	var raw := JSON.stringify({"format":FORMAT,"payload_json":payload_json,"sha256":payload_json.sha256_text()})
	if raw.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok":false,"reason":"expedition_save_too_large"}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"expedition_save_temp_open_failed"}
	file.store_string(raw)
	file.flush()
	file.close()
	# Verify all the reconstructed owners before replacing the durable file.
	var checked := read(temp,expedition.expedition_id,player.character_id)
	if not bool(checked.get("ok",false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return {"ok":false,"reason":"expedition_save_temp_invalid","detail":String(checked.get("reason","unknown"))}
	var status := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	if status != OK:
		return {"ok":false,"reason":"expedition_save_replace_failed","error":status}
	return {"ok":true,"path":path}

static func _ledgers_monotonic(previous: ExpeditionState, next: ExpeditionState) -> String:
	for name in [TOMBSTONES_KEY,MARKERS_KEY,GroundLootSettlementAdapter.MIGRATED_KEY]:
		var old: Dictionary = previous.world_state.get(name,{})
		var now: Dictionary = next.world_state.get(name,{})
		for id in old:
			if not now.has(id) or JSON.stringify(old[id]) != JSON.stringify(now[id]):
				return "expedition_ledger_rollback_" + name
	return ""

## One-time handoff from a VERIFIED legacy combat-world snapshot. A
## previously created expedition save must never be overwritten by import.
static func import_committed_world(path: String, old_snapshot: String, encounter_key: String, expedition_id: String, player_id: String) -> Dictionary:
	if FileAccess.file_exists(path):
		return {"ok":false,"reason":"expedition_save_already_exists"}
	var legacy := MapWorldCommitService.read(old_snapshot,encounter_key,expedition_id,player_id)
	if not bool(legacy.get("ok",false)):
		return {"ok":false,"reason":"legacy_world_not_verified","detail":String(legacy.get("reason","unknown"))}
	return save(path,legacy["expedition"],legacy["character"],legacy["repository"])

## Publish a terminal encounter ONLY from a verified battle-world snapshot.
## An expected expedition checksum prevents a stale battle from replacing
## an expedition that was modified by another action in the meantime.
static func publish_verified_combat(path: String, combat_snapshot: String, encounter_key: String, expedition_id: String, player_id: String, expected_base_sha256: String) -> Dictionary:
	if expected_base_sha256.length() != 64:
		return {"ok":false,"reason":"invalid_expected_expedition_revision"}
	var original: Dictionary = read(path,expedition_id,player_id)
	if not bool(original.get("ok",false)):
		return original
	var envelope: Dictionary = _read_payload_envelope(path)
	if not bool(envelope.get("ok",false)):
		return envelope
	if String(envelope.get("sha256","")) != expected_base_sha256:
		return {"ok":false,"reason":"stale_expedition_save"}
	var terminal: Dictionary = MapWorldCommitService.read(combat_snapshot,encounter_key,expedition_id,player_id)
	if not bool(terminal.get("ok",false)):
		return {"ok":false,"reason":"combat_world_not_verified","detail":String(terminal.get("reason","unknown"))}
	var current: ExpeditionState = original["expedition"]
	var next: ExpeditionState = terminal["expedition"]
	if not next.is_active() or not current.is_active():
		return {"ok":false,"reason":"expedition_not_active"}
	if Dictionary(current.world_state.get(MARKERS_KEY,{})).has(encounter_key):
		return {"ok":false,"reason":"encounter_already_published"}
	var hash := String(terminal["receipt_sha256"])
	if String(Dictionary(next.world_state.get(MARKERS_KEY,{})).get(encounter_key,"")) != hash:
		return {"ok":false,"reason":"combat_marker_missing"}
	if not Dictionary(next.world_state.get(TOMBSTONES_KEY,{})).has(encounter_key):
		return {"ok":false,"reason":"combat_tombstone_missing"}
	return save(path,next,terminal["character"],terminal["repository"])

## Crash-recovery reconciliation: terminal combat can already be durable
## while the expedition file still contains its pre-battle revision.
## Re-running this operation must not reroll, overwrite later progress,
## or treat an already-published receipt as a second reward.
static func recover_pending_combat(path: String, combat_snapshot: String, encounter_key: String, expedition_id: String, player_id: String, expected_base_sha256: String) -> Dictionary:
	if expected_base_sha256.length() != 64:
		return {"ok":false,"reason":"invalid_expected_expedition_revision"}
	var terminal: Dictionary = MapWorldCommitService.read(combat_snapshot,encounter_key,expedition_id,player_id)
	if not bool(terminal.get("ok",false)):
		return {"ok":false,"reason":"recovery_combat_snapshot_invalid","detail":String(terminal.get("reason","unknown"))}
	var current: Dictionary = read(path,expedition_id,player_id)
	if not bool(current.get("ok",false)):
		return current
	var saved_world: ExpeditionState = current["expedition"]
	var current_markers: Dictionary = saved_world.world_state.get(MARKERS_KEY,{})
	var receipt_hash := String(terminal["receipt_sha256"])
	if current_markers.has(encounter_key):
		if String(current_markers[encounter_key]) != receipt_hash:
			return {"ok":false,"reason":"recovery_receipt_conflict"}
		var tombstones: Dictionary = saved_world.world_state.get(TOMBSTONES_KEY,{})
		if not tombstones.has(encounter_key) or String(Dictionary(tombstones[encounter_key]).get("receipt_sha256","")) != receipt_hash:
			return {"ok":false,"reason":"recovery_tombstone_conflict"}
		return {"ok":true,"already_published":true,"recovered":false}
	var revision: Dictionary = _read_payload_envelope(path)
	if not bool(revision.get("ok",false)):
		return revision
	if String(revision.get("sha256","")) != expected_base_sha256:
		return {"ok":false,"reason":"recovery_base_revision_changed"}
	# The terminal snapshot is the durable outcome owner; the ordinary
	# publisher still checks ledger monotonicity and item uniqueness.
	var result: Dictionary = publish_verified_combat(path,combat_snapshot,encounter_key,expedition_id,player_id,expected_base_sha256)
	if not bool(result.get("ok",false)):
		return result
	return {"ok":true,"already_published":false,"recovered":true}

static func _read_payload_envelope(path: String) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not FileAccess.file_exists(path):
		return {"ok":false,"reason":"expedition_envelope_not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"expedition_envelope_open_failed"}
	var raw := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(raw)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT or not envelope.get("payload_json") is String:
		return {"ok":false,"reason":"expedition_envelope_invalid"}
	var payload_json := String(envelope["payload_json"])
	if payload_json.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"expedition_envelope_integrity_failed"}
	return {"ok":true,"sha256":String(envelope["sha256"])}

static func save(path: String, expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> Dictionary:
	if not _valid_identity(expedition,player,repository) or not MapWorldCommitService._valid_path(path):
		return {"ok":false,"reason":"expedition_save_invalid_context"}
	if expedition.status not in [ExpeditionState.STATUS_ACTIVE,ExpeditionState.STATUS_COMPLETED,ExpeditionState.STATUS_EXITED,ExpeditionState.STATUS_EXPIRED]:
		return {"ok":false,"reason":"expedition_save_invalid_status"}
	var issue := _validate_locations(expedition,player,repository)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	if FileAccess.file_exists(path):
		var previous := read(path,expedition.expedition_id,player.character_id)
		if not bool(previous.get("ok",false)):
			return {"ok":false,"reason":"expedition_save_previous_invalid","detail":String(previous.get("reason","unknown"))}
		var prior: ExpeditionState = previous["expedition"]
		if prior.status != ExpeditionState.STATUS_ACTIVE:
			return {"ok":false,"reason":"expedition_already_closed"}
		issue = _ledgers_monotonic(prior,expedition)
		if not issue.is_empty():
			return {"ok":false,"reason":issue}
	return _write(path,expedition,player,repository)
