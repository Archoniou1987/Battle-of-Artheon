extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok := true
	var settlements := {"town":WorldInstanceContract.settlement("town","forest",1)}
	var instance := WorldInstanceContract.instance("MAP-POP","town","forest",1284,1,20,20,1)
	var generated_result := MapInstanceGenerationService.generate(instance,settlements)
	ok = ok and bool(generated_result.get("ok",false))
	if not ok:
		print("GENERATED_MAP_POPULATION_TEST=FAIL generation")
		quit(1)
		return
	var catalog := NpcRepository.new()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/starting_region_npcs.json"))
	ok = ok and raw is Dictionary
	if raw is Dictionary:
		catalog.load_definitions(raw)
	var expedition := ExpeditionState.new("TEST_MAP_POP")
	var generated: Dictionary = generated_result["generated"]
	var mounted := GeneratedMapPopulationService.populate(generated,expedition,catalog)
	ok = ok and bool(mounted.get("ok",false))
	if bool(mounted.get("ok",false)):
		var map: TacticalMapState = mounted["map"]
		var bridge: MapNpcBridge = mounted["bridge"]
		ok = ok and bridge.instances.size() >= Array(generated["npc_cells"]).size()
		for id in bridge.instances.keys():
			ok = ok and map.entity_positions.has(id)
		var first_id := ""
		for id in bridge.instances.keys():
			first_id = String(id)
			break
		if not first_id.is_empty():
			var pos: Vector2i = map.entity_positions[first_id]
			ok = ok and not bridge.npc_at(map,pos).is_empty()
	print("GENERATED_MAP_POPULATION_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
