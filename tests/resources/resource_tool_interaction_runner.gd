extends SceneTree

func _init()->void:
	call_deferred("_run")

func _run()->void:
	var repository:=ItemRepository.new()
	var character:=CharacterState.new("PLAYER_TOOL_TEST", "Tool Tester", 20)
	var pickaxe:Dictionary = {
		"instance_id":"TOOL_PICKAXE_001",
		"equip_slots":["tool"],
		"slot_usage":["tool"],
		"durability_current":20,
		"durability_max":20,
		"resource_categories":["ore"],
		"tool_level":25,
		"resource_bonus_yield":2
	}
	var knife:Dictionary = {
		"instance_id":"TOOL_KNIFE_001",
		"equip_slots":["tool"],
		"slot_usage":["tool"],
		"durability_current":20,
		"durability_max":20,
		"resource_categories":["hide"],
		"tool_level":15,
		"resource_bonus_yield":0
	}
	var valid:=repository.add_item(pickaxe) and repository.add_item(knife)
	valid = valid and character.receive_item("TOOL_PICKAXE_001", repository)
	valid = valid and character.receive_item("TOOL_KNIFE_001", repository)
	var iron:=ResourceDefinition.new("RES002", "Iron Ore", "ore", 20, "common")
	var hide:=ResourceDefinition.new("RES_HIDE_010", "Wolf Hide", "hide", 10, "common")
	var high_ore:=ResourceDefinition.new("RES_HIGH_ORE", "Black Iron Ore", "ore", 40, "green")
	var no_tool_required:=ResourceToolService.evaluate(character, repository, hide, ResourceToolService.MODE_REQUIRED)
	valid = valid and not bool(no_tool_required.get("allowed", true))
	valid = valid and character.equip("tool", "TOOL_PICKAXE_001", repository)
	var gather:=ResourceToolService.evaluate(character, repository, iron, ResourceToolService.MODE_GATHERING)
	var bonus:=ResourceToolService.evaluate(character, repository, iron, ResourceToolService.MODE_BONUS)
	var too_high:=ResourceToolService.evaluate(character, repository, high_ore, ResourceToolService.MODE_GATHERING)
	valid = valid and bool(gather.get("allowed", false)) and bool(gather.get("tool_matched", false))
	valid = valid and ResourceToolService.apply_bonus(2, bonus) == 4
	valid = valid and not bool(too_high.get("allowed", true))
	valid = valid and String(character.unequip("tool")) == "TOOL_PICKAXE_001"
	valid = valid and character.equip("tool", "TOOL_KNIFE_001", repository)
	var hide_required:=ResourceToolService.evaluate(character, repository, hide, ResourceToolService.MODE_REQUIRED)
	var ore_with_knife:=ResourceToolService.evaluate(character, repository, iron, ResourceToolService.MODE_BONUS)
	valid = valid and bool(hide_required.get("allowed", false))
	valid = valid and bool(ore_with_knife.get("allowed", false)) and not bool(ore_with_knife.get("tool_matched", true))
	valid = valid and ResourceToolService.apply_bonus(2, ore_with_knife) == 2
	print("RESOURCE_TOOL required=%s bonus=%d high_level=%s" % [String(hide_required.get("allowed", false)), ResourceToolService.apply_bonus(2, bonus), String(too_high.get("allowed", true))])
	print("RESOURCE_TOOL_INTERACTION_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
