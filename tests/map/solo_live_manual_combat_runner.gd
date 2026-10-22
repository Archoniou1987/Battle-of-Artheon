extends SceneTree

## Real Solo NPC encounter: player-selected body zones and manual PAR073
## block zones, canonical grouped attacks, checkpoint and restart.
const EXP := "user://test_live_manual_combat_exp.json"
const TOWN := "user://test_live_manual_combat_town.json"
const MANIFEST := "user://test_live_manual_combat_manifest.json"
const ID := "solo_exp_manual_combat"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_MANUAL_COMBAT_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	_run()
	print("LIVE_MANUAL_COMBAT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _requested_zones(count: int, zone: String) -> Array[String]:
	var zones: Array[String] = []
	for i in range(count):
		zones.append(zone)
	return zones

func _chosen_blocks(capacity: int, first: String) -> Array[String]:
	var blocks: Array[String] = []
	for zone in [first,"waist","legs","arms","head","chest"]:
		if blocks.size() >= capacity:
			break
		if not blocks.has(zone):
			blocks.append(zone)
	return blocks

func _attack_zones_for_round(sim: GroupCombatSimulator, number: int) -> Array[String]:
	var zones: Array[String] = []
	for event in sim.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == PLAYER and int(event.payload.get("round",-1)) == number and not bool(event.payload.get("is_extra_attack",false)) and not bool(event.payload.get("is_counterattack",false)):
			zones.append(String(event.payload.get("zone","")))
	return zones

func _run() -> void:
	var artifacts := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Manual Fighter",20)
	var repo := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_created")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,987,START,hero,repo,MANIFEST).get("ok",false)),"world_created")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(opened.get("ok",false)),"map_opened")
	if not bool(opened.get("ok",false)):
		return
	var start := SoloLiveNpcCombat.start(opened["session"],TARGET)
	check(bool(start.get("ok",false)),"npc_encounter_created")
	if not bool(start.get("ok",false)):
		print("LIVE_MANUAL_START_REASON=",start.get("reason","unknown"))
		return
	var live: SoloLiveNpcCombat = start["combat"]
	var simulator: GroupCombatSimulator = live.battle["simulator"]
	var view := live.combat_view()
	check(bool(view.get("ok",false)) and not bool(view.get("finished",true)),"combat_view_ready")
	if not bool(view.get("ok",false)):
		return
	var controls: Dictionary = view.get("controls",{})
	var attack_count := int(controls.get("attack_count",0))
	var block_count := int(controls.get("block_capacity",0))
	check(attack_count>=1,"real_par_weapon_attack_count")
	check(block_count>=1 and block_count<=4,"par073_block_zone_count")
	check(Array(view.get("enemies",[])).size()>=1,"real_npc_hp_visible")
	var first_attacks := _requested_zones(attack_count,"head")
	var first_blocks := _chosen_blocks(block_count,"chest")
	var base_round := simulator.state.round_number
	var base_event_id := simulator.state.next_event_id
	var base_rng := simulator.engine.combat_rng.state
	var base_revision := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	var bad := live.play_round({"player_id":PLAYER,"attack_zones":["not_a_zone"],"block_zones":first_blocks})
	check(not bool(bad.get("ok",false)) and String(bad.get("reason",""))=="invalid_attack_zone","invalid_zone_rejected")
	check(simulator.state.round_number==base_round and simulator.state.next_event_id==base_event_id and simulator.engine.combat_rng.state==base_rng,"invalid_zone_does_not_advance_or_roll")
	var wrong_count := live.play_round({"player_id":PLAYER,"attack_zones":first_attacks,"block_zones":[]})
	check(not bool(wrong_count.get("ok",false)) and String(wrong_count.get("reason",""))=="invalid_block_zone_count","invalid_block_count_rejected")
	check(simulator.state.round_number==base_round and simulator.state.next_event_id==base_event_id,"invalid_block_does_not_change_round")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==base_revision,"invalid_orders_never_change_world")
	check(not FileAccess.file_exists(live.checkpoint_path),"invalid_orders_do_not_create_checkpoint")
	var turn1 := live.play_round({"player_id":PLAYER,"attack_zones":first_attacks,"block_zones":first_blocks})
	check(bool(turn1.get("ok",false)),"selected_first_round_resolved")
	if not bool(turn1.get("ok",false)):
		print("LIVE_MANUAL_ROUND_REASON=",turn1.get("reason","unknown"))
		return
	check(simulator.state.round_number==1,"selected_first_round_number")
	check(_attack_zones_for_round(simulator,1)==first_attacks,"manual_hit_zones_in_actual_combat_events")
	check(CombatModifierService.manual_block_zones(simulator.state.get_combatant(PLAYER))==first_blocks,"manual_block_stored_on_canonical_fighter")
	check(FileAccess.file_exists(live.checkpoint_path),"first_round_checkpoint_persisted")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==base_revision,"active_combat_does_not_commit_world")
	var after1 := live.combat_view()
	check(bool(after1.get("ok",false)) and int(after1.get("round",-1))==1,"combat_view_after_first_round")
	check(not Array(after1.get("last_round_log",[])).is_empty(),"canonical_combat_event_log_visible")
	check(String(turn1.get("state",""))=="ongoing","first_round_not_terminal_before_resume")
	if String(turn1.get("state",""))!="ongoing":
		return
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"world_remounted_for_resume")
	if not bool(pending.get("ok",false)):
		return
	var restored := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(restored.get("ok",false)),"same_checkpoint_restored")
	if not bool(restored.get("ok",false)):
		print("LIVE_MANUAL_RESUME_REASON=",restored.get("reason","unknown"),":",restored.get("detail",""))
		return
	var resumed: SoloLiveNpcCombat = restored["combat"]
	var sim2: GroupCombatSimulator = resumed.battle["simulator"]
	check(sim2.state.round_number==1 and sim2.state.next_event_id==simulator.state.next_event_id,"restart_has_no_replayed_events")
	check(_attack_zones_for_round(sim2,1)==first_attacks,"attack_choices_persisted_in_log")
	check(CombatModifierService.manual_block_zones(sim2.state.get_combatant(PLAYER))==first_blocks,"manual_block_choices_survive_restart")
	check(not bool(pending["session"].move_one_step(Vector2i(5,5)).get("ok",false)),"locked_map_does_not_move")
	var second_controls := sim2.player_controls(PLAYER)
	var second_stunned := bool(second_controls.get("stunned",false))
	var second_attacks := [] as Array[String] if second_stunned else _requested_zones(int(second_controls.get("attack_count",0)),"legs")
	var second_blocks := [] as Array[String] if second_stunned else _chosen_blocks(int(second_controls.get("block_capacity",0)),"arms")
	var turn2 := resumed.play_round({"player_id":PLAYER,"attack_zones":second_attacks,"block_zones":second_blocks})
	check(bool(turn2.get("ok",false)),"second_selected_round_resolved")
	if not bool(turn2.get("ok",false)):
		print("LIVE_MANUAL_SECOND_REASON=",turn2.get("reason","unknown"))
		return
	check(sim2.state.round_number==2,"second_round_exactly_once")
	check(_attack_zones_for_round(sim2,2)==second_attacks,"second_round_uses_new_hit_zones")
	check(CombatModifierService.manual_block_zones(sim2.state.get_combatant(PLAYER))==second_blocks,"second_round_replaces_block_selection")
	check(_attack_zones_for_round(sim2,1)==first_attacks,"earlier_round_event_history_unchanged")
	var reloaded := resumed.combat_view()
	check(bool(reloaded.get("ok",false)) and int(reloaded.get("round",-1))==2,"live_readout_uses_same_second_round")
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
