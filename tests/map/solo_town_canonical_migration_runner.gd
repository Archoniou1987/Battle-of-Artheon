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
	# Browser legacy migration: reject orphan repository entries from the
	# canonical snapshot without modifying the old repository itself.
	check(legacy_items.add_item({"instance_id":"ORPHAN_DEMO_ITEM","weight":0.2}),"legacy_orphan_fixture_registered")
	var filtered := SoloTownSaveService.prepare_legacy_inventory_migration(legacy_owner,legacy_items)
	check(bool(filtered.get("ok",false)),"legacy_owned_projection_ready")
	check(int(filtered.get("orphan_count",-1))==1,"legacy_orphan_count_detected")
	check(legacy_items.has_item("ORPHAN_DEMO_ITEM"),"original_legacy_repository_preserved")
	if not bool(filtered.get("ok",false)):
		quit(1)
		return
	var prepared_repo: ItemRepository = filtered["repository"]
	check(prepared_repo.has_item("MIGRATED_ITEM") and not prepared_repo.has_item("ORPHAN_DEMO_ITEM"),"canonical_projection_contains_only_owned_items")
	var initial := SoloTownSaveService.save(PATH,legacy_owner,prepared_repo)
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
	owner.in_combat = true
	check(not bool(SoloTownSaveService.save(PATH,owner,repository,String(canonical["sha256"])).get("ok",false)),"world_combat_write_stays_blocked")
	var arena_saved := SoloTownSaveService.save(PATH,owner,repository,String(canonical["sha256"]),true)
	check(bool(arena_saved.get("ok",false)),"arena_can_persist_resources_during_training")
	owner.in_combat = false
	var arena_revision: String = String(arena_saved.get("sha256",""))
	var updated := SoloTownSaveService.save(PATH,owner,repository,arena_revision)
	check(bool(updated.get("ok",false)),"canonical_revision_update")
	var stale := SoloTownSaveService.save(PATH,legacy_owner,legacy_items,String(canonical["sha256"]))
	check(not bool(stale.get("ok",false)),"old_legacy_owner_cannot_resurrect_inventory")
	var after := SoloTownSaveService.read(PATH,"player")
	check(bool(after.get("ok",false)),"restart_uses_canonical")
	if bool(after.get("ok",false)):
		check(after["character"].inventory.owns("NEW_TOWN_ITEM"),"new_item_survives_reopen")
		check(after["repository"].size()==2,"exact_item_count_after_restart")
	check(not bool(SoloTownSaveService.save(PATH,legacy_owner,legacy_items).get("ok",false)),"unversioned_second_import_forbidden")
	# Regression: ITEM v1.2 uses slot_usage=[] for a 1H weapon.
	# Equipping interprets it as the selected slot; saving/loading must agree.
	var one_h_owner := CharacterState.new("one_h_save_owner","1H persistence",20)
	var one_h_repo := ItemRepository.new()
	var one_h_item := {
		"instance_id":"V12_EMPTY_USAGE_1H",
		"name":"One handed fixture",
		"type":"weapon","item_type":"weapon",
		"equip_slots":["main_hand"],"slot_usage":[],
		"requirements":{},"par_stats":{},"par_bonuses":{}
	}
	ItemDurabilityService.initialize_item(one_h_item,100)
	check(one_h_repo.add_item(one_h_item),"v12_one_h_item_registered")
	check(one_h_owner.receive_item("V12_EMPTY_USAGE_1H",one_h_repo),"v12_one_h_item_owned")
	check(one_h_owner.equip("main_hand","V12_EMPTY_USAGE_1H",one_h_repo),"v12_one_h_equipped")
	var one_h_saved := MapWorldCommitService._character_to_dict(one_h_owner)
	var one_h_loaded := MapWorldCommitService._restore_character(one_h_saved,one_h_repo)
	check(bool(one_h_loaded.get("ok",false)),"v12_one_h_empty_slot_usage_restores")
	if bool(one_h_loaded.get("ok",false)):
		var one_h_restored: CharacterState = one_h_loaded["character"]
		check(one_h_restored.equipment.get_equipped_instance_id("main_hand")=="V12_EMPTY_USAGE_1H","v12_one_h_item_preserved_in_slot")
		check(one_h_restored.inventory.owns("V12_EMPTY_USAGE_1H"),"v12_one_h_item_still_owned")
	var one_h_path := PATH + ".v12_empty_usage"
	var one_h_written := SoloTownSaveService.save(one_h_path,one_h_owner,one_h_repo)
	check(bool(one_h_written.get("ok",false)),"v12_one_h_empty_usage_town_save")
	var one_h_read := SoloTownSaveService.read(one_h_path,"one_h_save_owner")
	check(bool(one_h_read.get("ok",false)),"v12_one_h_empty_usage_town_read")
	# Negative control: never accept a partially occupied genuine 2H weapon.
	var two_h_repo := ItemRepository.new()
	var two_h_item := one_h_item.duplicate(true)
	two_h_item["instance_id"]="V12_REQUIRED_TWO_SLOTS"
	two_h_item["slot_usage"]=["main_hand","off_hand"]
	check(two_h_repo.add_item(two_h_item),"two_h_fixture_registered")
	var two_h_owner := CharacterState.new("two_h_invalid_owner","2H validation",20)
	check(two_h_owner.receive_item("V12_REQUIRED_TWO_SLOTS",two_h_repo),"two_h_fixture_owned")
	var two_h_saved := MapWorldCommitService._character_to_dict(two_h_owner)
	var partial_slots: Dictionary = two_h_saved["equipment"]
	partial_slots["main_hand"]="V12_REQUIRED_TWO_SLOTS"
	var rejected := MapWorldCommitService._restore_character(two_h_saved,two_h_repo)
	check(not bool(rejected.get("ok",false)) and String(rejected.get("reason",""))=="world_equipment_occupancy_mismatch","partial_two_h_still_rejected")
	check(String(rejected.get("detail","")).contains("V12_REQUIRED_TWO_SLOTS") and String(rejected.get("detail","")).contains("occupied=") and String(rejected.get("detail","")).contains("usage="),"bad_legacy_equipment_has_read_only_diagnostics")
	if FileAccess.file_exists(one_h_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(one_h_path))
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("CANONICAL_TOWN_MIGRATION_TEST="+("PASS" if failures.is_empty() else "FAIL")+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
