class_name MapCombatOutcomeService
extends RefCounted

static func resolve_victory(result:Dictionary,map,bridge:MapNpcBridge,npc:NpcInstance,player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if npc==null: return {"ok":false,"reason":"missing_npc"}
	if String(result.get("winner_id",""))!=player.character_id or String(result.get("loser_id",""))!=npc.instance_id:
		return {"ok":false,"reason":"not_player_victory"}
	var drops:=loot_service.roll(npc,repository,player,quality_chances)
	if not bridge.resolve_death(map,npc.instance_id): return {"ok":false,"reason":"death_resolution_failed"}
	return {"ok":true,"npc_instance_id":npc.instance_id,"npc_state":npc.life_state,"drops":drops,"drop_count":drops.size()}


static func resolve_group_victory(result:Dictionary,map,bridge:MapNpcBridge,npcs:Array[NpcInstance],player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if String(result.get("winning_team",""))!="players":
		return {"ok":false,"reason":"not_player_victory"}
	var dead_ids:Array[String]=[]
	for raw_id in result.get("dead_ids",[]):
		dead_ids.append(String(raw_id))
	var defeated_ids:Array[String]=[]
	var pool:=EncounterLootPool.new()
	for npc in npcs:
		if npc==null or not dead_ids.has(npc.instance_id):
			continue
		var inventory_before:Dictionary={}
		for item_id in player.inventory.item_ids():
			inventory_before[String(item_id)]=true
		var npc_drops:=loot_service.roll(npc,repository,player,quality_chances)
		for raw_drop in npc_drops:
			if not (raw_drop is Dictionary):
				continue
			var drop:Dictionary=raw_drop
			var item_id:=String(drop.get("instance_id",""))
			if item_id.is_empty():
				continue
			pool.add_drop(item_id,npc.instance_id)
			# Legacy loot service transfers immediately; undo that transfer so
			# encounter loot remains unclaimed until the player clicks it.
			if not inventory_before.has(item_id) and player.inventory.owns(item_id):
				player.inventory.remove(item_id)
		if not bridge.resolve_death(map,npc.instance_id):
			return {"ok":false,"reason":"death_resolution_failed","npc_instance_id":npc.instance_id}
		defeated_ids.append(npc.instance_id)
	pool.assign_all(player.character_id)
	return {"ok":true,"defeated_ids":defeated_ids,"defeated_count":defeated_ids.size(),"loot_pool":pool,"drops":pool.item_ids(),"drop_count":pool.entries.size()}
