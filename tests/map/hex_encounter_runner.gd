extends SceneTree

func _initialize()->void:
	var map:=TacticalMapState.new(8, 8)
	var service:=HexEncounterService.new()
	var valid:=map.place_entity("PLAYER", Vector2i(1, 1))

	var ambush:=HexEncounter.new("ENC_AMBUSH_001", HexEncounter.TRIGGER_ENTER, "spawn_npc", {"npc_template_id":"NPC003"}, true)
	var altar:=HexEncounter.new("ENC_ALTAR_001", HexEncounter.TRIGGER_INTERACT, "apply_effect", {"effect_id":"EFF_ALTAR"}, true, ["ALTAR_UNLOCKED"])
	var secret:=HexEncounter.new("ENC_SECRET_001", HexEncounter.TRIGGER_DISCOVER, "reveal_object", {"object_id":"CHEST_SECRET_001"}, true)

	valid = valid and service.add_encounter(ambush, Vector2i(2, 1), map)
	valid = valid and service.add_encounter(altar, Vector2i(3, 1), map)
	valid = valid and service.add_encounter(secret, Vector2i(4, 1), map)

	var move:=map.move_entity("PLAYER", Vector2i(2, 1))
	var entered:=service.on_move(move)
	valid = valid and entered.size() == 1 and str(entered[0].get("consequence", "")) == "spawn_npc"
	valid = valid and service.on_move({"ok":true, "to":Vector2i(2, 1)}).is_empty()

	valid = valid and service.interact(Vector2i(3, 1)).is_empty()
	service.set_flag("ALTAR_UNLOCKED")
	var altar_result:=service.interact(Vector2i(3, 1))
	valid = valid and altar_result.size() == 1 and str(altar_result[0].get("consequence", "")) == "apply_effect"

	var discovered:=service.discover(Vector2i(4, 1))
	valid = valid and discovered.size() == 1 and str(discovered[0].get("consequence", "")) == "reveal_object"
	valid = valid and service.discover(Vector2i(4, 1)).is_empty()

	print("HEX_ENCOUNTER enter=%d interact=%d discover=%d" % [entered.size(), altar_result.size(), discovered.size()])
	print("HEX_ENCOUNTER_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
