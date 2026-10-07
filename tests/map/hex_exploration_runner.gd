extends SceneTree
func _initialize()->void:
	var map:=TacticalMapState.new(15,15)
	var center:=Vector2i(7,7)
	var revealed:=map.reveal_from(center,2)
	var valid:=revealed.size()==19
	valid=valid and map.exploration_state(center)=="revealed"
	valid=valid and map.exploration_state(Vector2i(9,7))=="revealed"
	valid=valid and map.exploration_state(Vector2i(10,7))=="unknown"
	map.mark_visited(center)
	valid=valid and map.exploration_state(center)=="visited"
	var snapshot:=map.exploration_snapshot()
	var restored:=TacticalMapState.new(15,15)
	restored.restore_exploration(snapshot)
	valid=valid and restored.exploration_state(center)=="visited"
	valid=valid and restored.exploration_state(Vector2i(9,7))=="revealed"
	valid=valid and restored.exploration_state(Vector2i(10,7))=="unknown"
	restored.reveal_from(Vector2i(9,7),1)
	valid=valid and restored.exploration_state(Vector2i(10,7))=="revealed"
	valid=valid and restored.exploration_state(center)=="visited"
	print("HEX_EXPLORATION revealed_radius2=%d saved=%d"%[revealed.size(),snapshot.size()])
	print("HEX_EXPLORATION_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
