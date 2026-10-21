extends SceneTree

const EXP := "user://test_live_solo_map_exp.json"
const TOWN := "user://test_live_solo_map_town.json"
const MANIFEST := "user://test_live_solo_map_manifest.json"
const ID := "solo_exp_player"
var failures: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("LIVE_SOLO_MAP_CASE=FAIL ",name)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
	var player := CharacterState.new("player","Explorer",4)
	var items := ItemRepository.new()
	check(items.add_item({"instance_id":"FIRST_SWORD","weight":1.0}),"sword_instance")
	check(player.inventory.add_instance("FIRST_SWORD",items),"sword_owned")
	check(bool(SoloTownSaveService.save(TOWN,player,items).get("ok",false)),"city_before_departure")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,123,Vector2i(5,5),player,items,MANIFEST).get("ok",false)),"expedition_created")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(bool(opened.get("ok",false)),"live_map_open")
	if not bool(opened.get("ok",false)):
		quit(1)
		return
	var first: SoloLiveMapSession = opened["session"]
	check(first.npc_bridge.instances.size()==3,"three_stable_npc_instances")
	check(first.npc_bridge.instances.has("solo_npc_bandit_01"),"stable_bandit_id")
	var adjacent: Vector2i = first.map.neighbors(Vector2i(5,5))[0]
	check(not bool(first.move_one_step(Vector2i(11,11)).get("ok",false)),"non_adjacent_rejected")
	check(bool(first.move_one_step(adjacent).get("ok",false)),"adjacent_step_saved")
	var reopened := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(bool(reopened.get("ok",false)),"reload_live_map")
	if not bool(reopened.get("ok",false)):
		quit(1)
		return
	var next: SoloLiveMapSession = reopened["session"]
	check(next.expedition.player_position == adjacent,"step_survives_reload")
	check(next.character.inventory.owns("FIRST_SWORD"),"item_survives_reload")
	check(next.npc_bridge.instances.size()==3 and next.npc_bridge.instances.has("solo_npc_bandit_01"),"npc_instances_reconstructed_after_restart")
	var enemy_cell := Vector2i(7,5)
	var combat_contact := next.move_one_step(enemy_cell)
	check(not bool(combat_contact.get("ok",false)) and String(combat_contact.get("reason",""))=="combat_ui_not_connected","enemy_contact_is_fail_closed")
	check(next.expedition.player_position==adjacent,"blocked_combat_does_not_move_player")
	var reread := ExpeditionSaveService.read(EXP,ID,"player")
	check(bool(reread.get("ok",false)) and reread["expedition"].player_position==adjacent,"blocked_combat_does_not_change_durable_save")
	var pending := FileAccess.open(MANIFEST,FileAccess.WRITE)
	if pending != null:
		pending.store_string("pending")
		pending.close()
	check(not bool(next.return_to_town(TOWN).get("ok",false)),"pending_combat_blocks_checkout")
	wipe(MANIFEST)
	var returned := next.return_to_town(TOWN)
	check(bool(returned.get("ok",false)),"real_map_checkout")
	if not bool(returned.get("ok",false)):
		print("LIVE_SOLO_MAP_RETURN_REASON=",returned.get("reason",""),":",returned.get("detail",""))
	var town := SoloTownSaveService.read(TOWN,"player")
	check(bool(town.get("ok",false)),"returned_town_loaded")
	if bool(town.get("ok",false)):
		check(town["character"].inventory.owns("FIRST_SWORD") and town["repository"].size()==1,"original_instance_no_duplication")
	var closed := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(not bool(closed.get("ok",false)),"closed_exp_not_reopened")
	var scene := load("res://scenes/main/solo_live_map.tscn") as PackedScene
	check(scene != null,"real_scene_importable")
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
	print("LIVE_SOLO_MAP_TEST="+("PASS" if failures.is_empty() else "FAIL")+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)
