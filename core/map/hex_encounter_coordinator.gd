class_name HexEncounterCoordinator
extends RefCounted

var combat_active:bool=false

func try_start(map:TacticalMapState,bridge:MapNpcBridge,player_id:String,rng:RandomNumberGenerator)->Dictionary:
	if combat_active:
		return {"ok":false,"reason":"combat_active"}
	if map==null or bridge==null or rng==null or not map.entity_positions.has(player_id):
		return {"ok":false,"reason":"invalid_context"}
	var player_pos:Vector2i=map.entity_positions[player_id]
	var primary:Array[String]=[]
	for npc in bridge.npc_at(map,player_pos):
		primary.append(npc.instance_id)
	if primary.is_empty():
		return {"ok":false,"reason":"no_hostile_contact"}
	# Combat requires contact; detection alone never starts combat.
	var assembled:=_assemble_from_player(map,bridge,player_pos,primary,rng)
	if bool(assembled.get("ok",false)):
		combat_active=true
	return assembled

func _assemble_from_player(map:TacticalMapState,bridge:MapNpcBridge,player_pos:Vector2i,primary:Array[String],rng:RandomNumberGenerator)->Dictionary:
	# Primary detected NPC may stand outside the join ring; do not teleport it.
	var ids:Array[String]=[]
	var members:Array[NpcInstance]=[]
	var chosen:Dictionary={}
	for npc_id in primary:
		if chosen.has(npc_id) or not bridge.instances.has(npc_id):
			continue
		var npc:NpcInstance=bridge.instances[npc_id]
		if not npc.is_alive() or not map.entity_positions.has(npc_id):
			continue
		chosen[npc_id]=true
		ids.append(npc_id)
		members.append(npc)
	var candidates:Array=bridge.instances.keys()
	candidates.sort()
	for raw_id in candidates:
		var npc_id:String=String(raw_id)
		if chosen.has(npc_id) or not map.entity_positions.has(npc_id):
			continue
		var npc:NpcInstance=bridge.instances[npc_id]
		if not npc.is_alive() or HexGrid.distance(map.entity_positions[npc_id],player_pos)>1:
			continue
		var chance:=clampf(npc.aggression,0.0,100.0)
		if chance>=100.0 or (chance>0.0 and rng.randf()*100.0<chance):
			chosen[npc_id]=true
			ids.append(npc_id)
			members.append(npc)
	if members.is_empty():
		return {"ok":false,"reason":"no_npc"}
	var first:NpcInstance=members[0]
	return {"ok":true,"npc":first,"npcs":members,"npc_instance_id":first.instance_id,
		"npc_template_id":first.template_id,"npc_instance_ids":ids,"combat_cell":player_pos}

func finish_combat()->void:
	combat_active=false
