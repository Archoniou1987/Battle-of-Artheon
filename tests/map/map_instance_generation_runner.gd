extends SceneTree

var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("MAP_INSTANCE_GENERATION_CASE=FAIL ",label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settlements := {"home":WorldInstanceContract.settlement("home","forest",1)}
	var definition := WorldInstanceContract.instance("MAP-0001","home","forest",1337,1,20,20,75)
	var first := MapInstanceGenerationService.generate(definition,settlements)
	var second := MapInstanceGenerationService.generate(definition,settlements)
	_check(bool(first.get("ok",false)),"generation_accepted")
	_check(bool(second.get("ok",false)),"generation_repeat_accepted")
	if bool(first.get("ok",false)) and bool(second.get("ok",false)):
		var a: Dictionary = first["generated"]
		var b: Dictionary = second["generated"]
		var map: TacticalMapState = a["map"]
		_check(map.width == 20 and map.height == 20,"requested_size")
		_check(int(a["seed"]) == 1337,"requested_seed")
		_check(a["entrance"] == b["entrance"] and a["exit"] == b["exit"],"deterministic_entrance_exit")
		_check(a["regions"] == b["regions"],"deterministic_existing_region_generator")
		_check(a["patrols"] == b["patrols"],"deterministic_existing_patrol_generator")
		_check(a["npc_cells"] == b["npc_cells"],"deterministic_existing_npc_cells")
		_check(a["boss_groups"] == b["boss_groups"],"deterministic_existing_boss_groups")
		_check(a.has("region_npcs") and a.has("region_objects") and a.has("encounter_service"),"existing_subsystems_not_dropped")
		_check(first["instance"]["instance_id"] == "MAP-0001","instance_identity_retained")
	var different_id := definition.duplicate(true)
	different_id["instance_id"] = "MAP-0002"
	var same_seed := MapInstanceGenerationService.generate(different_id,settlements)
	_check(bool(same_seed.get("ok",false)),"second_instance_same_seed_allowed")
	if bool(same_seed.get("ok",false)) and bool(first.get("ok",false)):
		_check(same_seed["generated"]["entrance"] == first["generated"]["entrance"],"identity_does_not_modify_terrain")
	var wrong_version := definition.duplicate(true)
	wrong_version["generation_version"] = 2
	_check(String(MapInstanceGenerationService.generate(wrong_version,settlements).get("reason","")) == "unsupported_generation_version","new_versions_fail_closed")
	var bad_biome := definition.duplicate(true)
	bad_biome["biome_id"] = "swamp"
	_check(String(MapInstanceGenerationService.generate(bad_biome,settlements).get("reason","")) == "map_settlement_biome_mismatch","biome_gate")
	var closed := definition.duplicate(true)
	closed["lifecycle"] = WorldInstanceContract.STATE_CLOSED
	_check(String(MapInstanceGenerationService.generate(closed,settlements).get("reason","")) == "map_instance_closed","closed_instance_not_regenerated")
	print("MAP_INSTANCE_GENERATION_TEST=","PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)
