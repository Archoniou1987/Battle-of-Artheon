extends SceneTree

## UI wiring smoke: elixir and instant ABI fire on press, not End Turn.
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("ELIXIR_ABI_PRESS: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hero := CharacterState.new("PRESS_HERO","Press Hero",5)
	var repo := ItemRepository.new()
	ArenaTestElixirs.seed(hero,repo)
	check(hero.equip("waist","elixir_test_belt_v1",repo),"equip_belt")
	check(hero.assign_elixir(0,"elixir_test_hp_v1",repo),"assign_health")
	check(hero.assign_elixir(1,"elixir_test_fire_v1",repo),"assign_fire")
	var arena := ArenaScreen.new(hero,repo)
	root.add_child(arena)
	await process_frame
	check(arena.combat_session != null,"session_created")
	if arena.combat_session == null:
		_finish()
		return
	check(arena.player_elixir_slots.size()==4,"four_buttons")
	check(not arena.player_elixir_slots[0].disabled,"hp_button_ready")
	var player := arena.combat_session.fighter(true)
	player.hp = player.max_hp - 50
	arena._sync_combat_session()
	var old_charges := int(repo.get_item("elixir_test_hp_v1").get("charges",0))
	arena.player_elixir_slots[0].emit_signal("pressed")
	check(arena.combat_session.state.round_number==1,"click_opens_round")
	check(player.hp==player.max_hp,"button_restored_hp_immediately")
	check(int(repo.get_item("elixir_test_hp_v1").get("charges",0))==old_charges-1,"charge_used_once")
	check(arena.player_elixir_slots[0].disabled and arena.player_elixir_slots[1].disabled,"all_elixirs_disabled_after_use")
	var support := {"name":"Guard","application_timing":"instant","target_team":"ALLY","components":[{"kind":"effect","effect_id":"EFF006"}],"mana_cost":0}
	arena.combat_session.ability_scheduler.definitions["ABI_PRESS_GUARD"]=support
	arena.combat_session.ability_scheduler.loadouts[arena.combat_session.player_id]=["ABI_PRESS_GUARD"]
	arena.combat_session.player_ability_slots=["ABI_PRESS_GUARD","","","",""]
	arena._refresh_ability_buttons()
	check(not arena.ability_buttons[0].disabled,"guard_button_ready")
	arena.ability_buttons[0].emit_signal("pressed")
	check(arena.combat_session.locked_ability_id=="ABI_PRESS_GUARD","button_committed_abi")
	check(CombatModifierService.damage_reduction(player,1)>0.0,"guard_active_on_click")
	check(arena.ability_buttons[0].disabled,"ability_buttons_locked")
	check(Array(arena.combat_session.effect_view(true).get("buffs",[])).is_empty(),"guard_hidden_mid_round")
	arena.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("ELIXIR_ABI_PRESS_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
