extends SceneTree

## Real Village -> Arena -> persistent CharacterState -> progression JSON ->
## reopened Arena -> restarted Village, for BOTH victory and defeat.
## No synthetic combat outcome is supplied to the game controller.
const PROGRESSION_SAVE := "user://character_progression_v1.json"
const INVENTORY_SAVE := "user://character_inventory_v1.json"
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ARENA_TERMINAL_SAVE_CASE=FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_remove_saves()
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	_check(packed != null, "main_scene_available")
	if packed == null:
		_finish()
		return
	var first := packed.instantiate()
	root.add_child(first)
	await process_frame
	var hero := first.get("player_character") as CharacterState
	var repository := first.get("item_repository") as ItemRepository
	_check(hero != null and repository != null, "village_character_and_items")
	if hero == null or repository == null:
		first.queue_free()
		await process_frame
		_finish()
		return
	first.call("_open_panel", "Арена")
	await process_frame
	var arena := first.get_node_or_null("ArenaScreen") as ArenaScreen
	_check(arena != null and arena.combat_session != null, "first_arena_ready")
	if arena == null or arena.combat_session == null:
		first.queue_free()
		await process_frame
		_finish()
		return

	# The first fight ends in a genuine engine-resolved player victory.
	var player := arena.combat_session.fighter(true)
	var npc := arena.combat_session.fighter(false)
	_configure_player_hit(player)
	npc.hp = 1
	npc.armour.clear()
	npc.combat_stats["dodge_rating_percent"] = 0.0
	npc.combat_stats["shield_auto_block_rating_percent"] = 0.0
	npc.combat_stats["damage_reduction_pct"] = 0.0
	npc.combat_stats["damage_reduction"] = 0.0
	npc.combat_loadout["can_manual_block"] = false
	npc.combat_loadout["can_auto_block"] = false
	arena._play_combat_round(["chest"], _blocks(player))
	var victory_session := arena.combat_session
	_check(victory_session.state.round_number == 1, "victory_commits_exactly_one_round")
	_check(victory_session.orchestrator.battle_outcome() == "winner:player", "real_player_victory")
	_check(npc.is_death_finalized(), "victory_finalizes_npc_death")
	_check(bool(CombatDiagnostics.round_trace(victory_session.state, 1).get("valid_event_lineage", false)), "victory_engine_event_lineage")
	_check(arena.round_button.disabled, "victory_disables_end_turn")
	var victory_hp := player.visible_hp()
	var victory_mana := player.mana
	_check(hero.current_hp == victory_hp and hero.current_mana == victory_mana, "victory_writes_live_resources_back")
	_check((arena.hp_overlays["player"] as Label).text == "%d / %d" % [victory_hp, player.max_hp], "victory_hp_overlay")
	_check(arena.log_view.text.contains("Бой завершён: winner:player"), "victory_outcome_visible_in_journal")
	_check(_saved_resources_match(victory_hp, victory_mana), "victory_resources_in_progression_json")
	_assert_terminal_retry_atomic(arena, victory_session, "victory")
	arena.back_requested.emit()
	_check(not hero.in_combat, "victory_exit_unpauses_out_of_combat")
	first.queue_free()
	await process_frame

	# Character resources, but not the defeated training NPC, survive reload.
	var second := packed.instantiate()
	root.add_child(second)
	await process_frame
	var restored := second.get("player_character") as CharacterState
	_check(restored != null, "reloaded_village_character")
	if restored == null:
		second.queue_free()
		await process_frame
		_finish()
		return
	_check(restored.current_hp == victory_hp and restored.current_mana == victory_mana, "victory_resources_survive_restart")
	second.call("_open_panel", "Арена")
	await process_frame
	var second_arena := second.get_node_or_null("ArenaScreen") as ArenaScreen
	_check(second_arena != null and second_arena.combat_session != null, "arena_reopens_after_victory")
	if second_arena == null or second_arena.combat_session == null:
		second.queue_free()
		await process_frame
		_finish()
		return
	var second_player := second_arena.combat_session.fighter(true)
	var second_npc := second_arena.combat_session.fighter(false)
	_check(second_player.hp == victory_hp and second_player.mana == victory_mana, "reopened_fighter_uses_saved_resources")
	_check(second_arena.combat_session.state.round_number == 0 and not second_npc.is_death_finalized(), "training_arena_starts_fresh_match")
	# Second fight ends in actual NPC victory. Stun prevents the hero's
	# outgoing action and manual defence; NPC uses its genuine weapon event.
	second_player.hp = 1
	second_player.armour.clear()
	second_player.tempo_stun_round = 1
	second_player.combat_stats["dodge_rating_percent"] = 0.0
	second_player.combat_stats["damage_reduction_pct"] = 0.0
	second_player.combat_stats["damage_reduction"] = 0.0
	second_npc.combat_stats["hit_chance_rating_percent"] = 100.0
	second_arena._play_combat_round(["chest"], _blocks(second_player))
	_check(second_arena.combat_session.state.round_number == 1, "defeat_commits_exactly_one_round")
	_check(second_player.is_death_finalized() and second_player.visible_hp() == 0, "defeat_finalizes_player_death")
	_check(second_arena.combat_session.orchestrator.battle_outcome() == "winner:enemy", "real_npc_victory")
	_check(restored.current_hp == 0, "defeat_writes_zero_hp_back")
	_check(bool(CombatDiagnostics.round_trace(second_arena.combat_session.state, 1).get("valid_event_lineage", false)), "defeat_engine_event_lineage")
	_check(second_arena.round_button.disabled, "defeat_disables_end_turn")
	_check((second_arena.hp_overlays["player"] as Label).text == "0 / %d" % second_player.max_hp, "defeat_overlay_shows_zero")
	_check(second_arena.log_view.text.contains("Бой завершён: winner:enemy"), "defeat_outcome_visible_in_journal")
	_check(_saved_resources_match(0, restored.current_mana), "defeat_zero_hp_in_progression_json")
	_assert_terminal_retry_atomic(second_arena, second_arena.combat_session, "defeat")
	second_arena.back_requested.emit()
	second.queue_free()
	await process_frame

	var third := packed.instantiate()
	root.add_child(third)
	await process_frame
	var dead_hero := third.get("player_character") as CharacterState
	_check(dead_hero != null and dead_hero.current_hp == 0, "zero_hp_survives_village_restart")
	third.call("_open_panel", "Арена")
	await process_frame
	var third_arena := third.get_node_or_null("ArenaScreen") as ArenaScreen
	_check(third_arena != null and third_arena.combat_session != null, "arena_reopened_with_zero_hp")
	if third_arena != null and third_arena.combat_session != null:
		_check(third_arena.round_button.disabled, "zero_hp_reentry_remains_locked")
		var denied: Dictionary = third_arena.combat_session.play_round(["chest"], _blocks(third_arena.combat_session.fighter(true)))
		_check(not bool(denied.get("ok", false)) and String(denied.get("reason", "")) == "player_has_no_hp", "zero_hp_cannot_start_new_turn")
		_check(third_arena.combat_session.state.round_number == 0 and third_arena.combat_session.state.event_log.is_empty(), "zero_hp_denied_without_events")
	third.queue_free()
	await process_frame
	_finish()

func _configure_player_hit(player: CombatantState) -> void:
	player.combat_stats["hit_chance_rating_percent"] = 100.0

func _blocks(player: CombatantState) -> Array[String]:
	var result: Array[String] = []
	for zone in ["chest", "arms", "waist", "legs"]:
		if result.size() < CombatModifierService.manual_block_zone_capacity(player):
			result.append(zone)
	return result

func _saved_resources_match(hp: int, mana: int) -> bool:
	if not FileAccess.file_exists(PROGRESSION_SAVE):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESSION_SAVE))
	if not raw is Dictionary or not raw.get("resources", {}) is Dictionary:
		return false
	var resources: Dictionary = raw["resources"]
	return int(resources.get("hp", -1)) == hp and int(resources.get("mana", -1)) == mana

func _assert_terminal_retry_atomic(arena: ArenaScreen, session: ArenaCombatSession, label: String) -> void:
	var before_round := session.state.round_number
	var before_log := session.state.event_log.size()
	var before_event_id := session.state.next_event_id
	var before_player_hp := session.fighter(true).hp
	var before_player_mana := session.fighter(true).mana
	var before_enemy_hp := session.fighter(false).hp
	# Directly call the presentation adapter even though the actual End Turn
	# button is disabled: invalid retries must not re-enable that button.
	arena._play_combat_round(["chest"], _blocks(session.fighter(true)))
	_check(arena.round_button.disabled, label + "_rejected_retry_stays_disabled")
	_check(session.state.round_number == before_round and session.state.event_log.size() == before_log and session.state.next_event_id == before_event_id, label + "_retry_does_not_allocate_events")
	_check(session.state.pending_events.is_empty(), label + "_retry_has_no_pending_events")
	_check(session.fighter(true).hp == before_player_hp and session.fighter(true).mana == before_player_mana and session.fighter(false).hp == before_enemy_hp, label + "_retry_does_not_mutate_resources")

func _remove_saves() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESSION_SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INVENTORY_SAVE))

func _finish() -> void:
	_remove_saves()
	print("ARENA_TERMINAL_SAVE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
