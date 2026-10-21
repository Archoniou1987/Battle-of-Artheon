extends SceneTree

## Real map -> checkpointed fight -> receipt -> ground migration -> one
## authoritative world bundle -> restart -> manual 5-second pickup.
const FIGHT := "user://test_solo_ground_fight.json"
const RECEIPT := "user://test_solo_ground_receipt.json"
const WORLD := "user://test_solo_ground_world.json"
const ENCOUNTER := "solo:ground:bandits"
const EXPEDITION := "SOLO_GROUND_E2E"
const CELL := Vector2i(5,5)
var errors: Array[String] = []

func check(ok: bool,label: String) -> void:
	if not ok:
		errors.append(label)
		print("SOLO_GROUND_COMBAT_CASE=FAIL ",label)

func clear_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	test_chain()
	print("SOLO_GROUND_COMBAT_TEST=", "PASS" if errors.is_empty() else "FAIL", " errors=",errors)
	quit(0 if errors.is_empty() else 1)

func world() -> Dictionary:
	var catalog := NpcRepository.new()
	catalog.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map := TacticalMapState.new(12,12)
	var bridge := MapNpcBridge.new()
	var repo := ItemRepository.new()
	if not map.place_entity("PLAYER",Vector2i(4,5)):
		return {}
	for i in range(2):
		var id := "GROUND_BANDIT_%02d" % (i+1)
		var item_id := "GROUND_SWORD_%02d" % (i+1)
		var npc := NpcInstance.new(id,catalog.get_npc("NPC003"))
		if not bridge.register_npc(map,npc,CELL):
			return {}
		if not repo.add_item({"instance_id":item_id,"quality":"common","weight":1.5,"durability":{"current":11,"max":20}}):
			return {}
		if not npc.receive_item(item_id,repo):
			return {}
	return {"map":map,"bridge":bridge,"catalog":catalog,"repository":repo}

func test_chain() -> void:
	GroupCombatCheckpointService.clear(FIGHT)
	clear_file(RECEIPT)
	clear_file(WORLD)
	var level := world()
	check(not level.is_empty(),"level_created")
	if level.is_empty():
		return
	var player := CharacterState.new("PLAYER","Hunter",20)
	var expedition := ExpeditionState.new(EXPEDITION)
	var turns := HexMapTurnService.new()
	var contact := turns.move_player(level["map"],level["bridge"],"PLAYER",CELL,RandomNumberGenerator.new())
	check(bool(contact.get("ok",false)) and contact.has("encounter"),"hex_contact")
	if not contact.has("encounter"):
		return
	var stats := player.resource_snapshot(level["repository"])
	var fighter := TestFixtureLoader.new_combatant("PLAYER","Hunter",20,int(stats["max_hp"]),int(stats["max_mana"]))
	TestFixtureLoader.set_weapon_profiles(fighter,[{"damage_min":10000.0,"damage_max":10000.0,"damage_type":"slashing"}])
	fighter.combat_stats["hit_chance_rating_percent"] = 100.0
	fighter.combat_stats["dodge_rating_percent"] = 100.0
	var session := turns.begin_resumable_group_combat(contact["encounter"],level["catalog"],fighter,ENCOUNTER,FIGHT)
	check(bool(session.get("ok",false)),"checkpointed_encounter")
	if not bool(session.get("ok",false)):
		return
	var sim: GroupCombatSimulator = session["simulator"]
	var verdict := sim.run()
	check(String(verdict.get("winning_team","")) == "players","player_wins")
	if String(verdict.get("winning_team","")) != "players":
		return
	var committed := turns.finalize_group_victory_atomic(session,ENCOUNTER,expedition,level["map"],level["bridge"],player,level["repository"],NpcPossessionLootService.new(1),{"common":100.0},RECEIPT,FIGHT,WORLD,1000,true)
	check(bool(committed.get("ok",false)),"ground_atomic_finalize")
	if not bool(committed.get("ok",false)):
		print("SOLO_GROUND_COMBAT_REASON=",committed.get("reason",""),":",committed.get("detail",""))
		return
	check(not turns.coordinator.combat_active,"map_unpaused_only_after_commit")
	check(not FileAccess.file_exists(RECEIPT) and not FileAccess.file_exists(FIGHT),"journals_acknowledged")
	check(expedition.restore_loot_pool(ENCOUNTER) == null,"old_pool_removed")
	check(GroundLootService.items_at(expedition,CELL,"PLAYER").size()==2,"two_objects_visible_on_cell")
	check(GroundLootService.items_at(expedition,Vector2i(4,5),"PLAYER").is_empty(),"no_remote_loot")
	check(player.inventory.size()==0,"not_auto_awarded_to_inventory")
	var checkpoint := MapWorldCommitService.read(WORLD,ENCOUNTER,EXPEDITION,"PLAYER")
	check(bool(checkpoint.get("ok",false)),"ground_saved_in_world_bundle")
	if not bool(checkpoint.get("ok",false)):
		print("SOLO_GROUND_WORLD_READ=",checkpoint.get("reason",""))
		return
	var continued: ExpeditionState = checkpoint["expedition"]
	var carried: CharacterState = checkpoint["character"]
	var repo: ItemRepository = checkpoint["repository"]
	check(GroundLootService.items_at(continued,CELL,"PLAYER").size()==2 and repo.size()==2,"reloaded_two_ground_instances")
	check(GroundLootService.remove_expired(continued,repo,100000)==0,"ground_items_live_until_expedition_closes")
	var regenerated := world()
	var reconciled := MapWorldCommitService.reconcile_map(continued,regenerated["map"],regenerated["bridge"])
	check(bool(reconciled.get("ok",false)) and int(reconciled.get("deaths_applied",-1))==2,"defeated_npcs_do_not_respawn")
	# The reconstructed world starts the player outside the reward cell;
	# manual pickup only becomes available after walking onto that cell.
	var approach := regenerated["map"].move_entity("PLAYER",CELL)
	check(bool(approach.get("ok",false)),"player_walks_to_ground_items")
	if not bool(approach.get("ok",false)):
		return
	var pickup := GroundLootService.new()
	var started := pickup.begin_pickup(continued,regenerated["map"],carried,repo,"GROUND_SWORD_01",100010)
	check(bool(started.get("ok",false)),"first_pickup_started")
	if not bool(started.get("ok",false)):
		print("SOLO_GROUND_START_REASON=",started.get("reason",""))
		return
	var premature := pickup.finish_pickup(String(started["ticket"]),continued,regenerated["map"],carried,repo,100014,10,100.0)
	check(not bool(premature.get("ok",false)),"five_seconds_required")
	var claimed := pickup.finish_pickup(String(started["ticket"]),continued,regenerated["map"],carried,repo,100015,10,100.0)
	check(bool(claimed.get("ok",false)),"first_ground_item_claimed")
	if not bool(claimed.get("ok",false)):
		print("SOLO_GROUND_PICKUP_REASON=",claimed.get("reason",""))
		return
	check(carried.inventory.owns("GROUND_SWORD_01"),"original_instance_in_inventory")
	check(GroundLootService.items_at(continued,CELL,"PLAYER").size()==1,"one_ground_item_remaining")
	var saved := MapWorldCommitService.save_progress(WORLD,ENCOUNTER,continued,carried,repo)
	check(bool(saved.get("ok",false)),"pickup_atomically_saved")
	if not bool(saved.get("ok",false)):
		print("SOLO_GROUND_SAVE_REASON=",saved.get("reason",""),":",saved.get("detail",""))
		return
	var after := MapWorldCommitService.read(WORLD,ENCOUNTER,EXPEDITION,"PLAYER")
	check(bool(after.get("ok",false)),"restarted_after_pickup")
	if bool(after.get("ok",false)):
		check(after["character"].inventory.owns("GROUND_SWORD_01"),"claim_survives_restart")
		check(GroundLootService.items_at(after["expedition"],CELL,"PLAYER").size()==1,"no_item_resurrection")
		check(after["repository"].size()==2,"repository_never_duplicated")
	clear_file(WORLD)
	GroupCombatCheckpointService.clear(FIGHT)
	clear_file(RECEIPT)
