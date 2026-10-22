extends SceneTree

## Screenshots of the real SoloCombatScreen layout hosted by SoloLiveMap.
## Snapshot is a clearly labeled UI fixture, never a simulated fight or save.
const OUTPUT := "res://test-results/solo-visual"
const SIZES := {"portrait": Vector2i(390, 844), "landscape": Vector2i(844, 390)}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var scene := load("res://scenes/main/solo_live_map.tscn") as PackedScene
	if scene == null:
		push_error("VISUAL_CAPTURE_FAIL: cannot load SoloLiveMap")
		quit(1)
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	var screen := page.get("solo_combat_screen") as SoloCombatScreen
	var map_scroll := page.get("game_map_scroll") as ScrollContainer
	if screen == null or map_scroll == null:
		push_error("VISUAL_CAPTURE_FAIL: game combat screen missing")
		quit(1)
		return
	var equipment: Array = []
	for slot in SoloCombatScreen.EQUIPMENT:
		equipment.append({"slot": slot, "instance_id": "", "active": false, "name": ""})
	equipment[0] = {
		"slot": "head", "instance_id": "fixture_helm", "name": "Шлем (демо)",
		"active": true, "item": {"instance_id": "fixture_helm", "name": "Шлем", "rarity": "blue", "atlas_index": 1}
	}
	equipment[5] = {
		"slot": "main_hand", "instance_id": "fixture_sword", "name": "Клинок (демо)",
		"active": true, "item": {"instance_id": "fixture_sword", "name": "Клинок", "rarity": "green", "atlas_index": 2}
	}
	var fixture: Dictionary = {
		"ok": true, "round": 4, "finished": false,
		"player": {
			"id": "player", "name": "Герой (демо)", "level": 12,
			"hp": 74, "max_hp": 120, "mana": 18, "max_mana": 45,
			"ap": 3, "max_ap": 5,
			"effects": [
				{"id": "BUFF01", "name": "Защита", "polarity": "BUFF", "stacks": 2, "remaining_rounds": 3},
				{"id": "EFF02", "name": "Яд", "polarity": "DEBUFF", "stacks": 1, "remaining_rounds": 2}
			]
		},
		"enemies": [
			{"id": "npc_1", "name": "Бандит (демо)", "level": 11, "hp": 36, "max_hp": 75,
			 "mana": 0, "max_mana": 0, "effects": [
				{"id": "EFF03", "name": "Кровотечение", "polarity": "DEBUFF", "stacks": 1, "remaining_rounds": 2}
			]},
			{"id": "npc_2", "name": "Разбойник (демо)", "level": 11, "hp": 45, "max_hp": 65,
			 "mana": 10, "max_mana": 20, "effects": []}
		],
		"equipment_slots": equipment,
		"ability_slots": [
			{"id": "ABI003", "name": "Огненный шар", "mana_cost": 12, "available": true},
			{"id": "", "available": false}, {"id": "", "available": false},
			{"id": "ABI004", "name": "Лечение", "mana_cost": 10, "available": true},
			{"id": "", "available": false}
		],
		"elixir_loadout": {"slots": [
			{"instance_id": "potion_1", "charges": 2, "max_charges": 3},
			{"instance_id": "potion_2", "charges": 1, "max_charges": 4},
			{"instance_id": "", "charges": 0, "max_charges": 0},
			{"instance_id": "", "charges": 0, "max_charges": 0}
		]},
		"elixir_availability": [true, true, false, false],
		"controls": {"ok": true, "attack_count": 2, "block_capacity": 2,
			"stunned": false, "target_id": "npc_1"},
		"last_round_log": [
			"Герой атакует бандита (голова): 15 урона",
			"Бандит отражает удар щитом",
			"Яд наносит 4 урона"
		]
	}
	map_scroll.visible = false
	screen.visible = true
	screen.present(fixture)
	screen.round_label.text = "VISUAL FIXTURE • НЕ ИГРОВОЙ БОЙ"
	for key in ["portrait", "landscape"]:
		var viewport_size: Vector2i = SIZES[key]
		root.size = viewport_size
		await process_frame
		await process_frame
		screen._apply_orientation()
		screen.scroll.scroll_vertical = 0
		await RenderingServer.frame_post_draw
		var max_scroll := maxi(0, int(screen.scroll.get_v_scroll_bar().max_value - screen.scroll.size.y))
		for frame in range(8):
			screen.scroll.scroll_vertical = mini(max_scroll, frame * maxi(1, int(screen.scroll.size.y) - 30))
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_%02d.png" % [OUTPUT, key, frame]
			var err := root.get_texture().get_image().save_png(file)
			if err != OK:
				push_error("VISUAL_CAPTURE_FAIL: " + file + " code=" + str(err))
				quit(1)
				return
			print("VISUAL_CAPTURE_FILE=", file, " scroll=", screen.scroll.scroll_vertical)
			if screen.scroll.scroll_vertical >= max_scroll:
				break
	page.queue_free()
	print("SOLO_VISUAL_CAPTURE=PASS")
	quit(0)
