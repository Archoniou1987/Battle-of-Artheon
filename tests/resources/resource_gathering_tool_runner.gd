extends SceneTree

func _initialize()->void:
	var resources:=ResourceRepository.new()
	var iron:=ResourceDefinition.new("RES002", "Iron Ore", "ore", 20, "common")
	var valid:=resources.add_resource(iron)
	var sources:=ResourceSourceRepository.new()
	var vein:=ResourceSource.new("SRC_TOOL_IRON_001", "RES002", 5, 2, 3, 60.0)
	valid = valid and sources.add_source(vein, resources)

	var map:=TacticalMapState.new(6, 6)
	var mine:=MapArea.new("MINE_TOOL_001", "resource")
	valid = valid and mine.add_resource_source("SRC_TOOL_IRON_001")
	valid = valid and map.add_area(mine, [Vector2i(2, 2)])
	valid = valid and map.place_entity("PLAYER_GATHER_TOOL", Vector2i(2, 2))

	var items:=ItemRepository.new()
	var player:=CharacterState.new("PLAYER_GATHER_TOOL", "Gather Tester", 20)
	var pickaxe:Dictionary = {
		"instance_id":"PICKAXE_GATHER_001",
		"equip_slots":["tool"],
		"slot_usage":["tool"],
		"durability_current":20,
		"durability_max":20,
		"resource_categories":["ore"],
		"tool_level":25,
		"resource_bonus_yield":1
	}
	valid = valid and items.add_item(pickaxe)
	valid = valid and player.receive_item("PICKAXE_GATHER_001", items)

	var service:=ResourceGatheringService.new()
	var begin:=service.begin(map, "PLAYER_GATHER_TOOL", "MINE_TOOL_001", sources)
	valid = valid and bool(begin.get("ok", false))
	var blocked:=service.gather_with_tool("SRC_TOOL_IRON_001", sources, resources, player, items, 2)
	valid = valid and not bool(blocked.get("ok", true))
	valid = valid and str(blocked.get("reason", "")) == "tool_required"
	valid = valid and vein.quantity == 5

	valid = valid and player.equip("tool", "PICKAXE_GATHER_001", items)
	var gathered:=service.gather_with_tool("SRC_TOOL_IRON_001", sources, resources, player, items, 2)
	valid = valid and bool(gathered.get("ok", false))
	valid = valid and int(gathered.get("base_quantity", 0)) == 2
	valid = valid and int(gathered.get("tool_bonus_quantity", 0)) == 1
	valid = valid and int(gathered.get("quantity", 0)) == 3
	valid = valid and int(gathered.get("remaining", -1)) == 2

	var final_gather:=service.gather_with_tool("SRC_TOOL_IRON_001", sources, resources, player, items, 2)
	valid = valid and int(final_gather.get("quantity", 0)) == 2
	valid = valid and int(final_gather.get("tool_bonus_quantity", -1)) == 0
	valid = valid and bool(final_gather.get("depleted", false))
	valid = valid and vein.quantity == 0

	print("RESOURCE_GATHERING_TOOL remaining=%d first=%d final=%d" % [vein.quantity, int(gathered.get("quantity", 0)), int(final_gather.get("quantity", 0))])
	print("RESOURCE_GATHERING_TOOL_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
