extends SceneTree

## Visual-only capture of the real SoloLiveMap scene tree in two mobile
## viewports. Representative fixture values are injected into widgets;
## this NEVER starts a fight or saves canonical game state.
const OUTPUT := "res://test-results/solo-visual"
const SIZES := {"portrait":Vector2i(390,844),"landscape":Vector2i(844,390)}

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
	var panel := page.get("combat_panel") as VBoxContainer
	var root_scroll := page.get_child(1) as ScrollContainer
	if panel == null or root_scroll == null:
		push_error("VISUAL_CAPTURE_FAIL: missing real scene widgets")
		quit(1)
		return
	# This is a layout fixture, not simulated combat and not a screenshot
	# of a user save. All widgets themselves come from the actual scene.
	panel.visible = true
	page.get("status_label").text = "VISUAL FIXTURE • прототип, не игровой сейв"
	page.get("combat_summary").text = "Раунд 5 • Герой: 74/120 HP, 18/45 MP • Волк 36/75 HP"
	page.call("_update_combat_hp_bars",{
		"name":"Герой","hp":74,"max_hp":120,
		"effects":[{"name":"Броня","polarity":"BUFF","stacks":2,"remaining_rounds":3},{"name":"Яд","polarity":"DEBUFF","stacks":1,"remaining_rounds":2}]
	},[{"name":"Волк","hp":36,"max_hp":75,"effects":[{"name":"Кровотечение","polarity":"DEBUFF","stacks":1,"remaining_rounds":2}]}])
	var gear: Array = []
	var slot_names := ["head","chest","hands","waist","legs","main_hand","off_hand","ring1","ring2","feet"]
	for slot in slot_names:
		gear.append({"slot":slot,"instance_id":"","name":"","active":false})
	gear[0] = {"slot":"head","instance_id":"fixture_head","name":"Шлем (пример)","active":true}
	gear[5] = {"slot":"main_hand","instance_id":"fixture_sword","name":"Меч (пример)","active":true}
	page.call("_update_equipment_grid",gear)
	var attack := page.get("attack_zone_row") as VBoxContainer
	var block := page.get("block_zone_row") as GridContainer
	for n in range(2):
		var option := OptionButton.new()
		option.custom_minimum_size.y = 48
		for body_part in ["Голова","Грудь","Руки","Пояс","Ноги"]:
			option.add_item(body_part)
		option.select(n+1)
		attack.add_child(option)
	for i in range(5):
		var cb := CheckBox.new()
		cb.custom_minimum_size.y = 44
		cb.text = ["Голова","Грудь","Руки","Пояс","Ноги"][i]
		cb.button_pressed = i == 1 or i == 2
		block.add_child(cb)
	var ability := page.get("ability_selector") as OptionButton
	ability.add_item("Без ABI")
	for n in range(5):
		ability.add_item("ABI %d • пример" % (n+1))
	var potion := page.get("elixir_selector") as OptionButton
	potion.add_item("Без эликсира")
	for n in range(4):
		potion.add_item("Эликсир %d • пример" % (n+1))
	page.get("elixir_summary").text = "Эликсиры: 1/3 • 2/3 • пусто • закрыт (пример)"
	page.get("round_button").visible = true
	page.get("effects_label").text = "Эффекты героя: Броня ×2 (3 р.), Яд ×1 (2 р.)"
	page.get("combat_log_label").text = "Последний раунд:\nГерой наносит удар\nВолк блокирует\nЯд наносит урон"
	# The battle panel is injected into the unchanged SoloLiveMap control
	# hierarchy; both sizes therefore expose actual overflow and spacing.
	for key in ["portrait","landscape"]:
		var viewport_size: Vector2i = SIZES[key]
		root.size = viewport_size
		await process_frame
		await process_frame
		root_scroll.scroll_vertical = 0
		await process_frame
		await RenderingServer.frame_post_draw
		var max_scroll := maxi(0,int(root_scroll.get_v_scroll_bar().max_value)-viewport_size.y)
		for frame in range(8):
			root_scroll.scroll_vertical = mini(max_scroll,frame * maxi(1,viewport_size.y-80))
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_%02d.png" % [OUTPUT,key,frame]
			var err := root.get_texture().get_image().save_png(file)
			if err != OK:
				push_error("VISUAL_CAPTURE_FAIL: "+file+" code="+str(err))
				quit(1)
				return
			print("VISUAL_CAPTURE_FILE=",file," scroll=",root_scroll.scroll_vertical)
			if root_scroll.scroll_vertical >= max_scroll:
				break
	page.queue_free()
	print("SOLO_VISUAL_CAPTURE=PASS")
	quit(0)
