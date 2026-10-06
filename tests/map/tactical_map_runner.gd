extends SceneTree

func _initialize()->void:
	var map:=TacticalMapState.new(15, 15)
	map.set_terrain(Vector2i(2, 1), "road", 0.7)
	map.set_terrain(Vector2i(3, 1), "swamp", 2.0)
	map.set_obstacle(Vector2i(2, 2), "rock", true)
	var mine:=MapArea.new("IRON_AREA_01", "resource", 5, "uncommon", 1.5, 60.0)
	mine.loot_group_ids.append("RESOURCE_IRON_05")
	var mine_cells:Array[Vector2i] = [Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2)]
	var area_ok:=map.add_area(mine, mine_cells)
	map.cell(Vector2i(4, 1)).object_ids.append("ORE_HINT_01")
	map.cell(Vector2i(3, 1)).triggers.append("ENTER_IRON_AREA")
	var placed:=map.place_entity("PLAYER_MAP_TEST", Vector2i(1, 1))
	var road:=map.move_entity("PLAYER_MAP_TEST", Vector2i(2, 1))
	var blocked:=map.move_entity("PLAYER_MAP_TEST", Vector2i(2, 2))
	var swamp:=map.move_entity("PLAYER_MAP_TEST", Vector2i(3, 1))
	var gathering:=ResourceGatheringService.new().begin(map, "PLAYER_MAP_TEST", "IRON_AREA_01")
	var valid:=map.cells.size() == 225 and area_ok and placed
	valid = valid and bool(road.get("ok", false)) and is_equal_approx(float(road.get("movement_cost", 0.0)), 0.7)
	valid = valid and not bool(blocked.get("ok", true)) and String(blocked.get("reason", "")) == "blocked"
	valid = valid and bool(swamp.get("ok", false)) and is_equal_approx(float(swamp.get("movement_cost", 0.0)), 2.0)
	valid = valid and (swamp.get("areas", []) as Array).has("IRON_AREA_01")
	valid = valid and bool(gathering.get("ok", false)) and is_equal_approx(float(gathering.get("duration_sec", 0.0)), 60.0)
	valid = valid and String(gathering.get("rarity", "")) == "uncommon" and is_equal_approx(float(gathering.get("richness", 0.0)), 1.5)
	print("TACTICAL_MAP cells=%d road_cost=%.1f blocked=%s resource_area=%s gather=%.0fs" % [map.cells.size(), float(road.get("movement_cost", 0.0)), String(blocked.get("reason", "")), String((swamp.get("areas", []) as Array)[0]), float(gathering.get("duration_sec", 0.0))])
	print("TACTICAL_MAP_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
