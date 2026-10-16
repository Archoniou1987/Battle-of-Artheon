extends SceneTree

# Contract smoke test: arena dummy and NPC-style character must use the same
# combatant builder and the arena must delegate rounds to the shared engine.
# This is not a map/encounter integration test.
func _initialize() -> void:
	ArenaCombatSession.training_dummy_clear_defaults = true
	ArenaCombatSession.training_dummy_items.clear()
	var repository := ItemRepository.new()
	var hero := CharacterState.new("PARITY_HERO", "Hero", 1)
	var arena := ArenaCombatSession.new(hero, repository)
	var npc_character := CharacterState.new("PARITY_NPC", "NPC", 1)
	var npc_repository := ItemRepository.new()
	var npc := CharacterCombatBuilder.build(npc_character, npc_repository, {"health": 10000, "mana": 0})
	var dummy := arena.fighter(false)
	var valid := true
	valid = valid and arena.engine is CombatEngine
	valid = valid and arena.orchestrator is RoundOrchestrator
	valid = valid and arena.commands is CombatCommandApi
	valid = valid and arena.state.get_combatant(arena.player_id) != null
	valid = valid and arena.state.get_combatant(ArenaCombatSession.ENEMY_ID) == dummy
	valid = valid and npc is CombatantState
	valid = valid and npc.level == dummy.level
	valid = valid and npc.max_hp == dummy.max_hp
	valid = valid and npc.max_mana == dummy.max_mana
	valid = valid and dummy.combatant_id == ArenaCombatSession.ENEMY_ID
	var round_result: Dictionary = arena.play_round(["chest"], ["chest"])
	valid = valid and bool(round_result.get("ok", false))
	valid = valid and arena.state.round_number == 1
	valid = valid and not arena.state.event_log.is_empty()
	print("ARENA_NPC_CONTRACT_TEST=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
