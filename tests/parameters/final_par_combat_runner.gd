extends SceneTree

var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)

func put(hero: CharacterState, repo: ItemRepository, id: String, slot: String, extra: Dictionary) -> void:
	var item := {"instance_id":id, "equip_slots":[slot], "slot_usage":[slot]}
	item.merge(extra, true)
	ItemDurabilityService.initialize_item(item, 100)
	check(repo.add_item(item) and hero.receive_item(id, repo) and hero.equip(slot, id, repo), "equip " + id)

func weapon(minimum: float, kind: String = "slashing") -> Dictionary:
	return {"type":"weapon", "damage":{"min":minimum,"max":minimum,"type":kind}, "par_stats":{"PAR057":1}}

func _initialize() -> void:
	weapon_cases()
	shared_combat_cases()
	npc_level_cases()
	stun_cases()
	for message in errors:
		push_error(message)
	print("FINAL_PAR_COMBAT_TEST=", "PASS" if errors.is_empty() else "FAIL", " failures=", errors.size())
	quit(0 if errors.is_empty() else 1)

func weapon_cases() -> void:
	for mode in ["fists", "mh", "oh", "dual", "two_handed", "broken_mh", "broken_oh"]:
		var hero := CharacterState.new("hero_" + mode, "Hero")
		var repo := ItemRepository.new()
		if mode in ["mh", "dual", "two_handed", "broken_mh"]:
			var item := weapon(10)
			if mode == "two_handed":
				item["slot_usage"] = ["main_hand", "off_hand"]
			put(hero, repo, "mh_" + mode, "main_hand", item)
		if mode in ["oh", "dual", "broken_oh"]:
			var dagger := weapon(5, "piercing")
			dagger["on_hit_effect"] = {"effect_id":"EFF001", "chance":100}
			put(hero, repo, "oh_" + mode, "off_hand", dagger)
		if mode == "broken_mh":
			var broken := repo.get_item("mh_" + mode)
			broken["durability_current"] = 0
			repo.update_item(broken)
		if mode == "broken_oh":
			var broken := repo.get_item("oh_" + mode)
			broken["durability_current"] = 0
			repo.update_item(broken)
		if mode == "two_handed":
			var forbidden := weapon(5, "piercing")
			forbidden.merge({"instance_id":"forbidden_oh","equip_slots":["off_hand"],"slot_usage":["off_hand"]})
			ItemDurabilityService.initialize_item(forbidden, 100)
			repo.add_item(forbidden)
			hero.receive_item("forbidden_oh", repo)
			# EquipmentState refuses the occupied OH. Atomic replacement is a separate supported operation.
			check(not hero.equip("off_hand", "forbidden_oh", repo), "2H reserves OH through the character API")
		var fighter := CharacterCombatBuilder.build(hero, repo)
		check(fighter != null, mode + " build")
		if fighter == null:
			continue
		var expected_count := 2 if mode in ["oh", "dual"] else 1
		check(fighter.combat_stats.par_totals.PAR057 == expected_count, mode + " PAR057")
		var profiles := WeaponAttackProfile.all(fighter)
		check(profiles.size() == expected_count, mode + " profile count")
		check(profiles[0].weapon_index == 0 and fighter.combat_stats.weapon_profiles[0].slot == "main_hand", mode + " MH first")
		var view := CharacterStatsService.snapshot(hero, repo)
		check(profiles[0].damage_min == view.main_hand_damage[0], mode + " UI damage matches combat")
		if mode in ["fists", "oh", "broken_mh", "broken_oh"]:
			check(profiles[0].damage_min == 3 and profiles[0].damage_max == 5 and profiles[0].damage_type == "blunt", mode + " fist 2-4 plus PAR052 exactly once")
		if mode in ["oh", "dual"]:
			check(profiles[1].weapon_index == 1 and profiles[1].damage_min == 6, mode + " OH index and damage")
			var trigger: Dictionary = fighter.combat_stats.weapon_on_hit_effects[0]
			check(trigger.weapon_index == 1 and trigger.source_instance_id == "oh_" + mode, mode + " OH trigger keeps weapon ownership")
			var state := CombatState.new()
			state.add_combatant(fighter)
			var target := CharacterCombatBuilder.build(CharacterState.new("target_" + mode, "Target"), ItemRepository.new())
			state.add_combatant(target)
			var engine := CombatEngine.new(state)
			var parent := state.create_event(CombatEvent.Kind.ATTACK, fighter.combatant_id, target.combatant_id, {"weapon_index":0})
			engine._trigger_weapon_on_hit(parent, fighter, target, {"on_hit_effect":1})
			check(state.pending_events.is_empty(), mode + " OH effect never belongs to MH")
			parent.payload.weapon_index = 1
			engine._trigger_weapon_on_hit(parent, fighter, target, {"on_hit_effect":1})
			check(state.pending_events.size() == 1, mode + " OH effect triggers on OH")
			fighter.combat_stats.weapon_profiles[1].is_unarmed = true
			check(not bool(ParAttackContract.validate(fighter).ok), "OH cannot masquerade as a virtual fist")

func shared_combat_cases() -> void:
	var hero := CharacterState.new("caster", "Caster")
	var repo := ItemRepository.new()
	put(hero, repo, "rating_ring", "ring1", {"combat_stats":{"hit_chance_direct_pct":2},"par_stats":{"PAR030":10,"PAR033":500,"PAR035":100,"PAR075":100,"PAR150":100}})
	var fighter := CharacterCombatBuilder.build(hero, repo)
	var view := CharacterStatsService.snapshot(hero, repo)
	check(view.hit_chance_rating == 15 and is_equal_approx(view.hit_chance_rating_percent, 5), "primary and equipment hit sum before matrix")
	check(view.crit_damage_rating == 105 and is_equal_approx(view.crit_damage_rating_percent, 21), "PAR035 is a rating")
	check(view.counterattack_rating == 105 and is_equal_approx(view.counterattack_rating_percent, 21), "PAR075 is a rating, never direct percent")
	check(view.magic_damage_rating == 105 and is_equal_approx(view.magic_damage_rating_percent, 21), "PAR150 is a rating")
	var direct := CharacterStatsService.snapshot(hero, repo, {"magic_damage_direct_pct":7})
	check(is_equal_approx(direct.magic_damage_rating_percent, 28), "direct percentage is added after conversion")
	var target := CharacterCombatBuilder.build(CharacterState.new("target", "Target"), ItemRepository.new(), {"health":2000})
	var state := CombatState.new()
	state.add_combatant(fighter)
	state.add_combatant(target)
	state.begin_round()
	var engine := CombatEngine.new(state)
	var observed: Array[CombatEvent] = []
	for magic in [false, true]:
		var payload := {"raw_damage":10.0,"damage_type":"fire" if magic else "slashing","uses_magic_hit":magic,"magic_hit_roll":1,"rolls":{"hit":1,"crit":1,"dodge":100}}
		var attack := state.create_event(CombatEvent.Kind.ATTACK, "caster", "target", payload)
		state.queue_event(attack)
		engine.resolve_pending_events()
		observed.append(attack)
	check(observed[0].result.hit_chance == 100 and observed[1].result.hit_chance == 100, "one PAR030 and one approved hit baseline for both attack types")
	check(bool(observed[0].result.critical) and bool(observed[1].result.critical), "PAR033 critical applies to physical and magical attacks")
	check(is_equal_approx(observed[0].result.raw_damage, 17.1), "existing 1.5 crit plus PAR035 percentage points")
	check(is_equal_approx(observed[1].result.raw_damage, 20.691), "weapon magic PAR150 and PAR035 each apply once")
	var action := AbilityRuntime.build_action_event(state, "caster", "target", "AUDIT_PROJECTILE", {"delivery_type":"PROJECTILE","uses_magic_hit":true,"magic_hit_roll":1,"rolls":{"crit":1},"components":[{"kind":"damage","amount":10.0,"damage_type":"fire"}]})
	state.queue_event(action)
	engine.resolve_pending_events()
	var child: CombatEvent = null
	for event in state.event_log:
		if event.parent_event_id == action.event_id and event.kind == CombatEvent.Kind.ATTACK:
			child = event
	check(child != null, "ABI projectile creates an attack")
	if child != null:
		check(bool(child.payload.uses_magic_hit) and bool(child.payload.hit_already_resolved), "ABI preserves magic routing and does not reroll hit")
		check(is_equal_approx(child.result.raw_damage, 20.691), "ABI magic percent is not applied twice")
	var zero := engine._make_action_component_event(action, {"kind":"damage","amount":0,"damage_type":"fire"}, "target", 1)
	check(zero.payload.raw_damage == 0, "PAR150 never creates flat damage from zero")
	var group := GroupCombatState.new(state)
	group.add_member("A", "caster")
	group.add_member("B", "target")
	group.set_active_opponent("caster", "target")
	var zones := CombatZoneState.new(group)
	zones.set_zone("caster", CombatZoneState.ZONE_2)
	zones.set_zone("target", CombatZoneState.ZONE_2)
	var api := CombatCommandApi.new(state, group, zones, RoundOrchestrator.new(state, engine, group, zones))
	for id in ParCombatContract.RATINGS:
		var saved: Variant = fighter.combat_stats.par_totals[id]
		fighter.combat_stats.par_totals.erase(id)
		check(not bool(ParCombatContract.validate(fighter).ok), "diagnose missing " + id)
		var old_print := Engine.print_error_messages
		Engine.print_error_messages = false
		var result := api.queue_default_weapon_attacks("caster")
		var bad := state.create_event(CombatEvent.Kind.ATTACK, "caster", "target", {"raw_damage":999,"rolls":{"hit":1}})
		engine.resolve_event(bad)
		Engine.print_error_messages = old_print
		check(not bool(result.ok) and state.pending_events.is_empty(), "no partial queue without " + id)
		check(bad.result.get("outcome") == "invalid_par_contract", "engine rejects missing " + id)
		fighter.combat_stats.par_totals[id] = saved

	for key in ParCombatContract.RATINGS.values():
		var field: String = key + "_percent"
		var saved: Variant = fighter.combat_stats[field]
		fighter.combat_stats.erase(field)
		check(not bool(ParCombatContract.validate(fighter).ok), "converted rating cannot default to zero: " + field)
		fighter.combat_stats[field] = saved
	fighter.combat_stats.hit_chance_rating += 1
	check(not bool(ParCombatContract.validate(fighter).ok), "semantic rating cannot diverge from PAR source")
	fighter.combat_stats.hit_chance_rating -= 1
	fighter.active_effects.append({"definition":{"magic_damage_direct_pct":NAN},"start_round":state.round_number,"remaining_rounds":1})
	var saved_print := Engine.print_error_messages
	Engine.print_error_messages = false
	var invalid := state.create_event(CombatEvent.Kind.ATTACK, "caster", "target", {"raw_damage":999,"rolls":{"hit":1}})
	engine.resolve_event(invalid)
	Engine.print_error_messages = saved_print
	check(invalid.result.get("outcome") == "invalid_par_contract" and state.pending_events.is_empty(), "non-finite runtime overlay cannot enter damage")
	fighter.active_effects.clear()

func npc_level_cases() -> void:
	var totals := {"PAR052":0,"PAR057":1,"PAR073":1}
	for id in ParCombatContract.RATINGS:
		totals[id] = 100
	var npc := NpcState.new({"id":"audit_npc","name":"NPC","level":1,"base":{"health":100,"mana":0,"par_totals":totals,"par_attack_ranges":{"PAR050":{"min":2,"max":4,"type":"blunt"}},"combat_stats":{"weapon_profiles":[{"slot":"main_hand","damage_min":2,"damage_max":4,"damage_type":"blunt"}]}}})
	check(is_equal_approx(NpcCombatBuilder.build(npc).combat_stats.crit_chance_rating_percent, 20), "NPC template-level rating")
	var repo := NpcRepository.new()
	repo.add(npc)
	var instance := NpcInstance.new("audit_npc_instance", npc)
	instance.level = 100
	var player := CharacterCombatBuilder.build(CharacterState.new("npc_test_player", "Player"), ItemRepository.new())
	var session := MapEncounterCombatService.begin({"ok":true,"npcs":[instance]}, repo, player)
	check(bool(session.ok) and session.enemy.level == 100 and is_equal_approx(session.enemy.combat_stats.crit_chance_rating_percent, 2.5), "NPC instance level owns its RatingMatrix conversion")

func stun_cases() -> void:
	var hero := CharacterState.new("stunned", "Stunned")
	var session := ArenaCombatSession.new(hero, ItemRepository.new())
	var fighter := session.fighter(true)
	fighter.tempo = -100
	check(not bool(session.commands.queue_default_weapon_attacks(fighter.combatant_id).ok) and session.state.pending_events.is_empty(), "stun rejects command attacks before queue mutation")
	var scheduler := AbilityScheduler.new({"STUN_TEST":{"mana_cost":3,"components":[{"kind":"damage","amount":10,"damage_type":"fire"}]}}, {fighter.combatant_id:["STUN_TEST"]})
	var mana := fighter.mana
	check(scheduler.cast_event(session.state, fighter.combatant_id, session.ENEMY_ID, "STUN_TEST") == null and fighter.mana == mana, "stun rejects ABI before charging mana")
	check(scheduler.ready_events(session.state, fighter.combatant_id, session.ENEMY_ID).is_empty(), "stun rejects scheduled ABI")
	var result := session.play_round(["head"], ["head", "chest"])
	check(bool(result.ok) and session.state.round_number == 1, "stunned arena player can still end the round")
	var attacks := 0
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and event.source_id == fighter.combatant_id:
			attacks += 1
	check(attacks == 0, "stun suppresses player attacks in Arena")
