extends SceneTree

func _initialize()->void:
	var valid:=true
	var profile:=ExpeditionProfile.new("small_adventure",32,18,12,"normal")
	valid=valid and profile.width==32 and profile.height==18
	valid=valid and profile.energy_cost==12 and profile.difficulty_id=="normal"
	valid=valid and profile.lifetime_policy=="persistent"
	valid=valid and profile.death_policy=="standard"
	valid=valid and profile.exit_policy=="free_exit"

	var state:=ExpeditionState.new("EXP_TEST",profile,777)
	state.player_position=Vector2i(7,9)
	state.created_at_unix=1000
	state.world_state={"opened_objects":["CHEST_01"],"defeated_entities":["NPC_01"]}
	var restored:=ExpeditionState.from_dict(state.to_dict())
	valid=valid and restored.expedition_id=="EXP_TEST"
	valid=valid and restored.seed_value==777
	valid=valid and restored.player_position==Vector2i(7,9)
	valid=valid and restored.world_state==state.world_state
	valid=valid and restored.profile.width==32 and restored.profile.height==18

	var timed:=ExpeditionProfile.new(
		"event",200,100,40,"hard",
		ExpeditionProfile.LIFETIME_TIME_LIMITED,
		"standard",
		"free_exit",
		86400,
		"close"
	)
	var event:=ExpeditionState.new("EVENT_TEST",timed,123)
	event.expires_at_unix=100000
	valid=valid and not bool(event.refresh_lifetime(100001).get("expired",false))
	valid=valid and bool(event.refresh_lifetime(186400).get("expired",false))
	valid=valid and event.status==ExpeditionState.STATUS_EXPIRED

	var center:=Vector2i(10,10)
	var neighbors:=SquareGrid.neighbors(center)
	valid=valid and neighbors.size()==4
	valid=valid and SquareGrid.distance(Vector2i(0,0),Vector2i(3,4))==7
	valid=valid and neighbors.has(Vector2i(11,10)) and neighbors.has(Vector2i(10,11))
	valid=valid and neighbors.has(Vector2i(9,10)) and neighbors.has(Vector2i(10,9))

	print("EXPEDITION_FOUNDATION_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
