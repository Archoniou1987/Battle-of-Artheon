extends SceneTree

# Run: godot --headless --path . --script res://tests/map_generation_connectivity.gd
const SEED_COUNT := 200

func _initialize() -> void:
	var failures: Array[String] = []
	for seed_value in range(1, SEED_COUNT + 1):
		var generated: Dictionary = LocationGenerator.generate(20, 20, seed_value)
		_check(generated, seed_value, failures)
	if failures.is_empty():
		print("Map connectivity PASS: %d seeds" % SEED_COUNT)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Map connectivity FAIL: %d errors" % failures.size())
		quit(1)

func _check(generated: Dictionary, seed_value: int, failures: Array[String]) -> void:
	var world: TacticalMapState = generated["map"]
	var entrance: Vector2i = generated["entrance"]
	var reachable: Dictionary = {}
	var queue: Array[Vector2i] = [entrance]
	reachable[entrance] = true
	var cursor := 0
	while cursor < queue.size():
		var pos: Vector2i = queue[cursor]
		cursor += 1
		for next_pos in world.neighbors(pos, true):
			if not reachable.has(next_pos):
				reachable[next_pos] = true
				queue.append(next_pos)
	_assert_reachable(reachable, generated["exit"], seed_value, "exit", failures)
	var regions: Array = generated["regions"]
	if regions.size() < 1 or regions.size() > 3:
		failures.append("seed %d: region count %d" % [seed_value, regions.size()])
	for entity_id in world.entity_positions.keys():
		_assert_reachable(reachable, world.entity_positions[entity_id], seed_value, "entity " + str(entity_id), failures)
	for pos in generated["resource_cells"]:
		_assert_reachable(reachable, pos, seed_value, "resource", failures)
	for pos in generated["object_cells"]:
		_assert_reachable(reachable, pos, seed_value, "object", failures)
	for prop in generated["region_objects"]:
		_assert_reachable(reachable, prop["pos"], seed_value, "region prop", failures)
	var region_patrol_counts: Dictionary = {}
	for patrol in generated["patrols"]:
		var route: Array = patrol["path"]
		if route.size() < 2:
			failures.append("seed %d: empty patrol route" % seed_value)
			continue
		if patrol.has("region_id"):
			var region_id: String = str(patrol["region_id"])
			region_patrol_counts[region_id] = int(region_patrol_counts.get(region_id, 0)) + 1
			if region_patrol_counts[region_id] > 1:
				failures.append("seed %d: multiple patrols in %s" % [seed_value, region_id])
			if route.size() < 4 or route.size() > 8:
				failures.append("seed %d: thematic patrol length %d" % [seed_value, route.size()])
		for index in range(route.size()):
			var pos: Vector2i = route[index]
			_assert_reachable(reachable, pos, seed_value, "patrol route", failures)
			if index > 0 and HexGrid.distance(route[index - 1], pos) != 1:
				failures.append("seed %d: disconnected patrol step" % seed_value)
			if patrol.has("region_id"):
				var inside := false
				for region in regions:
					if region["region_id"] == patrol["region_id"] and region["cells"].has(pos):
						inside = true
						break
				if not inside:
					failures.append("seed %d: patrol left region" % seed_value)

func _assert_reachable(reachable: Dictionary, pos: Vector2i, seed_value: int, what: String, failures: Array[String]) -> void:
	if not reachable.has(pos):
		failures.append("seed %d: unreachable %s at %s" % [seed_value, what, str(pos)])
