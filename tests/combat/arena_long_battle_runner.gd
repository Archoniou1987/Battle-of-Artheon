extends SceneTree

## Twenty real Arena rounds: approved sword ABI301, synthetic test-only
## ally heal, engine-created bleeding/HoT, elixirs and round diagnostics.
## No active_effects are inserted by the test.
const TOTAL_ROUNDS := 20
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ARENA_LONG_BATTLE_FAIL=", label)

func _init() -> void:
	_run_long_battle()
	print("ARENA_LONG_BATTLE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _run_long_battle() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("LONG_BATTLE_HERO", "Long Battle Hero", 10)
	var sword: Dictionary = {
		"instance_id": "LONG_BATTLE_SWORD",
		"equip_slots": ["main_hand"],
		"slot_usage": ["main_hand"],
		"abilities": ["ABI301"],
		"par_stats": {"PAR057": 1},
		"damage": {"min": 3.0, "max": 4.0, "type": "slashing"}
	}
	var chest: Dictionary = {
		"instance_id": "LONG_BATTLE_CHEST",
		"equip_slots": ["chest"],
		"slot_usage": ["chest"],
		"abilities": ["TEST_LAB_HEAL"]
	}
	for item in [sword, chest]:
		ItemDurabilityService.initialize_item(item, 100)
		_check(repo.add_item(item), "inventory_item_" + String(item["instance_id"]))
		_check(hero.receive_item(String(item["instance_id"]), repo), "owned_item_" + String(item["instance_id"]))
	_check(hero.equip("main_hand", "LONG_BATTLE_SWORD", repo), "mainhand_equipped")
	_check(hero.equip("chest", "LONG_BATTLE_CHEST", repo), "healing_chest_equipped")
	_check(ArenaTestElixirs.seed(hero, repo), "seed_real_elixirs")
	_check(hero.equip("waist", "elixir_test_belt_v1", repo), "elixir_belt_equipped")
	_check(hero.assign_elixir(0, "elixir_test_hp_v1", repo), "hp_elixir_assigned")
	_check(hero.assign_elixir(1, "elixir_test_mana_v1", repo), "mana_elixir_assigned")
	if not failures.is_empty():
		return

	var session := ArenaCombatSession.new(hero, repo)
	var player := session.fighter(true)
	var npc := session.fighter(false)
	player.max_hp = 50000
	player.hp = 20000
	player.max_mana = 500
	player.mana = 250
	npc.max_hp = 80000
	npc.hp = 60000
	npc.max_mana = 500
	npc.mana = 250
	# Disable unrelated natural round regeneration to make resource accounting
	# exact. ABI, effect and elixir implementations remain the actual ones.
	player.combat_stats["hp_regen_round"] = 0.0
	player.combat_stats["mana_regen_round"] = 0.0
	npc.combat_stats["hp_regen_round"] = 0.0
	npc.combat_stats["mana_regen_round"] = 0.0
	session.engine.combat_rng.seed = 20261021
	# Generic ally healing is test-only and never lives in production ABI.
	session.ability_scheduler.definitions["TEST_LAB_HEAL"] = {
		"name":"Тестовое лечение",
		"delivery_type":"DIRECT","target_scope":"SINGLE","target_team":"ALLY",
		"components":[{"kind":"heal","amount":100},{"kind":"effect","effect_id":"EFF004","base_chance":100}],
		"mana_cost":10,"cooldown_rounds":1
	}
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = ["TEST_LAB_HEAL"]
	player.combat_stats["hit_chance_rating_percent"] = 100.0
	npc.combat_stats["dodge_rating_percent"] = 0.0
	npc.combat_stats["shield_auto_block_rating_percent"] = 0.0
	npc.combat_loadout["can_auto_block"] = false

	var blocks: Array[String] = []
	for zone in ["chest", "arms", "waist", "legs"]:
		if blocks.size() < CombatModifierService.manual_block_zone_capacity(player):
			blocks.append(zone)
	_check(blocks.size() == CombatModifierService.manual_block_zone_capacity(player), "block_fixture")
	_check(session.player_attack_count() == 1, "one_weapon_action_per_round")
	var slots: Array[Dictionary] = session.player_ability_options()
	_check(slots.size() == 6, "six_abi_slots")
	if slots.size() != 6 or not failures.is_empty():
		return
	_check(String(slots[0].get("id", "")) == "ABI301", "approved_sword_slot")
	_check(String(slots[4].get("id", "")) == "TEST_LAB_HEAL", "isolated_healing_slot")
	if not failures.is_empty():
		return

	var sword_casts := 0
	var heal_casts := 0
	var npc_heals := 0
	var bleed_ticks := 0
	var regen_ticks := 0
	var unique_events: Dictionary = {}
	var previous_logged_events := 0
	for round_number in range(1, TOTAL_ROUNDS + 1):
		var selected_abi := ""
		if round_number % 3 == 1:
			selected_abi = "ABI301"
		elif round_number % 3 == 2:
			selected_abi = "TEST_LAB_HEAL"
		# Two different real elixirs across the same persistent session.
		# One potion may be combined with physical attacks and a selected ABI.
		if round_number == 5 or round_number == 11:
			var elixir_id := "elixir_test_hp_v1" if round_number == 5 else "elixir_test_mana_v1"
			var slot := 0 if round_number == 5 else 1
			var before_charges := int(repo.get_item(elixir_id).get("charges", -1))
			var potion: Dictionary = session.use_elixir(slot)
			_check(bool(potion.get("ok", false)), "elixir_used_round_%d" % round_number)
			_check(int(repo.get_item(elixir_id).get("charges", -1)) == before_charges - 1, "one_charge_spent_round_%d" % round_number)
			var rejected_potion: Dictionary = session.use_elixir(1 - slot)
			_check(not bool(rejected_potion.get("ok", true)), "shared_elixir_limit_round_%d" % round_number)
			if not bool(potion.get("ok", false)):
				return
		if round_number == 6:
			_check(session.elixir_cooldown() > 0, "shared_elixir_cooldown_after_use")
		if round_number == 9:
			# Invalid input must not consume a turn even with existing ABI/EFF,
			# a ticking cooldown and nonempty canonical history.
			var before_round := session.state.round_number
			var before_player_hp := player.hp
			var before_player_mana := player.mana
			var before_npc_hp := npc.hp
			var before_next_id := session.state.next_event_id
			var before_log_count := session.state.event_log.size()
			var before_player_effects: Array = player.active_effects.duplicate(true)
			var before_npc_effects: Array = npc.active_effects.duplicate(true)
			var before_cooldowns: Dictionary = session.ability_scheduler.cooldowns_by_combatant.duplicate(true)
			var denied: Dictionary = session.play_round(["head"], ["invalid_zone"], selected_abi)
			_check(not bool(denied.get("ok", false)), "late_invalid_block_rejected")
			_check(session.state.round_number == before_round, "late_reject_no_round_advance")
			_check(player.hp == before_player_hp and player.mana == before_player_mana and npc.hp == before_npc_hp, "late_reject_no_resource_change")
			_check(session.state.next_event_id == before_next_id and session.state.event_log.size() == before_log_count and session.state.pending_events.is_empty(), "late_reject_no_events")
			_check(player.active_effects == before_player_effects and npc.active_effects == before_npc_effects, "late_reject_no_effect_ticks")
			_check(session.ability_scheduler.cooldowns_by_combatant == before_cooldowns, "late_reject_no_cooldown_change")
		var options: Array[Dictionary] = session.player_ability_options()
		if not selected_abi.is_empty():
			var option_index := 0 if selected_abi == "ABI301" else 4
			_check(bool(options[option_index].get("available", false)), "ability_ready_round_%d" % round_number)
		var mana_before := player.mana
		var npc_mana_before := npc.mana
		var result: Dictionary = session.play_round(["head"], blocks, selected_abi)
		_check(bool(result.get("ok", false)), "round_%d_accepted_%s" % [round_number, String(result.get("reason", ""))])
		if not bool(result.get("ok", false)):
			return
		_check(session.state.round_number == round_number, "round_number_%d" % round_number)
		_check(session.active_round == null and session.locked_ability_id.is_empty(), "round_closed_%d" % round_number)
		_check(session.state.pending_events.is_empty(), "pending_queue_empty_%d" % round_number)
		_check(String(result.get("outcome", "")) == "ongoing", "round_%d_still_fighting" % round_number)
		_check(not player.is_death_finalized() and not npc.is_death_finalized(), "round_%d_both_alive" % round_number)
		_check(player.mana >= 0 and player.mana <= player.max_mana and npc.mana >= 0 and npc.mana <= npc.max_mana, "round_%d_resource_bounds" % round_number)
		var player_after_regen := mini(player.max_mana, mana_before + 5) # unified base PAR015: +5/round
	_check(player.mana == player_after_regen - (10 if selected_abi == "TEST_LAB_HEAL" else 0), "round_%d_player_mana_debit" % round_number)
		var audit: Dictionary = CombatDiagnostics.round_trace(session.state, round_number)
		_check(bool(audit.get("valid_event_lineage", false)), "lineage_round_%d" % round_number)
		_check(int(audit.get("event_count", 0)) > 0, "events_round_%d" % round_number)
		var weapons: Dictionary = audit.get("weapon_attacks_by_source", {})
		var casts: Dictionary = audit.get("abi_casts_by_source", {})
		_check(int(weapons.get(session.player_id, 0)) == 1, "one_player_strike_round_%d" % round_number)
		_check(int(weapons.get(ArenaCombatSession.ENEMY_ID, 0)) >= 1, "npc_physical_round_%d" % round_number)
		_check(int(casts.get(session.player_id, 0)) == (0 if selected_abi.is_empty() else 1), "one_or_zero_player_abi_round_%d" % round_number)
		var round_npc_casts := int(casts.get(ArenaCombatSession.ENEMY_ID, 0))
		_check(round_npc_casts <= 1, "npc_one_abi_max_round_%d" % round_number)
		var npc_after_regen := mini(npc.max_mana, npc_mana_before + 5)
	_check(npc.mana == npc_after_regen - 10 * round_npc_casts, "npc_abi_mana_debit_round_%d" % round_number)
		npc_heals += round_npc_casts
		if selected_abi == "ABI301":
			sword_casts += 1
			_check(int(Dictionary(audit.get("applied_effects_by_id", {})).get("EFF301", 0)) <= 1, "engine_sword_bleed_applied_at_most_once_round_%d" % round_number)
		elif selected_abi == "TEST_LAB_HEAL":
			heal_casts += 1
			_check(int(Dictionary(audit.get("applied_effects_by_id", {})).get("EFF004", 0)) >= 1, "engine_regeneration_applied_round_%d" % round_number)
		var ticks: Dictionary = audit.get("periodic_ticks_by_id", {})
		bleed_ticks += int(ticks.get("EFF301", 0))
		regen_ticks += int(ticks.get("EFF004", 0))
		if round_number == 2:
			_check(int(ticks.get("EFF301", 0)) <= 1, "bleeding_does_not_duplicate_next_round")
		if round_number == 3:
			_check(int(ticks.get("EFF004", 0)) >= 1, "regeneration_starts_next_round")
		_check(Array(result.get("lines", [])).size() > 0, "journal_round_%d" % round_number)
		_check(session.state.event_log.size() > previous_logged_events, "journal_grows_round_%d" % round_number)
		previous_logged_events = session.state.event_log.size()
		for trace in Array(audit.get("events", [])):
			var event_id := int(Dictionary(trace).get("id", -1))
			_check(event_id > 0 and not unique_events.has(event_id), "global_event_id_unique_%d_%d" % [round_number, event_id])
			unique_events[event_id] = true
		for combatant in [player, npc]:
			for raw in combatant.active_effects:
				var record: Dictionary = raw
				var effect_id := String(record.get("effect_id", ""))
				_check(int(record.get("remaining_rounds", 0)) > 0, "no_expired_effects_in_state_%d" % round_number)
				if effect_id == "EFF301":
					_check(int(record.get("stacks",0))<=5,"real_bleed_stack_cap_%d" % round_number)
				elif effect_id == "EFF004":
					_check(int(record.get("stacks",0))<=3,"real_heal_stack_cap_%d" % round_number)
		print("ARENA_LONG_BATTLE_ROUND=", round_number, " player_abi=", selected_abi,
			" npc_abi=", round_npc_casts, " bleed_ticks=", ticks.get("EFF301", 0),
			" regen_ticks=", ticks.get("EFF004", 0), " events=", audit.get("event_count", 0))
	_check(sword_casts == 7 and heal_casts == 7, "expected_selected_abi_count")
	_check(npc_heals > 0 and npc_heals <= 10, "npc_automated_heal_schedule")
	_check(bleed_ticks >= 7 and regen_ticks >= 7, "multiple_real_effect_ticks_across_rounds")
	_check(unique_events.size() == session.state.event_log.size(), "canonical_global_event_count")
	_check(session.orchestrator.battle_outcome() == "ongoing", "combat_open_after_twenty_rounds")
