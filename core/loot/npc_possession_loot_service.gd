class_name NpcPossessionLootService
extends RefCounted

var rng:=RandomNumberGenerator.new()

func _init(seed_value:int=1)->void:
	rng.seed=seed_value

func roll(npc:NpcInstance, repository:ItemRepository, player:CharacterState, quality_chances:Dictionary)->Array[Dictionary]:
	var awarded:Array[Dictionary]=[]
	var seen:Dictionary={}
	for item_id in npc.equipment.slots.values():
		if item_id==null: continue
		var id:=String(item_id)
		if not seen.has(id):
			seen[id]=true
			_try_award(id,npc,repository,player,quality_chances,awarded)
	for id in npc.bag.instance_ids():
		var item_id:=String(id)
		if not seen.has(item_id):
			seen[item_id]=true
			_try_award(item_id,npc,repository,player,quality_chances,awarded)
	return awarded

func _try_award(item_id:String,npc:NpcInstance,repository:ItemRepository,player:CharacterState,chances:Dictionary,awarded:Array[Dictionary])->void:
	var item:=repository.get_item(item_id)
	if item.is_empty(): return
	var chance:=clampf(float(chances.get(String(item.get("quality","common")),0.0)),0.0,100.0)
	if rng.randf()*100.0>=chance: return
	if not player.inventory.add_instance(item_id,repository): return
	var result:=item.duplicate(true)
	result["loot_source_id"]=npc.instance_id
	awarded.append(result)
