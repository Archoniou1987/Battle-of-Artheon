extends SceneTree

const PATH := "user://test_canonical_town_migration_v1.json"
var failures: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("CANONICAL_TOWN_CASE=FAIL ",name)

func _initialize() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var legacy_owner := CharacterState.new("player","Герой",7)
	var legacy_items := ItemRepository.new()
	check(legacy_items.add_item({"instance_id":"MIGRATED_ITEM","weight":1.0}),"old_item_register")
	check(legacy_owner.inventory.add_instance("MIGRATED_ITEM",legacy_items),"old_item_owned")
	var initial := SoloTownSaveService.save(PATH,legacy_owner,legacy_items)
	check(bool(initial.get("ok",false)),"one_time_canonical_initialization")
	if not bool(initial.get("ok",false)):
		quit(1)
		return
	var canonical := SoloTownSaveService.read(PATH,"player")
	check(bool(canonical.get("ok",false)),"canonical_restores")
	if not bool(canonical.get("ok",false)):
		quit(1)
		return
	var owner: CharacterState = canonical["character"]
	var repository: ItemRepository = canonical["repository"]
	check(owner.progression.level==7 and owner.inventory.owns("MIGRATED_ITEM"),"legacy_progress_and_items_preserved")
	check(repository.add_item({"instance_id":"NEW_TOWN_ITEM","weight":0.2}),"new_item_register")
	check(owner.inventory.add_instance("NEW_TOWN_ITEM",repository),"new_item_owned")
	var updated := SoloTownSaveService.save(PATH,owner,repository,String(canonical["sha256"]))
	check(bool(updated.get("ok",false)),"canonical_revision_update")
	var stale := SoloTownSaveService.save(PATH,legacy_owner,legacy_items,String(canonical["sha256"]))
	check(not bool(stale.get("ok",false)),"old_legacy_owner_cannot_resurrect_inventory")
	var after := SoloTownSaveService.read(PATH,"player")
	check(bool(after.get("ok",false)),"restart_uses_canonical")
	if bool(after.get("ok",false)):
		check(after["character"].inventory.owns("NEW_TOWN_ITEM"),"new_item_survives_reopen")
		check(after["repository"].size()==2,"exact_item_count_after_restart")
	check(not bool(SoloTownSaveService.save(PATH,legacy_owner,legacy_items).get("ok",false)),"unversioned_second_import_forbidden")
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("CANONICAL_TOWN_MIGRATION_TEST="+("PASS" if failures.is_empty() else "FAIL")+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
