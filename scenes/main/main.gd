extends Control

const LOCATION_NAME := "Стартовая деревня"
const IMAGE_PATH := "res://assets/locations/starting_village.jpg"
const DESIGN_SIZE := Vector2(1672.0, 941.0)
const MOBILE_RATIO := 1.65
const HEADER_HEIGHT := 46.0
const FOOTER_HEIGHT := 78.0
const SERVICES := [
	{"name": "Кузнец", "symbol": "⚒", "position": Vector2(0.18, 0.49)},
	{"name": "Рынок", "symbol": "◆", "position": Vector2(0.37, 0.54)},
	{"name": "Главное здание", "symbol": "⌂", "position": Vector2(0.51, 0.40)},
	{"name": "Тренировочное поле", "symbol": "⚔", "position": Vector2(0.80, 0.53)}
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


func _ready() -> void:
	_build_screen()
	get_viewport().size_changed.connect(_layout_panorama)
	call_deferred("_layout_panorama")


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

	var footer := HBoxContainer.new()
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


func _is_mobile_layout() -> bool:
	return OS.has_feature("mobile") or (location_area.size.y > 0.0 and location_area.size.x / location_area.size.y < MOBILE_RATIO)


func _layout_panorama() -> void:
	if location_area == null or panorama == null:
		return
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


func _open_panel(section: String) -> void:
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
