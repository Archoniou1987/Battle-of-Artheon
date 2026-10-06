class_name ResourceGatheringService
extends RefCounted

func can_gather(map:TacticalMapState, entity_id:String, area_id:String)->bool:
	if not map.entity_positions.has(entity_id) or not map.areas.has(area_id):
		return false
	var area:MapArea = map.areas[area_id]
	if area.depleted or area.area_type != "resource":
		return false
	var pos:Vector2i = map.entity_positions[entity_id]
	return map.cell(pos).area_ids.has(area_id)

func begin(map:TacticalMapState, entity_id:String, area_id:String)->Dictionary:
	if not can_gather(map, entity_id, area_id):
		return {"ok":false}
	var area:MapArea = map.areas[area_id]
	return {"ok":true, "area_id":area.area_id, "duration_sec":area.gathering_time_sec, "level":area.level, "rarity":area.rarity, "richness":area.richness, "loot_group_ids":area.loot_group_ids.duplicate()}
