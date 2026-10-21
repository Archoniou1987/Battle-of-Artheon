extends SceneTree

const SAVE := "user://test_town_exp_bridge.json"
const MANIFEST := "user://test_town_exp_manifest.json"
const EXP := "TOWN_EXP_BRIDGE_TEST"
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("TOWN_EXP_BRIDGE_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	wipe(SAVE)
	wipe(MANIFEST)
	var town := CharacterState.new("player","Герой",5)
	var repo := ItemRepository.new()
	check(repo.add_item({"instance_id":"TOWN_SWORD","weight":1.0}),"town_sword_registered")
	check(town.inventory.add_instance("TOWN_SWORD",repo),"town_sword_owned")
	check(SoloTownExpeditionBridge.expedition_id_for_player(town.character_id)=="solo_exp_player","stable_town_expedition_id")
	var origin_ids := town.inventory.instance_ids().duplicate()
	var first := SoloTownExpeditionBridge.create_from_town(SAVE,EXP,321,Vector2i(3,4),town,repo,MANIFEST)
	check(bool(first.get("ok",false)),"first_seed_success")
	check(town.inventory.instance_ids()==origin_ids and repo.size()==1,"town_source_unchanged")
	check(not bool(SoloTownExpeditionBridge.create_from_town(SAVE,EXP,321,Vector2i(3,4),town,repo,MANIFEST).get("ok",false)),"second_seed_rejected")
	var opened := SoloTownExpeditionBridge.open_existing(SAVE,EXP,town.character_id,MANIFEST)
	check(bool(opened.get("ok",false)),"existing_opened")
	if not bool(opened.get("ok",false)):
		print("TOWN_BRIDGE_OPEN_REASON=",opened.get("reason",""))
		quit(1)
		return
	var expedition: ExpeditionState = opened["expedition"]
	var player: CharacterState = opened["character"]
	var inventory: ItemRepository = opened["repository"]
	check(expedition.seed_value==321 and expedition.player_position==Vector2i(3,4),"map_seed_and_player_hex")
	check(player.inventory.owns("TOWN_SWORD") and inventory.size()==1,"original_item_preserved")
	check(SoloTownExpeditionBridge.town_matches_origin(expedition,town,repo),"town_origin_matches_before_changes")
	# A new expedition item belongs to the expedition. Reentering from
	# stale town data must NOT recreate, discard or overwrite it.
	check(inventory.add_item({"instance_id":"EXPEDITION_GEM","weight":0.2}),"expedition_gem_added")
	check(player.inventory.add_instance("EXPEDITION_GEM",inventory),"expedition_gem_owned")
	check(bool(ExpeditionSaveService.save(SAVE,expedition,player,inventory).get("ok",false)),"expedition_progress_saved")
	check(not bool(SoloTownExpeditionBridge.create_from_town(SAVE,EXP,321,Vector2i(3,4),town,repo,MANIFEST).get("ok",false)),"stale_town_cannot_reseed")
	var again := SoloTownExpeditionBridge.open_existing(SAVE,EXP,town.character_id,MANIFEST)
	check(bool(again.get("ok",false)),"expedition_reopened")
	if bool(again.get("ok",false)):
		check(again["character"].inventory.owns("TOWN_SWORD") and again["character"].inventory.owns("EXPEDITION_GEM"),"both_items_after_reload")
		check(again["repository"].size()==2,"no_repository_duplicate")
	check(not bool(SoloTownExpeditionBridge.open_existing(SAVE,EXP,"someone_else",MANIFEST).get("ok",false)),"wrong_owner_denied")
	check(repo.size()==1 and town.inventory.size()==1,"city_inventory_never_mutated")
	# An active manifest blocks seeding (even when expedition save is
	# deleted). The bridge never erases a pending combat to start fresh.
	wipe(SAVE)
	var f := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if f != null:
		f.store_string("pending")
		f.close()
	check(not bool(SoloTownExpeditionBridge.create_from_town(SAVE,EXP,321,Vector2i(3,4),town,repo,MANIFEST).get("ok",false)),"pending_combat_blocks_reseed")
	wipe(MANIFEST)
	wipe(SAVE)
	print("TOWN_EXP_BRIDGE_TEST="+("PASS" if failures.is_empty() else "FAIL")+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
