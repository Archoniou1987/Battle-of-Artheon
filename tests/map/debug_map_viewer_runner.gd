extends SceneTree

func _initialize()->void:
	call_deferred("_run")

func _run()->void:
	var packed:=load("res://scenes/debug/debug_map_viewer.tscn") as PackedScene
	if packed==null:
		print("DEBUG_MAP_VIEWER_TEST=FAIL load")
		quit(1)
		return
	var viewer:=packed.instantiate()
	root.add_child(viewer)
	await process_frame
	var canvas:=viewer.get_node("Root/MapPanel/Scroll/Canvas") as DebugMapCanvas
	var seed_input:=viewer.get_node("Root/Sidebar/SeedRow/Seed") as SpinBox
	var summary:=viewer.get_node("Root/Sidebar/Summary") as Label
	var valid:=canvas!=null and seed_input!=null and summary!=null
	valid=valid and not canvas.generated.is_empty()
	valid=valid and canvas.generated.get("seed",-1)==777
	valid=valid and summary.text.contains("Map: 20x20")
	var expedition:=ExpeditionState.new("MAP_LOOT")
	var pool:=EncounterLootPool.new()
	pool.add_drop("VISIBLE_ITEM","NPC")
	pool.assign_all("PLAYER")
	pool.place_on_hex(Vector2i(3,4),int(Time.get_unix_time_from_system()))
	valid=valid and expedition.save_loot_pool("ENCOUNTER",pool)
	viewer.set_loot_context(expedition,"PLAYER")
	valid=valid and canvas.loot_markers.size()==1 and canvas.loot_markers.has(Vector2i(3,4))
	viewer.set_loot_context(expedition,"OTHER")
	valid=valid and canvas.loot_markers.is_empty()
	viewer.set_loot_context(expedition,"PLAYER")
	pool.entries.clear()
	valid=valid and expedition.save_loot_pool("ENCOUNTER",pool)
	viewer.refresh_loot_markers()
	valid=valid and canvas.loot_markers.is_empty()
	var claim_repo:=ItemRepository.new()
	var claim_player:=CharacterState.new("PLAYER","Tester")
	var claim_pool:=EncounterLootPool.new()
	valid=valid and claim_repo.add_item({"instance_id":"CLAIM_ITEM"})
	valid=valid and claim_pool.add_drop("CLAIM_ITEM","NPC")
	claim_pool.assign_all("PLAYER")
	claim_pool.place_on_hex(Vector2i(5,6),int(Time.get_unix_time_from_system()))
	valid=valid and expedition.save_loot_pool("CLAIM_ENCOUNTER",claim_pool)
	viewer.set_loot_claim_context(expedition,claim_player,claim_repo)
	valid=valid and not viewer._loot_dialog.visible
	viewer._on_loot_hex_selected(Vector2i(5,6))
	valid=valid and viewer._loot_dialog.visible
	viewer._claim_all()
	valid=valid and claim_player.inventory.owns("CLAIM_ITEM")
	valid=valid and not canvas.loot_markers.has(Vector2i(5,6))
	valid=valid and not viewer._loot_dialog.visible
	seed_input.value=1234
	viewer.call("_regenerate")
	await process_frame
	valid=valid and canvas.generated.get("seed",-1)==1234
	valid=valid and not canvas.generated.get("boss_groups",[]).is_empty()
	print("DEBUG_MAP_VIEWER_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
