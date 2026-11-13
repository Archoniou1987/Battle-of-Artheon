class_name SoloTownExpeditionBridge
extends RefCounted

## Town and expedition MUST NOT concurrently mutate independent copies
## of the same player's inventory. This bridge only seeds an expedition
## once and returns the canonical saved owners on subsequent launches.
const ORIGIN_KEY := "solo_town_origin_v1"
const START_CELL_KEY := ExpeditionState.SOLO_START_CELL_KEY

static func expedition_id_for_player(player_id: String) -> String:
	if not MapWorldCommitService._valid_id(player_id):
		return ""
	return "solo_exp_" + player_id

static func _town_fingerprint(player: CharacterState, repository: ItemRepository) -> String:
	var character_data := MapWorldCommitService._character_to_dict(player)
	var payload := JSON.stringify({"character":character_data,"repository":repository.to_dict()})
	return payload.sha256_text()

static func create_from_town(path: String, expedition_id: String, seed: int, starting_cell: Vector2i, town_player: CharacterState, town_repository: ItemRepository, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if town_player == null or town_repository == null or not MapWorldCommitService._valid_id(expedition_id) or not MapWorldCommitService._valid_path(path) or not MapWorldCommitService._valid_path(manifest_path):
		return {"ok":false,"reason":"invalid_town_handoff"}
	if town_player.in_combat:
		return {"ok":false,"reason":"town_combat_active"}
	if FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"pending_combat_must_recover"}
	if FileAccess.file_exists(path):
		return {"ok":false,"reason":"expedition_already_exists"}
	# Validate the actual complete character/repository contract before
	# creating the save. Do not mutate the town's live references.
	var copied_repository := ItemRepository.from_dict(town_repository.to_dict())
	if copied_repository.size() != town_repository.size():
		return {"ok":false,"reason":"town_repository_invalid"}
	var restored: Dictionary = MapWorldCommitService._restore_character(MapWorldCommitService._character_to_dict(town_player),copied_repository)
	if not bool(restored.get("ok",false)):
		return {"ok":false,"reason":"town_character_invalid","detail":String(restored.get("reason","unknown"))}
	var expedition := ExpeditionState.new(expedition_id,null,seed)
	expedition.player_position = starting_cell
	expedition.world_state[START_CELL_KEY] = [starting_cell.x,starting_cell.y]
	var fingerprint := _town_fingerprint(town_player,town_repository)
	expedition.world_state[ORIGIN_KEY] = {"character_id":town_player.character_id,"fingerprint":fingerprint}
	var created: Dictionary = ExpeditionSaveService.save(path,expedition,restored["character"],copied_repository)
	if not bool(created.get("ok",false)):
		return created
	return {"ok":true,"expedition_id":expedition_id,"player_id":town_player.character_id,"origin_sha256":fingerprint}

static func open_existing(path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	# This gate recovers terminal outcomes before returning owners.
	var checked: Dictionary = SoloExpeditionLaunchGate.inspect(path,manifest_path,expedition_id,player_id)
	if not bool(checked.get("ok",false)):
		return checked
	if String(checked.get("state","")) not in ["ready","ready_after_recovery"]:
		return {"ok":false,"reason":"expedition_not_started","state":checked.get("state","")}
	var expedition: ExpeditionState = checked["expedition"]
	var origin: Variant = expedition.world_state.get(ORIGIN_KEY,{})
	if not origin is Dictionary or String(origin.get("character_id","")) != player_id or String(origin.get("fingerprint","")).length() != 64:
		return {"ok":false,"reason":"invalid_town_origin"}
	return {"ok":true,"state":checked["state"],"expedition":expedition,"character":checked["character"],"repository":checked["repository"]}


## The next Solo run must never overwrite the previous expedition. Only a
## fully closed, adopted snapshot can be archived. A crash after rename
## leaves the canonical town intact and the launch gate in NEW state.
static func archive_adopted_expedition(path: String, town_path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not MapWorldCommitService._valid_path(town_path) or FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"archive_invalid_path_or_pending_combat"}
	var old := ExpeditionSaveService.read(path,expedition_id,player_id)
	if not bool(old.get("ok",false)):
		return {"ok":false,"reason":"archive_expedition_invalid","detail":String(old.get("reason","unknown"))}
	var expedition: ExpeditionState = old["expedition"]
	if expedition.status != ExpeditionState.STATUS_EXITED or not expedition.world_state.has(SoloTownReturnService.RETURN_KEY):
		return {"ok":false,"reason":"archive_requires_returned_expedition"}
	var sealed := ExpeditionSaveService._read_payload_envelope(path)
	if not bool(sealed.get("ok",false)):
		return sealed
	var town := SoloTownSaveService.read(town_path,player_id)
	if not bool(town.get("ok",false)):
		return {"ok":false,"reason":"archive_town_invalid","detail":String(town.get("reason","unknown"))}
	var origin: Dictionary = town.get("return_origin",{})
	if String(origin.get("expedition_id","")) != expedition_id or String(origin.get("snapshot_sha256","")) != String(sealed["sha256"]):
		return {"ok":false,"reason":"archive_return_not_adopted"}
	var archive_path := path + ".closed_" + String(sealed["sha256"]).substr(0,24)
	if FileAccess.file_exists(archive_path):
		return {"ok":false,"reason":"archive_already_exists","archive_path":archive_path}
	var status := DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(archive_path))
	if status != OK:
		return {"ok":false,"reason":"archive_move_failed","code":status}
	return {"ok":true,"archive_path":archive_path}


static func town_matches_origin(expedition: ExpeditionState, town_player: CharacterState, town_repository: ItemRepository) -> bool:
	if expedition == null or town_player == null or town_repository == null:
		return false
	var origin: Variant = expedition.world_state.get(ORIGIN_KEY,{})
	return origin is Dictionary and String(origin.get("character_id","")) == town_player.character_id and String(origin.get("fingerprint","")) == _town_fingerprint(town_player,town_repository)
