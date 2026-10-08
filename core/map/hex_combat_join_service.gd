class_name HexCombatJoinService
extends RefCounted

# Primary combatants are mandatory. Nearby NPCs join once based on aggression.
static func assemble(map:TacticalMapState,bridge:MapNpcBridge,combat_cell:Vector2i,primary_ids:Array[String],aggression:Dictionary,rng:RandomNumberGenerator)->Dictionary:
	if map==null or bridge==null or rng==null or not map.in_bounds(combat_cell):
		return {"ok":false,"reason":"invalid_context"}
	var members:Array[NpcInstance]=[]
	var ids:Array[String]=[]
	var selected:Dictionary={}
	for npc_id in primary_ids:
		if selected.has(npc_id) or not bridge.instances.has(npc_id) or not map.entity_positions.has(npc_id):
			return {"ok":false,"reason":"invalid_primary"}
		var npc:NpcInstance=bridge.instances[npc_id]
		if not npc.is_alive() or map.entity_positions[npc_id]!=combat_cell:
			return {"ok":false,"reason":"invalid_primary"}
		selected[npc_id]=true
		members.append(npc)
		ids.append(npc_id)
	if ids.is_empty():
		return {"ok":false,"reason":"missing_primary"}
	var candidates:Array=bridge.instances.keys()
	candidates.sort()
	for raw_id in candidates:
		var npc_id:String=String(raw_id)
		if selected.has(npc_id) or not map.entity_positions.has(npc_id):
			continue
		var npc:NpcInstance=bridge.instances[npc_id]
		if not npc.is_alive():
			continue
		var position:Vector2i=map.entity_positions[npc_id]
		if HexGrid.distance(position,combat_cell)>1:
			continue
		var chance:=clampf(float(aggression.get(npc_id,npc.aggression)),0.0,100.0)
		if chance>=100.0 or (chance>0.0 and rng.randf()*100.0<chance):
			selected[npc_id]=true
			members.append(npc)
			ids.append(npc_id)
	return {"ok":true,"npcs":members,"npc_instance_ids":ids,"combat_cell":combat_cell}
