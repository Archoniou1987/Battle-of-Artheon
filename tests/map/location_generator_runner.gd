extends SceneTree
func _initialize()->void:
	var valid:=true
	for seed_value in range(1,201):
		var generated:=LocationGenerator.generate(20,20,seed_value)
		var map:TacticalMapState=generated.map
		var entrance:Vector2i=generated.entrance
		var exit:Vector2i=generated.exit
		var path:=HexPathfinder.find_path(map,entrance,exit)
		valid=valid and map.in_bounds(entrance) and map.in_bounds(exit)
		valid=valid and map.cell(entrance).is_passable() and map.cell(exit).is_passable()
		valid=valid and not path.is_empty()
		valid=valid and path[0]==entrance and path[path.size()-1]==exit
		if not valid:
			print("LOCATION_GENERATOR_FAILED_SEED=%d"%seed_value)
			break
	var first:=LocationGenerator.generate(20,20,777)
	var second:=LocationGenerator.generate(20,20,777)
	valid=valid and first.entrance==second.entrance and first.exit==second.exit
	valid=valid and first.guaranteed_path==second.guaranteed_path
	print("LOCATION_GENERATOR_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
