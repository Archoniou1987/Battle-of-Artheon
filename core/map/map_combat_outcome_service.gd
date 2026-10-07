class_name MapCombatOutcomeService
extends RefCounted

static func resolve_victory(result:Dictionary,map:TacticalMapState,bridge:MapNpcBridge,npc:NpcInstance,player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if npc==null: return {"ok":false,"reason":"missing_npc"}
	if String(result.get("winner_id",""))!=player.character_id or String(result.get("loser_id",""))!=npc.instance_id:
		return {"ok":false,"reason":"not_player_victory"}
	var drops:=loot_service.roll(npc,repository,player,quality_chances)
	if not bridge.resolve_death(map,npc.instance_id): return {"ok":false,"reason":"death_resolution_failed"}
	return {"ok":true,"npc_instance_id":npc.instance_id,"npc_state":npc.life_state,"drops":drops,"drop_count":drops.size()}
