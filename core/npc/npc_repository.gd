class_name NpcRepository
extends RefCounted
var _npcs:Dictionary={}
func add(npc:NpcState)->bool:
	if npc.npc_id.is_empty() or _npcs.has(npc.npc_id): return false
	_npcs[npc.npc_id]=npc
	return true
func get_npc(npc_id:String)->NpcState:
	return _npcs.get(npc_id,null) as NpcState
func size()->int:return _npcs.size()
func load_definitions(document:Dictionary)->void:
	for raw in document.get("npcs",[]):add(NpcState.new(raw as Dictionary))
