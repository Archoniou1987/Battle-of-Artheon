extends Control

const LOCATION_NAME := "Стартовая деревня"
const SERVICES := [
	{"name": "Кузнец", "symbol": "⚒", "position": Vector2(0.72, 0.42)},
	{"name": "Торговец", "symbol": "◆", "position": Vector2(0.46, 0.62)},
	{"name": "Таверна", "symbol": "♜", "position": Vector2(0.24, 0.44)},
	{"name": "Арена", "symbol": "⚔", "position": Vector2(0.82, 0.70)}
]
const NAVIGATION := [
	{"name": "Персонаж", "symbol": "♟"},
	{"name": "Инвентарь", "symbol": "▣"},
	{"name": "Умения", "symbol": "✦"},
	{"name": "Задания", "symbol": "☷"},
	{"name": "Карта", "symbol": "◇"},
	{"name": "Меню", "symbol": "☰"}
]

var backdrop: TextureRect
var location_area: Control
var popup: PanelContainer
var popup_title: Label
var popup_description: Label


func _ready() -> void:
	_build_screen()
	get_viewport().size_changed.connect(_layout_services)


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
	header.custom_minimum_size.y = 54
	header.add_theme_constant_override("separation", 16)
	frame.add_child(header)
	var title := _label(LOCATION_NAME, 23, Color("#f1ddbb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("Уровень 1", 16, Color("#d4ba8d")))

	location_area = Control.new()
	location_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_area.clip_contents = true
	frame.add_child(location_area)

	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_area.add_child(backdrop)
	var image_path := "res://assets/locations/starting_village.png"
	if ResourceLoader.exists(image_path):
		backdrop.texture = load(image_path)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color("#344638")
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		location_area.add_child(placeholder)
		var hint := _label("Здесь появится иллюстрация стартовой деревни", 18, Color("#e3dcc5"))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		hint.position = Vector2(-235, -70)
		hint.custom_minimum_size.x = 470
		location_area.add_child(hint)

	for service in SERVICES:
		var button := Button.new()
		button.name = str(service["name"])
		button.text = str(service["symbol"]) + "\n" + str(service["name"])
		button.custom_minimum_size = Vector2(118, 64)
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_open_panel.bind(str(service["name"])))
		location_area.add_child(button)
	location_area.resized.connect(_layout_services)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 76
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
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(350, 190)
	add_child(popup)
	var contents := VBoxContainer.new()
	popup.add_child(contents)
	popup_title = _label("", 22, Color("#f1ddbb"))
	contents.add_child(popup_title)
	popup_description = _label("", 16, Color("#d8dbe0"))
	contents.add_child(popup_description)
	var close := Button.new()
	close.text = "Вернуться в поселение"
	close.pressed.connect(func() -> void: popup.visible = false)
	contents.add_child(close)


func _layout_services() -> void:
	if location_area == null:
		return
	for index in range(SERVICES.size()):
		var service: Dictionary = SERVICES[index]
		var button := location_area.get_node_or_null(str(service["name"])) as Button
		if button == null:
			continue
		var point: Vector2 = service["position"]
		button.position = Vector2(
			clampf(location_area.size.x * point.x - 59.0, 0.0, maxf(0.0, location_area.size.x - 118.0)),
			clampf(location_area.size.y * point.y - 32.0, 0.0, maxf(0.0, location_area.size.y - 64.0))
		)


func _open_panel(section: String) -> void:
	popup_title.text = section
	popup_description.text = "Раздел будет подключён на следующем этапе."
	if section == "Меню":
		popup_description.text = "Технические инструменты доступны ниже."
		var debug_map := Button.new()
		debug_map.text = "Отладочная карта"
		debug_map.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/debug/debug_map_viewer.tscn"))
		var debug_combat := Button.new()
		debug_combat.text = "Отладочный бой"
		debug_combat.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/debug/debug_combat_viewer.tscn"))
		for child in popup.get_child(0).get_children():
			if child.name.begins_with("Debug"):
				child.queue_free()
		debug_map.name = "DebugMap"
		debug_combat.name = "DebugCombat"
		popup.get_child(0).add_child(debug_map)
		popup.get_child(0).add_child(debug_combat)
	popup.visible = true


func _label(value: String, font_size: int, tint: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", tint)
	return result
