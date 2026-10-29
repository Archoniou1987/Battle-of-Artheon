extends SceneTree

## Stage 1 full-battle vertical slice: genuine ArenaCombatSession -> PAR ->
## physical attack + manual defence + ABI -> CombatEngine/Orchestrator ->
## canonical events -> journal projection -> visible EFF. No UI mocks.
var failures: Array[String] = []

func _check(value: bool, code: String) -> void:
	if not value:
		failures.append(code)
		push_error("FULL_BATTLE_SLICE: " + code)

func _init() -> void:
	var repo := ItemRepository.new()
	var hero := CharacterState.new("FULL_BATTLE_HERO", "Integrated Hero", 10)
	var sword := {
		"instance_id":"FULL_BATTLE_MH", "equip_slots":["main_hand","off_hand"],
		"slot_usage":["main_hand"], "abilities":["ABI003"],
		"par_stats":{"PAR057":1},
		"damage":{"min":3.0,"max":4.0,"type":"slashing"}
	}
	var offhand := {
		"instance_id":"FULL_BATTLE_OH", "equip_slots":["main_hand","off_hand"],
		"slot_usage":["off_hand"], "par_stats":{"PAR057":1},
		"damage":{"min":1.0,"max":2.0,"type":"piercing"}
	}
	for item in [sword, offhand]:
		ItemDurabilityService.initialize_item(item, 100)
		_check(repo.add_item(item), "fixture_item_repository")
		_check(hero.receive_item(String(item["instance_id"]),repo), "fixture_item_ownership")
	_check(hero.equip("main_hand","FULL_BATTLE_MH",repo), "fixture_main_hand")
	_check(hero.equip("off_hand","FULL_BATTLE_OH",repo), "fixture_off_hand")
	if not failures.is_empty():
		_finish()
		return

	var session := ArenaCombatSession.new(hero,repo)
	var player := session.fighter(true)
	var enemy := session.fighter(false)
	player.mana = 100
	player.max_mana = 100
	_check(session.player_attack_count() == 2, "two_independent_weapon_attacks")
	_check(session.player_ability_slots.size() == 5, "five_ability_slots")
	_check(String(session.player_ability_slots[0]) == "ABI003", "main_hand_abi")
	_check(not CombatDiagnostics.combatant_trace(player,0).get("combat_stats",{}).is_empty(), "par_diagnostic_readout")

	var block_count := CombatModifierService.manual_block_zone_capacity(player)
	var blocks: Array[String] = []
	for i in range(block_count):
		blocks.append(["chest","arms","waist","legs"][i])
	var before_hp := player.hp
	var before_mana := player.mana
	var before_round := session.state.round_number
	var rejected := session.play_round(["invalid_zone","legs"],blocks,"ABI003")
	_check(not bool(rejected.get("ok",false)), "invalid_command_rejected")
	_check(player.hp == before_hp and player.mana == before_mana, "rejection_no_resource_mutation")
	_check(session.state.round_number == before_round, "rejection_no_round_consumption")
	_check(session.state.pending_events.is_empty(), "rejection_no_pending_events")
	_check(session.active_round == null, "rejection_does_not_open_round")

	var result := session.play_round(["head","legs"],blocks,"ABI003")
	_check(bool(result.get("ok",false)), "valid_full_round_accepted")
	if not bool(result.get("ok",false)):
		_finish()
		return
	_check(int(result.get("round",0)) == before_round + 1, "exactly_one_round")
	_check(session.active_round == null, "completed_round_not_left_open")
	_check(session.locked_ability_id.is_empty(), "abi_lock_released_at_round_end")
	_check(session.state.pending_events.is_empty(), "no_unresolved_pending_events")
	_check(String(result.get("outcome","")) == session.orchestrator.battle_outcome(), "same_combat_outcome")
	_check(enemy.visible_hp() <= enemy.max_hp and player.visible_hp() <= player.max_hp, "combat_resources_bounded")
	_check(not player.is_death_finalized() or player.visible_hp() == 0, "death_state_consistent")

	var attacks := 0
	var casts := 0
	var physical_indices: Array[int] = []
	var event_ids: Dictionary = {}
	var round_events := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) != session.state.round_number:
			continue
		round_events += 1
		_check(not event_ids.has(event.event_id), "unique_event_id")
		event_ids[event.event_id] = true
		var trace := CombatDiagnostics.event_trace(event)
		_check(int(trace.get("id",-1)) == event.event_id, "diagnostic_event_identity")
		if event.source_id == session.player_id and event.kind == CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)) and not bool(event.payload.get("is_counterattack",false)):
			attacks += 1
			physical_indices.append(int(event.payload.get("weapon_index",-1)))
		if event.source_id == session.player_id and event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("ability_id","")) == "ABI003":
			casts += 1
	var audit: Dictionary = CombatDiagnostics.round_trace(session.state,session.state.round_number)
	_check(bool(audit.get("valid_event_lineage",false)), "engine_event_parentage")
	_check(int(audit.get("event_count",0)) == round_events, "diagnostic_event_reconciliation")
	_check(int(Dictionary(audit.get("weapon_attacks_by_source",{})).get(session.player_id,0)) == 2, "diagnostic_dual_weapon_attacks")
	_check(int(Dictionary(audit.get("abi_casts_by_source",{})).get(session.player_id,0)) == 1, "diagnostic_one_abi")
	_check(round_events > 0, "engine_emitted_events")
	_check(attacks == 2 and physical_indices.has(0) and physical_indices.has(1), "two_weapon_events")
	_check(casts == 1, "single_abi_dispatch")
	var mana_cost := int(AbilityCatalog.definition(session.ability_scheduler.definitions,"ABI003").get("mana_cost",0))
	_check(player.mana == before_mana - mana_cost, "abi_uses_par_resources")

	var journal: Array = Array(result.get("lines",[]))
	var weapon_lines := 0
	var abi_lines := 0
	for line_value in journal:
		var line := String(line_value)
		if line.contains("атакует"):
			weapon_lines += 1
		if line.contains("ABI «Fireball»"):
			abi_lines += 1
	_check(weapon_lines >= 2 and abi_lines == 1, "journal_reconciles_physical_and_abi")

	# The true EFF view is read from the same session. Force two disclosed
	# presentation records only AFTER the combat assertions, without casting
	# or modifying the engine's round resolution.
	enemy.active_effects.append({"effect_id":"FULL_SLICE_BUFF","definition":{"kind":"buff","name":"Defence"},"stacks":2,"remaining_rounds":3,"start_round":session.state.round_number,"revealed":true})
	enemy.active_effects.append({"effect_id":"FULL_SLICE_DEBUFF","definition":{"kind":"debuff","name":"Weakness"},"stacks":1,"remaining_rounds":2,"start_round":session.state.round_number,"revealed":true})
	var effect_view := session.effect_view(false)
	var found_buff := false
	var found_debuff := false
	for raw in Array(effect_view.get("buffs",[])):
		if String(Dictionary(raw).get("id","")) == "FULL_SLICE_BUFF":
			found_buff = true
	for raw in Array(effect_view.get("debuffs",[])):
		if String(Dictionary(raw).get("id","")) == "FULL_SLICE_DEBUFF":
			found_debuff = true
	_check(found_buff, "eff_buff_projection")
	_check(found_debuff, "eff_debuff_projection")

	_finish()

func _finish() -> void:
	for failure in failures:
		print("FULL_BATTLE_SLICE_FAIL=",failure)
	print("FULL_BATTLE_SLICE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
