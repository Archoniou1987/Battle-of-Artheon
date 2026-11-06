extends SceneTree

## Actual Solo map integration: 2 seconds, persisted instance ownership,
## interrupted actions, idempotency and a separate 5-second shared default.
const EXP := "user://test_live_pickup_exp.json"
const TOWN := "user://test_live_pickup_town.json"
const MANIFEST := "user://test_live_pickup_manifest.json"
const ID := "solo_exp_pickup_player"
const PLAYER := "player"
const CELL := Vector2i(6,5)
const ITEM := "SOLO_PICKUP_TEST_LOOT"
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_PICKUP_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("LIVE_SOLO_PICKUP_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
	var character := CharacterState.new(PLAYER,"Collector",5)
	var items := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,character,items).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,125,CELL,character,items,MANIFEST).get("ok",false)),"expedition_saved")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(opened.get("ok",false)),"map_open")
	if not bool(opened.get("ok",false)):
		return
	var session: SoloLiveMapSession = opened["session"]
	check(session.repository.add_item({"instance_id":ITEM,"weight":0.5,"quality":"common","durability":{"current":7,"max":10}}),"item_instance_created")
	check(bool(GroundLootService.place_unowned(session.expedition,session.repository,ITEM,CELL,"test_npc").get("ok",false)),"ground_item_placed")
	check(bool(ExpeditionSaveService.save(EXP,session.expedition,session.character,session.repository).get("ok",false)),"ground_item_saved")
	var restored := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(restored.get("ok",false)),"ground_survives_restart")
	if not bool(restored.get("ok",false)):
		return
	session = restored["session"]
	check(session.visible_ground_items().size()==1,"item_visible_on_current_cell")
	check(not session.character.inventory.owns(ITEM),"item_not_automatically_owned")
	var test_start := session.begin_ground_pickup(ITEM,100)
	check(bool(test_start.get("ok",false)) and int(test_start.get("complete_at_unix",-1))==102,"solo_duration_two_seconds")
	if not bool(test_start.get("ok",false)):
		return
	var ticket := String(test_start["ticket"])
	var early := session.finish_ground_pickup(ticket,101)
	check(not bool(early.get("ok",false)) and String(early.get("reason",""))=="pickup_still_running","cannot_claim_before_two_seconds")
	check(session.visible_ground_items().size()==1 and not session.character.inventory.owns(ITEM),"early_attempt_does_not_mutate_owners")
	# A pending action is ephemeral: restarting destroys the ticket.
	var restart := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(restart.get("ok",false)),"restart_during_pickup")
	if not bool(restart.get("ok",false)):
		return
	session = restart["session"]
	check(not bool(session.finish_ground_pickup(ticket,102).get("ok",false)),"old_ticket_invalid_after_restart")
	var cancelled := session.begin_ground_pickup(ITEM,110)
	check(bool(cancelled.get("ok",false)),"cancelled_pickup_started")
	if bool(cancelled.get("ok",false)):
		check(session.cancel_ground_pickup(String(cancelled["ticket"])),"pickup_cancelled")
		check(not bool(session.finish_ground_pickup(String(cancelled["ticket"]),112).get("ok",false)),"cancelled_ticket_not_reusable")
	var moved := session.begin_ground_pickup(ITEM,120)
	check(bool(moved.get("ok",false)),"movement_pickup_started")
	if bool(moved.get("ok",false)):
		session.map.entity_positions[PLAYER] = Vector2i(5,5)
		var interrupted := session.finish_ground_pickup(String(moved["ticket"]),122)
		check(String(interrupted.get("reason",""))=="pickup_interrupted_by_movement","movement_prevents_pickup")
		session.map.entity_positions[PLAYER] = CELL
	check(not session.character.inventory.owns(ITEM),"interruptions_never_grant_item")
	var last := session.begin_ground_pickup(ITEM,130)
	check(bool(last.get("ok",false)),"final_pickup_started")
	if not bool(last.get("ok",false)):
		return
	check(bool(session.finish_ground_pickup(String(last["ticket"]),132).get("ok",false)),"pickup_completed_at_two_seconds")
	check(session.character.inventory.owns(ITEM) and session.visible_ground_items().is_empty(),"item_transferred_once")
	check(session.repository.get_item(ITEM).get("durability",{}).get("current",-1)==7,"original_item_instance_retained")
	check(not bool(session.finish_ground_pickup(String(last["ticket"]),133).get("ok",false)),"same_ticket_not_replayed")
	check(not bool(session.begin_ground_pickup(ITEM,134).get("ok",false)),"collected_item_not_on_ground")
	var final_world := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(final_world.get("ok",false)),"pickup_world_valid")
	if bool(final_world.get("ok",false)):
		check(final_world["character"].inventory.owns(ITEM) and GroundLootService.items_at(final_world["expedition"],CELL,PLAYER).is_empty(),"canonical_save_contains_only_owned_item")
		check(final_world["repository"].size()==1,"original_repository_instance_not_duplicated")
	var base := GroundLootService.new()
	var shared_character := CharacterState.new("shared","Shared",1)
	var shared_map := TacticalMapState.new(8,8)
	var shared_exp := ExpeditionState.new("shared_exp")
	var shared_repo := ItemRepository.new()
	check(shared_map.place_entity("shared",CELL),"shared_map_player")
	check(shared_repo.add_item({"instance_id":"shared_item","weight":1.0}),"shared_instance")
	check(bool(GroundLootService.place_unowned(shared_exp,shared_repo,"shared_item",CELL,"test").get("ok",false)),"shared_ground_item")
	var shared_start := base.begin_pickup(shared_exp,shared_map,shared_character,shared_repo,"shared_item",200)
	check(int(shared_start.get("complete_at_unix",-1))==205,"non_solo_default_still_five_seconds")
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
