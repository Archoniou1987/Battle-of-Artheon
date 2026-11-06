extends SceneTree

## Real Solo fight: spent elixir + terminal victory must publish exactly
## one charge debit and one settlement. Restart must not re-award loot.
const EXP := "user://test_live_elixir_victory_crash_exp.json"
const TOWN := "user://test_live_elixir_victory_crash_town.json"
const MANIFEST := "user://test_live_elixir_victory_crash_manifest.json"
const ID := "solo_exp_elixir_victory_crash"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
const ELIXIR := "elixir_test_hp_v1"
var errors: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		print("LIVE_ELIXIR_VICTORY_CRASH_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func orders(sim: GroupCombatSimulator,slot: int) -> Dictionary:
	var controls := sim.player_controls(PLAYER)
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	if not bool(controls.get("stunned",false)):
		for i in range(int(controls.get("attack_count",0))):
			attacks.append("chest")
		for zone in CombatCommandApi.BODY_ZONES:
			if blocks.size() < int(controls.get("block_capacity",0)):
				blocks.append(zone)
	return {"player_id":PLAYER,"attack_zones":attacks,"block_zones":blocks,"ability_id":"","elixir_slot":slot}

func _initialize() -> void:
	_run()
	print("LIVE_ELIXIR_VICTORY_CRASH_TEST=", "PASS" if errors.is_empty() else "FAIL"," errors=",errors)
	quit(0 if errors.is_empty() else 1)

func _run() -> void:
	var paths := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Victory Elixir Hero",100)
	var repo := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repo),"elixir_fixture_seeded")
	check(hero.equip("waist","elixir_test_belt_v1",repo),"belt_equipped")
	check(hero.assign_elixir(0,ELIXIR,repo),"potion_assigned")
	var original := int(repo.get_item(ELIXIR).get("charges",-1))
	var hp_pool := int(hero.resource_snapshot(repo).get("max_hp",0))
	check(hp_pool > 50,"real_hp_pool")
	hero.current_hp = maxi(1,hp_pool-35)
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,996,START,hero,repo,MANIFEST).get("ok",false)),"expedition_created")
	var mounted := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(mounted.get("ok",false)),"map_open")
	if not bool(mounted.get("ok",false)):
		return
	var started := SoloLiveNpcCombat.start(mounted["session"],TARGET)
	check(bool(started.get("ok",false)),"real_bandit_encounter")
	if not bool(started.get("ok",false)):
		print("LIVE_ELIXIR_VICTORY_CRASH_START=",started.get("reason","unknown"))
		return
	var combat: SoloLiveNpcCombat = started["combat"]
	var sim: GroupCombatSimulator = combat.battle["simulator"]
	var base_revision := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var first := sim.run_round(orders(sim,0))
	check(bool(first.get("ok",false)) and bool(first.get("checkpoint_ok",false)),"potion_first_round_checkpoint")
	if not bool(first.get("ok",false)) or not bool(first.get("checkpoint_ok",false)):
		return
	check(int(combat.owner.repository.get_item(ELIXIR).get("charges",-1))==original-1,"charge_spent_once")
	for i in range(100):
		if sim.controller.combat_finished():
			break
		var round_result := sim.run_round(orders(sim,-1))
		if not bool(round_result.get("ok",false)) or not bool(round_result.get("checkpoint_ok",false)):
			check(false,"victory_round_checkpoint_failed")
			return
	check(sim.controller.combat_finished() and sim.controller.winning_team()=="players","real_victory_checkpointed")
	if not sim.controller.combat_finished() or sim.controller.winning_team()!="players":
		return
	var audit := SoloCombatElixirJournal.inspect(sim.state,combat.owner.character,combat.owner.repository)
	check(bool(audit.get("ok",false)) and int(Dictionary(audit.get("counts",{})).get(ELIXIR,0))==1,"one_elixir_use_in_terminal_checkpoint")
	var stage := combat.turns.finalize_group_victory_atomic(combat.battle,combat.encounter_key,combat.owner.expedition,combat.owner.map,combat.owner.npc_bridge,combat.owner.character,combat.owner.repository,NpcPossessionLootService.new(1),{"common":100.0},combat.receipt_path,combat.checkpoint_path,combat.terminal_path,int(Time.get_unix_time_from_system()),true)
	check(bool(stage.get("ok",false)) and FileAccess.file_exists(combat.terminal_path),"victory_snapshot_staged_before_crash")
	if not bool(stage.get("ok",false)):
		print("LIVE_ELIXIR_VICTORY_CRASH_STAGE=",stage.get("reason","unknown"),":",stage.get("detail",""))
		return
	var old_world := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(old_world.get("ok",false)),"original_world_unpublished")
	if bool(old_world.get("ok",false)):
		check(int(old_world["repository"].get_item(ELIXIR).get("charges",-1))==original,"stage_does_not_debit_base")
	check(FileAccess.file_exists(MANIFEST),"pending_manifest_still_exists")
	var launch := SoloExpeditionLaunchGate.inspect(EXP,MANIFEST,ID,PLAYER)
	check(bool(launch.get("ok",false)) and String(launch.get("state",""))=="ready_after_recovery","restart_publishes_staged_victory")
	if not bool(launch.get("ok",false)):
		print("LIVE_ELIXIR_VICTORY_CRASH_RECOVER=",launch.get("reason","unknown"),":",launch.get("detail",""))
		return
	check(not FileAccess.file_exists(MANIFEST),"manifest_cleared_after_victory")
	var saved := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(saved.get("ok",false)),"published_expedition_readable")
	if not bool(saved.get("ok",false)):
		return
	check(int(saved["repository"].get_item(ELIXIR).get("charges",-1))==original-1,"victory_keeps_exact_charge_debit")
	var expedition: ExpeditionState = saved["expedition"]
	var settlement: Dictionary = expedition.world_state.get(MapCombatSettlementService.MARKER_KEY,{})
	check(settlement.has(combat.encounter_key),"victory_settlement_recorded")
	var tombstones: Dictionary = expedition.world_state.get(MapWorldCommitService.TOMBSTONES_KEY,{})
	check(tombstones.has(combat.encounter_key),"npc_death_tombstone_recorded")
	check(not expedition.world_state.get(SoloCombatDefeatService.LEDGER_KEY,{}).has(combat.encounter_key),"victory_never_staged_as_defeat")
	var loot_before: Array = GroundLootService.items_at(expedition,TARGET,PLAYER)
	var settled_hash := String(settlement.get(combat.encounter_key,""))
	var world_hash := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var reopened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(reopened.get("ok",false)),"victory_world_reopened")
	if bool(reopened.get("ok",false)):
		var again: SoloLiveMapSession = reopened["session"]
		check(int(again.repository.get_item(ELIXIR).get("charges",-1))==original-1,"restart_never_refunds_potion")
		check(String(again.expedition.world_state.get(MapCombatSettlementService.MARKER_KEY,{}).get(combat.encounter_key,""))==settled_hash,"settlement_marker_not_replaced")
		check(GroundLootService.items_at(again.expedition,TARGET,PLAYER).size()==loot_before.size(),"restart_does_not_duplicate_ground_loot")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==world_hash,"restart_does_not_republish_world")
	check(not base_revision.is_empty() and base_revision != world_hash,"victory_advances_world_revision_once")
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
