extends SceneTree
func _initialize()->void:
	var groups_doc:=TestFixtureLoader.load_json("res://data/loot/loot_groups.json")
	var groups:Dictionary={}
	for raw in groups_doc.groups:
		var g:=raw as Dictionary
		groups[String(g.id)]=g
	var templates:Dictionary={}
	for level in [1,5,10,65,70,73,80]:
		var id:="TEST_SWORD_%d"%level
		templates[id]={"id":id,"name":"Test Sword %d"%level,"item_level":level,"loot_category":"equipment","item_type":"weapon"}
	templates["QUEST_BANDIT_TOKEN"]={"id":"QUEST_BANDIT_TOKEN","name":"Bandit Mark","item_level":1,"loot_category":"quest","item_type":"quest"}
	var service:=LootGroupService.new(7005)
	var group_ids:Array=["HUMANOID_COMMON","BANDIT_COMMON","QUEST_BANDIT"]
	var low:=service.candidates(5,"normal",group_ids,groups,templates,{"active_quests":["QUEST001"]})
	var high:=service.candidates(70,"elite",group_ids,groups,templates,{"active_quests":["QUEST001"]})
	var no_quest:=service.candidates(5,"normal",group_ids,groups,templates,{})
	var low_range:=LootLevelProfile.range_for(5,"normal")
	var high_range:=LootLevelProfile.range_for(70,"elite")
	var valid:=low_range.min==1 and low_range.max==5 and high_range.min==68 and high_range.max==73
	valid=valid and _scaled_in_range(low,low_range) and _scaled_in_range(high,high_range)
	valid=valid and _has_fixed(low,"QUEST_BANDIT_TOKEN") and _has_fixed(high,"QUEST_BANDIT_TOKEN") and not _has_fixed(no_quest,"QUEST_BANDIT_TOKEN")
	print("LOOT_GROUP normal_lv5_range=%d-%d candidates=%s" % [low_range.min,low_range.max,_summary(low)])
	print("LOOT_GROUP elite_lv70_range=%d-%d candidates=%s" % [high_range.min,high_range.max,_summary(high)])
	print("LOOT_GROUP quest_fixed_low=%s quest_fixed_high=%s inactive=%s" % [str(_has_fixed(low,"QUEST_BANDIT_TOKEN")),str(_has_fixed(high,"QUEST_BANDIT_TOKEN")),str(_has_fixed(no_quest,"QUEST_BANDIT_TOKEN"))])
	print("LOOT_GROUP_LEVEL_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _scaled_in_range(items:Array,r:Dictionary)->bool:
	var found:=false
	for c in items:
		if String(c.mode)!="scaled": continue
		found=true
		var level:=int((c.template as Dictionary).item_level)
		if level<r.min or level>r.max:return false
	return found

func _has_fixed(items:Array,id:String)->bool:
	for c in items:
		if String(c.mode)=="fixed" and String((c.template as Dictionary).id)==id:return true
	return false

func _summary(items:Array)->String:
	var out:Array=[]
	for c in items:out.append("%s:L%d:%s"%[String((c.template as Dictionary).id),int((c.template as Dictionary).item_level),String(c.mode)])
	return JSON.stringify(out)
