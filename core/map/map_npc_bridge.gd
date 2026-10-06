class_name MapNpcBridge
extends RefCounted

var instances:Dictionary={}

func register_npc(map:TacticalMapState,npc:NpcInstance,pos:Vector2i)->bool:
	if npc==null or npc.instance_id.is_empty() or instances.has(npc.instance_id): return false
	if not map.place_entity(npc.instance_id,pos): return false
	instances[npc.instance_id]=npc
	return true

func npc_at(map:TacticalMapState,pos:Vector2i)->Array[NpcInstance]:
	var result:Array[NpcInstance]=[]
	for entity_id in map.entities_at(pos):
		if instances.has(entity_id): result.append(instances[entity_id])
	return result

func encounter_at(map:TacticalMapState,pos:Vector2i)->Dictionary:
	var npcs:=npc_at(map,pos)
	if npcs.is_empty(): return {"ok":false,"reason":"no_npc"}
	var npc:NpcInstance=npcs[0]
	return {"ok":true,"npc_instance_id":npc.instance_id,"npc_template_id":npc.template_id,"npc":npc}
