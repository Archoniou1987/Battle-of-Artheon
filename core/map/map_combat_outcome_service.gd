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
	var drops:Array=[]
	for npc in npcs:
		if npc==null or not dead_ids.has(npc.instance_id):
			continue
		var npc_drops:=loot_service.roll(npc,repository,player,quality_chances)
		if not bridge.resolve_death(map,npc.instance_id):
			return {"ok":false,"reason":"death_resolution_failed","npc_instance_id":npc.instance_id}
		defeated_ids.append(npc.instance_id)
		drops.append_array(npc_drops)
	return {"ok":true,"defeated_ids":defeated_ids,"defeated_count":defeated_ids.size(),"drops":drops,"drop_count":drops.size()}
