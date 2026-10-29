extends SceneTree

const SAVE := "user://test_town_return_solo.json"
const MANIFEST := "user://test_town_return_manifest.json"
const EXP := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		print("TOWN_RETURN_CASE=FAIL ",label)

func remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	remove_file(SAVE)
	remove_file(MANIFEST)
	var town := CharacterState.new("player","Герой",6)
	var repo := ItemRepository.new()
	check(repo.add_item({"instance_id":"TOWN_BLADE","weight":2.0}),"town_blade_exists")
	check(town.inventory.add_instance("TOWN_BLADE",repo),"town_blade_owned")
	var started: Dictionary = SoloTownExpeditionBridge.create_from_town(SAVE,EXP,1122,Vector2i(2,3),town,repo,MANIFEST)
	check(bool(started.get("ok",false)),"expedition_created")
	if not bool(started.get("ok",false)):
		quit(1)
		return
	var save: Dictionary = ExpeditionSaveService.read(SAVE,EXP,"player")
	var expedition: ExpeditionState = save["expedition"]
	var hero: CharacterState = save["character"]
	var items: ItemRepository = save["repository"]
	check(items.add_item({"instance_id":"BANDIT_LOOT","weight":0.5}),"combat_loot_item_registered")
	check(bool(GroundLootService.place_unowned(expedition,items,"BANDIT_LOOT",Vector2i(2,3),"battle").get("ok",false)),"unclaimed_loot_ground")
	check(items.add_item({"instance_id":"QUEST_REWARD","weight":0.1}),"quest_item_registered")
	check(hero.inventory.add_instance("QUEST_REWARD",items),"quest_item_owned")
	check(bool(ExpeditionSaveService.save(SAVE,expedition,hero,items).get("ok",false)),"expedition_updated")
	var pending := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if pending != null:
		pending.store_string("pending")
		pending.close()
	check(not bool(SoloTownReturnService.close_for_town(SAVE,EXP,"player",MANIFEST).get("ok",false)),"pending_combat_blocks_return")
	remove_file(MANIFEST)
	check(not bool(SoloTownReturnService.load_returned_owner(SAVE,EXP,"player",MANIFEST).get("ok",false)),"active_world_cannot_pretend_exited")
	var closed: Dictionary = SoloTownReturnService.close_for_town(SAVE,EXP,"player",MANIFEST)
	check(bool(closed.get("ok",false)) and not bool(closed.get("already_closed",true)),"exit_committed")
	if not bool(closed.get("ok",false)):
		print("TOWN_RETURN_REASON=",closed.get("reason",""),":",closed.get("detail",""))
		quit(1)
		return
	check(bool(SoloTownReturnService.close_for_town(SAVE,EXP,"player",MANIFEST).get("already_closed",false)),"repeat_exit_idempotent")
	var returned: Dictionary = SoloTownReturnService.load_returned_owner(SAVE,EXP,"player",MANIFEST)
	check(bool(returned.get("ok",false)),"city_owner_reloaded")
	if bool(returned.get("ok",false)):
		var city_character: CharacterState = returned["character"]
		var city_repo: ItemRepository = returned["repository"]
		check(city_character.inventory.owns("TOWN_BLADE") and city_character.inventory.owns("QUEST_REWARD"),"owned_items_returned")
		check(not city_character.inventory.owns("BANDIT_LOOT") and not city_repo.has_item("BANDIT_LOOT"),"unclaimed_ground_not_imported")
		check(city_repo.size()==2,"only_two_owned_items")
		check(repo.size()==1 and town.inventory.size()==1,"legacy_town_never_mutated")
	var persisted: Dictionary = ExpeditionSaveService.read(SAVE,EXP,"player")
	check(bool(persisted.get("ok",false)),"closed_expedition_readable")
	if bool(persisted.get("ok",false)):
		check(persisted["expedition"].status == ExpeditionState.STATUS_EXITED,"closed_status_durable")
		check(GroundLootService.items_at(persisted["expedition"],Vector2i(2,3),"player").is_empty(),"closed_ground_inaccessible")
	check(not bool(SoloTownReturnService.load_returned_owner(SAVE,EXP,"someone_else",MANIFEST).get("ok",false)),"wrong_player_blocked")
	remove_file(SAVE)
	remove_file(MANIFEST)
	print("TOWN_RETURN_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
