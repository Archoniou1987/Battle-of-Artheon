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
	var hero_panel := screen.fighters_column.get_child(0) as PanelContainer
	var hero_column := hero_panel.get_child(0) as VBoxContainer
	var equipment_grid: GridContainer
	for node in hero_column.get_children():
		if node is HBoxContainer:
			for inside in node.get_children():
				if inside is GridContainer:
					equipment_grid = inside
	check(equipment_grid != null and equipment_grid.get_child_count() == 10, "ten item icon controls")
	if equipment_grid != null:
		var helmet := equipment_grid.get_child(0) as ItemIcon
		check(helmet != null and helmet.instance_id == "fixture_helm", "equipment survives child ready")
		check(helmet != null and helmet._icon_texture != null and helmet._icon_texture.texture != null, "real item texture applied after ready")
	check(screen.attack_buttons[0].custom_minimum_size.y >= 80, "mobile attack touch size compensates Godot canvas stretch")
	check(screen.abi_buttons[0].custom_minimum_size.y >= 80, "mobile ABI touch size compensates Godot canvas stretch")
	check(screen.round_button.custom_minimum_size.y >= 80, "mobile end-round touch height")
	check(screen.fighters_column.get_child_count() == 3, "hero and two NPC cards")
	check(screen.attack_buttons.size() == 5 and screen.block_buttons.size() == 5, "five hit/block zones")
	check(screen.abi_buttons.size() == 5 and screen.potion_buttons.size() == 4, "five ABI and four potions")
	check(screen.chosen_attack.size() == 1 and screen.chosen_attack[0] == "chest", "one selected zone prepares all physical hits")
	check(screen.chosen_blocks.size() == 2, "canonical PAR073 defense capacity")
	screen._choose_zone(true, "head")
	screen._choose_zone(false, "legs")
	check(screen.chosen_attack == ["chest", "head"], "split two physical hits")
	check(screen.chosen_blocks == ["arms", "legs"], "independent two-zone defense")
	screen._choose_ability(0)
	screen._choose_elixir(0)
	check(last_elixir == 0 and screen.chosen_abi == "ABI003", "ABI and potion selections coexist")
	screen._submit()
	check(last_orders.get("player_id", "") == "player", "submitted owner identity")
	check(last_orders.get("attack_zones", []) == ["chest", "head"], "submitted split hits")
	check(last_orders.get("block_zones", []) == ["arms", "legs"], "submitted exact block zones")
	check(last_orders.get("ability_id", "") == "ABI003" and int(last_orders.get("elixir_slot", -1)) == 0, "submitted one ABI and elixir")
	check(screen.round_button.disabled, "submission locks duplicate taps")
	screen.present(fixture)
	screen._choose_zone(true, "chest")
	check(screen.round_button.disabled, "no attack selection cannot advance a round")
	screen.present(fixture)
	screen._choose_elixir(0)
	screen.set_ability_options([{"id": "ABI003", "available": false}])
	check(screen.abi_buttons[0].disabled, "ability availability updates after potion selection")
	var stunned: Dictionary = fixture.duplicate(true)
	stunned["controls"]["stunned"] = true
	screen.present(stunned)
	check(screen.chosen_attack.is_empty() and screen.chosen_blocks.is_empty(), "stun clears physical orders")
	screen._submit()
	check(last_orders.get("attack_zones", []) == [] and last_orders.get("block_zones", []) == [], "stun submits no physical actions")
	var finished: Dictionary = fixture.duplicate(true)
	finished["finished"] = true
	screen.present(finished)
	check(not screen.round_button.disabled, "terminal checkpoint confirmation remains available")
	screen._submit()
	check(last_orders.is_empty(), "terminal confirmation never queues another action")
	root.size = Vector2i(390, 844)
	await process_frame
	screen._apply_orientation()
	check(screen.arena_layout.vertical, "portrait stacks two panels")
	root.size = Vector2i(844, 390)
	await process_frame
	screen._apply_orientation()
	check(not screen.arena_layout.vertical, "landscape uses two columns")
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
