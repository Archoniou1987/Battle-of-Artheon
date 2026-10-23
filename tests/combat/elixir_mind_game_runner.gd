extends SceneTree

## Elixir Mind Game contract and manual ABI timing. One runner, one CI step.
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error("ELIXIR_MIND_GAME: " + label)

func fixture() -> Dictionary:
	var hero := CharacterState.new("ELIXIR_HERO","Elixir Hero",5)
	var repository := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repository),"seed_test_fixtures")
	check(hero.equip("waist","elixir_test_belt_v1",repository),"equip_belt")
	check(hero.elixir_capacity(repository)==4,"four_slots_belt")
	for pair in [[0,"elixir_test_hp_v1"],[1,"elixir_test_mana_v1"],[2,"elixir_test_fire_v1"],[3,"elixir_test_cleanse_v1"]]:
		check(hero.assign_elixir(int(pair[0]),String(pair[1]),repository),"assign_"+String(pair[1]))
	var session := ArenaCombatSession.new(hero,repository)
	return {"hero":hero,"repository":repository,"session":session}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_immediate_hp_and_cooldown()
	_test_mana_and_ownership()
	_test_fire_ward_and_surprise()
	_test_stat_buff()
	_test_cleanse_visibility()
	_test_abi_manual_timings()
	_test_persistence()
	print("ELIXIR_MIND_GAME_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_immediate_hp_and_cooldown() -> void:
	var setup := fixture()
	var session: ArenaCombatSession = setup["session"]
	var repo: ItemRepository = setup["repository"]
	var hero := session.fighter(true)
	hero.hp = hero.max_hp - 35
	var first := session.use_elixir(0)
	check(bool(first.get("ok",false)),"hp_click_succeeds")
	check(session.state.round_number==1,"click_starts_mind_game")
	check(hero.hp==hero.max_hp,"hp_instant_and_overheal_clamped")
	check(int(repo.get_item("elixir_test_hp_v1").get("charges",-1))==2,"charge_decrement_once")
	check(not bool(session.use_elixir(1).get("ok",true)),"same_round_global_limit")
	check(int(repo.get_item("elixir_test_mana_v1").get("charges",-1))==3,"rejected_use_keeps_charges")
	var before_round := session.state.round_number
	var denied := session.use_elixir(9)
	check(not bool(denied.get("ok",true)) and session.state.round_number==before_round,"invalid_slot_rejects_without_round")
	check(session.elixir_cooldown()>0,"global_cooldown_visible")

func _test_mana_and_ownership() -> void:
	var setup := fixture()
	var session: ArenaCombatSession = setup["session"]
	var repo: ItemRepository = setup["repository"]
	var hero := session.fighter(true)
	hero.mana = 0
	check(bool(session.use_elixir(1).get("ok",false)),"mana_click_succeeds")
	check(hero.mana==mini(hero.max_mana,30),"mana_restored_immediately")
	check(not bool(session.use_elixir(1).get("ok",true)),"cannot_reuse_mana_same_round")
	check(int(repo.get_item("elixir_test_mana_v1").get("charges",-1))==2,"mana_charge_persisted")
	check(not bool(session.use_elixir(3).get("ok",true)),"other_slot_limited")
	var ch: CharacterState = setup["hero"]
	check(not ch.assign_elixir(2,"elixir_test_mana_v1",repo),"duplicate_slot_blocked")
	check(not ch.remove_item("elixir_test_mana_v1"),"cannot_remove_equipped_quickslot")
	# The potion restores Mana during Mind Game, enabling a Standard ABI.
	session.ability_scheduler.loadouts[session.player_id]=["ABI004"]
	session.player_ability_slots=["ABI004","","","",""]
	check(bool(session.activate_ability("ABI004").get("ok",false)),"mana_potion_enables_standard_abi")
	check(hero.mana==mini(hero.max_mana,30)-10,"standard_abi_mana_cost_after_potion")


func _test_fire_ward_and_surprise() -> void:
	var setup := fixture()
	var session: ArenaCombatSession = setup["session"]
	var hero := session.fighter(true)
	var baseline := CombatModifierService.magic_resist(hero,"fire",1)
	check(bool(session.use_elixir(2).get("ok",false)),"fire_ward_click_succeeds")
	var after := CombatModifierService.magic_resist(hero,"fire",1)
	check(after>baseline and after>=0.89,"fire_ward_applied_before_combat")
	check(Array(session.effect_view(true).get("buffs",[])).is_empty(),"ward_hidden_until_end_round")
	var hit := session.state.create_event(CombatEvent.Kind.DAMAGE,ArenaCombatSession.ENEMY_ID,session.player_id,{"amount":100,"damage_type":"fire"})
	session.engine.resolve_event(hit)
	check(int(hit.result.get("final_damage",-1))<=11,"ward_reduces_current_round_fire_damage")
	session.orchestrator.end_round()
	check(Array(session.effect_view(true).get("buffs",[])).size()==1,"ward_revealed_after_round")

func _test_stat_buff() -> void:
	var setup := fixture()
	var hero: CharacterState = setup["hero"]
	var repository: ItemRepository = setup["repository"]
	var session: ArenaCombatSession = setup["session"]
	check(hero.clear_elixir(2),"clear_fixture_fire_slot")
	check(hero.assign_elixir(2,"elixir_test_focus_v1",repository),"assign_stat_buff")
	var initial := CombatModifierService.effective_percent(session.fighter(true),"crit_chance_rating",1)
	check(bool(session.use_elixir(2).get("ok",false)),"stat_buff_click")
	var modified := CombatModifierService.effective_percent(session.fighter(true),"crit_chance_rating",1)
	check(modified>=initial+19.9,"stat_buff_affects_canonical_crit_readout")
	check(Array(session.effect_view(true).get("buffs",[])).is_empty(),"stat_buff_hidden_until_reveal")

func _test_cleanse_visibility() -> void:
	var setup := fixture()
	var session: ArenaCombatSession = setup["session"]
	session.fighter(true).active_effects.append({"effect_id":"KNOWN_BAD","definition":{"kind":"debuff","damage_reduction":-0.1},"source_id":ArenaCombatSession.ENEMY_ID,"start_round":0,"remaining_rounds":3,"revealed":true})
	session.fighter(true).active_effects.append({"effect_id":"HIDDEN_BAD","definition":{"kind":"debuff","damage_reduction":-0.1},"source_id":ArenaCombatSession.ENEMY_ID,"start_round":1,"remaining_rounds":3,"revealed":false,"dispel_available_round":2})
	check(bool(session.use_elixir(3).get("ok",false)),"cleanse_click_succeeds")
	var ids: Array[String] = []
	for record in session.fighter(true).active_effects:
		ids.append(String(record.get("effect_id","")))
	check(not ids.has("KNOWN_BAD") and ids.has("HIDDEN_BAD"),"cleanse_removes_known_not_instant_hidden")

func _test_abi_manual_timings() -> void:
	var setup := fixture()
	var session: ArenaCombatSession = setup["session"]
	var player := session.fighter(true)
	player.mana = 100
	player.max_mana = 100
	var instant: Dictionary = {"name":"Ward ABI","application_timing":"instant","target_team":"ALLY","components":[{"kind":"effect","effect_id":"EFF006"}],"mana_cost":2}
	var standard: Dictionary = {"name":"Healing ABI","application_timing":"standard","target_team":"ALLY","components":[{"kind":"heal","amount":30}],"mana_cost":2}
	var dot: Dictionary = {"name":"Curse","application_timing":"instant","target_team":"ENEMY","components":[{"kind":"effect","effect_id":"EFF003"}]}
	check(AbilityRuntime.validate_definition("ABI_TEST_INSTANT",instant).is_empty(),"hand_authored_instant_valid")
	check(AbilityRuntime.validate_definition("ABI_TEST_HEAL",standard).is_empty(),"hand_authored_standard_heal_valid")
	check(AbilityRuntime.validate_definition("ABI_TEST_DOT",dot).has("instant_periodic_damage_or_heal_requires_standard"),"instant_dot_rejected")
	check(AbilityRuntime.validate_definition("ABI_TEST_HEAL",{"components":[{"kind":"heal","amount":1}],"application_timing":"instant"}).has("instant_damage_or_heal_requires_standard"),"instant_direct_heal_rejected")
	session.ability_scheduler.definitions["ABI_TEST_INSTANT"]=instant
	session.ability_scheduler.definitions["ABI_TEST_HEAL"]=standard
	session.ability_scheduler.loadouts[session.player_id]=["ABI_TEST_INSTANT","ABI_TEST_HEAL"]
	session.player_ability_slots = ["ABI_TEST_INSTANT","ABI_TEST_HEAL","","",""]
	check(bool(session.activate_ability("ABI_TEST_INSTANT").get("ok",false)),"instant_abi_click_succeeds")
	check(session.locked_ability_id=="ABI_TEST_INSTANT","instant_abi_committed")
	check(Array(session.effect_view(true).get("buffs",[])).is_empty(),"instant_abi_hidden")
	check(CombatModifierService.damage_reduction(player,1)>0.0,"instant_abi_modifier_active")
	check(not bool(session.activate_ability("ABI_TEST_HEAL").get("ok",true)),"second_abi_blocked")
	var other := fixture()
	var treatment: ArenaCombatSession = other["session"]
	treatment.ability_scheduler.definitions["ABI_TEST_HEAL"]=standard
	treatment.ability_scheduler.loadouts[treatment.player_id]=["ABI_TEST_HEAL"]
	treatment.player_ability_slots=["ABI_TEST_HEAL","","","",""]
	var subject := treatment.fighter(true)
	subject.hp=subject.max_hp-40
	subject.mana=100
	var initial_hp := subject.hp
	check(bool(treatment.activate_ability("ABI_TEST_HEAL").get("ok",false)),"standard_abi_commit_succeeds")
	check(subject.hp==initial_hp,"standard_heal_not_applied_on_click")
	check(treatment.active_round!=null and treatment.active_round.locked_actions.size()==1,"standard_action_sealed")
	var required:=CombatModifierService.manual_block_zone_capacity(subject)
	var blocks:Array[String]=[]
	for zone in ["head","chest","arms","waist"]:
		if blocks.size()<required:
			blocks.append(zone)
	var round := treatment.play_round(["chest"],blocks)
	check(bool(round.get("ok",false)),"sealed_standard_round_resolved")
	check(subject.hp>initial_hp,"standard_heal_resolves_at_end_turn")
	check(treatment.locked_ability_id.is_empty(),"abi_budget_reopens_next_round")

func _test_persistence() -> void:
	var setup := fixture()
	var hero: CharacterState = setup["hero"]
	var repo: ItemRepository = setup["repository"]
	var restored_repo := ItemRepository.from_dict(repo.to_dict())
	var fresh := CharacterState.new(hero.character_id,"Reload",hero.level)
	fresh.inventory=InventoryState.from_dict(hero.inventory.to_dict(),restored_repo)
	fresh.equipment.slots=hero.equipment.slots.duplicate(true)
	check(fresh.restore_elixir_slots(hero.elixir_slots,restored_repo),"restore_owned_elixir_slots")
	check(fresh.elixir_slots==hero.elixir_slots,"persistent_elixir_assignment")
