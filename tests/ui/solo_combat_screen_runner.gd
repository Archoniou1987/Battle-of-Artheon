extends SceneTree

## No fake combat engine: assert that the UI emits legal-shaped commands only.
var failures: Array[String] = []
var last_orders: Dictionary = {}
var last_elixir := -99

func check(valid: bool, label: String) -> void:
	if not valid:
		failures.append(label)
		push_error("SOLO_COMBAT_UI: " + label)

func _on_orders(orders: Dictionary) -> void:
	last_orders = orders.duplicate(true)

func _on_elixir(index: int) -> void:
	last_elixir = index

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen := SoloCombatScreen.new()
	root.add_child(screen)
	await process_frame
	screen.round_requested.connect(_on_orders)
	screen.elixir_selected.connect(_on_elixir)
	var gear: Array = []
	for slot in SoloCombatScreen.EQUIPMENT:
		gear.append({"slot": slot, "instance_id": "", "name": "", "active": false})
	gear[0] = {
		"slot": "head", "instance_id": "fixture_helm", "name": "Fixture Helmet",
		"active": true, "item": {"instance_id": "fixture_helm", "name": "Fixture Helmet", "rarity": "blue", "atlas_index": 1}
	}
	var fixture: Dictionary = {
		"ok": true, "round": 3, "finished": false,
		"player": {"id": "player", "name": "Hero", "hp": 80, "max_hp": 100,
			"mana": 30, "max_mana": 40, "level": 5, "effects": []},
		"enemies": [
			{"id": "npc1", "name": "Bandit", "hp": 40, "max_hp": 70, "effects": []},
			{"id": "npc2", "name": "Wolf", "hp": 50, "max_hp": 50, "effects": []}
		],
		"equipment_slots": gear,
		"ability_slots": [
			{"id": "ABI003", "available": true, "name": "Fire", "mana_cost": 10},
			{"id": "", "available": false}, {"id": "", "available": false},
			{"id": "", "available": false}, {"id": "", "available": false}
		],
		"elixir_loadout": {"slots": [
			{"instance_id": "flask", "charges": 2, "max_charges": 3},
			{"instance_id": "", "charges": 0, "max_charges": 0},
			{"instance_id": "", "charges": 0, "max_charges": 0},
			{"instance_id": "", "charges": 0, "max_charges": 0}
		]},
		"elixir_availability": [true, false, false, false],
		"controls": {"ok": true, "attack_count": 2, "block_capacity": 2,
			"stunned": false, "target_id": "npc1"},
		"last_round_log": ["A hit B"]
	}
	screen.present(fixture)
	await process_frame # deferred binding runs after ItemIcon._ready()
	await process_frame
	check(screen.square_host != null and screen.square_content != null, "single 480x480 Face to Face stage")
	check(screen.square_content.size == Vector2(480, 480), "arena keeps 1:1 logical geometry")
	check(screen.tab_container.get_tab_count() == 2, "only participants and journal remain outside Arena square")
	check(screen.roster_allies.get_child_count() == 2, "player occupies ally roster")
	check(screen.roster_enemies.get_child_count() == 3, "two NPCs belong only to opponent roster")

	var arena := screen.shared_arena
	check(arena is ArenaScreen and arena.external_combat_mode, "real Arena template mounted for live map combat")
	check(arena.combat_session == null, "expedition Arena never constructs a second test engine")
	# Engine-disclosed effects, not UI-generated fixture effects, must fill
	# the approved avatar corner in live external combat mode.
	var effects_fixture: Dictionary = fixture.duplicate(true)
	effects_fixture["player"]["effects"] = [{"id":"EFF_A","name":"Guard","polarity":"BUFF","stacks":1,"remaining_rounds":2}]
	effects_fixture["enemies"][0]["effects"] = [{"id":"EFF_B","name":"Poison","polarity":"DEBUFF","stacks":2,"remaining_rounds":3}]
	screen.present(effects_fixture)
	check(arena._effect_entries(true, "Баффы").size() == 1, "player disclosed buff appears in shared Arena")
	check(arena._effect_entries(false, "Дебаффы").size() == 1, "enemy disclosed debuff appears in shared Arena")
	check(arena._effect_entries(false, "Баффы").is_empty(), "effect polarity does not leak into wrong row")
	check(arena.effects_rows["player_Баффы"].visible and arena.effects_rows["enemy_Дебаффы"].visible, "live buff/debuff overlay rows are visible")
	arena._show_effect_detail(true, "Баффы", 0)
	check(screen.detail_text.text.contains("Guard"), "tap on live effect opens details in owning battle UI")

	screen.present(fixture)
	check(arena._effect_entries(true, "Баффы").is_empty(), "effect projection clears on next empty snapshot")
	check(arena.square_content.size == Vector2(480, 480), "original Arena square preserved")
	check(arena.square_content.scale.is_equal_approx(Vector2.ONE), "shared Arena never scales its 480px content internally")
	check(screen.square_content.get_child_count() == 1 and screen.square_content.get_child(0) == arena, "host holds only the original Arena, no trial layers")
	check(arena.player_slots.size() == 14 and arena.enemy_slots.size() == 14, "actual Arena equipment slots reused")
	check(arena.ability_buttons.size() == 5 and arena.player_elixir_slots.size() == 4, "real Arena ABI and elixirs reused")
	# The original Arena background and five ABI slots remain one stable
	# 480x480 composition; long ability labels cannot widen individual cells.
	check(arena.arena_background.position.is_equal_approx(Vector2.ZERO), "Arena background anchored to top-left")
	check(arena.arena_background.size.is_equal_approx(arena.square_content.size), "Arena background covers native square exactly: background=%s square=%s" % [str(arena.arena_background.size), str(arena.square_content.size)])
	check(arena.arena_background.anchor_right == 1.0 and arena.arena_background.anchor_bottom == 1.0, "Arena background follows square boundaries on viewport changes")
	arena.ability_buttons[0].text = "ABILITY_WITH_VERY_LONG_DISPLAY_NAME"
	await process_frame
	for abi in arena.ability_buttons:
		check(absf(abi.size.x - 34.0) <= 1.0 and absf(abi.size.y - 34.0) <= 1.0, "all ABI touch cells stay precisely 34x34")
	screen.present(fixture)

	check(arena.attack_buttons.size() == 5 and arena.defense_buttons.size() == 5, "real Arena zone selectors reused")
	check(screen.attack_buttons.is_empty() and screen.abi_buttons.is_empty(), "temporary Solo input widgets no longer mounted")
	check(screen.chosen_attack == ["chest"] and screen.chosen_blocks.size() == 2, "live round choices initialized")
	arena._select_zone(false, "head")
	arena._select_zone(true, "legs")
	check(screen.chosen_attack == ["chest", "head"], "shared Arena selects split physical hits")
	check(screen.chosen_blocks == ["chest", "legs"], "shared Arena selects defense zones")
	screen._choose_ability(0)
	screen._choose_elixir(0)
	check(last_elixir == 0 and screen.chosen_abi == "ABI003", "ABI and potion selections coexist")
	check(arena.player_elixir_slots[0].toggle_mode, "live potion uses selectable button mode")
	check(arena.ability_buttons[0].button_pressed and arena.player_elixir_slots[0].button_pressed, "selected ABI and potion are visible on the shared Arena")
	# Real Arena callbacks, not duplicate Solo widgets, produce one exact command.
	last_orders.clear()
	screen._submit()
	check(last_orders.get("player_id", "") == "player", "submitted owner identity")
	check(last_orders.get("attack_zones", []) == ["chest", "head"], "submitted split hits")
	check(last_orders.get("block_zones", []) == ["chest", "legs"], "submitted exact block zones")
	check(last_orders.get("ability_id", "") == "ABI003" and int(last_orders.get("elixir_slot", -1)) == 0, "submitted one ABI and elixir")
	check(screen.round_button.disabled, "submission locks duplicate taps")
	last_orders.clear()
	screen._submit()
	check(last_orders.is_empty(), "double End Turn does not emit a second round")
	# Next-round data must come from the newly published canonical snapshot,
	# never from the previous selected ABI/potion or stale resource values.
	var next_round: Dictionary = fixture.duplicate(true)
	next_round["round"] = 4
	next_round["player"]["hp"] = 61
	next_round["player"]["mana"] = 12
	next_round["enemies"][0]["hp"] = 19
	next_round["ability_slots"][0]["available"] = false
	next_round["elixir_loadout"]["slots"][0]["charges"] = 1
	next_round["elixir_availability"] = [false, false, false, false]
	next_round["last_round_log"] = ["Round four: confirmed hit"]
	screen.present(next_round)
	check(screen.round_label.text.contains("5"), "next round label follows engine round snapshot")
	check(arena.hp_overlays["player"].text.contains("61"), "player HP updates after round")
	check(arena.hp_overlays["enemy"].text.contains("19"), "selected opponent HP updates after round")
	check(arena.mana_labels["player"].text.contains("12"), "mana updates after round")
	check(arena.player_elixir_slots[0].text == "1/3", "consumed elixir charge updates after round")
	check(arena.ability_buttons[0].disabled and arena.player_elixir_slots[0].disabled, "cooldown and consumed potion become unavailable")
	check(screen.chosen_abi.is_empty() and screen.chosen_elixir == -1, "previous ABI and elixir do not leak into next round")
	check(not arena.ability_buttons[0].button_pressed and not arena.player_elixir_slots[0].button_pressed, "next round clears previous selection visual state")
	check(not screen.round_button.disabled, "next round releases End Turn lock with valid choices")
	screen.present(fixture)
	screen.shared_arena._select_zone(false, "chest")
	check(screen.round_button.disabled, "no attack selection cannot advance a round")
	screen.present(fixture)
	screen._choose_elixir(0)
	screen.set_ability_options([{"id": "ABI003", "available": false}])
	check(screen.shared_arena.ability_buttons[0].disabled, "ability availability updates after potion selection")
	# Unarmed fighters have one real manual block, not zero.
	var fists: Dictionary = fixture.duplicate(true)
	fists["controls"]["block_capacity"] = 1
	screen.present(fists)
	check(arena.defense_capacity == 1 and arena.defense_zones.size() == 1, "unarmed fighter retains one manual defense zone")
	screen._submit()
	check(Array(last_orders.get("block_zones", [])).size() == 1, "unarmed round submits exactly one manual block")
	var stunned: Dictionary = fixture.duplicate(true)
	stunned["controls"]["stunned"] = true
	screen.present(stunned)
	check(screen.chosen_attack.is_empty() and screen.chosen_blocks.is_empty(), "stun clears physical orders")
	check(arena.attack_buttons[0].disabled and arena.defense_buttons[0].disabled, "stunned Arena disables physical input")
	check(arena.player_elixir_slots[0].disabled, "stunned UI disables elixirs despite stale availability")
	screen._choose_elixir(0)
	check(screen.chosen_elixir == -1, "stun ignores potion commands even with stale fixture availability")
	screen._submit()
	check(last_orders.get("attack_zones", []) == [] and last_orders.get("block_zones", []) == [], "stun submits no physical actions")
	var finished: Dictionary = fixture.duplicate(true)
	finished["finished"] = true
	finished["winner"] = "players"
	screen.present(finished)
	check(not screen.round_button.disabled, "terminal checkpoint confirmation remains available")
	check(screen.instruction_label.text.contains("Победа"), "victory label reflects authoritative winner")
	check(screen.instruction_label.text.contains("подтвердите"), "terminal checkpoint is not falsely described as world-published")
	last_orders = {"not_yet": true}
	screen._submit()
	check(last_orders.is_empty(), "terminal confirmation never queues another action")
	check(screen.round_button.disabled, "terminal button locks after one confirmation")
	last_orders = {"still_locked": true}
	screen._submit()
	check(last_orders.has("still_locked"), "double terminal tap never emits second settlement request")
	var defeat: Dictionary = fixture.duplicate(true)
	defeat["finished"] = true
	defeat["winner"] = "enemies"
	screen.present(defeat)
	check(screen.instruction_label.text.contains("Поражение"), "defeat label reflects authoritative winner")
	var unresolved: Dictionary = fixture.duplicate(true)
	unresolved["finished"] = true
	screen.present(unresolved)
	check(screen.instruction_label.text.contains("Бой завершён"), "unknown terminal winner never mislabels defeat")
	root.size = Vector2i(390, 844)
	await process_frame
	screen._apply_orientation()
	check(screen.arena_layout.vertical and screen.square_host.custom_minimum_size.x == screen.square_host.custom_minimum_size.y, "portrait keeps square and scrolls actions below")
	check(arena.square_content.scale.is_equal_approx(Vector2.ONE), "portrait retains native Arena geometry")
	root.size = Vector2i(844, 390)
	await process_frame
	screen._apply_orientation()
	check(not screen.arena_layout.vertical and screen.square_host.custom_minimum_size.x == screen.square_host.custom_minimum_size.y, "landscape keeps square beside action column")
	check(arena.square_content.scale.is_equal_approx(Vector2.ONE), "landscape retains native Arena geometry")
	check(screen.square_content.scale.is_equal_approx(Vector2.ONE * (screen.square_host.custom_minimum_size.x / 480.0)), "outer host is the only active scaler")
	check(screen.square_host.custom_minimum_size.y <= screen.arena_layout.size.y + 1.0, "landscape Arena does not extend below available area")
	check(screen.square_host.get_global_rect().end.y <= screen.get_global_rect().end.y + 1.0, "landscape bottom edge, including End Turn, remains within visible screen")
	check(screen.square_host.get_global_rect().end.x <= screen.get_global_rect().end.x + 1.0, "landscape Arena right edge remains within screen")

	check(screen.info_column.get_parent() == screen.arena_layout, "secondary tabs and header share outside-square host")
	check(screen.tab_container.get_parent() == screen.info_column, "info tabs do not overlap Arena square")
	check(screen.square_host.custom_minimum_size.x >= minf(480.0, screen.arena_layout.size.y) - 10.0, "landscape Arena maximizes available height instead of fixed 330px reservation")
	# Regression: base Godot viewport is 720 logical px high. A 480px
	# upper cap would render the battle square at only 260px in 390px landscape.
	var arena_room := screen.size
	var min_info := screen.info_column.custom_minimum_size.x
	var fit_width := arena_room.x - min_info - float(screen.arena_layout.get_theme_constant("separation"))
	var expected_edge := floorf(maxf(1.0, minf(fit_width, arena_room.y)))
	check(absf(screen.square_host.custom_minimum_size.x - expected_edge) <= 1.0, "landscape uses full available edge, without legacy 480 design-size cap")
	if expected_edge > 500.0:
		check(screen.square_host.custom_minimum_size.x > 480.0, "Arena scales above its 480 logical design size when room permits")

	screen.queue_free()
	var map_scene := load("res://scenes/main/solo_live_map.tscn") as PackedScene
	check(map_scene != null, "real expedition scene exists")
	if map_scene != null:
		var map := map_scene.instantiate() as Control
		root.add_child(map)
		await process_frame
		check(map.get("solo_combat_screen") is SoloCombatScreen, "real expedition mounts game combat overlay")
		check(map.get("game_map_scroll") is ScrollContainer, "real map preserved behind overlay")
		map.queue_free()
	print("SOLO_COMBAT_SCREEN_TEST=", "PASS" if failures.is_empty() else "FAIL",
		" failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
