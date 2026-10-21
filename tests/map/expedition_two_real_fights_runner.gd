extends SceneTree

## Two REAL checkpointed battles, two receipts, two atomic world commits,
## one expedition save, one manual ground pickup, two full process reloads.
const SAVE := "user://test_real_two_fights_expedition.json"
const EXP_ID := "TWO_REAL_FIGHTS"
const CELL := Vector2i(5,5)
var failures: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		failures.append(name)
		print("TWO_REAL_FIGHTS_CASE=FAIL ",name)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("TWO_REAL_FIGHTS_TEST=" + ("PASS" if failures.is_empty() else "FAIL") + " failures=" + str(failures))
	quit(0 if failures.is_empty() else 1)

func make_world(n: int, repo: ItemRepository) -> Dictionary:
	var catalog := NpcRepository.new()
	catalog.load_definitions(TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json"))
	var map := TacticalMapState.new(12,12)
	var bridge := MapNpcBridge.new()
	if not map.place_entity("PLAYER",Vector2i(4,5)):
		return {}
	var id := "TWO_FIGHT_NPC_%02d" % n
	var item := "TWO_FIGHT_LOOT_%02d" % n
	var npc := NpcInstance.new(id,catalog.get_npc("NPC003"))
	if not bridge.register_npc(map,npc,CELL):
		return {}
	if not repo.add_item({"instance_id":item,"quality":"common","weight":1.0,"durability":{"current":10+n,"max":20}}):
		return {}
	if not npc.receive_item(item,repo):
		return {}
	return {"map":map,"bridge":bridge,"catalog":catalog,"item":item}

func fight(n: int, expedition: ExpeditionState, player: CharacterState, repo: ItemRepository, base_sha: String) -> bool:
	var key := "solo:two:fight_%02d" % n
	var checkpoint := "user://test_two_fights_checkpoint_%02d.json" % n
	var receipt := "user://test_two_fights_receipt_%02d.json" % n
	var snapshot := "user://test_two_fights_world_%02d.json" % n
	GroupCombatCheckpointService.clear(checkpoint)
	wipe(receipt)
	wipe(snapshot)
	var level := make_world(n,repo)
	check(not level.is_empty(),"world_"+str(n))
	if level.is_empty():
		return false
	var turns := HexMapTurnService.new()
	var encounter: Dictionary = turns.move_player(level["map"],level["bridge"],"PLAYER",CELL,RandomNumberGenerator.new())
	check(bool(encounter.get("ok",false)) and encounter.has("encounter"),"contact_"+str(n))
	if not encounter.has("encounter"):
		return false
	var stats := player.resource_snapshot(repo)
	var hero := TestFixtureLoader.new_combatant(player.character_id,"Map Hero",player.level,int(stats["max_hp"]),int(stats["max_mana"]))
	TestFixtureLoader.set_weapon_profiles(hero,[{"damage_min":10000.0,"damage_max":10000.0,"damage_type":"slashing"}])
	hero.combat_stats["hit_chance_rating_percent"]=100.0
	hero.combat_stats["dodge_rating_percent"]=100.0
	var opened: Dictionary = turns.begin_resumable_group_combat(encounter["encounter"],level["catalog"],hero,key,checkpoint)
	check(bool(opened.get("ok",false)),"open_"+str(n))
	if not bool(opened.get("ok",false)):
		return false
	var sim: GroupCombatSimulator = opened["simulator"]
	var verdict: Dictionary = sim.run()
	check(String(verdict.get("winning_team",""))=="players","win_"+str(n))
	if String(verdict.get("winning_team",""))!="players":
		return false
	var completed: Dictionary = turns.finalize_group_victory_atomic(opened,key,expedition,level["map"],level["bridge"],player,repo,NpcPossessionLootService.new(1),{"common":100.0},receipt,checkpoint,snapshot,1000+n,true)
	check(bool(completed.get("ok",false)),"atomic_finish_"+str(n))
	if not bool(completed.get("ok",false)):
		print("TWO_FIGHTS_ATOMIC_REASON=",completed.get("reason",""),":",completed.get("detail",""))
		return false
	check(not FileAccess.file_exists(receipt) and not FileAccess.file_exists(checkpoint),"journal_ack_"+str(n))
	var published: Dictionary = ExpeditionSaveService.publish_verified_combat(SAVE,snapshot,key,EXP_ID,player.character_id,base_sha)
	check(bool(published.get("ok",false)),"publish_"+str(n))
	if not bool(published.get("ok",false)):
		print("TWO_FIGHTS_PUBLISH_REASON=",published.get("reason",""),":",published.get("detail",""))
		return false
	check(not bool(ExpeditionSaveService.publish_verified_combat(SAVE,snapshot,key,EXP_ID,player.character_id,base_sha).get("ok",false)),"double_publish_blocked_"+str(n))
	wipe(snapshot)
	return true

func _run() -> void:
	wipe(SAVE)
	var expedition := ExpeditionState.new(EXP_ID)
	var player := CharacterState.new("PLAYER","Expedition Hero",20)
	var repo := ItemRepository.new()
	expedition.player_position=Vector2i(4,5)
	check(bool(ExpeditionSaveService.save(SAVE,expedition,player,repo).get("ok",false)),"before_any_battle")
	var base: Dictionary = ExpeditionSaveService._read_payload_envelope(SAVE)
	check(bool(base.get("ok",false)),"base_revision_created")
	if not bool(base.get("ok",false)):
		return
	if not fight(1,expedition,player,repo,String(base["sha256"])):
		return
	var first: Dictionary = ExpeditionSaveService.read(SAVE,EXP_ID,"PLAYER")
	check(bool(first.get("ok",false)),"reload_after_first_fight")
	if not bool(first.get("ok",false)):
		return
	var exp1: ExpeditionState = first["expedition"]
	var hero1: CharacterState = first["character"]
	var items1: ItemRepository = first["repository"]
	check(GroundLootService.items_at(exp1,CELL,"PLAYER").size()==1,"first_battle_ground_item")
	# Manual 5-second pickup, persisted to the same expedition snapshot.
	var map := TacticalMapState.new(12,12)
	check(map.place_entity("PLAYER",CELL),"post_fight_player_at_loot")
	var pickup := GroundLootService.new()
	var started: Dictionary = pickup.begin_pickup(exp1,map,hero1,items1,"TWO_FIGHT_LOOT_01",2000)
	check(bool(started.get("ok",false)),"start_real_pickup")
	if not bool(started.get("ok",false)):
		return
	var claimed: Dictionary = pickup.finish_pickup(String(started["ticket"]),exp1,map,hero1,items1,2005,10,100.0)
	check(bool(claimed.get("ok",false)),"complete_real_pickup")
	if not bool(claimed.get("ok",false)):
		return
	check(bool(ExpeditionSaveService.save(SAVE,exp1,hero1,items1).get("ok",false)),"save_manual_pickup")
	var revised: Dictionary = ExpeditionSaveService._read_payload_envelope(SAVE)
	check(bool(revised.get("ok",false)),"revision_before_second_fight")
	if not bool(revised.get("ok",false)):
		return
	if not fight(2,exp1,hero1,items1,String(revised["sha256"])):
		return
	var final: Dictionary = ExpeditionSaveService.read(SAVE,EXP_ID,"PLAYER")
	check(bool(final.get("ok",false)),"reload_after_second_fight")
	if not bool(final.get("ok",false)):
		return
	var world: ExpeditionState = final["expedition"]
	var hero: CharacterState = final["character"]
	var items: ItemRepository = final["repository"]
	check(Dictionary(world.world_state.get(MapWorldCommitService.TOMBSTONES_KEY,{})).size()==2,"two_real_tombstones")
	check(Dictionary(world.world_state.get(MapCombatSettlementService.MARKER_KEY,{})).size()==2,"two_real_receipt_hashes")
	check(hero.inventory.owns("TWO_FIGHT_LOOT_01"),"first_claim_remains_after_second_fight")
	check(GroundLootService.items_at(world,CELL,"PLAYER").size()==1,"only_second_reward_on_ground")
	check(String(GroundLootService.items_at(world,CELL,"PLAYER")[0].get("instance_id",""))=="TWO_FIGHT_LOOT_02","second_unique_reward_preserved")
	check(items.size()==2,"no_reward_instances_duplicated")
	check(int(items.get_item("TWO_FIGHT_LOOT_01").get("durability",{}).get("current",-1))==11,"first_item_condition_preserved")
	check(int(items.get_item("TWO_FIGHT_LOOT_02").get("durability",{}).get("current",-1))==12,"second_item_condition_preserved")
	wipe(SAVE)
