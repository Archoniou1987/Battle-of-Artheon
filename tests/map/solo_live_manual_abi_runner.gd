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
	var artifacts := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"ABI Adventurer",15)
	var repo := ItemRepository.new()
	var sword := {
		"instance_id":"SOLO_ABI_TEST_SWORD","equip_slots":["main_hand"],
		"slot_usage":["main_hand"],"abilities":["ABI003"],
		"damage":{"min":1.0,"max":2.0,"type":"slashing"}
	}
	var chest := {
		"instance_id":"SOLO_ABI_TEST_CHEST","equip_slots":["chest"],
		"slot_usage":["chest"],"abilities":["ABI004"]
	}
	for item in [sword,chest]:
		ItemDurabilityService.initialize_item(item,100)
		check(repo.add_item(item),"repository_item_"+String(item["instance_id"]))
		check(hero.receive_item(String(item["instance_id"]),repo),"owned_item_"+String(item["instance_id"]))
	check(hero.equip("main_hand","SOLO_ABI_TEST_SWORD",repo),"equipped_real_abi003")
	check(hero.equip("chest","SOLO_ABI_TEST_CHEST",repo),"equipped_real_abi004")
	check(EquipmentAbilityLoadout.active_abilities(hero,repo)==["ABI003","ABI004"],"abi_from_equipment_not_fixture")
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
	check(scheduler.definitions.has("ABI003") and scheduler.definitions.has("ABI004"),"production_abi_catalog_attached")
	check(not scheduler.definitions.has("TEST_ABI_FIREBALL"),"no_test_ability_in_live_world")
	check(AbilityCatalog.assigned_abilities(scheduler.loadouts,PLAYER)==["ABI003","ABI004"],"canonical_player_loadout")
	var view := live.combat_view()
	check(bool(view.get("ok",false)),"real_abi_view")
	if not bool(view.get("ok",false)):
		return
	var slots: Array = view.get("ability_slots",[])
	check(slots.size()==5,"all_five_abi_slots_visible")
	if slots.size()==5:
		check(String(slots[0].get("id",""))=="ABI003" and String(slots[3].get("id",""))=="ABI004","correct_equipment_abi_positions")
		check(String(slots[1].get("id","")).is_empty() and String(slots[2].get("id","")).is_empty() and String(slots[4].get("id","")).is_empty(),"empty_slots_not_executable")
	var controls: Dictionary = view.get("controls",{})
	check(bool(_option(controls,"ABI003").get("available",false)),"fireball_ready")
	check(bool(_option(controls,"ABI004").get("available",false)),"healing_ready")
	var initial_round: int = simulator.state.round_number
	var initial_events: int = simulator.state.next_event_id
	var initial_rng: int = simulator.engine.combat_rng.state
	var invalid := live.play_round(_orders(controls,"TEST_ABI_FIREBALL"))
	check(not bool(invalid.get("ok",false)) and String(invalid.get("reason",""))=="player_ability_not_equipped","fixture_spell_fails_closed")
	check(simulator.state.round_number==initial_round and simulator.state.next_event_id==initial_events and simulator.engine.combat_rng.state==initial_rng,"invalid_abi_does_not_consume_round_or_rng")
	check(not FileAccess.file_exists(live.checkpoint_path),"invalid_abi_creates_no_checkpoint")
	var mana_before := simulator.state.get_combatant(PLAYER).mana
	var first := live.play_round(_orders(controls,"ABI004"))
	check(bool(first.get("ok",false)),"first_manual_healing_round_resolved")
	if not bool(first.get("ok",false)):
		print("LIVE_MANUAL_ABI_ROUND1_REASON=",first.get("reason","unknown"),":",first.get("detail",""))
		return
	check(simulator.state.round_number==1,"healing_uses_one_round")
	check(_player_cast_count(simulator,1)==1 and _player_cast_id(simulator,1)=="ABI004","exactly_one_player_abi004_event")
	check(simulator.state.get_combatant(PLAYER).mana < mana_before,"cast_deducted_mana")
	check(FileAccess.file_exists(live.checkpoint_path),"ability_round_checkpoint_saved")
	check(int(scheduler.cooldowns_by_combatant.get(PLAYER,{}).get("ABI004",0))==3,"healing_ability_cooldown_recorded")
	var applied_healing_eff := false
	for raw_effect in simulator.state.get_combatant(PLAYER).active_effects:
		if String(Dictionary(raw_effect).get("effect_id",""))=="EFF004":
			applied_healing_eff = true
	check(applied_healing_eff,"production_abi004_applies_real_eff004")
	var after_first := live.combat_view()
	check(bool(after_first.get("ok",false)) and int(after_first.get("round",-1))==1,"real_abi_log_projection")
	check(Array(after_first.get("last_round_log",[])).size()>0,"real_abi_log_not_empty")
	var healing_effect_visible := false
	var first_player: Dictionary = after_first.get("player",{})
	for raw_effect in Array(first_player.get("effects",[])):
		if String(Dictionary(raw_effect).get("id",""))=="EFF004":
			healing_effect_visible = true
	check(healing_effect_visible,"live_view_discloses_real_eff004")
	if String(first.get("state",""))!="ongoing":
		check(false,"healing_round_must_remain_active_for_resume")
		return
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"pending_abi_world_opened")
	if not bool(pending.get("ok",false)):
		return
	var resumed := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(resumed.get("ok",false)),"same_abi_checkpoint_resumed")
	if not bool(resumed.get("ok",false)):
		print("LIVE_MANUAL_ABI_RESUME_REASON=",resumed.get("reason","unknown"),":",resumed.get("detail",""))
		return
	var recovered: SoloLiveNpcCombat = resumed["combat"]
	var sim2: GroupCombatSimulator = recovered.battle["simulator"]
	check(sim2.state.round_number==1 and sim2.state.next_event_id==simulator.state.next_event_id,"abi_round_and_events_restored")
	check(_player_cast_count(sim2,1)==1 and _player_cast_id(sim2,1)=="ABI004","abi_action_history_not_recast_on_resume")
	check(AbilityCatalog.assigned_abilities(sim2.attack_pipeline.ability_scheduler.loadouts,PLAYER)==["ABI003","ABI004"],"equipped_abi_loadout_persisted")
	check(int(sim2.attack_pipeline.ability_scheduler.cooldowns_by_combatant.get(PLAYER,{}).get("ABI004",0))==3,"abi_cooldown_survives_restart")
	var restored_healing_eff := false
	for raw_effect in sim2.state.get_combatant(PLAYER).active_effects:
		if String(Dictionary(raw_effect).get("effect_id",""))=="EFF004":
			restored_healing_eff = true
	check(restored_healing_eff,"eff004_survives_same_checkpoint")
	var resumed_view := recovered.combat_view()
	check(bool(resumed_view.get("ok",false)) and Array(resumed_view.get("ability_slots",[])).size()==5,"abi_slots_survive_restart")
	var round2_controls: Dictionary = resumed_view.get("controls",{})
	check(not bool(_option(round2_controls,"ABI004").get("available",true)),"healing_cooldown_blocks_next_round")
	var restored_round: int = sim2.state.round_number
	var restored_events: int = sim2.state.next_event_id
	var cooldown_cast := recovered.play_round(_orders(round2_controls,"ABI004"))
	check(not bool(cooldown_cast.get("ok",false)) and String(cooldown_cast.get("reason",""))=="player_ability_unavailable","cooldown_rejected_before_round")
	check(sim2.state.round_number==restored_round and sim2.state.next_event_id==restored_events,"cooldown_rejection_side_effect_free")
	var second := recovered.play_round(_orders(round2_controls,""))
	check(bool(second.get("ok",false)),"second_round_explicit_no_abi")
	if not bool(second.get("ok",false)):
		print("LIVE_MANUAL_ABI_ROUND2_REASON=",second.get("reason","unknown"),":",second.get("detail",""))
		return
	check(sim2.state.round_number==2,"no_abi_advances_once")
	check(_player_cast_count(sim2,2)==0,"explicit_skip_suppresses_autocast_for_player")
	check(int(sim2.attack_pipeline.ability_scheduler.cooldowns_by_combatant.get(PLAYER,{}).get("ABI004",0))==3,"skip_preserves_cooldown")
	var second_view := recovered.combat_view()
	check(bool(second_view.get("ok",false)) and int(second_view.get("round",-1))==2,"current_round_readout_updated")
	# The other real equipped slot is an offensive spell. Exercise its
	# dispatch only if battle is still active; no spell gets fabricated
	# or auto-cast if the previous round has already ended the encounter.
	if bool(second_view.get("ok",false)) and not bool(second_view.get("finished",true)):
		var third_controls: Dictionary = second_view.get("controls",{})
		check(bool(_option(third_controls,"ABI003").get("available",false)),"fireball_remains_equipped_and_ready")
		if bool(_option(third_controls,"ABI003").get("available",false)):
			var third := recovered.play_round(_orders(third_controls,"ABI003"))
			check(bool(third.get("ok",false)),"manual_fireball_round_resolved")
			if bool(third.get("ok",false)):
				check(_player_cast_count(sim2,3)==1 and _player_cast_id(sim2,3)=="ABI003","offensive_abi003_resolved_through_same_engine")
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
