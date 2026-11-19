extends SceneTree

var errors: Array[String] = []
const CELL := Vector2i(3,3)

func check(ok: bool,label: String) -> void:
	if not ok:
		errors.append(label)
		print("CELL_CONTENT_CASE=FAIL ",label)

func _initialize() -> void:
	var map := TacticalMapState.new(8,8)
	var bridge := MapNpcBridge.new()
	var expedition := ExpeditionState.new("CELL_CONTENT_SOLO")
	var player := CharacterState.new("PLAYER","Explorer",10)
	var repository := ItemRepository.new()
	check(map.place_entity("PLAYER",CELL),"placed_player")
	check(repository.add_item({"instance_id":"QUEST_SCROLL","weight":0.2}),"item_instance")
	check(bool(GroundLootService.place_unowned(expedition,repository,"QUEST_SCROLL",CELL,"quest").get("ok",false)),"placed_quest_item")
	check(repository.add_item({"instance_id":"NEARBY_KEY","weight":0.1}),"remote_instance")
	check(bool(GroundLootService.place_unowned(expedition,repository,"NEARBY_KEY",Vector2i(4,3),"other").get("ok",false)),"placed_remote_item")
	var npc_templates := NpcRepository.new()
	npc_templates.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var npc := NpcInstance.new("BANDIT_CELL",npc_templates.get_npc("NPC003"))
	check(bridge.register_npc(map,npc,CELL),"placed_npc")
	check(map.add_object("ALTAR_CELL",CELL),"placed_altar")
	var area := MapArea.new("HERBS","resource",1,"common",1.0,5.0)
	var cells: Array[Vector2i] = [CELL]
	check(map.add_area(area,cells),"resource_area")
	var read := CellContentService.inspect_current_cell(map,bridge,expedition,player,100)
	check(bool(read.get("ok",false)) and int(read.get("total",-1)) == 4,"four_objects_on_current_cell")
	var by_id: Dictionary = {}
	for entry in read.get("entries",[]):
		by_id[String(entry.get("id",""))] = entry
	check(by_id.has("QUEST_SCROLL") and not by_id.has("NEARBY_KEY"),"no_remote_ground_items")
	check(by_id.has("QUEST_SCROLL") and Array(by_id["QUEST_SCROLL"].get("actions",[])).has("pick_up"),"item_pickup_action")
	check(by_id.has("BANDIT_CELL") and Array(by_id["BANDIT_CELL"].get("actions",[])).has("attack"),"manual_attack_action")
	check(by_id.has("ALTAR_CELL") and Array(by_id["ALTAR_CELL"].get("actions",[])) == ["inspect"],"unresolved_object_inspect_only")
	check(by_id.has("HERBS") and Array(by_id["HERBS"].get("actions",[])).has("gather"),"resource_gather_action")
	check(player.inventory.size() == 0 and GroundLootService.items_at(expedition,CELL,"PLAYER").size() == 1,"projection_has_no_side_effects")
	check(bridge.resolve_death(map,"BANDIT_CELL"),"npc_marked_dead")
	var after := CellContentService.inspect_current_cell(map,bridge,expedition,player,110)
	check(int(after.get("total",-1)) == 3,"dead_npc_not_present")
	check(map.move_entity("PLAYER",Vector2i(4,3)).get("ok",false),"player_changes_cell")
	var next := CellContentService.inspect_current_cell(map,bridge,expedition,player,120)
	check(int(next.get("total",-1)) == 1 and String(next.get("entries",[])[0].get("id","")) == "NEARBY_KEY","follows_player_not_selected_hex")
	print("CELL_CONTENT_SOLO_TEST=" + ("PASS" if errors.is_empty() else "FAIL") + " errors=" + str(errors))
	quit(0 if errors.is_empty() else 1)
