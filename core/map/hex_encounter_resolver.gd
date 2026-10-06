class_name HexEncounterResolver
extends RefCounted

static func resolve(event:Dictionary, map:TacticalMapState)->Dictionary:
	if event.is_empty():
		return {"ok":false,"reason":"missing_event"}
	var consequence:=str(event.get("consequence",""))
	var payload:Dictionary=event.get("payload",{})
	match consequence:
		"reveal_object":
			var object_id:=str(payload.get("object_id",""))
			var pos:Vector2i=payload.get("position",Vector2i(-1,-1))
			if object_id.is_empty() or not map.in_bounds(pos):
				return {"ok":false,"reason":"invalid_object"}
			return {"ok":map.add_object(object_id,pos),"consequence":consequence,"object_id":object_id,"position":pos}
		"teleport":
			var entity_id:=str(payload.get("entity_id",""))
			var destination:Vector2i=payload.get("destination",Vector2i(-1,-1))
			if entity_id.is_empty() or not map.entity_positions.has(entity_id) or not map.in_bounds(destination) or not map.cell(destination).is_passable():
				return {"ok":false,"reason":"invalid_teleport"}
			var origin:Vector2i=map.entity_positions[entity_id]
			map.entity_positions[entity_id]=destination
			map.mark_visited(destination)
			return {"ok":true,"consequence":consequence,"entity_id":entity_id,"from":origin,"to":destination}
		"damage", "apply_effect", "spawn_npc", "start_quest":
			return {"ok":true,"consequence":consequence,"payload":payload.duplicate(true)}
		_:
			return {"ok":false,"reason":"unknown_consequence","consequence":consequence}
