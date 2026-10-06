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

func begin(map:TacticalMapState, entity_id:String, area_id:String, sources:ResourceSourceRepository = null)->Dictionary:
	if not can_gather(map, entity_id, area_id):
		return {"ok":false}
	var area:MapArea = map.areas[area_id]
	if sources == null or area.resource_source_ids.is_empty():
		return {"ok":true, "area_id":area.area_id, "duration_sec":area.gathering_time_sec, "level":area.level, "rarity":area.rarity, "richness":area.richness, "loot_group_ids":area.loot_group_ids.duplicate()}
	var available:Array[Dictionary] = []
	var duration:=0.0
	for source_id in area.resource_source_ids:
		var source:=sources.get_source(source_id)
		if source == null or source.is_depleted():
			continue
		available.append({"source_id":source.source_id, "resource_id":source.resource_id, "quantity":source.quantity, "yield_min":source.yield_min, "yield_max":source.yield_max})
		if duration <= 0.0 or source.gathering_time_sec < duration:
			duration = source.gathering_time_sec
	if available.is_empty():
		area.depleted = true
		return {"ok":false, "reason":"depleted"}
	return {"ok":true, "area_id":area.area_id, "duration_sec":duration, "sources":available}

func gather(source_id:String, sources:ResourceSourceRepository, requested_yield:int)->Dictionary:
	var source:=sources.get_source(source_id)
	if source == null:
		return {"ok":false, "reason":"unknown_source"}
	if source.is_depleted():
		return {"ok":false, "reason":"depleted"}
	var clamped_yield:=clampi(requested_yield, source.yield_min, source.yield_max)
	var gathered:=source.take(clamped_yield)
	return {"ok":gathered > 0, "source_id":source.source_id, "resource_id":source.resource_id, "quantity":gathered, "remaining":source.quantity, "depleted":source.is_depleted()}
