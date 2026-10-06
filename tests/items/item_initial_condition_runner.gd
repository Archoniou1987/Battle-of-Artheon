extends SceneTree

func _init() -> void:
	var template := {"id":"COND_TEST","name":"Condition Sword","item_level":1,"equip_slots":["main_hand"],"slot_usage":["main_hand"],"damage_min":1,"damage_max":2,"durability_max":50}
	var crafted := ItemGenerator.new(100).generate(template,"common",{"origin":"crafted","max_wear_min":1.0,"max_wear_max":1.0,"damage_min":1.0,"damage_max":1.0})
	var used_rule := {"origin":"loot","max_wear_min":0.20,"max_wear_max":0.40,"damage_min":0.10,"damage_max":0.60,"hidden_progress_min":0.0,"hidden_progress_max":1.0}
	var generator := ItemGenerator.new(200)
	var ok := int(crafted.durability_max)==50 and int(crafted.durability_current)==50 and int(crafted._durability_repair_progress)==0 and String(crafted.origin)=="crafted"
	var saw_aged:=false
	var saw_damaged:=false
	for i in range(100):
		var item:=generator.generate(template,"common",used_rule)
		var maximum:=int(item.durability_max)
		var current:=int(item.durability_current)
		var hidden:=int(item._durability_repair_progress)
		ok = ok and maximum>=30 and maximum<=40
		ok = ok and current>=0 and current<=maximum
		ok = ok and hidden>=0 and hidden<=maxi(0,maximum-2)
		ok = ok and String(item.origin)=="loot"
		saw_aged = saw_aged or maximum<50
		saw_damaged = saw_damaged or current<maximum
	ok = ok and saw_aged and saw_damaged
	print("ITEM_INITIAL_CONDITION_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
