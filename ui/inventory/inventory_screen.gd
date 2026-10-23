class_name InventoryScreen
extends Control

signal inventory_changed

## Responsive inventory shell. Uses live inventory/equipment instance IDs.
const INVENTORY_LOGICAL_EXTENT := 480.0
const INVENTORY_BACKGROUND_PATH := "res://assets/ui/arena/BOA_ARENA_BACKGROUND_V1.png"
const SLOT_NAMES := {
	"head": "Голова", "shoulders": "Плечи", "neck": "Шея", "back": "Спина",
	"chest": "Грудь", "wrists": "Наручи", "hands": "Перчатки", "waist": "Пояс", "legs": "Ноги",
	"main_hand": "Осн. рука", "off_hand": "Вторая рука",
	"ring1": "Кольцо I", "ring2": "Кольцо II", "feet": "Ступни"
}
var character: CharacterState
var repository: ItemRepository
var back_button: Button
var equipment_grid: GridContainer
const AVATARS := {"wanderer_01": "res://assets/avatars/wanderer_01.svg", "hero_realistic_01": "res://assets/avatars/hero_realistic_01.png"}
var avatar_id: String = "hero_realistic_01"
var avatar_texture: TextureRect
var character_portrait: PanelContainer
var bag_grid: GridContainer
var detail_dialog: ItemDetailDialog
var empty_slot_info: AcceptDialog
var layout_row: BoxContainer
var selected_instance_id := ""
var _last_tap_id := ""
var _last_tap_ms := 0
var discard_mode := false
var discard_ids: Dictionary = {}
var generator_dialog: AcceptDialog
var generator_template: OptionButton
var generator_par: OptionButton
var generator_amount: LineEdit
var generator_added: Label
var generator_status: Label
var generator_bonuses: Dictionary = {}
var discard_button: Button
var discard_cancel: Button
var discard_confirm: ConfirmationDialog
var slot_buttons: Dictionary = {}
var elixir_buttons: Array[ItemIcon] = []
## Reference the character-owned quickslots; no UI-local copy.
var elixir_assignments: Array[String] = ["", "", "", ""]
var _last_portrait := false
var bag_scroll: ScrollContainer
var bag_title: Label
var bag_panel: PanelContainer
var equipment_content: Control
var equipment_background: TextureRect
var visual_lab_dialog: AcceptDialog
var visual_lab_theme: OptionButton
var visual_lab_ghosts: CheckBox
var visual_lab_frames: CheckBox
var visual_lab_background: HSlider
var visual_lab_scenario: OptionButton
var visual_lab_scale: HSlider
var visual_lab_shift: HSlider
var visual_lab_scenario_index := 0
var visual_lab_equipment_scale := 1.0
var visual_lab_equipment_shift := 0.0
var visual_lab_theme_index := 0
var visual_lab_show_ghosts := false
var visual_lab_show_frames := true
var visual_lab_background_alpha := 1.0
var hp_label: Label
var hp_bar: ProgressBar
var stats_content: VBoxContainer
var stat_rows: Dictionary = {}
const RARITY_COLORS := {
	"grey": "#777f8a", "gray": "#777f8a", "common": "#aab0b8",
	"white": "#c5cbd2", "green": "#479c65", "uncommon": "#479c65",
	"blue": "#488acb", "rare": "#488acb", "purple": "#9867c5",
	"epic": "#d39a47", "orange": "#d39a47", "legendary": "#d95353", "red": "#d95353"
}

func _init(p_character: CharacterState = null, p_repository: ItemRepository = null) -> void:
	character = p_character
	repository = p_repository

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("#172334")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var header := HBoxContainer.new()
	back_button = Button.new()
	back_button.text = "← Назад"
	header.add_child(back_button)
	var heading := Label.new()
	heading.text = "Инвентарь"
	heading.add_theme_font_size_override("font_size", 24)
	header.add_child(heading)
	var visual_button := Button.new()
	visual_button.name = "VisualLabButton"
	visual_button.text = "🎨 Визуал"
	visual_button.pressed.connect(_open_visual_lab)
	header.add_child(visual_button)
	layout_row = BoxContainer.new()
	layout_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(layout_row)
	var square_host := Control.new()
	square_host.name = "EquipmentPanel"
	square_host.clip_contents = true
	layout_row.add_child(square_host)
	equipment_content = Control.new()
	equipment_content.name = "SquareContent"
	equipment_content.position = Vector2.ZERO
	equipment_content.size = Vector2(INVENTORY_LOGICAL_EXTENT, INVENTORY_LOGICAL_EXTENT)
	square_host.add_child(equipment_content)
	equipment_background = TextureRect.new()
	equipment_background.name = "InventoryBackground"
	equipment_background.texture = load(INVENTORY_BACKGROUND_PATH) as Texture2D
	# Fixed logical 480x480 image: the enclosing square is uniformly scaled.
	# Full-rect anchors plus explicit size caused Godot _set_size warnings.
	equipment_background.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	equipment_background.custom_minimum_size = Vector2.ZERO
	equipment_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	equipment_background.stretch_mode = TextureRect.STRETCH_SCALE
	equipment_background.size = Vector2(INVENTORY_LOGICAL_EXTENT, INVENTORY_LOGICAL_EXTENT)
	equipment_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_content.add_child(equipment_background)
	var middle := Control.new()
	middle.name = "EquipmentMiddle"
	middle.position = Vector2(23, 18)
	middle.scale = Vector2.ONE * 0.9025
	equipment_content.add_child(middle)
	var left_slots := Control.new()
	left_slots.name = "LeftSlots"
	middle.add_child(left_slots)
	left_slots.position = Vector2(4, 0)
	for slot in ["head", "shoulders", "chest", "main_hand", "waist", "legs", "feet"]:
		_add_equipment_slot(left_slots, slot)
	character_portrait = PanelContainer.new()
	character_portrait.name = "CharacterPortrait"
	character_portrait.custom_minimum_size = Vector2(356, 416)
	character_portrait.position = Vector2(62, 0)
	middle.add_child(character_portrait)
	avatar_texture = TextureRect.new()
	avatar_texture.name = "AvatarImage"
	avatar_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_portrait.add_child(avatar_texture)
	_apply_avatar()
	var portrait_frame := StyleBoxFlat.new()
	portrait_frame.bg_color = Color("#202b3b")
	portrait_frame.border_color = Color("#94774e")
	portrait_frame.set_border_width_all(2)
	character_portrait.add_theme_stylebox_override("panel", portrait_frame)
	var portrait_overlay := Control.new()
	portrait_overlay.name = "PortraitOverlay"
	character_portrait.add_child(portrait_overlay)
	portrait_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var health := HBoxContainer.new()
	health.name = "Health"
	health.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	health.position = Vector2(8, 8)
	health.custom_minimum_size = Vector2(340, 22)
	portrait_overlay.add_child(health)
	hp_label = Label.new()
	hp_label.custom_minimum_size.x = 105
	health.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 20
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	var hp_background := StyleBoxFlat.new()
	hp_background.bg_color = Color("#35383e")
	hp_background.border_color = Color("#b39a69")
	hp_background.set_border_width_all(2)
	hp_background.set_corner_radius_all(3)
	hp_bar.add_theme_stylebox_override("background", hp_background)
	health.add_child(hp_bar)

	var right_slots := Control.new()
	right_slots.name = "RightSlots"
	middle.add_child(right_slots)
	right_slots.position = Vector2(420, 0)
	for slot in ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]:
		_add_equipment_slot(right_slots, slot)
	var elixirs := HBoxContainer.new()
	elixirs.position = Vector2(122, 405)
	elixirs.name = "ElixirSlots"
	elixirs.alignment = BoxContainer.ALIGNMENT_CENTER
	elixirs.add_theme_constant_override("separation", 4)
	equipment_content.add_child(elixirs)
	for i in range(4):
		var quick := ItemIcon.new()
		quick.name = "Elixir%d" % (i + 1)
		elixirs.add_child(quick)
		quick.set_empty_placeholder_icon_visible(false)
		quick.set_item({}, "Эликсир %d" % (i + 1))
		quick.pressed.connect(_clear_elixir_slot.bind(i))
		elixir_buttons.append(quick)

	var stats_panel := VBoxContainer.new()
	stats_panel.name = "StatsPanel"
	stats_panel.position = Vector2.ZERO
	stats_panel.custom_minimum_size = Vector2(0, 112)
	stats_panel.add_theme_constant_override("separation", 1)
	var heading_stats := Label.new()
	heading_stats.text = "БОЕВЫЕ ХАРАКТЕРИСТИКИ"
	stats_panel.add_child(heading_stats)
	var stats_scroll := ScrollContainer.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.custom_minimum_size.y = 118
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stats_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stats_panel.add_child(stats_scroll)
	var table := HBoxContainer.new()
	table.name = "CombatTable"
	table.add_theme_constant_override("separation", 6)
	stats_scroll.add_child(table)
	var groups: Array = [
		["Атака", ["Урон оружия", "Попадание", "Крит"]],
		["Защита", ["Броня по зонам", "Уклонение", "Блок"]],
		["Маг. атака", ["Мана", "Магический урон", "Усиление стихий"]],
		["Маг. защита", ["Общее сопротивление", "Сопротивления стихиям"]]
	]
	for group in groups:
		var frame := PanelContainer.new()
		frame.name = "Group" + str(table.get_child_count() + 1)
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color("#202b3b")
		frame_style.border_color = Color("#756448")
		frame_style.set_border_width_all(1)
		frame_style.set_corner_radius_all(3)
		frame_style.content_margin_left = 7
		frame_style.content_margin_right = 7
		frame_style.content_margin_top = 4
		frame_style.content_margin_bottom = 4
		frame.add_theme_stylebox_override("panel", frame_style)
		table.add_child(frame)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		frame.add_child(column)
		var title := Label.new()
		title.text = String(group[0])
		title.add_theme_color_override("font_color", Color("#d3b37b"))
		column.add_child(title)
		for raw_name in group[1]:
			var name: String = String(raw_name)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 9)
			column.add_child(row)
			var label := Label.new()
			label.text = name
			label.add_theme_font_size_override("font_size", 11)
			row.add_child(label)
			var value := Label.new()
			value.text = "—"
			value.custom_minimum_size.x = 36
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.add_theme_font_size_override("font_size", 11)
			row.add_child(value)
			stat_rows[name] = value
	stats_content = stats_panel
	bag_panel = PanelContainer.new()
	bag_panel.name = "BagPanel"
	var bag_frame := StyleBoxFlat.new()
	bag_frame.bg_color = Color("#171c25")
	bag_frame.border_color = Color("#756448")
	bag_frame.set_border_width_all(1)
	bag_frame.content_margin_left = 10
	bag_frame.content_margin_right = 10
	bag_frame.content_margin_top = 6
	bag_frame.content_margin_bottom = 6
	bag_panel.add_theme_stylebox_override("panel", bag_frame)
	bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_row.add_child(bag_panel)
	var bag_content := VBoxContainer.new()
	bag_panel.add_child(bag_content)
	bag_content.add_child(header)
	bag_content.move_child(header, 0)
	bag_content.add_child(stats_panel)
	bag_content.move_child(stats_panel, 1)
	var bag_heading := HBoxContainer.new()
	bag_content.add_child(bag_heading)
	bag_title = Label.new()
	bag_title.text = "Сумка"
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_heading.add_child(bag_title)
	var generate_button := Button.new()
	generate_button.text = "Генератор"
	generate_button.pressed.connect(_open_item_generator)
	bag_heading.add_child(generate_button)
	_build_item_generator()
	discard_button = Button.new()
	discard_button.text = "Выкинуть"
	discard_button.pressed.connect(_discard_button_pressed)
	bag_heading.add_child(discard_button)
	discard_cancel = Button.new()
	discard_cancel.text = "Отмена"
	discard_cancel.visible = false
	discard_cancel.pressed.connect(_cancel_discard)
	bag_heading.add_child(discard_cancel)
	bag_scroll = ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_content.add_child(bag_scroll)
	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(bag_grid)
	detail_dialog = ItemDetailDialog.new(character, repository)
	add_child(detail_dialog)
	# Empty slots are still clickable hit regions over the square artwork.
	empty_slot_info = AcceptDialog.new()
	empty_slot_info.title = "Слот экипировки"
	empty_slot_info.ok_button_text = "Закрыть"
	add_child(empty_slot_info)
	discard_confirm = ConfirmationDialog.new()
	discard_confirm.title = "Подтверждение"
	discard_confirm.ok_button_text = "Да"
	discard_confirm.cancel_button_text = "Отмена"
	discard_confirm.confirmed.connect(_confirm_discard)
	add_child(discard_confirm)
	_build_visual_lab()
	detail_dialog.changed.connect(refresh)
	detail_dialog.elixir_requested.connect(_assign_elixir)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()

## Design experiments are intentionally session-only and never touch saves.
func _build_visual_lab() -> void:
	visual_lab_dialog = AcceptDialog.new()
	visual_lab_dialog.name = "VisualLabDialog"
	visual_lab_dialog.title = "Visual Lab · Inventory"
	visual_lab_dialog.ok_button_text = "Закрыть"
	visual_lab_dialog.min_size = Vector2i(310, 450)
	add_child(visual_lab_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	visual_lab_dialog.add_child(column)
	var note := Label.new()
	note.text = "Эксперименты без изменения предметов и сохранений."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	visual_lab_theme = OptionButton.new()
	visual_lab_theme.name = "Theme"
	for theme_data in VisualLabPresets.THEMES:
		visual_lab_theme.add_item(String(theme_data["title"]))
	visual_lab_theme.item_selected.connect(_visual_lab_theme_changed)
	column.add_child(visual_lab_theme)
	visual_lab_ghosts = CheckBox.new()
	visual_lab_ghosts.name = "GhostIcons"
	visual_lab_ghosts.text = "Силуэты пустых слотов"
	visual_lab_ghosts.button_pressed = false
	visual_lab_ghosts.toggled.connect(_visual_lab_ghosts_changed)
	column.add_child(visual_lab_ghosts)
	visual_lab_frames = CheckBox.new()
	visual_lab_frames.name = "EmptyFrames"
	visual_lab_frames.text = "Рамки пустых слотов"
	visual_lab_frames.button_pressed = true
	visual_lab_frames.toggled.connect(_visual_lab_frames_changed)
	column.add_child(visual_lab_frames)
	var opacity_label := Label.new()
	opacity_label.text = "Насыщенность фонового арта"
	column.add_child(opacity_label)
	visual_lab_background = HSlider.new()
	visual_lab_background.name = "BackgroundStrength"
	visual_lab_background.min_value = 0.15
	visual_lab_background.max_value = 1.0
	visual_lab_background.step = 0.05
	visual_lab_background.value = 1.0
	visual_lab_background.value_changed.connect(_visual_lab_background_changed)
	column.add_child(visual_lab_background)
	visual_lab_scenario = OptionButton.new()
	visual_lab_scenario.name = "Scenario"
	for scenario_name in VisualLabPreview.SCENARIOS:
		visual_lab_scenario.add_item(scenario_name)
	visual_lab_scenario.item_selected.connect(_visual_lab_scenario_changed)
	column.add_child(visual_lab_scenario)
	var scale_label := Label.new()
	scale_label.text = "Размер блока экипировки: 80–105%"
	column.add_child(scale_label)
	visual_lab_scale = HSlider.new()
	visual_lab_scale.name = "EquipmentScale"
	visual_lab_scale.min_value = 0.8
	visual_lab_scale.max_value = 1.05
	visual_lab_scale.step = 0.025
	visual_lab_scale.value = 1.0
	visual_lab_scale.value_changed.connect(_visual_lab_scale_changed)
	column.add_child(visual_lab_scale)
	var shift_label := Label.new()
	shift_label.text = "Смещение экипировки по горизонтали"
	column.add_child(shift_label)
	visual_lab_shift = HSlider.new()
	visual_lab_shift.name = "EquipmentShift"
	visual_lab_shift.min_value = -20
	visual_lab_shift.max_value = 20
	visual_lab_shift.step = 1
	visual_lab_shift.value_changed.connect(_visual_lab_shift_changed)
	column.add_child(visual_lab_shift)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Вернуть исходный вид"
	reset.pressed.connect(_reset_visual_lab)
	column.add_child(reset)

func _open_visual_lab() -> void:
	visual_lab_dialog.popup_centered(Vector2i(360, 520))

func _visual_lab_theme_changed(index: int) -> void:
	visual_lab_theme_index = index
	_apply_visual_lab()

func _visual_lab_ghosts_changed(value: bool) -> void:
	visual_lab_show_ghosts = value
	_apply_visual_lab()

func _visual_lab_frames_changed(value: bool) -> void:
	visual_lab_show_frames = value
	_apply_visual_lab()

func _visual_lab_background_changed(value: float) -> void:
	visual_lab_background_alpha = value
	_apply_visual_lab()

func _visual_lab_scenario_changed(index: int) -> void:
	visual_lab_scenario_index = index
	_apply_visual_lab()

func _visual_lab_scale_changed(value: float) -> void:
	visual_lab_equipment_scale = value
	_apply_visual_lab()

func _visual_lab_shift_changed(value: float) -> void:
	visual_lab_equipment_shift = value
	_apply_visual_lab()

func _reset_visual_lab() -> void:
	visual_lab_theme.select(0)
	visual_lab_ghosts.set_pressed_no_signal(false)
	visual_lab_frames.set_pressed_no_signal(true)
	visual_lab_background.set_value_no_signal(1.0)
	visual_lab_scenario.select(0)
	visual_lab_scale.set_value_no_signal(1.0)
	visual_lab_shift.set_value_no_signal(0.0)
	visual_lab_scenario_index = 0
	visual_lab_equipment_scale = 1.0
	visual_lab_equipment_shift = 0.0
	visual_lab_theme_index = 0
	visual_lab_show_ghosts = false
	visual_lab_show_frames = true
	visual_lab_background_alpha = 1.0
	_apply_visual_lab()

func _apply_visual_lab() -> void:
	if equipment_background == null:
		return
	var middle := equipment_content.get_node_or_null("EquipmentMiddle") as Control
	if middle != null:
		middle.scale = Vector2.ONE * (0.9025 * visual_lab_equipment_scale)
		middle.position = Vector2(23.0 + visual_lab_equipment_shift, 18.0)
	var palette := VisualLabPresets.theme(visual_lab_theme_index)
	equipment_background.modulate = Color(String(palette["background"]))
	equipment_background.modulate.a = visual_lab_background_alpha
	var preview_index := 0
	for slot in slot_buttons:
		var icon := slot_buttons[slot] as ItemIcon
		VisualLabPresets.configure_empty(icon, visual_lab_theme_index, visual_lab_show_ghosts, visual_lab_show_frames)
		var mock_active := visual_lab_scenario_index == 2 or (visual_lab_scenario_index == 1 and preview_index < 4)
		VisualLabPreview.show_mock(icon, mock_active, preview_index % VisualLabPreview.RARITIES.size())
		preview_index += 1
	for icon in elixir_buttons:
		VisualLabPresets.configure_empty(icon, visual_lab_theme_index, visual_lab_show_ghosts, visual_lab_show_frames)

func _add_equipment_slot(parent: Control, slot: String) -> void:
	var button := ItemIcon.new()
	button.name = slot
	button.pressed.connect(_select_slot.bind(slot))
	parent.add_child(button)
	button.set_empty_placeholder_icon_visible(false)
	button.set_item({}, SLOT_NAMES[slot])
	var row_index := parent.get_child_count() - 1
	button.position = Vector2(0, row_index * 60)
	slot_buttons[slot] = button


func _apply_layout() -> void:
	if layout_row == null:
		return
	var portrait := size.y > size.x
	_last_portrait = portrait
	layout_row.vertical = portrait
	var square_host := layout_row.get_node("EquipmentPanel") as Control
	var separation := float(layout_row.get_theme_constant("separation"))
	var available_width := size.x
	var available_height := size.y
	if portrait:
		available_height = maxf(1.0, size.y - 180.0 - separation)
	else:
		available_width = maxf(1.0, size.x - 260.0 - separation)
	var square_size := floorf(maxf(1.0, minf(available_width, available_height)))
	SquareUiGeometry.fit(square_host, equipment_content, square_size, INVENTORY_LOGICAL_EXTENT)
	if equipment_background != null:
		equipment_background.size = Vector2(INVENTORY_LOGICAL_EXTENT, INVENTORY_LOGICAL_EXTENT)
	layout_row.add_theme_constant_override("separation", 10)
	var cell_size := ItemIcon.CELL_SIZE * (square_size / 480.0)
	var gap := 8.0 * (square_size / 480.0)
	bag_grid.add_theme_constant_override("h_separation", roundi(gap))
	bag_grid.add_theme_constant_override("v_separation", roundi(gap))
	var bag_width := size.x if portrait else size.x - square_size - 10.0
	bag_width = maxf(1.0, bag_width - 22.0)
	bag_grid.columns = maxi(1, int(floor((bag_width + gap) / (cell_size + gap))))
	for icon in bag_grid.get_children():
		(icon as ItemIcon).custom_minimum_size = Vector2.ONE * cell_size

func _refresh_combat_stats() -> void:
	if stats_content == null:
		return
	for value in stat_rows.values():
		(value as Label).text = "—"
	if character == null or repository == null:
		hp_label.text = "HP —"
		hp_bar.value = 0
		_set_hp_colour(0.0)
		return
	var snapshot := CharacterCombatBuilder.build(character, repository)
	if snapshot == null:
		hp_label.text = "HP —"
		hp_bar.value = 0
		_set_hp_colour(0.0)
		push_error("Inventory combat stats unavailable: invalid character combat snapshot")
		return
	hp_label.text = "HP %d/%d" % [snapshot.hp, snapshot.max_hp]
	hp_bar.max_value = maxi(1, snapshot.max_hp)
	hp_bar.value = snapshot.hp
	_set_hp_colour(float(snapshot.hp) / float(maxi(1, snapshot.max_hp)))
	(stat_rows["Мана"] as Label).text = "%d / %d" % [snapshot.mana, snapshot.max_mana]
	if not snapshot.armour.is_empty():
		(stat_rows["Броня по зонам"] as Label).text = str(snapshot.armour)

func _set_hp_colour(remaining_fraction: float) -> void:
	if hp_bar == null:
		return
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e34b4b") if remaining_fraction <= 0.20 else (Color("#e3bf42") if remaining_fraction <= 0.50 else Color("#35bd61"))
	fill.set_corner_radius_all(2)
	hp_bar.add_theme_stylebox_override("fill", fill)


func _select_slot(slot: String) -> void:
	if discard_mode:
		return
	if character == null:
		return
	var id: Variant = character.equipment.get_equipped_instance_id(slot)
	selected_instance_id = String(id) if id != null else ""
	if id != null:
		_tap_item(selected_instance_id, slot, slot_buttons[slot] as Control)
	elif empty_slot_info != null:
		empty_slot_info.dialog_text = "%s — пусто" % SquareUiGeometry.equipment_name(slot)
		empty_slot_info.popup_centered(Vector2i(280, 110))

func _select_item(instance_id: String) -> void:
	if discard_mode:
		if discard_ids.has(instance_id):
			discard_ids.erase(instance_id)
		else:
			discard_ids[instance_id] = true
		_update_discard_controls()
		return
	selected_instance_id = instance_id
	for icon in bag_grid.get_children():
		if (icon as ItemIcon).instance_id == instance_id:
			_tap_item(instance_id, "", icon as Control)
			return

func _tap_item(instance_id: String, slot: String, target: Control) -> void:
	var now_ms := Time.get_ticks_msec()
	if _last_tap_id == instance_id and now_ms - _last_tap_ms <= 360:
		_last_tap_id = ""
		detail_dialog.item_id = instance_id
		detail_dialog.source_slot = slot
		if slot.is_empty():
			var item := repository.get_item(instance_id)
			if String(item.get("type", "")) == "consumable":
				_assign_elixir(instance_id)
			else:
				detail_dialog._equip()
		else:
			detail_dialog._unequip()
		return
	_last_tap_id = instance_id
	_last_tap_ms = now_ms
	if detail_dialog.visible and detail_dialog.item_id == instance_id:
		detail_dialog.visible = false
	else:
		detail_dialog.show_item(instance_id, slot, target)

func refresh() -> void:
	if character != null:
		elixir_assignments = character.elixir_slots.duplicate()
	if bag_grid == null:
		return
	_refresh_combat_stats()
	_refresh_elixir_slots()
	for slot in slot_buttons:
		var button := slot_buttons[slot] as Button
		var id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		var item := repository.get_item(String(id)) if id != null and repository != null else {}
		(button as ItemIcon).set_item(item, SLOT_NAMES[slot], id != null)
		button.modulate = Color("#ed5961") if id != null and not character.is_equipment_active(String(id), repository) else Color.WHITE
	_apply_visual_lab()
	for child in bag_grid.get_children():
		bag_grid.remove_child(child)
		child.queue_free()
	if character == null or repository == null:
		return
	var owned_ids: Array = []
	for instance_id in character.inventory.instance_ids():
		if not character.equipment.is_equipped(String(instance_id)) and not character.elixir_slots.has(String(instance_id)):
			owned_ids.append(instance_id)
	bag_title.text = "Сумка (%d)" % owned_ids.size()
	for instance_id in owned_ids:
		var item := repository.get_item(String(instance_id))
		var button := ItemIcon.new()
		button.pressed.connect(_select_item.bind(String(instance_id)))
		bag_grid.add_child(button)
		button.custom_minimum_size = Vector2.ONE * (ItemIcon.CELL_SIZE * (maxf(1.0, minf(size.x, size.y)) / 480.0))
		button.set_item(item, "", false)
	inventory_changed.emit()

func _assign_elixir(instance_id: String) -> void:
	if character == null or not character.inventory.owns(instance_id) or repository == null:
		return
	if character.elixir_slots.has(instance_id):
		detail_dialog.status_label.text = "Этот эликсир уже размещён в слоте."
		return
	var item := repository.get_item(instance_id)
	if String(item.get("type", "")) != "consumable":
		return
	for index in range(character.elixir_capacity(repository)):
		if character.elixir_slots[index].is_empty() and character.assign_elixir(index, instance_id, repository):
			detail_dialog.visible = false
			refresh()
			return
	detail_dialog.status_label.text = "Нет доступного слота эликсира — нужен пояс или свободное место."

func _clear_elixir_slot(index: int) -> void:
	if index < 0 or index >= elixir_assignments.size():
		return
	if character != null and character.clear_elixir(index):
		refresh()

func _refresh_elixir_slots() -> void:
	for index in range(elixir_buttons.size()):
		var instance_id := character.elixir_slots[index] if character != null else ""
		var item := repository.get_item(instance_id) if not instance_id.is_empty() and repository != null else {}
		elixir_buttons[index].set_item(item, "Эликсир %d" % (index + 1), not instance_id.is_empty())

func _rarity_color(item: Dictionary) -> Color:
	var rarity := str(item.get("rarity", "grey")).to_lower()
	return Color(str(RARITY_COLORS.get(rarity, "#777f8a")))


func _style_item_button(button: Button, border_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#263346")
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#33445a")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color("#eee4d2"))
	button.add_theme_font_size_override("font_size", 12)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func set_avatar_id(new_id: String) -> void:
	if not AVATARS.has(new_id):
		return
	avatar_id = new_id
	_apply_avatar()

func _apply_avatar() -> void:
	if avatar_texture == null:
		return
	var resource_path: String = String(AVATARS.get(avatar_id, AVATARS["wanderer_01"]))
	avatar_texture.texture = load(resource_path) as Texture2D

func _discard_button_pressed() -> void:
	if not discard_mode:
		discard_mode = true
		discard_ids.clear()
		detail_dialog.visible = false
		_update_discard_controls()
		return
	if discard_ids.is_empty():
		return
	discard_confirm.dialog_text = "Вы уверены, что хотите выкинуть эти предметы? (%d)" % discard_ids.size()
	discard_confirm.popup_centered()

func _cancel_discard() -> void:
	discard_mode = false
	discard_ids.clear()
	_update_discard_controls()

func _update_discard_controls() -> void:
	discard_cancel.visible = discard_mode
	discard_button.text = "Выкинуть (%d)" % discard_ids.size() if discard_mode else "Выкинуть"
	discard_button.disabled = discard_mode and discard_ids.is_empty()
	for icon in bag_grid.get_children():
		var item_icon := icon as ItemIcon
		item_icon.modulate = Color("#e5b35c") if discard_ids.has(item_icon.instance_id) else Color.WHITE

func _confirm_discard() -> void:
	if character == null or repository == null or not character.inventory.has_method("remove_instance"):
		return
	for id in discard_ids.keys():
		var item_id := String(id)
		if character.inventory.owns(item_id) and not character.equipment.is_equipped(item_id) and not character.elixir_slots.has(item_id):
			character.remove_item(item_id)
	_cancel_discard()
	refresh()


# Preview-only generator: produces real instances of locked templates.
func _build_item_generator() -> void:
	generator_dialog = AcceptDialog.new()
	generator_dialog.title = "Генератор предметов (тест)"
	generator_dialog.ok_button_text = "Закрыть"
	generator_dialog.min_size = Vector2i(560, 650)
	add_child(generator_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 550)
	generator_dialog.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var heading := Label.new()
	heading.text = "Шаблон предмета"
	content.add_child(heading)
	generator_template = OptionButton.new()
	content.add_child(generator_template)
	var par_heading := Label.new()
	par_heading.text = "Дополнительный PAR"
	content.add_child(par_heading)
	generator_par = OptionButton.new()
	content.add_child(generator_par)
	generator_amount = LineEdit.new()
	generator_amount.text = "10"
	generator_amount.placeholder_text = "Введите числовой бонус, например 30"
	generator_amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	content.add_child(generator_amount)
	# Web/mobile fallback: HTML canvas keyboard focus is unreliable on some browsers.
	# These buttons always allow numeric entry without the system keyboard.
	var keypad := GridContainer.new()
	keypad.columns = 3
	keypad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(keypad)
	for key_label in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "−", "0", "⌫"]:
		var key_button := Button.new()
		key_button.text = key_label
		key_button.custom_minimum_size = Vector2(72, 42)
		key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keypad.add_child(key_button)
		key_button.pressed.connect(_generator_keypad_press.bind(key_label))
	var reset_button := Button.new()
	reset_button.text = "Очистить число"
	reset_button.pressed.connect(func() -> void: generator_amount.text = "")
	content.add_child(reset_button)
	var add_button := Button.new()
	add_button.text = "Добавить PAR"
	add_button.pressed.connect(_generator_add_par)
	content.add_child(add_button)
	generator_added = Label.new()
	generator_added.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(generator_added)
	var clear_button := Button.new()
	clear_button.text = "Очистить бонусы"
	clear_button.pressed.connect(func() -> void:
		generator_bonuses.clear()
		_generator_update_summary()
	)
	content.add_child(clear_button)
	var create_button := Button.new()
	create_button.text = "Создать в сумке"
	create_button.pressed.connect(_generator_create)
	content.add_child(create_button)
	var enemy_button := Button.new()
	enemy_button.text = "Надеть на противника (манекен)"
	enemy_button.pressed.connect(_generator_equip_dummy)
	content.add_child(enemy_button)
	var clear_dummy_button := Button.new()
	clear_dummy_button.text = "Снять всё с манекена"
	clear_dummy_button.pressed.connect(func() -> void:
		ArenaCombatSession.training_dummy_items.clear()
		ArenaCombatSession.training_dummy_clear_defaults = true
		generator_status.text = "Экипировка манекена очищена. Применится при следующем входе на арену."
	)
	content.add_child(clear_dummy_button)
	generator_status = Label.new()
	generator_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(generator_status)


func _open_item_generator() -> void:
	generator_template.clear()
	var templates := ItemTemplateService.load_templates()
	var template_ids: Array = templates.keys()
	template_ids.sort()
	for template_id in template_ids:
		generator_template.add_item("%s — %s" % [template_id, String(Dictionary(templates[template_id]).get("name", template_id))])
		generator_template.set_item_metadata(generator_template.item_count - 1, template_id)
	generator_par.clear()
	var definitions := ParCalculationService.registry()
	var ids: Array = definitions.keys()
	ids.sort()
	for par_id in ids:
		# PAR057 is structural: it must come exclusively from the weapon template.
		if par_id == "PAR057":
			continue
		generator_par.add_item("%s — %s" % [par_id, String(Dictionary(definitions[par_id]).get("name", par_id))])
		generator_par.set_item_metadata(generator_par.item_count - 1, par_id)
	generator_bonuses.clear()
	_generator_update_summary()
	generator_status.text = "" if not template_ids.is_empty() else "Шаблоны не найдены."
	generator_dialog.popup_centered()


func _generator_keypad_press(key_label: String) -> void:
	var current := generator_amount.text
	match key_label:
		"⌫":
			generator_amount.text = current.substr(0, maxi(0, current.length() - 1))
		"−":
			generator_amount.text = current.substr(1) if current.begins_with("-") else "-" + current
		_:
			if current.length() < 7:
				generator_amount.text = current + key_label


func _generator_add_par() -> void:
	if generator_par.selected < 0:
		return
	var par_id := String(generator_par.get_selected_metadata())
	var entered := generator_amount.text.strip_edges()
	if not entered.is_valid_int():
		generator_status.text = "Введите целое число (например, 30 или -10)."
		return
	var amount := int(entered)
	if amount < -100000 or amount > 100000:
		generator_status.text = "Допустимый диапазон: -100000 ... 100000."
		return
	if amount == 0:
		generator_status.text = "Укажите ненулевой бонус."
		return
	generator_bonuses[par_id] = amount
	generator_status.text = ""
	_generator_update_summary()


func _generator_update_summary() -> void:
	if generator_added == null:
		return
	var entries: Array[String] = []
	var ids: Array = generator_bonuses.keys()
	ids.sort()
	for par_id in ids:
		var par_name := String(Dictionary(ParCalculationService.registry().get(par_id, {})).get("name", par_id))
		entries.append("%s — %s: %+d" % [par_id, par_name, int(generator_bonuses[par_id])])
	generator_added.text = "Бонусы: " + (", ".join(entries) if not entries.is_empty() else "нет")


func _generator_create() -> void:
	if character == null or repository == null or generator_template.selected < 0:
		generator_status.text = "Выберите шаблон."
		return
	var template_id := String(generator_template.get_selected_metadata())
	var templates := ItemTemplateService.load_templates()
	if not templates.has(template_id):
		generator_status.text = "Шаблон не найден."
		return
	var item := {
		"instance_id": "preview_%s_%s" % [template_id, str(Time.get_ticks_usec())],
		"template_id": template_id,
		"origin": "preview_generator",
		"par_bonuses": generator_bonuses.duplicate(true)
	}
	ItemDurabilityService.initialize_item(item, 100)
	if ItemTemplateService.resolve(item).is_empty():
		generator_status.text = "Предмет не прошёл проверку шаблона/PAR."
		return
	if not repository.add_item(item):
		generator_status.text = "Не удалось создать экземпляр."
		return
	var instance_id := String(item["instance_id"])
	if not character.receive_item(instance_id, repository):
		repository.remove_item(instance_id)
		generator_status.text = "Не удалось положить предмет в сумку."
		return
	refresh()
	generator_status.text = "Создан: %s. Предмет в сумке." % String(Dictionary(templates[template_id]).get("name", template_id))


# Preview-only: keep the generated test item in the training dummy loadout.
func _generator_equip_dummy() -> void:
	if generator_template.selected < 0:
		generator_status.text = "Выберите шаблон предмета."
		return
	var template_id := String(generator_template.get_selected_metadata())
	var templates := ItemTemplateService.load_templates()
	if not templates.has(template_id):
		generator_status.text = "Шаблон не найден."
		return
	var template: Dictionary = templates[template_id]
	var slots: Array = template.get("equip_slots", [])
	if slots.is_empty():
		generator_status.text = "Предмет нельзя экипировать."
		return
	var slot := String(slots[0])
	var instance := {
		"instance_id": "dummy_%s_%s" % [template_id, str(Time.get_ticks_usec())],
		"template_id": template_id,
		"origin": "preview_dummy_generator",
		"par_bonuses": generator_bonuses.duplicate(true)
	}
	if ItemTemplateService.resolve(instance).is_empty():
		generator_status.text = "Предмет не прошёл проверку шаблона/PAR."
		return
	ArenaCombatSession.training_dummy_items[slot] = instance.duplicate(true)
	generator_status.text = "Манекен: %s → %s. Вступит в силу при следующем входе на арену." % [String(template.get("name", template_id)), String(SLOT_NAMES.get(slot, slot))]
