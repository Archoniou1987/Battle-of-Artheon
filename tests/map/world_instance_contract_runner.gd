extends SceneTree

var failures: Array[String] = []

func _check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("WORLD_INSTANCE_CASE=FAIL ",name)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var forest := WorldInstanceContract.settlement("town_north","forest",1)
	var marsh := WorldInstanceContract.settlement("town_south","swamp",1)
	var towns := {"town_north":forest,"town_south":marsh}
	var first := WorldInstanceContract.instance("MAP-0001","town_north","forest",847291,1,50,50,75)
	var second := WorldInstanceContract.instance("MAP-0002","town_north","forest",847291,1,50,50,75)
	_check(WorldInstanceContract.validate_instance(first,towns) == "", "valid_shared_contract")
	_check(first["instance_id"] != second["instance_id"] and first["seed"] == second["seed"],"seed_is_not_instance_identity")
	_check(first["access_policy"] == WorldInstanceContract.POLICY_OPEN_PVP,"level75_open_pvp")
	_check(WorldInstanceContract.instance("MAP-LOW","town_north","forest",3,1,50,50,74)["access_policy"] == WorldInstanceContract.POLICY_SAFE,"level74_safe")
	_check(WorldInstanceContract.can_enter(first,towns,"town_north",75) == "","correct_area_enter")
	_check(WorldInstanceContract.can_enter(first,towns,"town_south",75) == "map_wrong_settlement","wrong_area_rejected")
	_check(WorldInstanceContract.can_enter(first,towns,"town_north",74) == "map_level_locked","underlevel_rejected")
	first["connections"] = [{"destination_id":"MAP-0002","travel_seconds":60}]
	_check(WorldInstanceContract.validate_connection(first,second,towns) == "","registered_same_biome_transition")
	var alien := WorldInstanceContract.instance("MAP-SOUTH","town_south","swamp",8,1,50,50,75)
	_check(WorldInstanceContract.validate_connection(first,alien,towns) == "map_connection_cross_area","cross_biome_rejected")
	second["lifecycle"] = WorldInstanceContract.STATE_CLOSED
	_check(WorldInstanceContract.validate_connection(first,second,towns) == "map_destination_closed","closed_map_unreachable")
	second["lifecycle"] = WorldInstanceContract.STATE_ACTIVE
	_check(WorldInstanceContract.can_enter(second,towns,"town_north",75) == "","new_instance_independent")
	var changed := first.duplicate(true)
	changed["biome_id"] = "swamp"
	_check(WorldInstanceContract.validate_instance(changed,towns) == "map_settlement_biome_mismatch","biome_tied_to_settlement")
	changed = first.duplicate(true)
	changed["connections"] = [{"destination_id":"MAP-0001","travel_seconds":60}]
	_check(WorldInstanceContract.validate_instance(changed,towns) == "map_connection_target_invalid","self_edge_rejected")
	print("WORLD_INSTANCE_CONTRACT_TEST=","PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)
