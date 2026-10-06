extends SceneTree

func _initialize()->void:
	var resources:=ResourceRepository.new()
	var copper:=ResourceDefinition.new("RES001", "Copper Ore", "ore", 5, "common")
	var iron:=ResourceDefinition.new("RES002", "Iron Ore", "ore", 20, "common")
	var valid:=resources.add_resource(copper) and resources.add_resource(iron)
	var sources:=ResourceSourceRepository.new()
	var iron_vein:=ResourceSource.new("SRC_IRON_001", "RES002", 5, 2, 3, 60.0, 1, 300.0)
	valid = valid and sources.add_source(iron_vein, resources)

	var map:=TacticalMapState.new(8, 8)
	var mine:=MapArea.new("MINE_001", "resource")
	valid = valid and mine.add_resource_source("SRC_IRON_001")
	var mine_cells:Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2)]
	valid = valid and map.add_area(mine, mine_cells)
	valid = valid and map.place_entity("PLAYER_RESOURCE_TEST", Vector2i(2, 2))

	var service:=ResourceGatheringService.new()
	var begin:=service.begin(map, "PLAYER_RESOURCE_TEST", "MINE_001", sources)
	valid = valid and bool(begin.get("ok", false)) and is_equal_approx(float(begin.get("duration_sec", 0.0)), 60.0)
	var first:=service.gather("SRC_IRON_001", sources, 3)
	var second:=service.gather("SRC_IRON_001", sources, 3)
	valid = valid and int(first.get("quantity", 0)) == 3 and int(first.get("remaining", -1)) == 2
	valid = valid and int(second.get("quantity", 0)) == 2 and bool(second.get("depleted", false))
	var empty:=service.begin(map, "PLAYER_RESOURCE_TEST", "MINE_001", sources)
	valid = valid and not bool(empty.get("ok", true)) and String(empty.get("reason", "")) == "depleted"
	var recovered:=iron_vein.recover(2)
	mine.depleted = false
	var restored:=service.begin(map, "PLAYER_RESOURCE_TEST", "MINE_001", sources)
	valid = valid and recovered == 2 and iron_vein.quantity == 2 and bool(restored.get("ok", false))
	print("RESOURCE_SOURCE remaining=%d recovered=%d" % [iron_vein.quantity, recovered])
	print("RESOURCE_SOURCE_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
