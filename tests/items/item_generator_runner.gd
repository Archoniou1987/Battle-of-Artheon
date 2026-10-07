extends SceneTree

func _init()->void:
	var file:=FileAccess.open("res://data/test/item_generator_template.json",FileAccess.READ)
	var template:Dictionary=JSON.parse_string(file.get_as_text())
	var generator:=ItemGenerator.new(50050)
	var items:=generator.generate_batch(template,100)
	var counts:Dictionary={"poor":0,"common":0,"green":0,"blue":0,"purple":0}
	var aggregate_examples:Array=[]
	var ids:Dictionary={}
	var ok:=items.size()==100
	for item in items:
		var q:=String(item.quality); counts[q]=int(counts.get(q,0))+1
		if ids.has(item.instance_id): ok=false
		ids[item.instance_id]=true
		var rule:Dictionary=ItemGenerator.QUALITY_RULES[q]
		if item.damage_min < int(round(25.0*float(rule.min_mult))) or item.damage_min > int(round(25.0*float(rule.max_mult))): ok=false
		if item.rolled_mods.size()!=int(rule.mods): ok=false
		var seen:Dictionary={}
		for mod in item.rolled_mods:
			var stat:=String(mod.stat); seen[stat]=int(seen.get(stat,0))+1
			if int(mod.value)<int(rule.mod_min) or int(mod.value)>int(rule.mod_max): ok=false
		for stat in seen:
			if int(seen[stat])>1 and aggregate_examples.size()<5: aggregate_examples.append({"instance":item.instance_id,"quality":q,"stat":stat,"rolls":seen[stat],"mods":item.rolled_mods})
	print("ITEM_GENERATOR_TEST=", "PASS" if ok else "FAIL")
	print(JSON.stringify({"generated":items.size(),"quality_counts":counts,"duplicate_mod_examples":aggregate_examples}))
	quit(0 if ok else 1)
