class_name SoloLiveMapSession
extends RefCounted

const WIDTH := 12
const HEIGHT := 12

var expedition: ExpeditionState
var character: CharacterState
var repository: ItemRepository
var map: TacticalMapState
var save_path: String
var manifest_path: String

static func open(path: String, manifest: String, expedition_id: String, player_id: String) -> Dictionary:
	var verified := SoloTownExpeditionBridge.open_existing(path,expedition_id,player_id,manifest)
	if not bool(verified.get("ok",false)):
		return verified
	var session := SoloLiveMapSession.new()
	session.expedition = verified["expedition"]
	session.character = verified["character"]
	session.repository = verified["repository"]
	session.save_path = path
	session.manifest_path = manifest
	session.map = TacticalMapState.new(WIDTH,HEIGHT)
	if not session.map.place_entity(player_id,session.expedition.player_position):
		return {"ok":false,"reason":"saved_player_hex_invalid"}
	session.map.mark_visited(session.expedition.player_position)
	session.map.reveal_from(session.expedition.player_position,3)
	return {"ok":true,"session":session}

func move_one_step(to: Vector2i) -> Dictionary:
	if expedition == null or map == null or not expedition.is_active():
		return {"ok":false,"reason":"expedition_not_active"}
	if FileAccess.file_exists(manifest_path):
		return {"ok":false,"reason":"pending_combat_blocks_movement"}
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

func return_to_town(town_path: String) -> Dictionary:
	var closed := SoloTownReturnService.close_for_town(save_path,expedition.expedition_id,character.character_id,manifest_path)
	if not bool(closed.get("ok",false)):
		return closed
	var adopted := SoloTownSaveService.adopt_closed_expedition(town_path,save_path,expedition.expedition_id,character.character_id,manifest_path)
	if not bool(adopted.get("ok",false)):
		return {"ok":false,"reason":"town_adoption_failed","detail":String(adopted.get("reason","unknown"))}
	return {"ok":true,"already_adopted":bool(adopted.get("already_adopted",false))}
