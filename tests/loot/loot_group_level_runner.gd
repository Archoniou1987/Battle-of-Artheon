extends SceneTree
func _initialize()->void:
	var groups_doc:Dictionary=TestFixtureLoader.load_json("res://data/loot/loot_groups.json")
	var groups:Dictionary={}
	for raw in groups_doc.get("groups",[]):
		var g:Dictionary=raw
		groups[String(g.get("id",""))]=g
	var templates:Dictionary={}
	for level in [1,5,10,65,70,73,80]:
		var id:String="TEST_SWORD_%d"%level
		templates[id]={"id":id,"name":"Test Sword %d"%level,"item_level":level,"loot_category":"equipment","item_type":"weapon"}
	templates["QUEST_BANDIT_TOKEN"]={"id":"QUEST_BANDIT_TOKEN","name":"Bandit Mark","item_level":1,"loot_category":"quest","item_type":"quest"}
	var service:=LootGroupService.new(7005)
	var group_ids:Array=["HUMANOID_COMMON","BANDIT_COMMON","QUEST_BANDIT"]
	var low:Array[Dictionary]=service.candidates(5,"normal",group_ids,groups,templates,{"active_quests":["QUEST001"]})
	var high:Array[Dictionary]=service.candidates(70,"elite",group_ids,groups,templates,{"active_quests":["QUEST001"]})
	var no_quest:Array[Dictionary]=service.candidates(5,"normal",group_ids,groups,templates,{})
	var low_range:Dictionary=LootLevelProfile.range_for(5,"normal")
	var high_range:Dictionary=LootLevelProfile.range_for(70,"elite")
	var valid:bool=int(low_range.get("min",0))==1 and int(low_range.get("max",0))==5 and int(high_range.get("min",0))==68 and int(high_range.get("max",0))==73
	valid=valid and _scaled_in_range(low,low_range) and _scaled_in_range(high,high_range)
	valid=valid and _has_fixed(low,"QUEST_BANDIT_TOKEN") and _has_fixed(high,"QUEST_BANDIT_TOKEN") and not _has_fixed(no_quest,"QUEST_BANDIT_TOKEN")
	print("LOOT_GROUP normal_lv5_range=%d-%d candidates=%s"%[int(low_range.get("min",0)),int(low_range.get("max",0)),_summary(low)])
	print("LOOT_GROUP elite_lv70_range=%d-%d candidates=%s"%[int(high_range.get("min",0)),int(high_range.get("max",0)),_summary(high)])
	print("LOOT_GROUP_LEVEL_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _scaled_in_range(items:Array[Dictionary],level_range:Dictionary)->bool:
	var found:bool=false
	var minimum:int=int(level_range.get("min",0))
	var maximum:int=int(level_range.get("max",0))
	for candidate in items:
		if String(candidate.get("mode",""))!="scaled":
			continue
		found=true
		var template:Dictionary=candidate.get("template",{})
		var level:int=int(template.get("item_level",0))
		if level<minimum or level>maximum:
			return false
	return found

func _has_fixed(items:Array[Dictionary],id:String)->bool:
	for candidate in items:
		if String(candidate.get("mode",""))!="fixed":
			continue
		var template:Dictionary=candidate.get("template",{})
		if String(template.get("id",""))==id:
			return true
	return false

func _summary(items:Array[Dictionary])->String:
	var out:Array[String]=[]
	for candidate in items:
		var template:Dictionary=candidate.get("template",{})
		out.append("%s:L%d:%s"%[String(template.get("id","")),int(template.get("item_level",0)),String(candidate.get("mode",""))])
	return JSON.stringify(out)
