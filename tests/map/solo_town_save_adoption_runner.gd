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
	for path in [EXPEDITION,TOWN,MANIFEST]:
		wipe(path)
	print("TOWN_ADOPT_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
