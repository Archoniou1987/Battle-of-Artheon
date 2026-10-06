extends SceneTree

func _initialize()->void:
	var repository:=ResourceRepository.new()
	var data:=_load_json("res://data/resources/resources.json")
	var valid:=true
	for raw_resource in data.get("resources", []):
		var row:=raw_resource as Dictionary
		var resource:=ResourceDefinition.new(
			String(row.get("id", "")),
			String(row.get("name", "")),
			String(row.get("category", "")),
			int(row.get("level", 0)),
			String(row.get("rarity", ""))
		)
		valid = valid and repository.add_resource(resource)

	valid = valid and repository.all_resources().size() == 6
	valid = valid and repository.has_resource("RES001") and repository.has_resource("RES006")
	var copper:=repository.get_resource("RES001")
	var iron:=repository.get_resource("RES002")
	var obsidian:=repository.get_resource("RES006")
	valid = valid and copper != null and copper.level == 5 and copper.category == "ore"
	valid = valid and iron != null and iron.level == 20
	valid = valid and obsidian != null and obsidian.level == 95
	var golem_range:=repository.resources_for("ore", 35, 65)
	valid = valid and golem_range.size() == 2
	valid = valid and golem_range[0].resource_id == "RES003" and golem_range[1].resource_id == "RES004"
	print("RESOURCE_DEFINITION count=%d golem_range=%d" % [repository.all_resources().size(), golem_range.size()])
	print("RESOURCE_DEFINITION_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _load_json(path:String)->Dictionary:
	var file:=FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed:Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
