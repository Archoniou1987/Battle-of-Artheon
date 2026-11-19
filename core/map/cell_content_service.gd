class_name CellContentService
extends RefCounted

## Read-only current-cell projection for Solo's lower/right "На клетке" tab.
## This never starts combat, claims loot or modifies the map; UI actions
## must execute through the owning map/ground/combat service.
const KIND_ITEM := "item"
const KIND_NPC := "npc"
const KIND_OBJECT := "object"
const KIND_RESOURCE := "resource"

static func _actions_for_npc(npc: NpcInstance) -> Array[String]:
	var actions: Array[String] = ["inspect","attack"]
	# NPC behaviour is data-owned; attacking a peaceful animal uses the
	# SAME combat path as attacking a hostile NPC. This is a UI-facing
	# action hint only, not a combat authorization.
	return actions

static func inspect_current_cell(map: TacticalMapState, bridge: MapNpcBridge, expedition: ExpeditionState, player: CharacterState, now_unix: int = -1) -> Dictionary:
	if map == null or bridge == null or expedition == null or player == null:
		return {"ok":false,"reason":"invalid_cell_context"}
	if not map.entity_positions.has(player.character_id):
		return {"ok":false,"reason":"player_not_on_map"}
	var position: Vector2i = map.entity_positions[player.character_id]
	if not map.in_bounds(position):
		return {"ok":false,"reason":"invalid_player_cell"}
	var entries: Array[Dictionary] = []
	var item_ids: Dictionary = {}
	for ground in GroundLootService.items_at(expedition,position,player.character_id,now_unix):
		var id := String(ground.get("instance_id",""))
		if id.is_empty() or item_ids.has(id):
			return {"ok":false,"reason":"invalid_cell_ground_item"}
		item_ids[id] = true
		entries.append({"kind":KIND_ITEM,"id":id,"actions":["inspect","pick_up"],"ground":ground})
	for npc in bridge.npc_at(map,position):
		entries.append({"kind":KIND_NPC,"id":npc.instance_id,"name":npc.display_name,"level":npc.level,"aggression":npc.aggression,"actions":_actions_for_npc(npc)})
	var current: MapCell = map.cell(position)
	for object_id in current.object_ids:
		# These IDs are presentation identifiers only; an action resolver
		# must authorize opening, gathering or talking using real object data.
		entries.append({"kind":KIND_OBJECT,"id":object_id,"actions":["inspect"]})
	for area_id in current.area_ids:
		var area: MapArea = map.areas.get(area_id,null) as MapArea
		if area != null and area.area_type == "resource" and not area.depleted:
			entries.append({"kind":KIND_RESOURCE,"id":area_id,"actions":["inspect","gather"],"gathering_time_sec":area.gathering_time_sec})
	return {"ok":true,"cell":position,"entries":entries,"total":entries.size()}

## Only one cell is readable via the player location. Avoid a public
## inspect_arbitrary_hex(...) method that UI might abuse for remote pickups.
