extends SceneTree

## Real canonical equipment + production ABI/EFF + GroupCombatSimulator:
## player-chosen cast and explicit skip, cooldown and restart preservation.
const EXP := "user://test_live_manual_abi_exp.json"
const TOWN := "user://test_live_manual_abi_town.json"
const MANIFEST := "user://test_live_manual_abi_manifest.json"
const ID := "solo_exp_manual_abi"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_MANUAL_ABI_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("LIVE_MANUAL_ABI_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _orders(controls: Dictionary, ability_id: String) -> Dictionary:
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	if not bool(controls.get("stunned",false)):
		for hit in range(int(controls.get("attack_count",0))):
			attacks.append("chest")
		for zone in CombatCommandApi.BODY_ZONES:
			if blocks.size() < int(controls.get("block_capacity",0)):
				blocks.append(zone)
	return {"player_id":PLAYER,"attack_zones":attacks,"block_zones":blocks,"ability_id":ability_id}

func _player_cast_count(sim: GroupCombatSimulator, round_number: int) -> int:
	var count := 0
	for event in sim.state.event_log:
		if event.kind == CombatEvent.Kind.ACTION and event.source_id == PLAYER and int(event.payload.get("round",-1)) == round_number and String(event.payload.get("source_kind","")) == "ability":
			count += 1
	return count

func _player_cast_id(sim: GroupCombatSimulator, round_number: int) -> String:
	for event in sim.state.event_log:
		if event.kind == CombatEvent.Kind.ACTION and event.source_id == PLAYER and int(event.payload.get("round",-1)) == round_number and String(event.payload.get("source_kind","")) == "ability":
			return String(event.payload.get("ability_id",""))
	return ""

func _option(controls: Dictionary, ability_id: String) -> Dictionary:
	for raw_option in Array(controls.get("abilities",[])):
		var option: Dictionary = raw_option
		if String(option.get("id","")) == ability_id:
			return option
	return {}

func _run() -> void:
	# Solo save/resume must carry the SAME approved sword ability, not an
	# obsolete test spell or placeholder chest healing ABI.
	var artifacts := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Sword Adventurer",15)
	var repo := ItemRepository.new()
	var sword := {
		"instance_id":"SOLO_ABI_TEST_SWORD","equip_slots":["main_hand"],
		"slot_usage":["main_hand"],"abilities":["ABI301"],"weapon_class":"sword",
		"par_stats":{"PAR057":1},
		"damage":{"min":1.0,"max":2.0,"type":"slashing"}
	}
	ItemDurabilityService.initialize_item(sword,100)
	check(repo.add_item(sword),"repository_item")
	check(hero.receive_item("SOLO_ABI_TEST_SWORD",repo),"item_owned")
	check(hero.equip("main_hand","SOLO_ABI_TEST_SWORD",repo),"equipped_approved_sword_abi")
	check(EquipmentAbilityLoadout.active_abilities(hero,repo)==["ABI301"],"approved_equipped_loadout")
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,991,START,hero,repo,MANIFEST).get("ok",false)),"expedition_created")
	var launched := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(launched.get("ok",false)),"world_opened")
	if not bool(launched.get("ok",false)):
		return
	var started := SoloLiveNpcCombat.start(launched["session"],TARGET)
	check(bool(started.get("ok",false)),"real_npc_battle_started")
	if not bool(started.get("ok",false)):
		print("LIVE_MANUAL_ABI_START_REASON=",started.get("reason","unknown"))
		return
	var live: SoloLiveNpcCombat = started["combat"]
	var simulator: GroupCombatSimulator = live.battle["simulator"]
	var scheduler := simulator.attack_pipeline.ability_scheduler
	check(scheduler.definitions.has("ABI301"),"production_sword_abi_available")
	check(not scheduler.definitions.has("TEST_ABI_FIREBALL"),"test_fixture_absent_from_real_catalog")
	check(AbilityCatalog.assigned_abilities(scheduler.loadouts,PLAYER)==["ABI301"],"canonical_player_loadout")
	var view: Dictionary = live.combat_view()
	check(bool(view.get("ok",false)),"real_abi_view")
	if not bool(view.get("ok",false)):
		return
	var slots: Array = view.get("ability_slots",[])
	check(slots.size()==6,"all_six_abi_slots")
	if slots.size()==6:
		check(String(slots[0].get("id",""))=="ABI301","weapon_slot_approved_abi")
		for i in [1,2,3,4,5]:
			check(String(slots[i].get("id","")).is_empty(),"unused_slot_empty_"+str(i))
	var controls: Dictionary = view.get("controls",{})
	check(bool(_option(controls,"ABI301").get("available",false)),"sword_abi_ready")
	var initial_round := simulator.state.round_number
	var initial_events := simulator.state.next_event_id
	var initial_rng := simulator.engine.combat_rng.state
	var invalid := live.play_round(_orders(controls,"TEST_ABI_FIREBALL"))
	check(not bool(invalid.get("ok",false)) and String(invalid.get("reason",""))=="player_ability_not_equipped","non_equipped_test_id_rejected")
	check(simulator.state.round_number==initial_round and simulator.state.next_event_id==initial_events and simulator.engine.combat_rng.state==initial_rng,"invalid_abi_is_atomic")
	check(not FileAccess.file_exists(live.checkpoint_path),"invalid_abi_no_checkpoint")
	var first := live.play_round(_orders(controls,"ABI301"))
	check(bool(first.get("ok",false)),"first_manual_sword_round")
	if not bool(first.get("ok",false)):
		print("LIVE_MANUAL_ABI_ROUND1_REASON=",first.get("reason","unknown"),":",first.get("detail",""))
		return
	check(simulator.state.round_number==1,"first_abi_one_round")
	check(_player_cast_count(simulator,1)==1 and _player_cast_id(simulator,1)=="ABI301","approved_abi_action_recorded")
	check(FileAccess.file_exists(live.checkpoint_path),"checkpoint_after_abi")
	var deadline := int(scheduler.cooldowns_by_combatant.get(PLAYER,{}).get("ABI301",0))
	check(deadline>1,"cooldown_after_abi")
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"pending_world_opened")
	if not bool(pending.get("ok",false)):
		return
	var resumed := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(resumed.get("ok",false)),"checkpoint_resume")
	if not bool(resumed.get("ok",false)):
		print("LIVE_MANUAL_ABI_RESUME_REASON=",resumed.get("reason","unknown"),":",resumed.get("detail",""))
		return
	var recovered: SoloLiveNpcCombat = resumed["combat"]
	var sim2: GroupCombatSimulator = recovered.battle["simulator"]
	check(sim2.state.round_number==1 and sim2.state.next_event_id==simulator.state.next_event_id,"round_and_events_restored")
	check(_player_cast_count(sim2,1)==1 and _player_cast_id(sim2,1)=="ABI301","abi_not_recast_during_resume")
	check(AbilityCatalog.assigned_abilities(sim2.attack_pipeline.ability_scheduler.loadouts,PLAYER)==["ABI301"],"approved_abi_loadout_persisted")
	check(int(sim2.attack_pipeline.ability_scheduler.cooldowns_by_combatant.get(PLAYER,{}).get("ABI301",0))==deadline,"cooldown_persisted")
	var restored_view := recovered.combat_view()
	check(bool(restored_view.get("ok",false)) and Array(restored_view.get("ability_slots",[])).size()==6,"slot_snapshot_restored")
	var round2_controls: Dictionary = restored_view.get("controls",{})
	check(not bool(_option(round2_controls,"ABI301").get("available",true)),"sword_abi_cooldown")
	var before_round := sim2.state.round_number
	var before_events := sim2.state.next_event_id
	var invalid_recast := recovered.play_round(_orders(round2_controls,"ABI301"))
	check(not bool(invalid_recast.get("ok",false)) and String(invalid_recast.get("reason",""))=="player_ability_unavailable","cooldown_rejects_before_round")
	check(sim2.state.round_number==before_round and sim2.state.next_event_id==before_events,"cooldown_rejection_atomic")
	var second := recovered.play_round(_orders(round2_controls,""))
	check(bool(second.get("ok",false)),"explicit_skip_advances")
	if bool(second.get("ok",false)):
		check(sim2.state.round_number==2,"second_round_exactly_once")
		check(_player_cast_count(sim2,2)==0,"no_autocast_on_skip")
	if bool(second.get("ok",false)) and String(second.get("state",""))=="ongoing":
		var third_controls: Dictionary = recovered.combat_view().get("controls",{})
		check(bool(_option(third_controls,"ABI301").get("available",false)),"sword_abi_ready_after_cooldown")
		if bool(_option(third_controls,"ABI301").get("available",false)):
			var third := recovered.play_round(_orders(third_controls,"ABI301"))
			check(bool(third.get("ok",false)),"sword_abi_after_cooldown")
			if bool(third.get("ok",false)):
				check(_player_cast_count(sim2,3)==1,"sword_abi_cast_once_in_round3")
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
