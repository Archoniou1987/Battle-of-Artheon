class_name SoloTownReturnService
extends RefCounted

## Close the authoritative Solo expedition FIRST. The city must rehydrate
## from this exact closed snapshot, never from its stale legacy saves.
## No second mutable town/character copy is persisted by this service.
const RETURN_KEY := "solo_town_return_v1"

static func _owned_repository(player: CharacterState, repository: ItemRepository) -> Dictionary:
	var result := ItemRepository.new()
	for id in player.inventory.instance_ids():
		var item_id := String(id)
		var item: Dictionary = repository.get_item(item_id)
		if item.is_empty() or not result.add_item(item.duplicate(true)):
			return {"ok":false,"reason":"missing_or_duplicate_owned_item"}
	return {"ok":true,"repository":result}

static func close_for_town(path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not MapWorldCommitService._valid_path(manifest_path):
		return {"ok":false,"reason":"return_invalid_path"}
	if FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"return_pending_combat"}
	var restored: Dictionary = ExpeditionSaveService.read(path,expedition_id,player_id)
	if not bool(restored.get("ok",false)):
		return restored
	var expedition: ExpeditionState = restored["expedition"]
	var player: CharacterState = restored["character"]
	var repository: ItemRepository = restored["repository"]
	var origin: Variant = expedition.world_state.get(SoloTownExpeditionBridge.ORIGIN_KEY,{})
	if not origin is Dictionary or String(origin.get("character_id","")) != player_id:
		return {"ok":false,"reason":"return_town_origin_invalid"}
	if not expedition.is_active():
		if expedition.status == ExpeditionState.STATUS_EXITED and expedition.world_state.has(RETURN_KEY):
			return {"ok":true,"already_closed":true}
		return {"ok":false,"reason":"return_expedition_not_active"}
	var owned := _owned_repository(player,repository)
	if not bool(owned.get("ok",false)):
		return owned
	# The return receipt seals exactly which instances belong to the hero.
	# Unclaimed ground items stay in the closed expedition's world_state.
	var owned_ids: Array = player.inventory.instance_ids().duplicate()
	owned_ids.sort()
	var previous_world: Dictionary = expedition.world_state.duplicate(true)
	expedition.world_state[RETURN_KEY] = {"player_id":player_id,"item_ids":owned_ids,"town_origin_sha256":String(origin.get("fingerprint",""))}
	expedition.status = ExpeditionState.STATUS_EXITED
	var saved: Dictionary = ExpeditionSaveService.save(path,expedition,player,repository)
	if not bool(saved.get("ok",false)):
		expedition.world_state = previous_world
		expedition.status = ExpeditionState.STATUS_ACTIVE
		return saved
	return {"ok":true,"already_closed":false,"saved_to":path}

static func load_returned_owner(path: String, expedition_id: String, player_id: String, manifest_path: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"return_pending_combat"}
	var restored: Dictionary = ExpeditionSaveService.read(path,expedition_id,player_id)
	if not bool(restored.get("ok",false)):
		return restored
	var expedition: ExpeditionState = restored["expedition"]
	var player: CharacterState = restored["character"]
	var repository: ItemRepository = restored["repository"]
	if expedition.status != ExpeditionState.STATUS_EXITED:
		return {"ok":false,"reason":"return_not_committed"}
	var receipt: Variant = expedition.world_state.get(RETURN_KEY,{})
	if not receipt is Dictionary or String(receipt.get("player_id","")) != player_id or not receipt.get("item_ids") is Array:
		return {"ok":false,"reason":"return_receipt_invalid"}
	var ids: Array = player.inventory.instance_ids().duplicate()
	ids.sort()
	if ids != Array(receipt["item_ids"]):
		return {"ok":false,"reason":"return_ownership_changed"}
	var isolated := _owned_repository(player,repository)
	if not bool(isolated.get("ok",false)):
		return isolated
	var owned_repo: ItemRepository = isolated["repository"]
	var reloaded := MapWorldCommitService._restore_character(MapWorldCommitService._character_to_dict(player),owned_repo)
	if not bool(reloaded.get("ok",false)):
		return {"ok":false,"reason":"return_character_rejected"}
	return {"ok":true,"character":reloaded["character"],"repository":owned_repo,"expedition":expedition}
