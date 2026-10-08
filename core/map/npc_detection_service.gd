class_name NpcDetectionService
extends RefCounted

static func detect(map:TacticalMapState,bridge:MapNpcBridge,player_id:String,radii:Dictionary={})->Array[Dictionary]:
	var found:Array[Dictionary]=[]
	if map==null or bridge==null or not map.entity_positions.has(player_id):
		return found
	var player_pos:Vector2i=map.entity_positions[player_id]
	var ids:Array=bridge.instances.keys()
	ids.sort()
	for raw_id in ids:
		var npc_id:String=String(raw_id)
		var npc:NpcInstance=bridge.instances[npc_id]
		if not npc.is_alive() or not map.entity_positions.has(npc_id):
			continue
		var radius:=maxi(0,int(radii.get(npc_id,npc.detection_radius)))
		var distance:=HexGrid.distance(map.entity_positions[npc_id],player_pos)
		if distance<=radius:
			found.append({"npc_instance_id":npc_id,"distance":distance,"radius":radius})
	return found
