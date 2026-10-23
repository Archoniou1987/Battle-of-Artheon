class_name SoloLiveMapSession
extends RefCounted

const WIDTH := 12
const HEIGHT := 12

var expedition: ExpeditionState
var character: CharacterState
var repository: ItemRepository
var map: TacticalMapState
var npc_bridge: MapNpcBridge
var save_path: String
var manifest_path: String
const SOLO_PICKUP_SECONDS := 2
var loot_pickups: GroundLootService = GroundLootService.new()

static func open(path: String, manifest: String, expedition_id: String, player_id: String) -> Dictionary:
	if path == SoloGameStateService.PATH:
		var gate := SoloExpeditionLaunchGate.inspect(path,manifest,expedition_id,player_id)
		if not bool(gate.get("ok",false)):
			return gate
		var unified := SoloGameStateService.read(path,player_id)
		if not bool(unified.get("ok",false)):
			return unified
		if String(unified.get("location","")) != SoloGameStateService.LOCATION_MAP:
			return {"ok":false,"reason":"game_state_not_on_map"}
		return _mount(path,manifest,unified["expedition"],unified["character"],unified["repository"])
	var verified := SoloTownExpeditionBridge.open_existing(path,expedition_id,player_id,manifest)
	if not bool(verified.get("ok",false)):
		return verified
	return _mount(path,manifest,verified["expedition"],verified["character"],verified["repository"])

## Mount an already independently validated expedition snapshot for
## checkpoint recovery. Never grant movement while a manifest exists.
static func open_pending(path: String, manifest: String, expedition_id: String, player_id: String) -> Dictionary:
	var pending := SoloCombatSessionManifest.read(manifest)
	if not bool(pending.get("ok",false)):
		return pending
	var data: Dictionary = pending["data"]
	if String(data.get("expedition_path","")) != path or String(data.get("expedition_id","")) != expedition_id or String(data.get("player_id","")) != player_id:
		return {"ok":false,"reason":"pending_owner_mismatch"}
	if FileAccess.file_exists(String(data["terminal_path"])):
		return {"ok":false,"reason":"pending_terminal_requires_recovery"}
	var verified := ExpeditionSaveService.read(path,expedition_id,player_id)
	if not bool(verified.get("ok",false)):
		return verified
	if not verified["expedition"].is_active():
		return {"ok":false,"reason":"pending_world_closed"}
	var base := ExpeditionSaveService._read_payload_envelope(path)
	if not bool(base.get("ok",false)) or String(base.get("sha256","")) != String(data["base_sha256"]):
		return {"ok":false,"reason":"pending_world_revision_changed"}
	return _mount(path,manifest,verified["expedition"],verified["character"],verified["repository"])

static func _mount(path: String, manifest: String, saved_expedition: ExpeditionState, saved_character: CharacterState, saved_repository: ItemRepository) -> Dictionary:
	var session := SoloLiveMapSession.new()
	session.expedition = saved_expedition
	session.character = saved_character
	session.repository = saved_repository
	session.save_path = path
	session.manifest_path = manifest
	session.map = TacticalMapState.new(WIDTH,HEIGHT)
	session.npc_bridge = MapNpcBridge.new()
	var npc_catalog := NpcRepository.new()
	var npc_document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/starting_region_npcs.json"))
	if not npc_document is Dictionary:
		return {"ok":false,"reason":"live_npc_catalog_invalid"}
	npc_catalog.load_definitions(npc_document)
	# Stable instance IDs and cells across all saves/restarts. The
	# encounter handler is intentionally not wired to the UI yet.
	var placements: Array = [
		{"id":"solo_npc_bandit_01","template":"NPC003","cell":Vector2i(7,5)},
		{"id":"solo_npc_wolf_01","template":"NPC001","cell":Vector2i(8,8)},
		{"id":"solo_npc_archer_01","template":"NPC004","cell":Vector2i(4,8)}
	]
	for placement in placements:
		var npc_id := String(placement["id"])
		if MapWorldCommitService.is_defeated_spawn(session.expedition,npc_id):
			continue
		var template: NpcState = npc_catalog.get_npc(String(placement["template"]))
		if template == null:
			return {"ok":false,"reason":"live_npc_template_missing"}
		var npc := NpcInstance.new(npc_id,template)
		if not session.npc_bridge.register_npc(session.map,npc,placement["cell"]):
			return {"ok":false,"reason":"live_npc_registration_failed"}
	if not session.map.place_entity(session.character.character_id,session.expedition.player_position):
		return {"ok":false,"reason":"saved_player_hex_invalid"}
	session.map.mark_visited(session.expedition.player_position)
	session.map.reveal_from(session.expedition.player_position,3)
	return {"ok":true,"session":session}

func move_one_step(to: Vector2i) -> Dictionary:
	if expedition == null or map == null or not expedition.is_active():
		return {"ok":false,"reason":"expedition_not_active"}
	if FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"pending_combat_blocks_movement"}
	# Do not allow the live world to move onto an enemy until the
	# verified battle UI and settlement contract are connected.
	# Movement and rewards must remain unchanged on a rejected contact.
	var encountered := npc_bridge.encounter_at(map,to)
	if bool(encountered.get("ok",false)):
		return {"ok":false,"reason":"combat_ui_not_connected","npc_instance_ids":encountered.get("npc_instance_ids",[])}
	var from := expedition.player_position
	var moved := map.move_entity(character.character_id,to)
	if not bool(moved.get("ok",false)):
		return moved
	expedition.player_position = to
	var stored := ExpeditionSaveService.save(save_path,expedition,character,repository)
	if not bool(stored.get("ok",false)):
		map.entity_positions[character.character_id] = from
		expedition.player_position = from
		return {"ok":false,"reason":"movement_save_failed","detail":String(stored.get("reason","unknown"))}
	map.reveal_from(to,3)
	return {"ok":true,"position":to}

## Solo's two-second pickup is a mode parameter; the shared service
## keeps its five-second default for other gameplay.
func visible_ground_items() -> Array[Dictionary]:
	if expedition == null or character == null:
		return []
	return GroundLootService.items_at(expedition,expedition.player_position,character.character_id,int(Time.get_unix_time_from_system()))

func begin_ground_pickup(instance_id: String, now_unix: int = -1) -> Dictionary:
	if expedition == null or character == null or repository == null or map == null or FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"pickup_world_locked"}
	var moment := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	return loot_pickups.begin_pickup(expedition,map,character,repository,instance_id,moment,SOLO_PICKUP_SECONDS)

func cancel_ground_pickup(ticket: String) -> bool:
	return loot_pickups.cancel_pickup(ticket)

func finish_ground_pickup(ticket: String, now_unix: int = -1) -> Dictionary:
	if expedition == null or character == null or repository == null or map == null or FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"pickup_world_locked"}
	var moment := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	# Transaction boundary: roll back BOTH item owners after a failed save.
	var previous_world: Dictionary = expedition.world_state.duplicate(true)
	var previous_inventory: Dictionary = character.inventory.to_dict()
	var result := loot_pickups.finish_pickup(ticket,expedition,map,character,repository,moment)
	if not bool(result.get("ok",false)):
		return result
	var saved := ExpeditionSaveService.save(save_path,expedition,character,repository)
	if not bool(saved.get("ok",false)):
		expedition.world_state = previous_world
		character.inventory = InventoryState.from_dict(previous_inventory,repository)
		return {"ok":false,"reason":"pickup_save_failed","detail":String(saved.get("reason","unknown"))}
	return {"ok":true,"instance_id":String(result["instance_id"]),"saved":true}

func return_to_town(town_path: String) -> Dictionary:
	if save_path == SoloGameStateService.PATH:
		return SoloGameStateService.set_location(save_path,character.character_id,SoloGameStateService.LOCATION_TOWN,manifest_path)
	var closed := SoloTownReturnService.close_for_town(save_path,expedition.expedition_id,character.character_id,manifest_path)
	if not bool(closed.get("ok",false)):
		return closed
	var adopted := SoloTownSaveService.adopt_closed_expedition(town_path,save_path,expedition.expedition_id,character.character_id,manifest_path)
	if not bool(adopted.get("ok",false)):
		return {"ok":false,"reason":"town_adoption_failed","detail":String(adopted.get("reason","unknown"))}
	return {"ok":true,"already_adopted":bool(adopted.get("already_adopted",false))}
