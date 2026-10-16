extends SceneTree

## PAR010, PAR015/016: persistent current pools and one end-of-round
## regeneration boundary shared by Arena, duel and group combat.
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _initialize() -> void:
	equipment_and_persistence()
	round_regeneration()
	npc_regeneration()
	arena_regeneration()
	duel_regeneration()
	group_regeneration()
	for failure in failures:
		push_error(failure)
	print("PAR_RESOURCE_LIFECYCLE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func equip_ring(character: CharacterState, repository: ItemRepository, item_id: String, stats: Dictionary) -> bool:
	var item := {
		"instance_id": item_id,
		"equip_slots": ["ring1"],
		"slot_usage": ["ring1"],
		"par_stats": stats.duplicate(true)
	}
	ItemDurabilityService.initialize_item(item, 100)
	return repository.add_item(item) and character.receive_item(item_id, repository) and character.equip("ring1", item_id, repository)

func equipment_and_persistence() -> void:
	var hero := CharacterState.new("resource_equipment", "Resource equipment")
	var repo := ItemRepository.new()
	var original := hero.resource_snapshot(repo)
	check(original.get("hp") == original.get("max_hp"), "initial HP starts full")
	check(original.get("mana") == original.get("max_mana"), "initial mana starts full")
	var initial_hp: int = int(original.get("max_hp", 0))
	var initial_mana: int = int(original.get("max_mana", 0))
	hero.current_hp = 100
	hero.current_mana = 20
	check(equip_ring(hero, repo, "resource_ring", {"PAR010":5000, "PAR011":300}), "equip PAR010/011 ring")
	var with_ring := hero.resource_snapshot(repo)
	check(int(with_ring.get("max_hp", -1)) == initial_hp + 5000, "PAR010 increases max HP")
	check(int(with_ring.get("max_mana", -1)) == initial_mana + 300, "PAR011 increases max mana")
	check(int(with_ring.get("hp", -1)) == 100, "PAR010 never heals current HP")
	check(int(with_ring.get("mana", -1)) == 20, "PAR011 never restores current mana")
	var fighter := CharacterCombatBuilder.build(hero, repo)
	check(fighter != null, "resource equipment combat build")
	if fighter != null:
		check(fighter.hp == 100 and fighter.max_hp == initial_hp + 5000, "UI/combat agree on current HP after equip")
		check(fighter.mana == 20 and fighter.max_mana == initial_mana + 300, "combat snapshot preserves mana")
	hero.current_hp = 4900
	hero.current_mana = 250
	check(hero.unequip("ring1", repo) == "resource_ring", "unequip PAR010/011 ring")
	check(hero.current_hp == initial_hp and hero.current_mana == initial_mana, "resource cap applies immediately on unequip")
	var without_ring := hero.resource_snapshot(repo)
	check(int(without_ring.get("hp", -1)) == initial_hp, "HP clamps to lower max after unequip")
	check(int(without_ring.get("mana", -1)) == initial_mana, "mana clamps to lower max after unequip")
	hero.current_hp = 88
	hero.current_mana = 17
	var saved := hero.resources_to_dict()
	var loaded := CharacterState.new("resource_restored", "Restored")
	check(loaded.restore_resources(saved), "restore valid current resources")
	var restored := loaded.resource_snapshot(ItemRepository.new())
	check(int(restored.get("hp", -1)) == 88 and int(restored.get("mana", -1)) == 17, "current resources persist independently")
	check(not loaded.restore_resources({"hp":-1,"mana":0}), "reject negative saved HP")
	check(not loaded.restore_resources({"hp":1.5,"mana":0}), "reject fractional saved HP")
	var test_override := CharacterCombatBuilder.build(loaded, ItemRepository.new(), {"health":10000,"mana":0})
	check(test_override != null, "explicit test pool override builds")
	if test_override != null:
		check(test_override.hp == 10000 and test_override.max_hp == 10000 and test_override.mana == 0, "test dummy overrides stay full")

func regen_fighter(id: String, hp_regen: float, mana_regen: float) -> CombatantState:
	var hero := CharacterState.new(id, id)
	var repo := ItemRepository.new()
	check(equip_ring(hero, repo, id + "_ring", {"PAR013":99.0, "PAR015":mana_regen, "PAR016":hp_regen}), "equip regen ring " + id)
	return CharacterCombatBuilder.build(hero, repo)

func round_regeneration() -> void:
	var fighter := regen_fighter("round_regen", 5.0, 7.0)
	check(fighter != null, "PAR015/016 hero combat build")
	if fighter == null:
		return
	check(is_equal_approx(float(fighter.combat_stats.get("hp_regen_round", -1)), 5.0), "PAR016 maps to round HP rate")
	check(is_equal_approx(float(fighter.combat_stats.get("mana_regen_round", -1)), 7.0), "PAR015 maps to round mana rate")
	fighter.hp = 90
	fighter.mana = 2
	var state := CombatState.new()
	state.add_combatant(fighter)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(state))
	orchestrator.begin_round()
	check(fighter.hp == 95 and fighter.mana == 9, "start-round PAR015/016 before actions, PAR013 excluded")
	orchestrator.end_round()
	check(fighter.hp == 95 and fighter.mana == 9, "end-round must not regenerate a second time")
	orchestrator.begin_round()
	check(fighter.hp == 100 and fighter.mana == 16, "second-round regen already applied at opening")
	orchestrator.end_round()
	check(fighter.hp == 100 and fighter.mana == 16, "no extra regeneration at second-round close")
	fighter.hp = fighter.max_hp - 1
	fighter.mana = fighter.max_mana - 1
	orchestrator.begin_round()
	orchestrator.end_round()
	check(fighter.hp == fighter.max_hp and fighter.mana == fighter.max_mana, "regeneration never exceeds maximum")
	fighter.hp = 90
	fighter.mana = 0
	fighter.active_effects.append({
		"definition":{"hp_regen_round":3.0,"mana_regen_round":4.0},
		"start_round":state.round_number + 1,"remaining_rounds":1
	})
	orchestrator.begin_round()
	check(fighter.hp == 98 and fighter.mana == 11, "runtime EFF regenerates at start of active round")
	orchestrator.end_round()
	check(fighter.hp == 98 and fighter.mana == 11, "runtime EFF does not regenerate on round close")
	orchestrator.begin_round()
	orchestrator.end_round()
	check(fighter.hp == 103 and fighter.mana == 18, "expired regen effect does not persist")
	fighter.hp = -10
	fighter.mana = 0
	orchestrator.begin_round()
	check(fighter.hp == -10 and fighter.mana == 0, "no regeneration for lethally wounded fighter at round opening")
	var outcome := orchestrator.end_round()
	check(fighter.hp == -10 and fighter.mana == 0, "passive regen cannot rescue lethal HP")
	check(fighter.is_death_finalized() and Array(outcome.get("dead_ids", [])).has(fighter.combatant_id), "death finalization unchanged")

func npc_regeneration() -> void:
	var totals := {"PAR052":0.0,"PAR057":1.0,"PAR073":1.0,"PAR015":7.0,"PAR016":5.0}
	for par_id in ParCombatContract.RATINGS:
		totals[par_id] = 0.0
	var npc := NpcState.new({
		"id":"npc_round_regen", "name":"NPC regen", "level":1,
		"base":{
			"health":100, "mana":40,
			"par_totals":totals,
			"par_attack_ranges":{"PAR050":{"min":2.0,"max":4.0,"type":"blunt"}},
			"combat_stats":{"weapon_profiles":[{"slot":"main_hand","damage_min":2.0,"damage_max":4.0,"damage_type":"blunt"}]}
		}
	})
	var actor := NpcCombatBuilder.build(npc)
	check(actor != null, "NPC round regen PAR contract")
	if actor == null:
		return
	check(is_equal_approx(float(actor.combat_stats.get("hp_regen_round", -1)), 5.0), "NPC PAR016 adapter")
	check(is_equal_approx(float(actor.combat_stats.get("mana_regen_round", -1)), 7.0), "NPC PAR015 adapter")
	actor.hp = 50
	actor.mana = 0
	var state := CombatState.new()
	state.add_combatant(actor)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(state))
	orchestrator.begin_round()
	orchestrator.end_round()
	check(actor.hp == 55 and actor.mana == 7, "NPC restores HP/mana once per opening round")

func arena_regeneration() -> void:
	var hero := CharacterState.new("arena_resource_player", "Arena resources")
	var repo := ItemRepository.new()
	check(equip_ring(hero, repo, "arena_regen_ring", {"PAR015":4.0, "PAR016":6.0}), "arena equip regen")
	var arena := ArenaCombatSession.new(hero, repo)
	var player := arena.fighter(true)
	var enemy := arena.fighter(false)
	player.hp = 70
	player.mana = 0
	player.tempo = -100.0
	enemy.tempo = -100.0
	var result := arena.play_round(["chest"], ["chest", "arms"])
	check(bool(result.get("ok", false)), "stunned arena round completes")
	check(player.hp == 76 and player.mana == 4, "Arena applies PAR015/016 once despite stun")

func duel_regeneration() -> void:
	var one := regen_fighter("duel_regen_one", 3.0, 4.0)
	var two := regen_fighter("duel_regen_two", 2.0, 5.0)
	if one == null or two == null:
		return
	one.hp = 60
	one.mana = 0
	two.hp = 55
	two.mana = 0
	one.tempo = -100.0
	two.tempo = -100.0
	var state := CombatState.new()
	state.add_combatant(one)
	state.add_combatant(two)
	var simulator := CombatSimulator.new(state)
	simulator.max_rounds = 1
	simulator.run_duel(one.combatant_id, two.combatant_id)
	check(state.round_number == 1, "duel exactly one round")
	check(one.hp == 63 and one.mana == 4, "duel PAR015/016 once for first actor")
	check(two.hp == 57 and two.mana == 5, "duel PAR015/016 once for second actor")

func group_regeneration() -> void:
	var one := regen_fighter("group_regen_one", 3.0, 4.0)
	var two := regen_fighter("group_regen_two", 2.0, 5.0)
	if one == null or two == null:
		return
	one.hp = 60
	one.mana = 0
	two.hp = 55
	two.mana = 0
	one.tempo = -100.0
	two.tempo = -100.0
	var state := CombatState.new()
	state.add_combatant(one)
	state.add_combatant(two)
	var groups := GroupCombatState.new(state)
	groups.add_member("A", one.combatant_id)
	groups.add_member("B", two.combatant_id)
	var simulator := GroupCombatSimulator.new(state, groups)
	var result := simulator.run_round()
	check(bool(result.get("ok", false)), "group round resolved")
	check(one.hp == 63 and one.mana == 4, "group PAR015/016 once for first actor")
	check(two.hp == 57 and two.mana == 5, "group PAR015/016 once for second actor")
