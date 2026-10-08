class_name MapCombatOutcomeService
extends RefCounted

static func resolve_victory(result:Dictionary,map,bridge:MapNpcBridge,npc:NpcInstance,player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if npc==null: return {"ok":false,"reason":"missing_npc"}
	if not npc.is_alive(): return {"ok":false,"reason":"npc_already_defeated"}
	if String(result.get("winner_id",""))!=player.character_id or String(result.get("loser_id",""))!=npc.instance_id:
		return {"ok":false,"reason":"not_player_victory"}
	if not bridge.instances.has(npc.instance_id) or not map.entity_positions.has(npc.instance_id):
		return {"ok":false,"reason":"npc_not_on_map"}
	var pool:=EncounterLootPool.new()
	for drop in loot_service.roll_drops(npc,repository,quality_chances):
		var item_id:=String(drop.get("instance_id",""))
		if not item_id.is_empty():
			pool.add_drop(item_id,npc.instance_id)
	if not bridge.resolve_death(map,npc.instance_id): return {"ok":false,"reason":"death_resolution_failed"}
	pool.assign_all(player.character_id)
	return {"ok":true,"npc_instance_id":npc.instance_id,"npc_state":npc.life_state,"loot_pool":pool,"drops":pool.item_ids(),"drop_count":pool.entries.size()}


static func resolve_group_victory(result:Dictionary,map,bridge:MapNpcBridge,npcs:Array[NpcInstance],player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if String(result.get("winning_team",""))!="players":
		return {"ok":false,"reason":"not_player_victory"}
	var dead_ids:Array[String]=[]
	for raw_id in result.get("dead_ids",[]):
		dead_ids.append(String(raw_id))
	var defeated_ids:Array[String]=[]
	var eligible:Array[NpcInstance]=[]
	var seen_ids:Dictionary={}
	for npc in npcs:
		if npc==null or not dead_ids.has(npc.instance_id):
			continue
		if seen_ids.has(npc.instance_id) or not npc.is_alive() or not bridge.instances.has(npc.instance_id) or not map.entity_positions.has(npc.instance_id):
			return {"ok":false,"reason":"invalid_or_already_resolved_npc","npc_instance_id":npc.instance_id}
		seen_ids[npc.instance_id]=true
		eligible.append(npc)
	if eligible.is_empty(): return {"ok":false,"reason":"no_defeated_npcs"}
	var pool:=EncounterLootPool.new()
	for npc in eligible:
		var npc_drops:=loot_service.roll_drops(npc,repository,quality_chances)
		for drop in npc_drops:
			var item_id:=String(drop.get("instance_id",""))
			if not item_id.is_empty():
				pool.add_drop(item_id,npc.instance_id)
		if not bridge.resolve_death(map,npc.instance_id):
			return {"ok":false,"reason":"death_resolution_failed","npc_instance_id":npc.instance_id}
		defeated_ids.append(npc.instance_id)
	pool.assign_all(player.character_id)
	return {"ok":true,"defeated_ids":defeated_ids,"defeated_count":defeated_ids.size(),"loot_pool":pool,"drops":pool.item_ids(),"drop_count":pool.entries.size()}
