class_name MapNpcBridge
extends RefCounted

var instances:Dictionary={}

func register_npc(map,npc:NpcInstance,pos:Vector2i)->bool:
	if npc==null or npc.instance_id.is_empty() or instances.has(npc.instance_id): return false
	if not map.place_entity(npc.instance_id,pos): return false
	instances[npc.instance_id]=npc
	return true

func npc_at(map,pos:Vector2i)->Array[NpcInstance]:
	var result:Array[NpcInstance]=[]
	for entity_id in map.entities_at(pos):
		if instances.has(entity_id):
			var npc:NpcInstance=instances[entity_id]
			if npc.is_alive(): result.append(npc)
	return result

func encounter_at(map,pos:Vector2i)->Dictionary:
	var npcs:=npc_at(map,pos)
	if npcs.is_empty(): return {"ok":false,"reason":"no_npc"}
	var npc:NpcInstance=npcs[0]
	var npc_ids:Array[String]=[]
	for member in npcs:
		npc_ids.append(member.instance_id)
	return {"ok":true,"npc_instance_id":npc.instance_id,"npc_template_id":npc.template_id,"npc":npc,"npcs":npcs,"npc_instance_ids":npc_ids}

func encounter_with_neighbors(map:TacticalMapState,pos:Vector2i,rng:RandomNumberGenerator)->Dictionary:
	var initial:=encounter_at(map,pos)
	if not bool(initial.get("ok",false)):
		return initial
	var primary_ids:Array[String]=[]
	for raw_id in initial.get("npc_instance_ids",[]):
		primary_ids.append(String(raw_id))
	var assembled:=HexCombatJoinService.assemble(map,self,pos,primary_ids,{},rng)
	if not bool(assembled.get("ok",false)):
		return assembled
	var members:Array=assembled.get("npcs",[])
	var primary:NpcInstance=members[0]
	return {"ok":true,"npc":primary,"npcs":members,
		"npc_instance_id":primary.instance_id,"npc_template_id":primary.template_id,
		"npc_instance_ids":assembled.get("npc_instance_ids",[]),
		"combat_cell":pos}

func resolve_death(map,npc_instance_id:String)->bool:
	if not instances.has(npc_instance_id): return false
	var npc:NpcInstance=instances[npc_instance_id]
	if not npc.mark_dead(): return false
	map.remove_entity(npc_instance_id)
	return true
