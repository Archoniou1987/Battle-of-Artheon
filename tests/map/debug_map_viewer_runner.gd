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
	seed_input.value=1234
	viewer.call("_regenerate")
	await process_frame
	valid=valid and canvas.generated.get("seed",-1)==1234
	valid=valid and not canvas.generated.get("boss_groups",[]).is_empty()
	print("DEBUG_MAP_VIEWER_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
