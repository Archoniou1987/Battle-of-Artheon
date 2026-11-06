extends SceneTree

const PATH := "user://test_multi_encounter_solo_save.json"
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("EXPEDITION_SAVE_CASE=FAIL ",label)

func _initialize() -> void:
	_run()
	print("EXPEDITION_SAVE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var expedition := ExpeditionState.new("EXPEDITION_MULTIFIGHT")
	var player := CharacterState.new("PLAYER","Expedition Hero",5)
	var repo := ItemRepository.new()
	expedition.player_position = Vector2i(2,3)
	check(bool(ExpeditionSaveService.save(PATH,expedition,player,repo).get("ok",false)),"save_before_first_battle")
	var recovered := ExpeditionSaveService.read(PATH,"EXPEDITION_MULTIFIGHT","PLAYER")
	check(bool(recovered.get("ok",false)),"restore_before_first_battle")
	if not bool(recovered.get("ok",false)):
		return
	var current: ExpeditionState = recovered["expedition"]
	var owner: CharacterState = recovered["character"]
	var items: ItemRepository = recovered["repository"]
	check(current.player_position == Vector2i(2,3),"restore_position")
	check(current.world_state.is_empty(),"no_fabricated_combat_receipt")
	check(items.add_item({"instance_id":"SWORD_A","weight":2.0}),"item_a_created")
	check(bool(GroundLootService.place_unowned(current,items,"SWORD_A",Vector2i(4,3),"encounter_a","PLAYER").get("ok",false)),"ground_a")
	var receipt_a := "a".repeat(64)
	current.world_state[MapCombatSettlementService.MARKER_KEY]={"battle_a":receipt_a}
	current.world_state[MapWorldCommitService.TOMBSTONES_KEY]={"battle_a":{"receipt_sha256":receipt_a,"npc_ids":["NPC_A"],"npc_positions":{"NPC_A":[4,3]}}}
	current.player_position=Vector2i(4,3)
	check(bool(ExpeditionSaveService.save(PATH,current,owner,items).get("ok",false)),"save_after_battle_a")
	var next := ExpeditionSaveService.read(PATH,"EXPEDITION_MULTIFIGHT","PLAYER")
	check(bool(next.get("ok",false)),"restore_after_battle_a")
	if not bool(next.get("ok",false)):
		return
	var more: ExpeditionState = next["expedition"]
	var hero: CharacterState = next["character"]
	var repository: ItemRepository = next["repository"]
	check(repository.add_item({"instance_id":"SWORD_B","weight":2.0}),"item_b_created")
	check(bool(GroundLootService.place_unowned(more,repository,"SWORD_B",Vector2i(5,3),"encounter_b","PLAYER").get("ok",false)),"ground_b")
	var receipt_b := "b".repeat(64)
	var ledgers: Dictionary = more.world_state[MapCombatSettlementService.MARKER_KEY]
	ledgers["battle_b"]=receipt_b
	more.world_state[MapCombatSettlementService.MARKER_KEY]=ledgers
	var tombstones: Dictionary = more.world_state[MapWorldCommitService.TOMBSTONES_KEY]
	tombstones["battle_b"]={"receipt_sha256":receipt_b,"npc_ids":["NPC_B"],"npc_positions":{"NPC_B":[5,3]}}
	more.world_state[MapWorldCommitService.TOMBSTONES_KEY]=tombstones
	more.player_position=Vector2i(5,3)
	check(bool(ExpeditionSaveService.save(PATH,more,hero,repository).get("ok",false)),"save_after_battle_b")
	var final_save := ExpeditionSaveService.read(PATH,"EXPEDITION_MULTIFIGHT","PLAYER")
	check(bool(final_save.get("ok",false)),"restore_after_two_battles")
	if not bool(final_save.get("ok",false)):
		return
	var final_exp: ExpeditionState = final_save["expedition"]
	check(Dictionary(final_exp.world_state[MapWorldCommitService.TOMBSTONES_KEY]).size()==2,"two_defeated_cohorts")
	check(GroundLootService.items_at(final_exp,Vector2i(4,3),"PLAYER").size()==1,"earlier_ground_loot_persists")
	check(GroundLootService.items_at(final_exp,Vector2i(5,3),"PLAYER").size()==1,"later_ground_loot_persists")
	var corrupted: ExpeditionState = ExpeditionState.from_dict(final_exp.to_dict())
	corrupted.world_state[MapCombatSettlementService.MARKER_KEY].erase("battle_a")
	var rejected := ExpeditionSaveService.save(PATH,corrupted,final_save["character"],final_save["repository"])
	check(not bool(rejected.get("ok",false)),"deny_removal_of_old_combat_marker")
	check(bool(ExpeditionSaveService.read(PATH,"EXPEDITION_MULTIFIGHT","PLAYER").get("ok",false)),"rejected_save_keeps_previous_snapshot")
	var closed := ExpeditionState.from_dict(final_exp.to_dict())
	closed.status=ExpeditionState.STATUS_EXITED
	check(bool(ExpeditionSaveService.save(PATH,closed,final_save["character"],final_save["repository"]).get("ok",false)),"save_explicit_expedition_exit")
	check(not bool(ExpeditionSaveService.save(PATH,closed,final_save["character"],final_save["repository"]).get("ok",false)),"closed_expedition_cannot_be_overwritten")
	var wrong_owner := ExpeditionSaveService.read(PATH,"EXPEDITION_MULTIFIGHT","SOMEONE_ELSE")
	check(not bool(wrong_owner.get("ok",false)),"wrong_owner_rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
