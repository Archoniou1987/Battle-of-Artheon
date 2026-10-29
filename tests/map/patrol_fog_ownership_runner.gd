extends SceneTree

## Regression: NPC movement is not player exploration. Confirm both the
## shared map API and the real patrol runtime without a mocked renderer.
func _initialize() -> void:
	var ok := true
	var world := TacticalMapState.new(20,20)
	var player_start := Vector2i(1,1)
	var patrol_start := Vector2i(15,15)
	var patrol_next := Vector2i(16,15)
	ok = ok and world.place_entity("player",player_start)
	ok = ok and world.place_entity("patrol-1",patrol_start)
	world.mark_visited(player_start)
	world.reveal_from(player_start,3)
	ok = ok and not world.cell(patrol_start).discovered
	ok = ok and not world.cell(patrol_next).discovered
	var patrol_def := {"patrol_id":"patrol-1","path":[patrol_start,patrol_next],"pause_points":[]}
	var patrol := MapPatrolRuntime.new()
	patrol.configure(world,[patrol_def],"player")
	var before := world.exploration_snapshot()
	var moved := patrol.advance(MapPatrolRuntime.STEP_SECONDS+1.0)
	ok = ok and moved and world.entity_positions["patrol-1"]==patrol_next
	ok = ok and world.exploration_snapshot()==before
	ok = ok and not world.cell(patrol_next).discovered and not world.cell(patrol_next).visited
	var player_step := Vector2i(2,1)
	var movement := world.move_entity("player",player_step)
	ok = ok and bool(movement.get("ok",false)) and world.cell(player_step).discovered and world.cell(player_step).visited
	# Returning along patrol route must also leave unknown cells hidden.
	var back := patrol.advance(MapPatrolRuntime.STEP_SECONDS+1.0)
	ok = ok and back and world.entity_positions["patrol-1"]==patrol_start
	ok = ok and not world.cell(patrol_start).discovered and not world.cell(patrol_start).visited
	print("PATROL_FOG_OWNERSHIP_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
