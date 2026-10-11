class_name InventoryScreen
extends Control

## Responsive inventory shell. Uses live inventory/equipment instance IDs.
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
const AVATARS := {"wanderer_01": "res://assets/avatars/wanderer_01.svg"}
var avatar_id: String = "wanderer_01"
var avatar_texture: TextureRect
var character_portrait: PanelContainer
var bag_grid: GridContainer
var detail_dialog: ItemDetailDialog
var layout_row: BoxContainer
var selected_instance_id := ""
var slot_buttons: Dictionary = {}
var _last_portrait := false
var bag_scroll: ScrollContainer
var bag_title: Label
var bag_panel: PanelContainer
var equipment_content: Control
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
	equipment_content.custom_minimum_size = Vector2(480, 480)
	square_host.add_child(equipment_content)
	var middle := Control.new()
	middle.name = "EquipmentMiddle"
	equipment_content.add_child(middle)
	var left_slots := Control.new()
	left_slots.name = "LeftSlots"
	middle.add_child(left_slots)
	left_slots.position = Vector2(0, 0)
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
	health.add_child(hp_bar)

	var right_slots := Control.new()
	right_slots.name = "RightSlots"
	middle.add_child(right_slots)
	right_slots.position = Vector2(424, 0)
	for slot in ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]:
		_add_equipment_slot(right_slots, slot)
	var elixirs := HBoxContainer.new()
	elixirs.position = Vector2(122, 420)
	elixirs.name = "ElixirSlots"
	elixirs.alignment = BoxContainer.ALIGNMENT_CENTER
	elixirs.add_theme_constant_override("separation", 4)
	equipment_content.add_child(elixirs)
	for i in range(4):
		var quick := ItemIcon.new()
		quick.name = "Elixir%d" % (i + 1)
		elixirs.add_child(quick)
		quick.set_item({}, "Эликсир %d" % (i + 1))

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
	bag_title = Label.new()
	bag_title.text = "Сумка"
	bag_content.add_child(bag_title)
	bag_scroll = ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_content.add_child(bag_scroll)
	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(bag_grid)
	detail_dialog = ItemDetailDialog.new(character, repository)
	add_child(detail_dialog)
	detail_dialog.changed.connect(refresh)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()

func _add_equipment_slot(parent: Control, slot: String) -> void:
	var button := ItemIcon.new()
	button.name = slot
	button.pressed.connect(_select_slot.bind(slot))
	parent.add_child(button)
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
	var available := minf(size.x, size.y)
	var square_size := maxf(1.0, available)
	square_host.custom_minimum_size = Vector2(square_size, square_size)
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	equipment_content.scale = Vector2.ONE * (square_size / 480.0)
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
		return
	var base := {"stats": character.progression.base_stats.duplicate(true)}
	var snapshot := CharacterCombatBuilder.build(character, repository, base)
	hp_label.text = "HP %d/%d" % [snapshot.hp, snapshot.max_hp]
	hp_bar.max_value = maxi(1, snapshot.max_hp)
	hp_bar.value = snapshot.hp
	(stat_rows["Мана"] as Label).text = str(snapshot.max_mana)
	if not snapshot.armour.is_empty():
		(stat_rows["Броня по зонам"] as Label).text = str(snapshot.armour)

func _select_slot(slot: String) -> void:
	if character == null:
		return
	var id: Variant = character.equipment.get_equipped_instance_id(slot)
	selected_instance_id = String(id) if id != null else ""
	if id != null:
		detail_dialog.show_item(selected_instance_id, slot)

func _select_item(instance_id: String) -> void:
	selected_instance_id = instance_id
	detail_dialog.show_item(instance_id)

func refresh() -> void:
	if bag_grid == null:
		return
	_refresh_combat_stats()
	for slot in slot_buttons:
		var button := slot_buttons[slot] as Button
		var id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		var item := repository.get_item(String(id)) if id != null and repository != null else {}
		(button as ItemIcon).set_item(item, SLOT_NAMES[slot], id != null)
	for child in bag_grid.get_children():
		bag_grid.remove_child(child)
		child.queue_free()
	if character == null or repository == null:
		return
	var owned_ids := character.inventory.instance_ids()
	bag_title.text = "Сумка (%d)" % owned_ids.size()
	for instance_id in owned_ids:
		var item := repository.get_item(String(instance_id))
		var button := ItemIcon.new()
		button.pressed.connect(_select_item.bind(String(instance_id)))
		bag_grid.add_child(button)
		button.custom_minimum_size = Vector2.ONE * (ItemIcon.CELL_SIZE * (maxf(1.0, minf(size.x, size.y)) / 480.0))
		button.set_item(item, "", character.equipment.is_equipped(String(instance_id)))

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
