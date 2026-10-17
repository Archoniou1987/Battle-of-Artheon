extends SceneTree

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func equip(character: CharacterState, repo: ItemRepository, id: String, slot: String, fields: Dictionary) -> void:
	var item := {"instance_id":id, "equip_slots":[slot], "slot_usage":[slot]}
	item.merge(fields, true)
	ItemDurabilityService.initialize_item(item, 100)
	check(repo.add_item(item), id + " add")
	check(character.receive_item(id, repo), id + " receive")
	check(character.equip(slot, id, repo), id + " equip")

func _initialize() -> void:
	var hero := CharacterState.new("par_hero", "PAR Hero")
	var repo := ItemRepository.new()
	check(hero.allocate_stat("PAR001"), "allocate canonical stat")
	check(hero.progression.save_pending_stats(), "commit primary allocation")
	var unarmed := ParCalculationService.calculate(hero, repo)
	check(float(unarmed.attack_ranges.PAR050.min) == 2 and float(unarmed.attack_ranges.PAR050.max) == 4 and unarmed.attack_ranges.PAR050.type == "blunt", "configured unarmed PAR050")
	check(unarmed.totals.PAR052 == 2 and unarmed.totals.PAR057 == 1, "unarmed bonus/count")
	var fist := CharacterCombatBuilder.build(hero, repo)
	check(bool(ParAttackContract.validate(fist).ok), "unarmed mandatory combat contract")
	check(WeaponAttackProfile.all(fist)[0].damage_min == 4, "unarmed bonus once")
	equip(hero, repo, "ring", "ring1", {"par_stats":{"PAR001":3,"PAR033":100,"PAR101":20,"PAR110":7}})
	equip(hero, repo, "sword", "main_hand", {"slot":"off_hand", "damage":{"min":10,"max":12,"type":"slashing"}, "par_stats":{"PAR057":1}})
	equip(hero, repo, "dagger", "off_hand", {"slot":"main_hand", "damage":{"min":3,"max":5,"type":"piercing"}, "par_stats":{"PAR057":1}})
	var par := ParCalculationService.calculate(hero, repo)
	check(par.totals.PAR001 == 5 and par.totals.PAR052 == 5, "primary equipment bonus and derivation once")
	check(par.totals.PAR057 == 2, "dual weapon count")
	check(par.attack_ranges.PAR050.min == 10 and par.attack_ranges.PAR051.min == 3, "actual equipped hands override template preference")
	var view := CharacterStatsService.snapshot(hero, repo)
	check(view.main_hand_damage == [15.0,17.0] and view.off_hand_damage == [8.0,10.0], "UI uses both canonical ranges")
	var fighter := CharacterCombatBuilder.build(hero, repo)
	check(fighter.armour.chest.slashing == 27 and fighter.armour.chest.blunt == 20, "general and typed PAR armour once")
	check(fighter.combat_stats.crit_chance_rating == 110, "primary and equipment critical rating once")
	# Stale runtime numeric profiles must not override mandatory PAR ranges.
	fighter.combat_stats.weapon_profiles[0].damage_min = 999
	fighter.combat_stats.weapon_profiles[0].damage_max = 999
	check(WeaponAttackProfile.all(fighter)[0].damage_min == 15, "no old profile damage fallback")
	var state := CombatState.new()
	state.add_combatant(fighter)
	var target := CharacterCombatBuilder.build(CharacterState.new("target", "Target"), ItemRepository.new(), {"health":1000})
	state.add_combatant(target)
	var group := GroupCombatState.new(state)
	group.add_member("A", fighter.combatant_id)
	group.add_member("B", target.combatant_id)
	group.set_active_opponent(fighter.combatant_id, target.combatant_id)
	group.set_active_opponent(target.combatant_id, fighter.combatant_id)
	var zones := CombatZoneState.new(group)
	zones.set_zone(fighter.combatant_id, CombatZoneState.ZONE_2)
	zones.set_zone(target.combatant_id, CombatZoneState.ZONE_2)
	var orchestrator := RoundOrchestrator.new(state, CombatEngine.new(TestFixtureLoader.canonicalize_state(state)), group, zones)
	var api := CombatCommandApi.new(state, group, zones, orchestrator)
	orchestrator.begin_round()
	var requests: Array[Dictionary] = [{"weapon_index":0,"attack_profile_id":"basic"},{"weapon_index":1,"attack_profile_id":"basic"}]
	var queued := api.queue_weapon_attack_sequence(fighter.combatant_id, requests)
	check(bool(queued.ok) and queued.event_ids.size() == 2, "valid ABI001 dual sequence")
	check(state.pending_events[0].payload.source_par == "PAR050" and state.pending_events[1].payload.source_par == "PAR051", "events identify mandatory PAR sources")
	state.pending_events.clear()
	var saved_range: Dictionary = fighter.combat_stats.par_attack_ranges.PAR051.duplicate(true)
	fighter.combat_stats.par_attack_ranges.erase("PAR051")
	check(not bool(ParAttackContract.validate(fighter).ok), "missing OH range diagnosed")
	var previous_print_errors := Engine.print_error_messages
	Engine.print_error_messages = false # Negative cases deliberately request diagnostic rejection.
	var rejected := api.queue_weapon_attack_sequence(fighter.combatant_id, requests)
	Engine.print_error_messages = previous_print_errors
	check(not bool(rejected.ok) and state.pending_events.is_empty(), "missing OH rejects whole sequence atomically")
	fighter.combat_stats.par_attack_ranges.PAR051 = saved_range
	check(not bool(ParAttackContract.resolve(fighter, {"weapon_index":0,"hit_count":2}).ok), "ABI001 cannot synthesize multiple hits from one weapon")
	var off_id: String = fighter.combat_stats.weapon_profiles[1].instance_id
	fighter.combat_stats.weapon_profiles[1].instance_id = fighter.combat_stats.weapon_profiles[0].instance_id
	check(not bool(ParAttackContract.validate(fighter).ok), "dual wield requires two distinct weapon instances")
	fighter.combat_stats.weapon_profiles[1].instance_id = off_id
	fighter.combat_stats.par_totals.erase("PAR052")
	check(not bool(ParAttackContract.validate(fighter).ok), "missing physical bonus is an error, never zero fallback")
	fighter.combat_stats.par_totals.PAR052 = 5
	fighter.combat_stats.par_totals.PAR057 = 1
	check(not bool(ParAttackContract.validate(fighter).ok), "two profiles cannot bypass PAR057")
	fighter.combat_stats.par_totals.PAR057 = 0
	check(not bool(ParAttackContract.validate(fighter).ok), "zero count cannot clamp silently to one")
	fighter.combat_stats.par_totals.PAR057 = 2
	var round := CombatRound.new(1)
	CombatAttackPipeline.new(state, 7).lock_basic_attack(round, fighter, target)
	check(round.locked_actions.size() == 2, "simulator uses same canonical dual sequence")
	for event in round.locked_actions:
		check(float(event.payload.damage_max) < 100, "simulator ignores stale 999 damage")
	# Save/reload preserves canonical item contributions and rejects mixed primary schemas.
	var restored := CharacterState.new("par_hero", "Restored")
	check(restored.restore_progression(hero.progression_snapshot()), "restore canonical progression")
	var restored_repo := ItemRepository.from_dict(repo.to_dict())
	restored.equipment.slots = hero.equipment.slots.duplicate(true)
	check(ParCalculationService.calculate(restored, restored_repo).totals == par.totals, "repository restart reproduces all PAR totals")
	var mixed := hero.progression_snapshot()
	mixed.base_stats["obsolete_primary"] = 1
	check(not restored.restore_progression(mixed), "mixed-schema save rejected")
	var generator := ItemGenerator.new(42)
	var generated := generator.generate({"id":"local_generator_only", "equip_slots":["main_hand"], "damage_min":4,"damage_max":6,"par_stats":{"PAR001":2}}, "purple")
	var generated_repo := ItemRepository.new()
	check(generated_repo.add_item(generated) and not generated_repo.get_item(generated.instance_id).is_empty(), "generated materialized instance does not resolve arena template")
	check(not generated.has("template_id") and generated.par_stats.PAR057 == 1, "generator provenance and attack count")
	var broken_hero := CharacterState.new("broken_metadata", "Broken")
	var broken_repo := ItemRepository.new()
	equip(broken_hero, broken_repo, "invalid_weapon", "main_hand", {"type":"weapon"})
	Engine.print_error_messages = false
	check(ParCalculationService.calculate(broken_hero, broken_repo).is_empty(), "declared weapon cannot become unarmed when damage is missing")
	Engine.print_error_messages = previous_print_errors
	for error in failures:
		push_error(error)
	print("PAR_MIGRATION_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
