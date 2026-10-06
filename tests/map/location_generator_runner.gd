extends SceneTree
func _initialize()->void:
	var valid:=true
	for seed_value in range(1,201):
		var generated:=LocationGenerator.generate(20,20,seed_value)
		var map:TacticalMapState=generated.map
		var entrance:Vector2i=generated.entrance
		var exit:Vector2i=generated.exit
		var result:=HexPathfinder.new().find_path(map,entrance,exit)
		var path:Array=result.get("path",[])
		valid=valid and map.in_bounds(entrance) and map.in_bounds(exit)
		valid=valid and map.cell(entrance).is_passable() and map.cell(exit).is_passable()
		valid=valid and bool(result.get("ok",false)) and not path.is_empty()
		valid=valid and path[0]==entrance and path[path.size()-1]==exit
		var occupied:Dictionary={}
		for group_name in ["resource_cells","npc_cells","object_cells","encounter_cells"]:
			for pos in generated[group_name]:
				valid=valid and map.in_bounds(pos) and map.cell(pos).is_passable()
				valid=valid and pos!=entrance and pos!=exit and not occupied.has(pos)
				occupied[pos]=true
		if not valid:
			print("LOCATION_GENERATOR_FAILED_SEED=%d"%seed_value)
			break
	var first:=LocationGenerator.generate(20,20,777)
	var second:=LocationGenerator.generate(20,20,777)
	valid=valid and first.entrance==second.entrance and first.exit==second.exit
	valid=valid and first.guaranteed_path==second.guaranteed_path
	valid=valid and first.resource_cells==second.resource_cells
	valid=valid and first.npc_cells==second.npc_cells
	valid=valid and first.object_cells==second.object_cells
	valid=valid and first.encounter_cells==second.encounter_cells
	print("LOCATION_GENERATOR_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
