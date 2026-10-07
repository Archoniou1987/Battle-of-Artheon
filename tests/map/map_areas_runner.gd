extends SceneTree
func _initialize()->void:
	var map:=TacticalMapState.new(12,12)
	var mine:=MapArea.new("MINE","resource")
	var danger:=MapArea.new("DANGER","danger")
	var camp:=MapArea.new("CAMP","camp")
	var mine_cells:Array[Vector2i]=[Vector2i(3,3),Vector2i(4,3),Vector2i(4,4)]
	var danger_cells:Array[Vector2i]=[Vector2i(4,3),Vector2i(5,3),Vector2i(5,4)]
	var camp_cells:Array[Vector2i]=[Vector2i(6,3),Vector2i(6,4)]
	var valid:=map.add_area(mine,mine_cells) and map.add_area(danger,danger_cells) and map.add_area(camp,camp_cells)
	valid=valid and map.areas_at(Vector2i(4,3)).size()==2
	valid=valid and map.areas_at(Vector2i(4,3)).has("MINE") and map.areas_at(Vector2i(4,3)).has("DANGER")
	valid=valid and map.place_entity("P",Vector2i(3,3))
	var overlap:=map.move_entity("P",Vector2i(4,3))
	valid=valid and (overlap.area_entered as Array).has("DANGER") and (overlap.area_stayed as Array).has("MINE")
	var leave_mine:=map.move_entity("P",Vector2i(5,3))
	valid=valid and (leave_mine.area_exited as Array).has("MINE") and (leave_mine.area_stayed as Array).has("DANGER")
	var outside:=map.move_entity("P",Vector2i(5,2))
	valid=valid and (outside.area_exited as Array).has("DANGER") and (outside.areas as Array).is_empty()
	var duplicate:=map.add_area(MapArea.new("MINE","resource"),[Vector2i(8,8)])
	valid=valid and not duplicate
	var invalid_positions:Array[Vector2i]=[Vector2i(99,99)]
	var invalid:=map.add_area(MapArea.new("BAD","danger"),invalid_positions)
	valid=valid and not invalid and not map.areas.has("BAD")
	print("MAP_AREAS overlap=%s enter=%s exit=%s"%[map.areas_at(Vector2i(4,3)),overlap.area_entered,leave_mine.area_exited])
	print("MAP_AREAS_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
