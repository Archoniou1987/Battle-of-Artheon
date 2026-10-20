extends SceneTree

## Stage 0: genuine Arena round with one weapon, one attack zone and manual
## defence. No mock effects, ABI casts or GUI state. Deterministic input only:
## damage can vary, so assert event lineage rather than a fixed HP delta.
func _init() -> void:
	var ok := _run()
	print("ARENA_BASIC_ROUND_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _run() -> bool:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("BASIC_ROUND_HERO", "Basic Hero", 1)
	var sword := {
		"instance_id":"BASIC_ROUND_SWORD",
		"equip_slots":["main_hand"],
		"slot_usage":["main_hand"],
		"par_stats":{"PAR057":1},
		"damage":{"min":3.0,"max":4.0,"type":"slashing"}
	}
	ItemDurabilityService.initialize_item(sword, 100)
	if not repository.add_item(sword):
		return _fail("item_repository")
	if not hero.receive_item("BASIC_ROUND_SWORD", repository):
		return _fail("item_ownership")
	if not hero.equip("main_hand","BASIC_ROUND_SWORD",repository):
		return _fail("equip_main_hand")
	var arena := ArenaCombatSession.new(hero,repository)
	var player := arena.fighter(true)
	if arena.player_attack_count() != 1:
		return _fail("exactly_one_player_strike")
	if CombatDiagnostics.combatant_trace(player,0).is_empty():
		return _fail("par_readout")
	var block_capacity := CombatModifierService.manual_block_zone_capacity(player)
	if block_capacity < 1 or block_capacity > 4:
		return _fail("block_capacity")
	var blocks: Array[String] = []
	var candidate_zones := ["chest","arms","waist","legs"]
	for index in range(block_capacity):
		blocks.append(String(candidate_zones[index]))
	var before_round := arena.state.round_number
	var before_hp := player.hp
	var invalid := arena.play_round(["invalid_zone"],blocks)
	if bool(invalid.get("ok",false)):
		return _fail("invalid_zone_accepted")
	if arena.state.round_number != before_round or player.hp != before_hp:
		return _fail("rejected_command_modified_state")
	var result := arena.play_round(["head"],blocks)
	if not bool(result.get("ok",false)):
		return _fail("valid_round_rejected_"+String(result.get("reason","unknown")))
	if arena.state.round_number != before_round + 1:
		return _fail("round_counter")
	var weapon_attacks := 0
	var enemy_attacks := 0
	var abi_actions := 0
	for event in arena.state.event_log:
		if int(event.payload.get("round",-1)) != arena.state.round_number:
			continue
		if event.kind == CombatEvent.Kind.ACTION and not String(event.payload.get("ability_id","")).is_empty():
			abi_actions += 1
		if event.kind == CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)) and not bool(event.payload.get("is_counterattack",false)):
			if event.source_id == arena.player_id:
				weapon_attacks += 1
				if String(event.payload.get("zone","")) != "head":
					return _fail("player_attack_zone")
			elif event.source_id == ArenaCombatSession.ENEMY_ID:
				enemy_attacks += 1
	if weapon_attacks != 1 or enemy_attacks < 1:
		return _fail("player_enemy_attack_events_"+str(weapon_attacks)+"_"+str(enemy_attacks))
	if abi_actions != 0:
		return _fail("unexpected_ability_cast")
	if not Array(result.get("lines",[])).is_empty():
		print("BASIC_ROUND_JOURNAL=",result["lines"])
	else:
		return _fail("missing_journal")
	return true

func _fail(reason: String) -> bool:
	push_error("ARENA_BASIC_ROUND_FAIL: "+reason)
	return false
