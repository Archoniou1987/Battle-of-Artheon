class_name SoloTownExpeditionBridge
extends RefCounted

## Town and expedition MUST NOT concurrently mutate independent copies
## of the same player's inventory. This bridge only seeds an expedition
## once and returns the canonical saved owners on subsequent launches.
const ORIGIN_KEY := "solo_town_origin_v1"

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

static func town_matches_origin(expedition: ExpeditionState, town_player: CharacterState, town_repository: ItemRepository) -> bool:
	if expedition == null or town_player == null or town_repository == null:
		return false
	var origin: Variant = expedition.world_state.get(ORIGIN_KEY,{})
	return origin is Dictionary and String(origin.get("character_id","")) == town_player.character_id and String(origin.get("fingerprint","")) == _town_fingerprint(town_player,town_repository)
