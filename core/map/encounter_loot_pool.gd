class_name EncounterLootPool
extends RefCounted

const LIFETIME_SECONDS:=15*60

var created_at_unix:int=0
var expires_at_unix:int=0
var hex_cell:Vector2i=Vector2i.ZERO
var entries:Array[Dictionary]=[]
var assigned_player_by_item:Dictionary={}

func place_on_hex(cell:Vector2i,now_unix:int)->void:
	hex_cell=cell
	created_at_unix=now_unix
	expires_at_unix=now_unix+LIFETIME_SECONDS

func is_expired(now_unix:int)->bool:
	return expires_at_unix>0 and now_unix>=expires_at_unix

func has_visible_loot(now_unix:int)->bool:
	return not entries.is_empty() and not is_expired(now_unix)

func expire(now_unix:int,repository:ItemRepository)->bool:
	if not is_expired(now_unix):
		return false
	for item_id in item_ids():
		if repository!=null:
			repository.remove_item(item_id)
	entries.clear()
	assigned_player_by_item.clear()
	return true

func add_drop(item_id:String,source_npc_instance_id:String)->bool:
	if item_id.is_empty() or item_ids().has(item_id):
		return false
	entries.append({"item_id":item_id,"source_npc_instance_id":source_npc_instance_id})
	return true

func item_ids()->Array[String]:
	var result:Array[String]=[]
	for entry in entries:
		result.append(String(entry.get("item_id","")))
	return result

func assign_all(player_id:String)->void:
	for item_id in item_ids():
		if not assigned_player_by_item.has(item_id) and not player_id.is_empty():
			assigned_player_by_item[item_id]=player_id

func available_for(player_id:String)->Array[String]:
	var result:Array[String]=[]
	for item_id in item_ids():
		if String(assigned_player_by_item.get(item_id,""))==player_id:
			result.append(item_id)
	return result

func claim(item_id:String,player:CharacterState,repository:ItemRepository,now_unix:int=-1)->bool:
	var checked_at:=now_unix if now_unix>=0 else int(Time.get_unix_time_from_system())
	if is_expired(checked_at) or player==null or repository==null or not item_ids().has(item_id) or String(assigned_player_by_item.get(item_id,""))!=player.character_id:
		return false
	if player.inventory.owns(item_id):
		return false
	var item=repository.get_item(item_id)
	if item==null or (item is Dictionary and item.is_empty()):
		return false
	if not player.inventory.add_instance(item_id,repository):
		return false
	assigned_player_by_item.erase(item_id)
	for i in range(entries.size()):
		if String(entries[i].get("item_id",""))==item_id:
			entries.remove_at(i)
			break
	return true


func to_dict()->Dictionary:
	return {
		"created_at_unix":created_at_unix,
		"expires_at_unix":expires_at_unix,
		"hex_cell":[hex_cell.x,hex_cell.y],
		"entries":entries.duplicate(true),
		"assigned_player_by_item":assigned_player_by_item.duplicate(true)
	}

static func from_dict(data:Dictionary)->EncounterLootPool:
	var pool:=EncounterLootPool.new()
	pool.created_at_unix=int(data.get("created_at_unix",0))
	pool.expires_at_unix=int(data.get("expires_at_unix",0))
	var raw_cell:Array=data.get("hex_cell",[0,0])
	if raw_cell.size()>=2:
		pool.hex_cell=Vector2i(int(raw_cell[0]),int(raw_cell[1]))
	for raw_entry in data.get("entries",[]):
		if not raw_entry is Dictionary:
			continue
		var entry:Dictionary=raw_entry
		pool.add_drop(String(entry.get("item_id","")),String(entry.get("source_npc_instance_id",entry.get("source_npc_id",""))))
	var raw_assignments:Dictionary=Dictionary(data.get("assigned_player_by_item",{}))
	for item_id in pool.item_ids():
		var player_id:=String(raw_assignments.get(item_id,""))
		if not player_id.is_empty():
			pool.assigned_player_by_item[item_id]=player_id
	return pool
