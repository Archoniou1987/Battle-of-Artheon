extends SceneTree

const EXP := "user://test_live_npc_combat_exp.json"
const TOWN := "user://test_live_npc_combat_town.json"
const MANIFEST := "user://test_live_npc_combat_manifest.json"
const ID := "solo_exp_player"
var errors: Array[String] = []

func check(ok: bool, name: String) -> void:
	if not ok:
		errors.append(name)
		print("LIVE_NPC_COMBAT_CASE=FAIL ",name)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	for path in [EXP,TOWN,MANIFEST]:
		wipe(path)
	var town := CharacterState.new("player","Hero",20)
	var items := ItemRepository.new()
	check(bool(SoloTownSaveService.save(TOWN,town,items).get("ok",false)),"canonical_town_created")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,123,Vector2i(6,5),town,items,MANIFEST).get("ok",false)),"expedition_created_adjacent_to_bandit")
	var opened := SoloLiveMapSession.open(EXP,MANIFEST,ID,"player")
	check(bool(opened.get("ok",false)),"live_session_open")
	if not bool(opened.get("ok",false)):
		quit(1)
		return
	var session: SoloLiveMapSession = opened["session"]
	check(not bool(SoloLiveNpcCombat.start(session,Vector2i(8,8)).get("ok",false)),"distant_enemy_cannot_start_fight")
	var began := SoloLiveNpcCombat.start(session,Vector2i(7,5))
	check(bool(began.get("ok",false)),"actual_character_builder_and_npc_combat_started")
	if not bool(began.get("ok",false)):
		print("LIVE_COMBAT_START_REASON=",began.get("reason",""))
		quit(1)
		return
	var combat: SoloLiveNpcCombat = began["combat"]
	check(FileAccess.file_exists(MANIFEST),"manifest_written_before_round")
	check(not bool(SoloLiveNpcCombat.start(session,Vector2i(7,5)).get("ok",false)),"second_battle_blocked_by_manifest")
	check(not bool(session.move_one_step(Vector2i(5,5)).get("ok",false)),"movement_locked_while_in_combat")
	check(not bool(session.return_to_town(TOWN).get("ok",false)),"return_locked_while_in_combat")
	var sim: GroupCombatSimulator = combat.battle["simulator"]
	check(sim.state.get_combatant("player") != null and sim.state.get_combatant("solo_npc_bandit_01") != null,"real_roster_ids")
	# Exercise exactly the UI -> authoritative engine order contract,
	# not the empty-order legacy auto-combat route.
	var view_before := combat.combat_view()
	check(bool(view_before.get("ok",false)), "real_combat_view_available_before_round")
	var controls: Dictionary = view_before.get("controls", {})
	check(bool(controls.get("ok",false)), "canonical_player_controls_available")
	var initial_round := sim.state.round_number
	var rejected := combat.play_round({
		"player_id":"player", "attack_zones":["invalid_zone"],
		"block_zones":[], "ability_id":"", "elixir_slot":-1
	})
	check(not bool(rejected.get("ok",false)), "invalid_ui_order_rejected_before_round")
	check(sim.state.round_number == initial_round, "rejected_ui_order_does_not_advance_engine")
	check(not FileAccess.file_exists(combat.checkpoint_path), "rejected_ui_order_does_not_create_checkpoint")
	var chosen_blocks: Array[String] = []
	for raw_zone in ["chest", "arms", "waist", "legs", "head"]:
		if chosen_blocks.size() >= int(controls.get("block_capacity", 0)):
			break
		chosen_blocks.append(raw_zone)
	var chosen_attacks: Array[String] = []
	if not bool(controls.get("stunned", false)):
		for i in range(int(controls.get("attack_count", 0))):
			chosen_attacks.append("chest")
	else:
		chosen_blocks.clear()
	var order := {
		"player_id":"player", "attack_zones":chosen_attacks,
		"block_zones":chosen_blocks, "ability_id":"", "elixir_slot":-1
	}
	var step := combat.play_round(order)
	check(bool(step.get("ok",false)) or String(step.get("state",""))=="defeat_pending_resolution","explicit_ui_order_round_processed")
	if bool(step.get("ok",false)):
		check(sim.state.round_number == initial_round + 1, "explicit_ui_order_advances_one_round")
		if String(step.get("state",""))=="ongoing":
			check(FileAccess.file_exists(combat.checkpoint_path),"explicit_ui_order_checkpoint_durable")
			var view_after := combat.combat_view()
			check(bool(view_after.get("ok",false)), "canonical_combat_view_available_after_round")
			if bool(view_after.get("ok",false)):
				check(int(view_after.get("round",-1)) == sim.state.round_number, "next_ui_snapshot_matches_saved_engine_round")
				var hero := sim.state.get_combatant("player")
				check(int(Dictionary(view_after.get("player",{})).get("hp",-1)) == hero.visible_hp(), "next_ui_snapshot_player_hp_is_authoritative")
				check(int(Dictionary(view_after.get("player",{})).get("mana",-1)) == hero.mana, "next_ui_snapshot_player_mana_is_authoritative")
	# Save remains last pre-fight state while manifest holds ownership.
	var saved := ExpeditionSaveService.read(EXP,ID,"player")
	check(bool(saved.get("ok",false)),"expedition_remains_readable_during_battle")
	# Tests must not leave abandoned manifests in the next CI script.
	wipe(MANIFEST)
	wipe(combat.checkpoint_path)
	wipe(combat.receipt_path)
	wipe(combat.terminal_path)
	for path in [EXP,TOWN]:
		wipe(path)
	print("LIVE_NPC_COMBAT_TEST="+("PASS" if errors.is_empty() else "FAIL")+" errors="+str(errors))
	quit(0 if errors.is_empty() else 1)
