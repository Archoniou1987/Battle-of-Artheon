extends SceneTree

const EXPEDITION := "user://test_town_adopt_expedition.json"
const TOWN := "user://test_town_adopt_canonical.json"
const MANIFEST := "user://test_town_adopt_pending.json"
const ID := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		errors.append(name)
		print("TOWN_ADOPT_CASE=FAIL ",name)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [EXPEDITION,TOWN,MANIFEST]:
		wipe(path)
	var city := CharacterState.new("player","Герой",5)
	var city_repo := ItemRepository.new()
	check(city_repo.add_item({"instance_id":"OLD_BLADE","weight":1.0}),"town_item")
	check(city.inventory.add_instance("OLD_BLADE",city_repo),"town_owns_item")
	check(bool(SoloTownSaveService.save(TOWN,city,city_repo).get("ok",false)),"city_snapshot_exists_before_departure")
	var created := SoloTownExpeditionBridge.create_from_town(EXPEDITION,ID,77,Vector2i(2,2),city,city_repo,MANIFEST)
	check(bool(created.get("ok",false)),"expedition_started")
	if not bool(created.get("ok",false)):
		quit(1)
		return
	var restored := ExpeditionSaveService.read(EXPEDITION,ID,"player")
	var expedition: ExpeditionState = restored["expedition"]
	var hero: CharacterState = restored["character"]
	var repo: ItemRepository = restored["repository"]
	check(repo.add_item({"instance_id":"EARNED_RING","weight":0.1}),"earned_item_created")
	check(hero.inventory.add_instance("EARNED_RING",repo),"earned_item_owned")
	check(repo.add_item({"instance_id":"UNCLAIMED_DROP","weight":0.5}),"ground_item_created")
	check(bool(GroundLootService.place_unowned(expedition,repo,"UNCLAIMED_DROP",Vector2i(2,2),"defeated").get("ok",false)),"ground_item_exists")
	check(bool(ExpeditionSaveService.save(EXPEDITION,expedition,hero,repo).get("ok",false)),"expedition_saved")
	check(not bool(SoloTownSaveService.adopt_closed_expedition(TOWN,EXPEDITION,ID,"player",MANIFEST).get("ok",false)),"not_closed_cannot_adopt")
	check(bool(SoloTownReturnService.close_for_town(EXPEDITION,ID,"player",MANIFEST).get("ok",false)),"expedition_closed")
	var city_before: Dictionary = SoloTownSaveService.read(TOWN,"player")
	check(bool(city_before.get("ok",false)) and city_before["repository"].size()==1,"city_unchanged_during_expedition")
	var adopted := SoloTownSaveService.adopt_closed_expedition(TOWN,EXPEDITION,ID,"player",MANIFEST)
	check(bool(adopted.get("ok",false)) and not bool(adopted.get("already_adopted",true)),"first_adoption")
	var previous := SoloTownSaveService.read(TOWN,"player")
	check(bool(previous.get("ok",false)),"town_snapshot_restores")
	if not bool(previous.get("ok",false)):
		quit(1)
		return
	var owner: CharacterState = previous["character"]
	var owned_repo: ItemRepository = previous["repository"]
	check(owner.inventory.owns("OLD_BLADE") and owner.inventory.owns("EARNED_RING"),"both_owned_items_preserved")
	check(not owner.inventory.owns("UNCLAIMED_DROP") and not owned_repo.has_item("UNCLAIMED_DROP"),"unclaimed_excluded")
	check(owned_repo.size()==2,"only_owned_instances")
	check(city.inventory.size()==1 and city_repo.size()==1,"original_town_untouched")
	var again := SoloTownSaveService.adopt_closed_expedition(TOWN,EXPEDITION,ID,"player",MANIFEST)
	check(bool(again.get("ok",false)) and bool(again.get("already_adopted",false)),"second_adoption_idempotent")
	var stale := SoloTownSaveService.save(TOWN,owner,owned_repo,"0".repeat(64))
	check(not bool(stale.get("ok",false)),"stale_town_write_denied")
	var changed := SoloTownSaveService.save(TOWN,owner,owned_repo,String(previous["sha256"]))
	check(bool(changed.get("ok",false)),"canonical_town_update")
	check(not bool(SoloTownSaveService.read(TOWN,"different_player").get("ok",false)),"wrong_player_denied")
	# Second visit: immutable history is archived only after canonical adoption.
	var old_snapshot := FileAccess.get_file_as_string(EXPEDITION)
	var pending_lock := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if pending_lock != null:
		pending_lock.store_string("pending")
		pending_lock.close()
	check(not bool(SoloTownExpeditionBridge.archive_adopted_expedition(EXPEDITION,TOWN,ID,"player",MANIFEST).get("ok",false)),"pending_combat_blocks_archive")
	wipe(MANIFEST)
	var archived := SoloTownExpeditionBridge.archive_adopted_expedition(EXPEDITION,TOWN,ID,"player",MANIFEST)
	check(bool(archived.get("ok",false)),"closed_adopted_expedition_archived")
	if bool(archived.get("ok",false)):
		var archive_path := String(archived["archive_path"])
		check(FileAccess.file_exists(archive_path) and not FileAccess.file_exists(EXPEDITION),"archive_preserves_old_file_and_frees_active_slot")
		check(FileAccess.get_file_as_string(archive_path)==old_snapshot,"archive_keeps_exact_completed_world_bytes")
		var next_town := SoloTownSaveService.read(TOWN,"player")
		check(bool(next_town.get("ok",false)),"second_departure_reads_committed_city")
		if bool(next_town.get("ok",false)):
			var next := SoloTownExpeditionBridge.create_from_town(EXPEDITION,ID,78,Vector2i(5,5),next_town["character"],next_town["repository"],MANIFEST)
			check(bool(next.get("ok",false)),"second_expedition_created")
			var saved_second := ExpeditionSaveService.read(EXPEDITION,ID,"player")
			check(bool(saved_second.get("ok",false)),"second_expedition_reopens")
			if bool(saved_second.get("ok",false)):
				check(saved_second["character"].inventory.owns("OLD_BLADE") and saved_second["character"].inventory.owns("EARNED_RING"),"second_expedition_inherits_owned_loot")
				check(not saved_second["repository"].has_item("UNCLAIMED_DROP"),"ground_loot_not_minted_into_second_expedition")
				check(saved_second["expedition"].is_active(),"second_expedition_active")
		wipe(archive_path)
	for path in [EXPEDITION,TOWN,MANIFEST]:
		wipe(path)
	print("TOWN_ADOPT_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
