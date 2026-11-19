extends SceneTree

func _initialize() -> void:
	var ok := true
	var generator := ItemTemplateGeneratorV12.new()
	var result := generator.generate({"archetypes":["STAFF_FIRE_BURST"],"school":"fire","weapon_hand":"2H","min_level":40,"max_level":40,"quality":"blue","count":1,"seed":1919})
	ok = ok and bool(result.get("ok",false))
	var rows: Array=result.get("rows",[])
	ok = ok and rows.size()==1
	if not rows.is_empty():
		var row: Dictionary=rows[0]
		ok = ok and String(row.get("archetype_id",""))=="STAFF_FIRE_BURST"
		ok = ok and String(row.get("slot",""))=="2H"
		var item := ItemV12InstanceFactory.instance_from_v12_row(row,1919)
		ok = ok and not item.is_empty()
		ok = ok and String(item.get("weapon_class",""))=="staff"
		ok = ok and Array(item.get("abilities",[]))==["ABI801","ABI802","ABI803","ABI804"]
		ok = ok and Array(item.get("slot_usage",[]))==["main_hand","off_hand"]
		ok = ok and Dictionary(item.get("damage",{})).get("min",0)==1
		ok = ok and Dictionary(item.get("damage",{})).get("max",0)==1
		ok = ok and String(item.get("generated_from_template",""))=="STAFF_FIRE_BURST"
		print("FIRE_STAFF_ITEM=",JSON.stringify({"id":item.get("id",""),"abilities":item.get("abilities",[]),"par":item.get("par_bonuses",{})}))
	var wrong := generator.generate({"archetypes":["STAFF_FIRE_BURST"],"school":"frost","weapon_hand":"2H","min_level":40,"max_level":40,"quality":"blue","count":1,"seed":1919})
	ok = ok and not bool(wrong.get("ok",false))
	print("FIRE_BURST_ITEM_FACTORY=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
