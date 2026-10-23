extends SceneTree

## A real equipped ABI004 needs mana. An equipped mana elixir may fund it
## in the SAME canonical group round, but never via a stateful preflight.
const EXP := "user://test_live_mana_abi_exp.json"
const TOWN := "user://test_live_mana_abi_town.json"
const MANIFEST := "user://test_live_mana_abi_manifest.json"
const ID := "solo_exp_mana_abi"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
const MANA_ITEM := "elixir_test_mana_v1"
var failures: Array[String] = []

func check(ok: bool,label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_MANA_ABI_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func orders(sim: GroupCombatSimulator,slot: int,ability: String) -> Dictionary:
	var controls := sim.player_controls(PLAYER)
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	if not bool(controls.get("stunned",false)):
		for i in range(int(controls.get("attack_count",0))):
			attacks.append("chest")
		for zone in CombatCommandApi.BODY_ZONES:
			if blocks.size() < int(controls.get("block_capacity",0)):
				blocks.append(zone)
	return {"player_id":PLAYER,"attack_zones":attacks,"block_zones":blocks,"ability_id":ability,"elixir_slot":slot}

func _initialize() -> void:
	_run()
	print("LIVE_MANA_ABI_TEST=", "PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var paths := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Mana ABI Hero",20)
	var repo := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repo),"elixir_fixtures")
	var chest: Dictionary = {"instance_id":"MANA_ABI_TEST_CHEST","equip_slots":["chest"],"slot_usage":["chest"],"abilities":["ABI004"]}
	ItemDurabilityService.initialize_item(chest,100)
	check(repo.add_item(chest) and hero.receive_item("MANA_ABI_TEST_CHEST",repo),"abi_item_received")
	check(hero.equip("chest","MANA_ABI_TEST_CHEST",repo),"healing_abi_equipped")
	check(hero.equip("waist","elixir_test_belt_v1",repo),"real_belt")
	check(hero.assign_elixir(0,MANA_ITEM,repo),"mana_elixir_assigned")
	var max_mana := int(hero.resource_snapshot(repo).get("max_mana",0))
	check(max_mana >= 10,"mana_capacity_for_ability")
	hero.current_mana = 0
	var initial_charges := int(repo.get_item(MANA_ITEM).get("charges",-1))
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,994,START,hero,repo,MANIFEST).get("ok",false)),"expedition_saved")
	var world := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(world.get("ok",false)),"world_opened")
	if not bool(world.get("ok",false)):
		return
	var started := SoloLiveNpcCombat.start(world["session"],TARGET)
	check(bool(started.get("ok",false)),"real_npc_contact")
	if not bool(started.get("ok",false)):
		print("MANA_ABI_START_REASON=",started.get("reason","unknown"))
		return
	var combat: SoloLiveNpcCombat = started["combat"]
	var sim: GroupCombatSimulator = combat.battle["simulator"]
	var actor: CombatantState = sim.state.get_combatant(PLAYER)
	check(actor.mana==0,"zero_initial_combat_mana")
	var normal := sim.player_controls(PLAYER)
	var boosted := sim.player_controls(PLAYER,0)
	var available_without := false
	var available_with := false
	for option in Array(normal.get("abilities",[])):
		if String(option.get("id",""))=="ABI004":
			available_without = bool(option.get("available",false))
	for option in Array(boosted.get("abilities",[])):
		if String(option.get("id",""))=="ABI004":
			available_with = bool(option.get("available",false))
	check(not available_without,"no_unfunded_cast")
	check(available_with,"selected_mana_elixir_funds_abi")
	check(actor.mana==0 and int(combat.owner.repository.get_item(MANA_ITEM).get("charges",-1))==initial_charges,"readout_never_spends_resources")
	var before_event := sim.state.next_event_id
	var refused := combat.play_round(orders(sim,-1,"ABI004"))
	check(not bool(refused.get("ok",false)) and String(refused.get("reason",""))=="player_ability_unavailable","unfunded_abi_rejected")
	check(sim.state.round_number==0 and sim.state.next_event_id==before_event and not FileAccess.file_exists(combat.checkpoint_path),"unfunded_abi_atomic")
	var first := combat.play_round(orders(sim,0,"ABI004"))
	check(bool(first.get("ok",false)),"mana_elixir_and_abi_same_round")
	if not bool(first.get("ok",false)):
		print("MANA_ABI_ROUND_REASON=",first.get("reason","unknown"),":",first.get("detail",""))
		return
	check(sim.state.round_number==1,"both_actions_one_round")
	check(int(combat.owner.repository.get_item(MANA_ITEM).get("charges",-1))==initial_charges-1,"one_potion_charge_spent")
	var potion_events := 0
	var abi_events := 0
	var potion_event_id := -1
	var abi_event_id := -1
	for event in sim.state.event_log:
		if event.source_id != PLAYER:
			continue
		if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("source_type",""))=="elixir" and String(event.payload.get("source_instance_id",""))==MANA_ITEM:
			potion_events += 1
			potion_event_id = event.event_id
		elif event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI004":
			abi_events += 1
			abi_event_id = event.event_id
	check(potion_events==1 and abi_events==1,"exactly_one_potion_and_one_abi")
	check(potion_event_id > 0 and abi_event_id > potion_event_id,"mana_restored_before_abi_event")
	check(actor.mana >= 0 and actor.mana < 30,"mana_restoration_pays_real_abi_cost")
	check(bool(SoloCombatElixirJournal.inspect(sim.state,combat.owner.character,combat.owner.repository).get("ok",false)),"same_round_journal_is_valid")
	if String(first.get("state",""))=="ongoing":
		var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
		check(bool(pending.get("ok",false)),"world_pending")
		if bool(pending.get("ok",false)):
			var restored := SoloLiveNpcCombat.resume(pending["session"])
			check(bool(restored.get("ok",false)),"combo_checkpoint_restored")
			if bool(restored.get("ok",false)):
				var live: SoloLiveNpcCombat = restored["combat"]
				var sim2: GroupCombatSimulator = live.battle["simulator"]
				check(int(live.owner.repository.get_item(MANA_ITEM).get("charges",-1))==initial_charges-1,"combination_spends_once_across_restart")
				check(sim2.state.get_combatant(PLAYER).mana==actor.mana,"combo_mana_and_spell_cost_restored")
	for path in [EXP,TOWN,MANIFEST,String(paths["checkpoint"]),String(paths["receipt"]),String(paths["terminal"])]:
		wipe(path)
