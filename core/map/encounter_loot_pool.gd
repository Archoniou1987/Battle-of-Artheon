class_name EncounterLootPool
extends RefCounted

var entries:Array[Dictionary]=[]
var assigned_player_by_item:Dictionary={}

func add_drop(item_id:String,source_npc_id:String)->void:
	if item_id.is_empty(): return
	entries.append({"item_id":item_id,"source_npc_id":source_npc_id})

func item_ids()->Array[String]:
	var result:Array[String]=[]
	for entry in entries:
		result.append(String(entry.get("item_id","")))
	return result

func assign_all(player_id:String)->void:
	for item_id in item_ids():
		assigned_player_by_item[item_id]=player_id

func available_for(player_id:String)->Array[String]:
	var result:Array[String]=[]
	for item_id in item_ids():
		if String(assigned_player_by_item.get(item_id,""))==player_id:
			result.append(item_id)
	return result

func claim(item_id:String,player:CharacterState,repository:ItemRepository)->bool:
	if player==null or String(assigned_player_by_item.get(item_id,""))!=player.character_id:
		return false
	if player.inventory.owns(item_id):
		return false
	var item=repository.get_item(item_id)
	if item==null:
		return false
	if not player.inventory.add(item_id):
		return false
	assigned_player_by_item.erase(item_id)
	for i in range(entries.size()):
		if String(entries[i].get("item_id",""))==item_id:
			entries.remove_at(i)
			break
	return true
