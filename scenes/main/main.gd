extends Control

const LOCATION_NAME := "Стартовая деревня"
const PROGRESSION_SAVE_PATH := "user://character_progression_v1.json"
const INVENTORY_SAVE_PATH := "user://character_inventory_v1.json"
# Temporary browser preview fixture; disable before public gameplay release.
const ENABLE_INVENTORY_PREVIEW_ITEMS := false
const INVENTORY_RESET_MARKER_PATH := "user://inventory_reset_empty_v1.marker"
const ARENA_TEST_INVENTORY_VERSION := 2
const IMAGE_PATH := "res://assets/locations/starting_village.jpg"
const DESIGN_SIZE := Vector2(1672.0, 941.0)
const PORTRAIT_NAV_COLUMNS := 3
const HEADER_HEIGHT := 46.0
const FOOTER_HEIGHT := 78.0
const SERVICES := [
	{"name": "Кузнец", "symbol": "⚒", "position": Vector2(0.18, 0.49)},
	{"name": "Рынок", "symbol": "◆", "position": Vector2(0.37, 0.54)},
	{"name": "Главное здание", "symbol": "⌂", "position": Vector2(0.51, 0.40)},
	{"name": "Арена", "symbol": "⚔", "position": Vector2(0.80, 0.53)}
]
const NAVIGATION := [
	{"name": "Персонаж", "symbol": "♟"},
	{"name": "Инвентарь", "symbol": "▣"},
	{"name": "Умения", "symbol": "✦"},
	{"name": "Задания", "symbol": "☷"},
	{"name": "Карта", "symbol": "◇"},
	{"name": "Меню", "symbol": "☰"}
]

var location_area: Control
var panorama: Control
var backdrop: TextureRect
var popup: PanelContainer
var popup_title: Label
var popup_description: Label
var popup_actions: VBoxContainer
var panorama_offset := 0.0
var dragging := false
var drag_origin := Vector2.ZERO
var drag_offset := 0.0
var service_buttons: Array[Button] = []
var footer: Control
var portrait_nav: GridContainer
var player_character: CharacterState
var character_screen: CharacterScreen
var inventory_screen: InventoryScreen
var arena_screen: ArenaScreen
var item_repository: ItemRepository
var landscape_nav: HBoxContainer


func _ready() -> void:
	player_character = CharacterState.new("player", "Герой")
	_load_saved_progression()
	item_repository = ItemRepository.new()
	var inventory_loaded := _load_saved_inventory()
	_reset_preview_inventory_once()
	# Never replace an existing save: doing so destroys user items and breaks persistence.
	# The training fixture is only generated for a fresh, interactive preview.
	if ENABLE_INVENTORY_PREVIEW_ITEMS and DisplayServer.get_name() != "headless":
		# Merge missing test instances without deleting saved inventory or replacing equipped items.
		ArenaTestEquipment.seed(player_character, item_repository)
	_build_screen()
	get_viewport().size_changed.connect(_layout_panorama)
	call_deferred("_layout_panorama")


# One-time preview migration: clear existing bag, equipment and quick slots.
# The marker prevents wiping items earned after the migration.
func _reset_preview_inventory_once() -> void:
	if FileAccess.file_exists(INVENTORY_RESET_MARKER_PATH):
		return
	player_character.inventory = InventoryState.new(player_character.character_id)
	player_character.equipment = EquipmentState.new()
	item_repository = ItemRepository.new()
	var marker := FileAccess.open(INVENTORY_RESET_MARKER_PATH, FileAccess.WRITE)
	if marker == null:
		push_warning("Inventory reset marker could not be saved")
		return
	marker.store_string("reset_v1")
	marker.close()
	_save_inventory()


func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = Color("#172334")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("separation", 0)
	add_child(frame)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = int(HEADER_HEIGHT)
	frame.add_child(header)
	var title := _label(LOCATION_NAME, 23, Color("#f1ddbb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("Уровень 1", 16, Color("#d4ba8d")))

	location_area = Control.new()
	location_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_area.clip_contents = true
	location_area.gui_input.connect(_on_panorama_input)
	location_area.mouse_filter = Control.MOUSE_FILTER_STOP
	location_area.resized.connect(_layout_panorama)
	frame.add_child(location_area)

	panorama = Control.new()
	panorama.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_area.add_child(panorama)

	backdrop = TextureRect.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	panorama.add_child(backdrop)
	if ResourceLoader.exists(IMAGE_PATH):
		backdrop.texture = load(IMAGE_PATH)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color("#344638")
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panorama.add_child(placeholder)
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var hint := _label("Иллюстрация стартовой деревни будет добавлена сюда", 18, Color("#e3dcc5"))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.position = Vector2(300, 250)
		panorama.add_child(hint)

	for service in SERVICES:
		var button := Button.new()
		button.name = str(service["name"])
		button.text = str(service["symbol"]) + "\n" + str(service["name"])
		button.custom_minimum_size = Vector2(190, 76)
		button.size = Vector2(190, 76)
		button.add_theme_font_size_override("font_size", 19)
		button.pressed.connect(_open_panel.bind(str(service["name"])))
		button.gui_input.connect(_on_panorama_input)
		service_buttons.append(button)
		panorama.add_child(button)

	landscape_nav = HBoxContainer.new()
	var footer := landscape_nav
	footer.custom_minimum_size.y = int(FOOTER_HEIGHT)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(footer)
	for entry in NAVIGATION:
		var button := Button.new()
		button.text = str(entry["symbol"]) + "\n" + str(entry["name"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 68
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_open_panel.bind(str(entry["name"])))
		footer.add_child(button)

	portrait_nav = GridContainer.new()
	portrait_nav.columns = PORTRAIT_NAV_COLUMNS
	portrait_nav.visible = false
	frame.add_child(portrait_nav)
	for entry in NAVIGATION:
		var mobile_button := Button.new()
		mobile_button.text = str(entry["symbol"]) + "\n" + str(entry["name"])
		mobile_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mobile_button.custom_minimum_size.y = 76
		mobile_button.add_theme_font_size_override("font_size", 18)
		mobile_button.pressed.connect(_open_panel.bind(str(entry["name"])))
		portrait_nav.add_child(mobile_button)

	popup = PanelContainer.new()
	popup.visible = false
	popup.custom_minimum_size = Vector2(340, 170)
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(popup)
	var contents := VBoxContainer.new()
	popup.add_child(contents)
	popup_title = _label("", 22, Color("#f1ddbb"))
	contents.add_child(popup_title)
	popup_description = _label("", 16, Color("#d8dbe0"))
	contents.add_child(popup_description)
	popup_actions = VBoxContainer.new()
	contents.add_child(popup_actions)
	var close := Button.new()
	close.text = "Вернуться в поселение"
	close.pressed.connect(func() -> void: popup.visible = false)
	contents.add_child(close)


func _layout_panorama() -> void:
	if location_area == null or panorama == null:
		return
	var portrait := size.y > size.x
	if portrait_nav != null:
		portrait_nav.visible = portrait
	if landscape_nav != null:
		landscape_nav.visible = not portrait
	var available := location_area.size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var scale_factor := maxf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	var scaled := DESIGN_SIZE * scale_factor
	# Cover the play area at every aspect ratio, avoiding letterboxing.
	panorama.size = scaled
	backdrop.size = scaled
	var max_offset := maxf(0.0, scaled.x - available.x)
	panorama_offset = clampf(panorama_offset, -max_offset * 0.5, max_offset * 0.5)
	panorama.position = Vector2((available.x - scaled.x) * 0.5 + panorama_offset, (available.y - scaled.y) * 0.5)
	for service in SERVICES:
		var button := panorama.get_node_or_null(str(service["name"])) as Button
		if button != null:
			var point: Vector2 = service["position"]
			button.position = scaled * point - button.size * 0.5
	if popup != null:
		popup.position = (size - popup.size) * 0.5


func _on_panorama_input(event: InputEvent) -> void:
	if panorama == null or location_area == null or panorama.size.x <= location_area.size.x:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			dragging = true
			drag_origin = event.position
			drag_offset = panorama_offset
		else:
			dragging = false
	elif event is InputEventScreenDrag and dragging:
		_shift_panorama(panorama_offset + event.relative.x)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			drag_origin = event.position
			drag_offset = panorama_offset
	elif event is InputEventMouseMotion and dragging:
		_shift_panorama(panorama_offset + event.relative.x)


func _shift_panorama(value: float) -> void:
	var overflow := maxf(0.0, panorama.size.x - location_area.size.x)
	panorama_offset = clampf(value, -overflow * 0.5, overflow * 0.5)
	panorama.position.x = (location_area.size.x - panorama.size.x) * 0.5 + panorama_offset



func _open_character_screen() -> void:
	if character_screen == null:
		character_screen = CharacterScreen.new(player_character)
		character_screen.item_repository = item_repository
		character_screen.name = "CharacterScreen"
		add_child(character_screen)
		character_screen.stats_committed.connect(_save_progression)
		character_screen.back_button.pressed.connect(func() -> void: character_screen.visible = false)
	character_screen.visible = true
	character_screen.refresh()


func _open_inventory_screen() -> void:
	if inventory_screen == null:
		inventory_screen = InventoryScreen.new(player_character, item_repository)
		inventory_screen.name = "InventoryScreen"
		add_child(inventory_screen)
		inventory_screen.inventory_changed.connect(_save_inventory)
		_load_saved_elixirs()
		inventory_screen.back_button.pressed.connect(func() -> void: inventory_screen.visible = false)
	inventory_screen.visible = true
	inventory_screen.refresh()


func _open_arena_screen() -> void:
	# Each entry starts a fresh training duel using the current equipment.
	if arena_screen != null:
		remove_child(arena_screen)
		arena_screen.queue_free()
	arena_screen = ArenaScreen.new(player_character, item_repository)
	arena_screen.name = "ArenaScreen"
	add_child(arena_screen)
	arena_screen.back_requested.connect(func() -> void: arena_screen.visible = false)
	arena_screen.visible = true
	arena_screen.refresh()


func _open_panel(section: String) -> void:
	if section == "Арена":
		_open_arena_screen()
		return
	if section == "Инвентарь":
		_open_inventory_screen()
		return
	if section == "Персонаж":
		_open_character_screen()
		return
	popup_title.text = section
	popup_description.text = "Раздел будет подключён на следующем этапе."
	for child in popup_actions.get_children():
		child.queue_free()
	if section == "Меню":
		popup_description.text = "Инструменты разработчика"
		_add_debug_button("Отладочная карта", "res://scenes/debug/debug_map_viewer.tscn")
		_add_debug_button("Отладочный бой", "res://scenes/debug/debug_combat_viewer.tscn")
	popup.visible = true
	popup.reset_size()
	popup.position = (size - popup.size) * 0.5


func _add_debug_button(title: String, path: String) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(func() -> void: get_tree().change_scene_to_file(path))
	popup_actions.add_child(button)


func _label(value: String, font_size: int, tint: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", tint)
	return result

# Deliberately isolated test data: no drops, prices, or balance rules.
func _seed_inventory_preview() -> void:
	var samples := [
		["Тренировочный меч", "grey", "weapon", ["main_hand"]],
		["Железный меч", "green", "weapon", ["main_hand"]],
		["Охотничий кинжал", "blue", "weapon", ["main_hand", "off_hand"]],
		["Тяжёлый топор", "purple", "weapon", ["main_hand"]],
		["Деревянный щит", "grey", "shield", ["off_hand"]],
		["Стальной щит", "green", "shield", ["off_hand"]],
		["Кожаный шлем", "green", "armour", ["head"]],
		["Капюшон следопыта", "blue", "armour", ["head"]],
		["Кожаная куртка", "grey", "armour", ["chest"]],
		["Кольчуга", "blue", "armour", ["chest"]],
		["Перчатки охотника", "green", "armour", ["hands"]],
		["Сапоги путника", "grey", "armour", ["feet"]],
		["Кольцо меди", "green", "ring", ["ring1", "ring2"]],
		["Кольцо луны", "purple", "ring", ["ring1", "ring2"]],
		["Пояс странника", "green", "armour", ["waist"]],
		["Наручи стража", "blue", "armour", ["wrists"]],
		["Эликсир здоровья", "green", "consumable", []],
		["Старая руда", "grey", "material", []],
		["Редкий самоцвет", "orange", "material", []],
		["Потрёпанная карта", "grey", "quest", []],
		["Кольцо титана (+25 STR)", "purple", "ring", ["ring1", "ring2"]],
		["Молот испытания (STR 10)", "blue", "weapon", ["main_hand"]]
	]
	for index in range(samples.size()):
		var sample: Array = samples[index]
		var instance_id := "preview_%02d" % (index + 1)
		var item := {
			"instance_id": instance_id,
			"name": String(sample[0]),
			"rarity": String(sample[1]),
			"type": String(sample[2]),
			"item_level": 1,
			# Temporary preview icon mapping; production templates will own stable icon_id.
			"icon_id": "ICON_%04d" % ([0, 1, 14, 2, 16, 17, 18, 19, 24, 27, 40, 48, 50, 51, 29, 41, 56, 61, 63, 60, 52, 3][index] + 1),
			"equip_slots": sample[3],
			"requirements": {"STR": 10} if index == 21 else {},
			"guaranteed_stats": {},
			"bonuses": {"STR": 25} if index == 20 else {},
			"description": "Тестовый предмет для проверки интерфейса. Не является частью игрового баланса."
		}
		ItemDurabilityService.initialize_item(item, 100)
		if item_repository.add_item(item):
			player_character.inventory.add_instance(instance_id, item_repository)


func _save_progression() -> void:
	if player_character == null:
		return
	var file := FileAccess.open(PROGRESSION_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Character progression save failed")
		return
	file.store_string(JSON.stringify({"schema_version": 1, "progression": player_character.progression_snapshot()}))
	file.close()

func _load_saved_progression() -> void:
	if not FileAccess.file_exists(PROGRESSION_SAVE_PATH):
		return
	var file := FileAccess.open(PROGRESSION_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary:
		return
	if int(raw.get("schema_version", 0)) != 1:
		return
	var data: Variant = raw.get("progression", {})
	if data is Dictionary:
		player_character.restore_progression(data)


func _save_inventory() -> void:
	if player_character == null or item_repository == null:
		return
	var file := FileAccess.open(INVENTORY_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Inventory save failed")
		return
	var quickslots: Array = inventory_screen.elixir_assignments.duplicate() if inventory_screen != null else ["", "", "", ""]
	var payload := {"schema_version": 1, "repository": item_repository.to_dict(), "inventory": player_character.inventory.to_dict(), "equipment": player_character.equipment.slots.duplicate(true), "elixirs": quickslots}
	file.store_string(JSON.stringify(payload))
	file.close()

func _load_saved_inventory() -> bool:
	if not FileAccess.file_exists(INVENTORY_SAVE_PATH):
		return false
	var file := FileAccess.open(INVENTORY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or int(raw.get("schema_version", 0)) != 1:
		return false
	var repository_data: Variant = raw.get("repository", {})
	var inventory_data: Variant = raw.get("inventory", {})
	var slots_data: Variant = raw.get("equipment", {})
	if not repository_data is Dictionary or not inventory_data is Dictionary or not slots_data is Dictionary:
		return false
	if String(inventory_data.get("owner_id", "")) != player_character.character_id:
		return false
	var loaded_repository := ItemRepository.from_dict(repository_data)
	var loaded_inventory := InventoryState.from_dict(inventory_data, loaded_repository)
	var ids: Variant = inventory_data.get("instance_ids", [])
	if not ids is Array or loaded_inventory.size() != ids.size():
		return false
	var loaded_equipment := EquipmentState.new()
	for slot in loaded_equipment.slots:
		var id: Variant = slots_data.get(slot, null)
		if id != null and (not id is String or not loaded_inventory.owns(String(id))):
			return false
		loaded_equipment.slots[slot] = id
	for key in slots_data:
		if not loaded_equipment.slots.has(key):
			return false
	for id in loaded_inventory.instance_ids():
		var occupied: Array = []
		for slot in loaded_equipment.slots:
			if loaded_equipment.slots[slot] == id:
				occupied.append(slot)
		if occupied.is_empty():
			continue
		var item := loaded_repository.get_item(String(id))
		var allowed: Array = item.get("equip_slots", [])
		var usage: Array = item.get("slot_usage", [occupied[0]])
		if not allowed.has(occupied[0]) or usage.size() != occupied.size():
			return false
		for slot in usage:
			if not occupied.has(slot):
				return false
	item_repository = loaded_repository
	player_character.inventory = loaded_inventory
	player_character.equipment = loaded_equipment
	return true


func _load_saved_elixirs() -> void:
	if inventory_screen == null or not FileAccess.file_exists(INVENTORY_SAVE_PATH):
		return
	var file := FileAccess.open(INVENTORY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not raw is Dictionary:
		return
	var elixirs: Variant = raw.get("elixirs", [])
	if not elixirs is Array or elixirs.size() != 4:
		return
	for i in range(4):
		var id: Variant = elixirs[i]
		if id is String and (id.is_empty() or player_character.inventory.owns(id)):
			inventory_screen.elixir_assignments[i] = id
