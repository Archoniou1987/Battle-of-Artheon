class_name NpcPossessionLootService
extends RefCounted

var rng:=RandomNumberGenerator.new()

func _init(seed_value:int=1)->void:
	rng.seed=seed_value

## Roll unique item instances owned by the NPC. This stage only selects drops;
## inventory transfer belongs to EncounterLootPool.claim().
func roll_drops(npc:NpcInstance,repository:ItemRepository,quality_chances:Dictionary)->Array[Dictionary]:
	var drops:Array[Dictionary]=[]
	var seen:Dictionary={}
	for item_id in npc.equipment.slots.values():
		if item_id==null: continue
		var id:=String(item_id)
		if not seen.has(id):
			seen[id]=true
			_try_drop(id,npc,repository,quality_chances,drops)
	for id in npc.bag.instance_ids():
		var item_id:=String(id)
		if not seen.has(item_id):
			seen[item_id]=true
			_try_drop(item_id,npc,repository,quality_chances,drops)
	return drops

func _try_drop(item_id:String,npc:NpcInstance,repository:ItemRepository,chances:Dictionary,drops:Array[Dictionary])->void:
	var item:=repository.get_item(item_id)
	if item.is_empty(): return
	var chance:=clampf(float(chances.get(String(item.get("quality","common")),0.0)),0.0,100.0)
	if rng.randf()*100.0>=chance: return
	var result:=item.duplicate(true)
	result["loot_source_id"]=npc.instance_id
	drops.append(result)
