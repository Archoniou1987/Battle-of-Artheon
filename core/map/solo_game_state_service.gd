class_name SoloGameStateService
extends RefCounted

## One durable Solo owner for character, item repository, world and location.
## Combat checkpoints remain separate crash-recovery journals, never another
## freely mutable character save. The envelope codec is deliberately shared
## with ExpeditionSaveService so verified combat receipts can publish to this
## same file without modifying the battle engine.
const PATH := "user://solo_game_state_v1.json"
const LEGACY_EXPEDITION := "user://solo_expedition_save_v1.json"
const LEGACY_TOWN := SoloTownSaveService.DEFAULT_PATH
const LOCATION_KEY := "solo_game_location_v1"
const LOCATION_TOWN := "town"
const LOCATION_MAP := "map"
const START_CELL := Vector2i(5,5)

static func _id(player_id: String) -> String:
	return SoloTownExpeditionBridge.expedition_id_for_player(player_id)

static func read(path: String, player_id: String) -> Dictionary:
	var stored := ExpeditionSaveService.read(path,_id(player_id),player_id)
	if not bool(stored.get("ok",false)):
		return stored
	var expedition: ExpeditionState = stored["expedition"]
	var location := String(expedition.world_state.get(LOCATION_KEY,""))
	if not expedition.is_active() or location not in [LOCATION_TOWN,LOCATION_MAP]:
		return {"ok":false,"reason":"game_state_location_or_status_invalid"}
	var envelope := ExpeditionSaveService._read_payload_envelope(path)
	if not bool(envelope.get("ok",false)):
		return envelope
	stored["location"] = location
	stored["sha256"] = String(envelope["sha256"])
	return stored

static func create(path: String, player: CharacterState, repository: ItemRepository, seed: int = 1) -> Dictionary:
	if player == null or repository == null or not MapWorldCommitService._valid_path(path):
		return {"ok":false,"reason":"game_state_invalid_create"}
	if FileAccess.file_exists(path):
		return {"ok":false,"reason":"game_state_already_exists"}
	var expedition := ExpeditionState.new(_id(player.character_id),null,seed)
	expedition.player_position = START_CELL
	expedition.world_state[ExpeditionState.SOLO_START_CELL_KEY] = [START_CELL.x,START_CELL.y]
	expedition.world_state[LOCATION_KEY] = LOCATION_TOWN
	var written := ExpeditionSaveService.save(path,expedition,player,repository)
	if not bool(written.get("ok",false)):
		return written
	return read(path,player.character_id)

## After a completed, formally adopted legacy expedition the town may have
## received further legitimate items and progression. Keep THAT later town
## owner, plus unowned world loot from the sealed expedition. The receipt
## proves its origin; never guess from item counts or character fingerprints.
static func _adopted_town_owner(expedition_path: String, town_path: String, player_id: String, old_expedition: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(town_path):
		return {"ok":false,"reason":"no_legacy_town"}
	var town := SoloTownSaveService.read(town_path,player_id)
	if not bool(town.get("ok",false)):
		return town
	var sealed := ExpeditionSaveService._read_payload_envelope(expedition_path)
	if not bool(sealed.get("ok",false)):
		return sealed
	var receipt: Dictionary = town["return_origin"]
	if String(receipt.get("expedition_id","")) != String(old_expedition["expedition"].expedition_id) or String(receipt.get("snapshot_sha256","")) != String(sealed["sha256"]):
		return {"ok":false,"reason":"legacy_return_not_adopted"}
	var legacy_hero: CharacterState = old_expedition["character"]
	var legacy_repository: ItemRepository = old_expedition["repository"]
	var city_hero: CharacterState = town["character"]
	var city_repository: ItemRepository = town["repository"]
	var merged := ItemRepository.new()
	var all_old: Dictionary = legacy_repository.to_dict().get("items",{})
	for raw_id in all_old.keys():
		var id := String(raw_id)
		if legacy_hero.inventory.owns(id):
			continue
		if city_hero.inventory.owns(id):
			return {"ok":false,"reason":"legacy_return_world_item_collision","item_id":id}
		if not merged.add_item(all_old[id]):
			return {"ok":false,"reason":"legacy_return_world_item_invalid","item_id":id}
	for raw_id in city_hero.inventory.instance_ids():
		var id := String(raw_id)
		if not merged.add_item(city_repository.get_item(id)):
			return {"ok":false,"reason":"legacy_return_city_item_invalid","item_id":id}
	return {"ok":true,"character":city_hero,"repository":merged}


## Once-only import. Legacy files are NEVER renamed, deleted or written by
## this service. An active map owns its latest progress; a closed map owns
## its returned result. The old town file stays available for manual recovery
## of any divergent city-only changes, not silently merged or discarded.
static func bootstrap(player_id: String, path: String = PATH, legacy_town: String = LEGACY_TOWN, legacy_expedition: String = LEGACY_EXPEDITION, manifest: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if FileAccess.file_exists(path):
		return read(path,player_id)
	if FileAccess.file_exists(legacy_expedition):
		if FileAccess.file_exists(manifest):
			var pending := SoloCombatSessionManifest.read(manifest)
			if not bool(pending.get("ok",false)):
				return {"ok":false,"reason":"legacy_pending_combat_invalid","detail":String(pending.get("reason","unknown"))}
			var pending_data: Dictionary = pending["data"]
			if String(pending_data.get("expedition_path","")) != legacy_expedition or String(pending_data.get("player_id","")) != player_id:
				return {"ok":false,"reason":"legacy_pending_combat_owner_mismatch"}
			# Only a fully sealed terminal outcome can be reconciled here.
			# An in-progress checkpoint stays untouched until the fight ends.
			if not FileAccess.file_exists(String(pending_data["terminal_path"])):
				return {"ok":false,"reason":"legacy_pending_combat_must_finish_before_migration"}
			var recovered := SoloCombatSessionManifest.recover_on_launch(manifest)
			if not bool(recovered.get("ok",false)):
				return {"ok":false,"reason":"legacy_terminal_recovery_failed","detail":String(recovered.get("reason","unknown"))}
		var previous := ExpeditionSaveService.read(legacy_expedition,_id(player_id),player_id)
		if not bool(previous.get("ok",false)):
			return {"ok":false,"reason":"legacy_expedition_invalid","detail":String(previous.get("reason","unknown"))}
		var expedition: ExpeditionState = previous["expedition"]
		if expedition.status not in [ExpeditionState.STATUS_ACTIVE,ExpeditionState.STATUS_EXITED]:
			return {"ok":false,"reason":"legacy_expedition_status_unsupported"}
		var location := LOCATION_MAP if expedition.is_active() else LOCATION_TOWN
		var selected_character: CharacterState = previous["character"]
		var selected_repository: ItemRepository = previous["repository"]
		var migrated_from := "legacy_expedition"
		if location == LOCATION_TOWN and FileAccess.file_exists(legacy_town):
			var accepted := _adopted_town_owner(legacy_expedition,legacy_town,player_id,previous)
			if bool(accepted.get("ok",false)):
				selected_character = accepted["character"]
				selected_repository = accepted["repository"]
				migrated_from = "legacy_returned_town"
			elif String(accepted.get("reason","")) in ["legacy_return_world_item_collision","legacy_return_world_item_invalid","legacy_return_city_item_invalid"]:
				return accepted
		expedition.status = ExpeditionState.STATUS_ACTIVE
		expedition.world_state.erase(SoloTownExpeditionBridge.ORIGIN_KEY)
		expedition.world_state.erase(SoloTownReturnService.RETURN_KEY)
		expedition.world_state[LOCATION_KEY] = location
		var saved := ExpeditionSaveService.save(path,expedition,selected_character,selected_repository)
		if not bool(saved.get("ok",false)):
			return {"ok":false,"reason":"game_state_legacy_import_failed","detail":String(saved.get("reason","unknown"))}
		var loaded := read(path,player_id)
		loaded["migrated_from"] = migrated_from
		loaded["legacy_town_preserved"] = FileAccess.file_exists(legacy_town)
		return loaded
	if FileAccess.file_exists(legacy_town):
		var town := SoloTownSaveService.read(legacy_town,player_id)
		if not bool(town.get("ok",false)):
			return {"ok":false,"reason":"legacy_town_invalid","detail":String(town.get("reason","unknown"))}
		var fresh := create(path,town["character"],town["repository"],1)
		if bool(fresh.get("ok",false)):
			fresh["migrated_from"] = "legacy_town"
		return fresh
	if FileAccess.file_exists(manifest):
		return {"ok":false,"reason":"orphan_legacy_combat_manifest"}
	return {"ok":false,"reason":"game_state_not_found"}

## Town mutations publish directly to the same durable owner that map
## movement and combat settlement use. sha is a stale-write guard, NOT a
## comparison or reconciliation of town and expedition characters.
static func save_town(path: String, player: CharacterState, repository: ItemRepository, expected_sha256: String) -> Dictionary:
	if player == null or repository == null:
		return {"ok":false,"reason":"game_state_town_owner_missing"}
	var current := read(path,player.character_id)
	if not bool(current.get("ok",false)):
		return current
	if String(current["location"]) != LOCATION_TOWN:
		return {"ok":false,"reason":"game_state_not_in_town"}
	if String(current["sha256"]) != expected_sha256:
		return {"ok":false,"reason":"game_state_stale_revision"}
	var committed := ExpeditionSaveService.save(path,current["expedition"],player,repository,true)
	if not bool(committed.get("ok",false)):
		return committed
	var revision := ExpeditionSaveService._read_payload_envelope(path)
	if not bool(revision.get("ok",false)):
		return revision
	return {"ok":true,"sha256":String(revision["sha256"])}

static func set_location(path: String, player_id: String, destination: String, manifest: String = SoloCombatSessionManifest.PATH) -> Dictionary:
	if destination not in [LOCATION_TOWN,LOCATION_MAP]:
		return {"ok":false,"reason":"game_state_unknown_destination"}
	if FileAccess.file_exists(manifest):
		return {"ok":false,"reason":"game_state_pending_combat"}
	var current := read(path,player_id)
	if not bool(current.get("ok",false)):
		return current
	if String(current["location"]) == destination:
		return {"ok":true,"already_there":true}
	var expedition: ExpeditionState = current["expedition"]
	expedition.world_state[LOCATION_KEY] = destination
	var result := ExpeditionSaveService.save(path,expedition,current["character"],current["repository"])
	if not bool(result.get("ok",false)):
		return result
	return {"ok":true,"already_there":false}
