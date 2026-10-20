extends SceneTree

## Stage 0: the smallest real Arena round. No ABI fixtures or EFF mocks.
## Verifies the wiring Player/NPC -> PAR -> Attack/Defence -> CombatEngine
## -> RoundOrchestrator -> resolved events/journal, before expanding scope.
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("BATTLE_BASELINE: " + label)

func _init() -> void:
	var repository := ItemRepository.new()
	var player := CharacterState.new("BATTLE_BASELINE_HERO","Baseline Hero",5)
	var weapon := {
		"instance_id":"BATTLE_BASELINE_SWORD",
		"equip_slots":["main_hand","off_hand"],
		"slot_usage":["main_hand"],
		"par_stats":{"PAR057":1},
		"damage":{"min":4.0,"max":6.0,"type":"slashing"}
	}
	ItemDurabilityService.initialize_item(weapon,100)
	check(repository.add_item(weapon), "item_added")
	check(player.receive_item("BATTLE_BASELINE_SWORD",repository), "item_owned")
	check(player.equip("main_hand","BATTLE_BASELINE_SWORD",repository), "item_equipped")
	if not failures.is_empty():
		_finish()
		return
	var session := ArenaCombatSession.new(player,repository)
	var actor := session.fighter(true)
	var target := session.fighter(false)
	check(session.state.round_number == 0, "initial_round_zero")
	check(session.player_attack_count() == 1, "one_basic_attack")
	check(not CombatDiagnostics.combatant_trace(actor,0).is_empty(), "PAR_snapshot")
	var capacity: int = CombatModifierService.manual_block_zone_capacity(actor)
	check(capacity >= 1 and capacity <= 4, "manual_block_capacity")
	if capacity < 1 or capacity > 4:
		_finish()
		return
	var chosen_blocks: Array[String] = []
	for i in range(capacity):
		chosen_blocks.append(["chest","arms","waist","legs"][i])
	var before_hp := actor.hp
	var invalid := session.play_round(["not_a_zone"],chosen_blocks)
	check(not bool(invalid.get("ok",false)), "invalid_attack_rejected")
	check(session.state.round_number == 0 and actor.hp == before_hp, "invalid_attack_atomic")
	var result := session.play_round(["legs"],chosen_blocks)
	check(bool(result.get("ok",false)), "basic_round_accepted")
	if not bool(result.get("ok",false)):
		print("BATTLE_BASELINE_REJECT_REASON=",result.get("reason","unknown"))
		_finish()
		return
	check(session.state.round_number == 1, "round_advanced_once")
	check(String(result.get("outcome","")) == session.orchestrator.battle_outcome(), "engine_outcome_matches")
	check(actor.visible_hp() <= actor.max_hp and target.visible_hp() <= target.max_hp, "HP_bounds")
	var physical_count := 0
	var opponent_physical_count := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) != 1:
			continue
		if event.kind != CombatEvent.Kind.ATTACK or not bool(event.payload.get("is_weapon_attack",false)):
			continue
		if event.source_id == session.player_id and not bool(event.payload.get("is_counterattack",false)):
			physical_count += 1
		elif event.source_id == ArenaCombatSession.ENEMY_ID:
			opponent_physical_count += 1
	check(physical_count == 1, "one_player_weapon_event")
	check(opponent_physical_count >= 1, "enemy_attack_event")
	check(Array(result.get("lines",[])).size() >= 2, "both_sides_in_journal")
	_finish()

func _finish() -> void:
	for failure in failures:
		print("BATTLE_BASELINE_FAIL=",failure)
	print("BATTLE_BASELINE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
