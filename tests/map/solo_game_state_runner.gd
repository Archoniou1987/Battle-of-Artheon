extends SceneTree

## Real-file regression for a single character/world owner. Legacy fixtures
## use isolated paths so the player's production save is never touched.
const GAME := "user://test_unified_game_state.json"
const TOWN := "user://test_unified_legacy_town.json"
const OLD_MAP := "user://test_unified_legacy_map.json"
const MANIFEST := "user://test_unified_pending.json"
const PLAYER := "player"
const ID := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		print("UNIFIED_SAVE_FAIL: ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [GAME,TOWN,OLD_MAP,MANIFEST]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Hero",5)
	var repo := ItemRepository.new()
	check(repo.add_item({"instance_id":"BASE_SWORD","weight":1.0}),"seed_item_record")
	check(hero.inventory.add_instance("BASE_SWORD",repo),"seed_item_owner")
	var created := SoloGameStateService.create(GAME,hero,repo,21)
	check(bool(created.get("ok",false)),"create_one_save")
	if not bool(created.get("ok",false)):
		quit(1)
		return
	check(String(created["location"]) == "town","initial_town")
	check(not FileAccess.file_exists(TOWN) and not FileAccess.file_exists(OLD_MAP),"no_second_save")
	var city_revision := String(created["sha256"])
	var to_map := SoloGameStateService.set_location(GAME,PLAYER,SoloGameStateService.LOCATION_MAP,MANIFEST)
	check(bool(to_map.get("ok",false)),"enter_map")
	var map_loaded := SoloGameStateService.read(GAME,PLAYER)
	check(bool(map_loaded.get("ok",false)) and String(map_loaded.get("location","")) == "map","map_persisted")
	if not bool(map_loaded.get("ok",false)):
		quit(1)
		return
	var world: ExpeditionState = map_loaded["expedition"]
	var combat_hero: CharacterState = map_loaded["character"]
	var items: ItemRepository = map_loaded["repository"]
	world.player_position = Vector2i(8,7)
	world.world_state["test_visited"] = {"8_7":true}
	check(items.add_item({"instance_id":"MAP_LOOT","weight":0.5}),"map_item_created")
	check(combat_hero.inventory.add_instance("MAP_LOOT",items),"map_item_owned")
	check(bool(ExpeditionSaveService.save(GAME,world,combat_hero,items).get("ok",false)),"map_progress_persisted")
	var locked := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if locked != null:
		locked.store_string("unfinished")
		locked.close()
	check(not bool(SoloGameStateService.set_location(GAME,PLAYER,"town",MANIFEST).get("ok",false)),"pending_combat_blocks_return")
	wipe(MANIFEST)
	check(bool(SoloGameStateService.set_location(GAME,PLAYER,"town",MANIFEST).get("ok",false)),"return_without_adoption")
	var home := SoloGameStateService.read(GAME,PLAYER)
	check(bool(home.get("ok",false)) and String(home.get("location","")) == "town","return_location")
	if bool(home.get("ok",false)):
		var saved_hero: CharacterState = home["character"]
		check(saved_hero.inventory.owns("BASE_SWORD") and saved_hero.inventory.owns("MAP_LOOT"),"items_survive_return")
		check(home["expedition"].player_position == Vector2i(8,7),"world_position_survives_return")
		check(bool(Dictionary(home["expedition"].world_state.get("test_visited",{})).get("8_7",false)),"world_progress_survives_return")
		var stored: ItemRepository = home["repository"]
		check(stored.add_item({"instance_id":"CITY_NEW","weight":0.2}),"city_item_generated")
		check(saved_hero.inventory.add_instance("CITY_NEW",stored),"city_item_owned")
		check(not bool(SoloGameStateService.save_town(GAME,saved_hero,stored,city_revision).get("ok",false)),"stale_revision_rejected")
		var town_saved := SoloGameStateService.save_town(GAME,saved_hero,stored,String(home["sha256"]))
		check(bool(town_saved.get("ok",false)),"city_commits_to_same_file")
		var restarted := SoloGameStateService.read(GAME,PLAYER)
		check(bool(restarted.get("ok",false)) and restarted["character"].inventory.owns("CITY_NEW") and restarted["character"].inventory.owns("MAP_LOOT"),"restart_no_character_handoff")
		check(bool(SoloGameStateService.set_location(GAME,PLAYER,"map",MANIFEST).get("ok",false)),"second_map_visit")
		var again := SoloGameStateService.read(GAME,PLAYER)
		check(again["expedition"].player_position == Vector2i(8,7),"second_map_keeps_same_world")
	wipe(GAME)
	# Legacy migration keeps both original files byte-for-byte. When an
	# expedition is active it takes precedence over a divergent old city.
	var old_hero := CharacterState.new(PLAYER,"Hero",5)
	var old_repo := ItemRepository.new()
	check(old_repo.add_item({"instance_id":"OLD_GEAR","weight":1.0}),"legacy_item")
	check(old_hero.inventory.add_instance("OLD_GEAR",old_repo),"legacy_owns")
	check(bool(SoloTownSaveService.save(TOWN,old_hero,old_repo).get("ok",false)),"legacy_town_written")
	var launched := SoloTownExpeditionBridge.create_from_town(OLD_MAP,ID,53,Vector2i(5,5),old_hero,old_repo,MANIFEST)
	check(bool(launched.get("ok",false)),"legacy_map_written")
	var town_sha := String(SoloTownSaveService.read(TOWN,PLAYER).get("sha256",""))
	check(old_repo.add_item({"instance_id":"CITY_ONLY","weight":0.1}),"diverged_city_item")
	check(old_hero.inventory.add_instance("CITY_ONLY",old_repo),"diverged_city_owner")
	check(bool(SoloTownSaveService.save(TOWN,old_hero,old_repo,town_sha).get("ok",false)),"divergent_city_saved")
	var old_town_bytes := FileAccess.get_file_as_string(TOWN)
	var old_map_bytes := FileAccess.get_file_as_string(OLD_MAP)
	var pending := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if pending != null:
		pending.store_string("legacy fight")
		pending.close()
	var blocked := SoloGameStateService.bootstrap(PLAYER,GAME,TOWN,OLD_MAP,MANIFEST)
	check(not bool(blocked.get("ok",false)) and not FileAccess.file_exists(GAME),"unfinished_legacy_fight_never_discarded")
	wipe(MANIFEST)
	var migrated := SoloGameStateService.bootstrap(PLAYER,GAME,TOWN,OLD_MAP,MANIFEST)
	check(bool(migrated.get("ok",false)) and String(migrated.get("location","")) == "map","active_legacy_map_import")
	check(bool(migrated.get("legacy_town_preserved",false)),"old_city_remains_accessible")
	check(FileAccess.get_file_as_string(TOWN) == old_town_bytes and FileAccess.get_file_as_string(OLD_MAP) == old_map_bytes,"legacy_bytes_unchanged")
	check(migrated["character"].inventory.owns("OLD_GEAR"),"legacy_character_import")
	check(not migrated["character"].inventory.owns("CITY_ONLY"),"no_silent_divergent_item_merge")
	var restarted_migration := SoloGameStateService.bootstrap(PLAYER,GAME,TOWN,OLD_MAP,MANIFEST)
	check(bool(restarted_migration.get("ok",false)) and String(restarted_migration.get("location","")) == "map","migration_idempotent")
	for path in [GAME,TOWN,OLD_MAP,MANIFEST]:
		wipe(path)
	if errors.is_empty():
		print("UNIFIED_GAME_STATE=PASS")
	quit(0 if errors.is_empty() else 1)
