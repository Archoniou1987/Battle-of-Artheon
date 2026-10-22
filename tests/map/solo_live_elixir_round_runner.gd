extends SceneTree

## One real Solo NPC + one equipped belt consumable: the canonical
## CombatEngine resolves it, the group checkpoint journals it, and restart
## reconstructs spent charges from the manifest-pinned base repository.
const EXP := "user://test_live_elixir_exp.json"
const TOWN := "user://test_live_elixir_town.json"
const MANIFEST := "user://test_live_elixir_manifest.json"
const ID := "solo_exp_elixir_live"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
const ELIXIR := "elixir_test_hp_v1"
var failures: Array[String] = []

func check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_ELIXIR_ROUND_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func orders(sim: GroupCombatSimulator,elixir_slot: int) -> Dictionary:
	var controls := sim.player_controls(PLAYER)
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	if not bool(controls.get("stunned",false)):
		for i in range(int(controls.get("attack_count",0))):
			attacks.append("chest")
		for zone in CombatCommandApi.BODY_ZONES:
			if blocks.size() < int(controls.get("block_capacity",0)):
				blocks.append(zone)
	return {"player_id":PLAYER,"attack_zones":attacks,"block_zones":blocks,"ability_id":"","elixir_slot":elixir_slot}

func _initialize() -> void:
	_run()
	print("LIVE_ELIXIR_ROUND_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var paths := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Elixir Adventurer",20)
	var repo := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repo),"fixture_elixirs")
	check(hero.equip("waist","elixir_test_belt_v1",repo),"belt_equip")
	check(hero.assign_elixir(0,ELIXIR,repo),"potion_slot_zero")
	check(hero.assign_elixir(1,"elixir_test_mana_v1",repo),"potion_slot_one")
	var pools := hero.resource_snapshot(repo)
	check(bool(pools.has("max_hp")),"real_character_hp_available")
	hero.current_hp = maxi(1,int(pools.get("max_hp",100))-35)
	var original_charges := int(repo.get_item(ELIXIR).get("charges",-1))
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,993,START,hero,repo,MANIFEST).get("ok",false)),"expedition_saved")
	var mounted := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(mounted.get("ok",false)),"map_mounted")
	if not bool(mounted.get("ok",false)):
		return
	var started := SoloLiveNpcCombat.start(mounted["session"],TARGET)
	check(bool(started.get("ok",false)),"live_npc_started")
	if not bool(started.get("ok",false)):
		print("LIVE_ELIXIR_START_REASON=",started.get("reason","unknown"))
		return
	var live: SoloLiveNpcCombat = started["combat"]
	var simulator: GroupCombatSimulator = live.battle["simulator"]
	var view := live.combat_view()
	var elixir_view: Dictionary = view.get("elixir_loadout",{})
	check(bool(elixir_view.get("ok",false)) and Array(elixir_view.get("slots",[])).size()==4,"four_slots_visible_in_live_combat")
	var base_event_id := simulator.state.next_event_id
	var invalid := live.play_round(orders(simulator,3))
	check(not bool(invalid.get("ok",false)) and simulator.state.round_number==0,"empty_elixir_rejected_before_round")
	check(simulator.state.next_event_id==base_event_id and not FileAccess.file_exists(live.checkpoint_path),"invalid_potion_never_committed")
	var first := live.play_round(orders(simulator,0))
	check(bool(first.get("ok",false)),"elixir_real_round")
	if not bool(first.get("ok",false)):
		print("LIVE_ELIXIR_ROUND1_REASON=",first.get("reason","unknown"),":",first.get("detail",""))
		return
	check(simulator.state.round_number==1,"exactly_one_round")
	check(FileAccess.file_exists(live.checkpoint_path),"elixir_checkpoint_saved")
	check(int(live.owner.repository.get_item(ELIXIR).get("charges",-1))==original_charges-1,"live_charge_decremented_once")
	var actual_heal := false
	for event in simulator.state.event_log:
		if event.kind == CombatEvent.Kind.EFFECT and event.source_id == PLAYER and String(event.payload.get("source_type","")) == "elixir" and String(event.payload.get("source_instance_id","")) == ELIXIR and int(event.result.get("healed",0)) > 0:
			actual_heal = true
	check(actual_heal,"existing_combat_engine_applied_real_healing")
	var audit := SoloCombatElixirJournal.inspect(simulator.state,live.owner.character,live.owner.repository)
	check(bool(audit.get("ok",false)) and int(Dictionary(audit.get("counts",{})).get(ELIXIR,0))==1,"one_use_derived_from_resolved_engine_events")
	check(int(audit.get("next_available_round",-1))==3,"two_round_shared_cooldown_start")
	var base := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(base.get("ok",false)),"precombat_base_readable")
	if bool(base.get("ok",false)):
		check(int(base["repository"].get_item(ELIXIR).get("charges",-1))==original_charges,"precombat_world_is_unchanged_during_battle")
		var reconstructed := SoloCombatElixirJournal.apply_to_baseline(simulator.state,base["character"],base["repository"])
		check(bool(reconstructed.get("ok",false)) and int(reconstructed["repository"].get_item(ELIXIR).get("charges",-1))==original_charges-1,"journal_reconciles_original_repository")
		var exhausted := ItemRepository.from_dict(base["repository"].to_dict())
		var insufficient := exhausted.get_item(ELIXIR)
		insufficient["charges"] = 0
		check(exhausted.update_item(insufficient),"overspend_fixture_created")
		check(not bool(SoloCombatElixirJournal.apply_to_baseline(simulator.state,base["character"],exhausted).get("ok",false)),"journal_refuses_overspending_original_item")
	if String(first.get("state",""))!="ongoing":
		check(false,"first_elixir_round_must_remain_resumable")
		return
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"checkpoint_world_pending")
	if not bool(pending.get("ok",false)):
		return
	var restored := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(restored.get("ok",false)),"same_checkpoint_resumed")
	if not bool(restored.get("ok",false)):
		print("LIVE_ELIXIR_RESUME_REASON=",restored.get("reason","unknown"),":",restored.get("detail",""))
		return
	var after: SoloLiveNpcCombat = restored["combat"]
	var sim2: GroupCombatSimulator = after.battle["simulator"]
	check(sim2.state.round_number==1 and sim2.state.next_event_id==simulator.state.next_event_id,"checkpoint_did_not_replay_elixir_effects")
	check(int(after.owner.repository.get_item(ELIXIR).get("charges",-1))==original_charges-1,"spent_charge_survives_process_restart")
	var bad_second := after.play_round(orders(sim2,1))
	check(not bool(bad_second.get("ok",false)) and String(bad_second.get("reason",""))=="elixir_shared_cooldown","shared_cooldown_denies_other_slot")
	check(sim2.state.round_number==1 and int(after.owner.repository.get_item(ELIXIR).get("charges",-1))==original_charges-1,"cooldown_rejection_has_no_side_effect")
	var second := after.play_round(orders(sim2,-1))
	check(bool(second.get("ok",false)),"second_round_without_elixir")
	if bool(second.get("ok",false)):
		check(sim2.state.round_number==2,"next_round_once")
		check(int(after.owner.repository.get_item(ELIXIR).get("charges",-1))==original_charges-1,"no_repeated_charge_debit")
		var persisted := SoloCombatElixirJournal.inspect(sim2.state,after.owner.character,after.owner.repository)
		check(bool(persisted.get("ok",false)) and int(Dictionary(persisted.get("counts",{})).get(ELIXIR,0))==1,"potion_event_once_even_after_second_round")
		if String(second.get("state",""))=="ongoing":
			var pending_again := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
			check(bool(pending_again.get("ok",false)),"second_checkpoint_world_readable")
			if bool(pending_again.get("ok",false)):
				var recovered_again := SoloLiveNpcCombat.resume(pending_again["session"])
				check(bool(recovered_again.get("ok",false)),"second_checkpoint_reopened_without_replay")
				if bool(recovered_again.get("ok",false)):
					var third_combat: SoloLiveNpcCombat = recovered_again["combat"]
					check(int(third_combat.owner.repository.get_item(ELIXIR).get("charges",-1))==original_charges-1,"repeat_restart_does_not_spend_twice")
		elif String(second.get("state","")) in ["victory","defeat"]:
			var terminal_world := ExpeditionSaveService.read(EXP,ID,PLAYER)
			check(bool(terminal_world.get("ok",false)),"terminal_elixir_world_readable")
			if bool(terminal_world.get("ok",false)):
				check(int(terminal_world["repository"].get_item(ELIXIR).get("charges",-1))==original_charges-1,"terminal_world_contains_exact_consumed_charge")
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
