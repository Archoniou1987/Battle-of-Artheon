class_name MapCellWorldSession
extends RefCounted

## Binds a real, verified atomic expedition snapshot to a live tactical map.
## A UI must never use a synthetic CharacterState for world-mutating actions.
## Map state is supplied by the same expedition owner, not reconstructed here.
var expedition: ExpeditionState
var character: CharacterState
var repository: ItemRepository
var bridge: MapNpcBridge
var map: TacticalMapState
var snapshot_path: String = ""
var encounter_key: String = ""

static func open(snapshot: String, key: String, expedition_id: String, player_id: String, live_map: TacticalMapState, live_bridge: MapNpcBridge) -> Dictionary:
	if live_map == null or live_bridge == null or snapshot.is_empty() or key.is_empty():
		return {"ok":false,"reason":"missing_world_dependencies"}
	var restored: Dictionary = MapWorldCommitService.read(snapshot,key,expedition_id,player_id)
	if not bool(restored.get("ok",false)):
		return {"ok":false,"reason":"world_snapshot_not_verified","detail":String(restored.get("reason","unknown"))}
	var loaded_expedition: ExpeditionState = restored["expedition"]
	var loaded_character: CharacterState = restored["character"]
	var loaded_repo: ItemRepository = restored["repository"]
	if not loaded_expedition.is_active() or loaded_expedition.expedition_id != expedition_id or loaded_character.character_id != player_id:
		return {"ok":false,"reason":"world_owner_mismatch"}
	if not live_map.entity_positions.has(player_id):
		return {"ok":false,"reason":"live_player_not_on_map"}
	# The caller must first rebuild/reconcile NPC tombstones from this very
	# snapshot, and align the player location. Never teleport silently.
	var player_pos: Vector2i = live_map.entity_positions[player_id]
	if player_pos != loaded_expedition.player_position:
		return {"ok":false,"reason":"map_position_differs_from_saved_expedition"}
	for npc_id in live_bridge.instances:
		var npc: NpcInstance = live_bridge.instances[npc_id]
		if npc != null and npc.is_alive() and MapWorldCommitService.is_defeated_spawn(loaded_expedition,String(npc_id)):
			return {"ok":false,"reason":"unreconciled_dead_npc","npc_id":String(npc_id)}
	var world := MapCellWorldSession.new()
	world.expedition = loaded_expedition
	world.character = loaded_character
	world.repository = loaded_repo
	world.map = live_map
	world.bridge = live_bridge
	world.snapshot_path = snapshot
	world.encounter_key = key
	return {"ok":true,"session":world}

func current_cell(now_unix: int = -1) -> Dictionary:
	return CellContentService.inspect_current_cell(map,bridge,expedition,character,now_unix)

func save_player_position() -> Dictionary:
	if map == null or not map.entity_positions.has(character.character_id):
		return {"ok":false,"reason":"player_not_on_map"}
	var previous: Vector2i = expedition.player_position
	expedition.player_position = map.entity_positions[character.character_id]
	var saved: Dictionary = MapWorldCommitService.save_progress(snapshot_path,encounter_key,expedition,character,repository)
	if not bool(saved.get("ok",false)):
		expedition.player_position = previous
	return saved
