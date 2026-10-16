extends SceneTree

# Compare the arena dummy against an NPC-style CharacterCombatBuilder combatant.
# Same combatants, commands and RNG seed must yield the same engine events.
# Map encounter transitions are intentionally outside this contract.
func _initialize() -> void:
	ArenaCombatSession.training_dummy_clear_defaults = true
	ArenaCombatSession.training_dummy_items.clear()
	var arena := _session()
	var npc_session := _session()
	var npc_character := CharacterState.new(ArenaCombatSession.ENEMY_ID, "Тренировочный противник", 1)
	var npc_repository := ItemRepository.new()
	var npc := CharacterCombatBuilder.build(npc_character, npc_repository, {"health": 10000, "mana": 0})
	var dummy := arena.fighter(false)
	var valid := arena.engine is CombatEngine and npc_session.engine is CombatEngine
	valid = valid and arena.commands is CombatCommandApi and npc_session.commands is CombatCommandApi
	valid = valid and npc.level == dummy.level and npc.max_hp == dummy.max_hp and npc.max_mana == dummy.max_mana
	valid = valid and JSON.stringify(npc.stats) == JSON.stringify(dummy.stats)
	valid = valid and JSON.stringify(npc.combat_stats) == JSON.stringify(dummy.combat_stats)
	npc_session.state.combatants[ArenaCombatSession.ENEMY_ID] = npc
	arena.engine.combat_rng.seed = 20261016
	npc_session.engine.combat_rng.seed = 20261016
	for round_index in range(2):
		var a: Dictionary = arena.play_round(["chest"], ["chest"])
		var b: Dictionary = npc_session.play_round(["chest"], ["chest"])
		valid = valid and bool(a.get("ok", false)) and bool(b.get("ok", false))
		valid = valid and JSON.stringify(a) == JSON.stringify(b)
		valid = valid and _event_signature(arena.state) == _event_signature(npc_session.state)
		valid = valid and arena.fighter(true).visible_hp() == npc_session.fighter(true).visible_hp()
		valid = valid and arena.fighter(false).visible_hp() == npc_session.fighter(false).visible_hp()
		if not valid:
			break
	valid = valid and arena.state.round_number == 2 and not arena.state.event_log.is_empty()
	print("ARENA_NPC_PARITY_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _session() -> ArenaCombatSession:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("PARITY_HERO", "Hero", 1)
	return ArenaCombatSession.new(hero, repository)

func _event_signature(state: CombatState) -> String:
	var signature: Array[Dictionary] = []
	for event in state.event_log:
		signature.append({
			"kind": int(event.kind),
			"source": event.source_id,
			"target": event.target_id,
			"payload": event.payload,
			"result": event.result
		})
	return JSON.stringify(signature)
