extends SceneTree

const CELL := Vector2i(3,4)
const EXPEDITION := "GROUND_LOOT_SOLO_TEST"
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("GROUND_LOOT_CASE=FAIL ",label)

func _initialize() -> void:
	_run()
	print("GROUND_LOOT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _new_item(id: String, weight: float = 1.0) -> Dictionary:
	return {"instance_id":id,"generated_from_template":"TEST","weight":weight,"quality":"common","durability":{"current":13,"max":20}}

func _run() -> void:
	var expedition := ExpeditionState.new(EXPEDITION)
	var map := TacticalMapState.new(8,8)
	var player := CharacterState.new("PLAYER","Test Hunter",1)
	var repository := ItemRepository.new()
	_check(map.place_entity("PLAYER",CELL),"map_player_exists")
	_check(repository.add_item(_new_item("DEER_HIDE",1.25)),"reward_item_created")
	_check(bool(GroundLootService.place_unowned(expedition,repository,"DEER_HIDE",CELL,"deer_quest").get("ok",false)),"quest_loot_placed")
	_check(not bool(GroundLootService.place_unowned(expedition,repository,"DEER_HIDE",CELL,"duplicate").get("ok",false)),"duplicate_ground_rejected")
	_check(GroundLootService.items_at(expedition,CELL,"PLAYER").size() == 1,"current_cell_has_item")
	_check(GroundLootService.items_at(expedition,Vector2i(0,0),"PLAYER").is_empty(),"remote_cell_not_visible")
	var svc := GroundLootService.new()
	var started := svc.begin_pickup(expedition,map,player,repository,"DEER_HIDE",100)
	_check(bool(started.get("ok",false)) and int(started.get("complete_at_unix",-1)) == 105,"five_seconds_required")
	if not bool(started.get("ok",false)):
		return
	var ticket := String(started["ticket"])
	_check(not bool(svc.finish_pickup(ticket,expedition,map,player,repository,104).get("ok",false)),"cannot_pick_up_early")
	_check(not player.inventory.owns("DEER_HIDE"),"not_claimed_before_five_seconds")
	var full := svc.finish_pickup(ticket,expedition,map,player,repository,105,0,100)
	_check(String(full.get("reason",""))=="pickup_slots_full","slots_enforced")
	_check(GroundLootService.items_at(expedition,CELL,"PLAYER").size()==1,"failed_pickup_does_not_delete")
	var weight_start := svc.begin_pickup(expedition,map,player,repository,"DEER_HIDE",110)
	_check(bool(weight_start.get("ok",false)),"weight_pickup_started")
	var overweight := svc.finish_pickup(String(weight_start.get("ticket","")),expedition,map,player,repository,115,5,1.0)
	_check(String(overweight.get("reason",""))=="pickup_overweight","weight_enforced")
	var move_start := svc.begin_pickup(expedition,map,player,repository,"DEER_HIDE",120)
	map.entity_positions["PLAYER"] = Vector2i(4,4)
	var interrupted := svc.finish_pickup(String(move_start.get("ticket","")),expedition,map,player,repository,125,5,10)
	_check(String(interrupted.get("reason",""))=="pickup_interrupted_by_movement","movement_cancels_pickup")
	map.entity_positions["PLAYER"] = CELL
	var attack_start := svc.begin_pickup(expedition,map,player,repository,"DEER_HIDE",130)
	_check(svc.cancel_pickup(String(attack_start.get("ticket",""))),"attack_cancels_pickup")
	_check(not bool(svc.finish_pickup(String(attack_start.get("ticket","")),expedition,map,player,repository,140,5,10).get("ok",false)),"cancelled_pickup_cannot_complete")
	var last := svc.begin_pickup(expedition,map,player,repository,"DEER_HIDE",150)
	_check(bool(svc.finish_pickup(String(last.get("ticket","")),expedition,map,player,repository,155,5,10).get("ok",false)),"successful_pickup")
	_check(player.inventory.owns("DEER_HIDE") and GroundLootService.items_at(expedition,CELL,"PLAYER").is_empty(),"one_item_transferred_to_bag")
	_check(repository.get_item("DEER_HIDE").get("durability",{}).get("current",-1)==13,"instance_durability_preserved")
	_check(not bool(svc.finish_pickup(String(last.get("ticket","")),expedition,map,player,repository,156,5,10).get("ok",false)),"pickup_not_repeatable")
	var dropped := GroundLootService.drop_from_bag(expedition,map,player,repository,"DEER_HIDE")
	_check(bool(dropped.get("ok",false)),"drop_on_map")
	_check(not player.inventory.owns("DEER_HIDE") and GroundLootService.items_at(expedition,CELL,"PLAYER").size()==1,"drop_moves_instance_without_destroying")
	_check(repository.has_item("DEER_HIDE"),"drop_keeps_original_instance")
	var saved: Variant = JSON.parse_string(JSON.stringify(expedition.to_dict()))
	var restored := ExpeditionState.from_dict(saved)
	var restored_repo := ItemRepository.from_dict(JSON.parse_string(JSON.stringify(repository.to_dict())))
	_check(GroundLootService.items_at(restored,CELL,"PLAYER").size()==1 and restored_repo.has_item("DEER_HIDE"),"ground_survives_restart")
	_check(GroundLootService.remove_expired(restored,restored_repo,100000)==0,"expedition_loot_has_no_fifteen_minute_ttl")
	var new_service := GroundLootService.new()
	var restored_ticket := new_service.begin_pickup(restored,map,player,restored_repo,"DEER_HIDE",100000)
	_check(bool(new_service.finish_pickup(String(restored_ticket.get("ticket","")),restored,map,player,restored_repo,100005,5,10).get("ok",false)),"pickup_after_restart")
	_check(repository.add_item(_new_item("HERBS",0.1)),"herb_instance_exists")
	_check(bool(GroundLootService.place_unowned(restored,repository,"HERBS",CELL,"quest","",GroundLootService.POLICY_TIMED,200).get("ok",false)),"timed_object_placed")
	_check(GroundLootService.remove_expired(restored,repository,201)==1 and not repository.has_item("HERBS"),"timed_object_expires_separately")
	_check(restored_repo.has_item("DEER_HIDE") and player.inventory.owns("DEER_HIDE"),"timed_cleanup_does_not_touch_persistent_reward")
