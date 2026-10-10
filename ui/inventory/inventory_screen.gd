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
var character_portrait: PanelContainer
var bag_grid: GridContainer
var detail_dialog: ItemDetailDialog
var layout_row: BoxContainer
var selected_instance_id := ""
var slot_buttons: Dictionary = {}
var _last_portrait := false
var bag_scroll: ScrollContainer
var bag_title: Label
var equipment_content: VBoxContainer
var hp_label: Label
var hp_bar: ProgressBar
var stats_content: VBoxContainer
var stat_tabs: Array[Button] = []
var active_stat_tab := 0
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
	root.add_child(header)
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
	equipment_content = VBoxContainer.new()
	equipment_content.name = "SquareContent"
	equipment_content.add_theme_constant_override("separation", 3)
	equipment_content.position = Vector2.ZERO
	equipment_content.custom_minimum_size = Vector2(480, 480)
	square_host.add_child(equipment_content)
	var middle := HBoxContainer.new()
	middle.name = "EquipmentMiddle"
	middle.add_theme_constant_override("separation", 6)
	equipment_content.add_child(middle)
	var left_slots := VBoxContainer.new()
	left_slots.name = "LeftSlots"
	left_slots.add_theme_constant_override("separation", 4)
	middle.add_child(left_slots)
	for slot in ["head", "shoulders", "chest", "main_hand", "waist", "legs", "feet"]:
		_add_equipment_slot(left_slots, slot)
	character_portrait = PanelContainer.new()
	character_portrait.name = "CharacterPortrait"
	character_portrait.custom_minimum_size = Vector2(356, 416)
	middle.add_child(character_portrait)
	var portrait_label := Label.new()
	portrait_label.text = "✦\nГЕРОЙ\nПО ПОЯС\n✦"
	portrait_label.add_theme_font_size_override("font_size", 19)
	portrait_label.add_theme_color_override("font_color", Color("#d3b37b"))
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	character_portrait.add_child(portrait_label)
	var portrait_frame := StyleBoxFlat.new()
	portrait_frame.bg_color = Color("#202b3b")
	portrait_frame.border_color = Color("#94774e")
	portrait_frame.set_border_width_all(2)
	character_portrait.add_theme_stylebox_override("panel", portrait_frame)
	var health := HBoxContainer.new()
	health.name = "Health"
	health.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	health.position = Vector2(8, 8)
	health.custom_minimum_size = Vector2(340, 22)
	character_portrait.add_child(health)
	hp_label = Label.new()
	hp_label.custom_minimum_size.x = 105
	health.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 20
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	health.add_child(hp_bar)

	var right_slots := VBoxContainer.new()
	right_slots.name = "RightSlots"
	right_slots.add_theme_constant_override("separation", 4)
	middle.add_child(right_slots)
	for slot in ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]:
		_add_equipment_slot(right_slots, slot)
	var elixirs := HBoxContainer.new()
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
	stats_panel.position = Vector2(8, 290)
	stats_panel.custom_minimum_size = Vector2(340, 112)
	stats_panel.add_theme_constant_override("separation", 1)
	character_portrait.add_child(stats_panel)
	var tabs := HBoxContainer.new()
	tabs.name = "StatTabs"
	tabs.add_theme_constant_override("separation", 1)
	stats_panel.add_child(tabs)
	for i in range(4):
		var tab := Button.new()
		tab.text = ["Атака", "Маг. атака", "Защита", "Маг. защита"][i]
		tab.add_theme_font_size_override("font_size", 10)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_choose_stat_tab.bind(i))
		tabs.add_child(tab)
		stat_tabs.append(tab)
	stats_content = VBoxContainer.new()
	stats_content.name = "StatRows"
	stats_content.add_theme_constant_override("separation", 0)
	stats_panel.add_child(stats_content)
	var bag_panel := PanelContainer.new()
	bag_panel.name = "BagPanel"
	bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_row.add_child(bag_panel)
	var bag_content := VBoxContainer.new()
	bag_panel.add_child(bag_content)
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
	slot_buttons[slot] = button


func _apply_layout() -> void:
	if layout_row == null:
		return
	var portrait := size.y > size.x
	_last_portrait = portrait
	layout_row.vertical = portrait
	var square_host := layout_row.get_node("EquipmentPanel") as Control
	var available := minf(size.x, size.y - 48.0) if not portrait else size.x
	var square_size := minf(480.0, maxf(180.0, available))
	square_host.custom_minimum_size = Vector2(square_size, square_size)
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equipment_content.scale = Vector2.ONE * (square_size / 480.0)
	bag_grid.columns = 4 if portrait else 6

func _choose_stat_tab(index: int) -> void:
	active_stat_tab = index
	_refresh_combat_stats()

func _refresh_combat_stats() -> void:
	if stats_content == null:
		return
	for child in stats_content.get_children():
		stats_content.remove_child(child)
		child.queue_free()
	for i in range(stat_tabs.size()):
		stat_tabs[i].disabled = i == active_stat_tab
	if character == null or repository == null:
		hp_label.text = "HP —"
		return
	var base := {"stats": character.progression.base_stats.duplicate(true)}
	var snapshot := CharacterCombatBuilder.build(character, repository, base)
	hp_label.text = "HP %d/%d" % [snapshot.hp, snapshot.max_hp]
	hp_bar.max_value = maxi(1, snapshot.max_hp)
	hp_bar.value = snapshot.hp
	var lines: Array[String] = []
	match active_stat_tab:
		0:
			lines = ["Урон оружия: —", "Попадание: —", "Крит: —"]
		1:
			lines = ["Мана: %d" % snapshot.max_mana, "Магический урон: —", "Усиление стихий: —"]
		2:
			lines = ["Броня по зонам: %s" % str(snapshot.armour) if not snapshot.armour.is_empty() else "Броня по зонам: —", "Уклонение: —", "Блок: —"]
		3:
			lines = ["Общее сопротивление: —", "Сопротивления стихиям: —"]
	for entry in lines:
		var label := Label.new()
		label.text = entry
		label.add_theme_font_size_override("font_size", 11)
		stats_content.add_child(label)

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
