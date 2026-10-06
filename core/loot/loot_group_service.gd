class_name LootGroupService
extends RefCounted

var rng:=RandomNumberGenerator.new()

func _init(seed_value:int=1)->void:
	rng.seed=seed_value

func candidates(source_level:int,rank:String,group_ids:Array,groups_by_id:Dictionary,templates_by_id:Dictionary,context:Dictionary={})->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var level_range:=LootLevelProfile.range_for(source_level,rank)
	for group_id in group_ids:
		var group:Dictionary=groups_by_id.get(String(group_id),{})
		for raw in group.get("entries",[]):
			var entry:=raw as Dictionary
			if not _conditions_met(entry.get("conditions",{}),context): continue
			if String(entry.get("mode","scaled"))=="fixed":
				var fixed_id:=String(entry.get("template_id",""))
				if templates_by_id.has(fixed_id): result.append({"group_id":group_id,"template":templates_by_id[fixed_id],"mode":"fixed"})
				continue
			var pool:Array[Dictionary]=[]
			for template in templates_by_id.values():
				var item:=template as Dictionary
				var item_level:=int(item.get("item_level",1))
				if item_level<level_range.min or item_level>level_range.max: continue
				if not _matches(item,entry): continue
				pool.append(item)
			if not pool.is_empty():
				result.append({"group_id":group_id,"template":pool[rng.randi_range(0,pool.size()-1)],"mode":"scaled","level_min":level_range.min,"level_max":level_range.max})
	return result

func _matches(item:Dictionary,entry:Dictionary)->bool:
	var category:=String(entry.get("category",""))
	if not category.is_empty() and String(item.get("loot_category",""))!=category: return false
	var item_type:=String(entry.get("item_type",""))
	if not item_type.is_empty() and String(item.get("item_type",""))!=item_type: return false
	return true

func _conditions_met(conditions:Dictionary,context:Dictionary)->bool:
	if conditions.is_empty(): return true
	if conditions.has("quest_active"):
		return (context.get("active_quests",[]) as Array).has(String(conditions.quest_active))
	return true
