class_name CharacterScreen
extends Control

## Self-contained responsive character view. No combat simulation mutations.
const STAT_LABELS := {
	"STR": "Сила", "DEX": "Ловкость", "INTU": "Интуиция",
	"WIS": "Мудрость", "INT": "Интеллект", "END": "Выносливость"
}
const STAT_ORDER := ["STR", "DEX", "INTU", "WIS", "INT", "END"]
const BG := Color("#172334")
const PANEL := Color("#243247")
const GOLD := Color("#e9d2a5")
const MUTED := Color("#bac6d4")
var character: CharacterState
var title_label: Label
var xp_label: Label
var xp_bar: ProgressBar
var points_label: Label
var stat_values: Dictionary = {}
var stat_buttons: Dictionary = {}
var stat_minus_buttons: Dictionary = {}
var save_button: Button
var reset_button: Button
var back_button: Button
var combat_section: VBoxContainer
var resistance_section: VBoxContainer

func _init(p_character: CharacterState = null) -> void:
	character = p_character

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	back_button = Button.new()
	back_button.text = "← Назад"
	header.add_child(back_button)
	title_label = _label("Персонаж", 23, GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	var level_card := _panel()
	body.add_child(level_card)
	var level_content := VBoxContainer.new()
	level_card.add_child(level_content)
	xp_label = _label("", 17, GOLD)
	level_content.add_child(xp_label)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size.y = 18
	xp_bar.show_percentage = false
	level_content.add_child(xp_bar)
	var stats_card := _panel()
	body.add_child(stats_card)
	var stats_content := VBoxContainer.new()
	stats_card.add_child(stats_content)
	points_label = _label("", 17, GOLD)
	stats_content.add_child(points_label)
	for stat in STAT_ORDER:
		var row := HBoxContainer.new()
		stats_content.add_child(row)
		var name_label := _label(STAT_LABELS[stat], 16, MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value := _label("", 17, GOLD)
		value.custom_minimum_size.x = 45
		row.add_child(value)
		stat_values[stat] = value
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(46, 44)
		minus.pressed.connect(_remove_pending.bind(stat))
		row.add_child(minus)
		stat_minus_buttons[stat] = minus
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(46, 44)
		plus.pressed.connect(_allocate.bind(stat))
		row.add_child(plus)
		stat_buttons[stat] = plus
	var actions := HBoxContainer.new()
	stats_content.add_child(actions)
	reset_button = Button.new()
	reset_button.text = "Сбросить"
	reset_button.pressed.connect(_reset_pending)
	actions.add_child(reset_button)
	save_button = Button.new()
	save_button.text = "Сохранить"
	save_button.pressed.connect(_save_pending)
	actions.add_child(save_button)
	var combat_card := _panel()
	body.add_child(combat_card)
	combat_section = VBoxContainer.new()
	combat_card.add_child(combat_section)
	var resist_card := _panel()
	body.add_child(resist_card)
	resistance_section = VBoxContainer.new()
	resist_card.add_child(resistance_section)
	refresh()

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color("#806746")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _allocate(stat: String) -> void:
	if character == null or not character.allocate_stat(stat):
		return
	refresh()

func _remove_pending(stat: String) -> void:
	if character != null and character.progression.remove_pending_stat(stat):
		refresh()

func _reset_pending() -> void:
	if character != null:
		character.progression.reset_pending_stats()
		refresh()

func _save_pending() -> void:
	if character != null and character.progression.save_pending_stats():
		refresh()

func refresh() -> void:
	if title_label == null:
		return
	if character == null:
		title_label.text = "Персонаж не загружен"
		return
	var progression := character.progression
	title_label.text = character.display_name
	var required := progression.required_xp()
	xp_label.text = "Уровень %d   •   Опыт %d / %d" % [progression.level, progression.xp_into_level, required] if required > 0 else "Уровень %d   •   Максимальный уровень текущей таблицы" % progression.level
	xp_bar.max_value = max(1, required)
	xp_bar.value = progression.xp_into_level
	points_label.text = "Характеристики  •  Свободные очки: %d" % progression.unspent_stat_points
	for stat in STAT_ORDER:
		(stat_values[stat] as Label).text = str(progression.displayed_stat(stat))
		(stat_buttons[stat] as Button).disabled = progression.unspent_stat_points <= 0
		(stat_minus_buttons[stat] as Button).disabled = int(progression.pending_stats.get(stat, 0)) <= 0
	save_button.disabled = progression.pending_stats.is_empty()
	reset_button.disabled = progression.pending_stats.is_empty()
	_refresh_derived_sections()

func _refresh_derived_sections() -> void:
	for child in combat_section.get_children():
		combat_section.remove_child(child)
		child.queue_free()
	for child in resistance_section.get_children():
		resistance_section.remove_child(child)
		child.queue_free()
	combat_section.add_child(_label("Боевые показатели", 18, GOLD))
	resistance_section.add_child(_label("Защита и сопротивления", 18, GOLD))
	if character == null:
		return
	# Only values already defined by CharacterCombatBuilder are displayed.
	# Other combat formulas will be connected when their data contracts are finalized.
	var stats := character.progression.base_stats
	var hp := 100 + int(stats.get("END", 0)) * 10
	var mana := int(stats.get("WIS", 0)) * 15
	_add_derived_row(combat_section, "Здоровье (база)", str(hp))
	_add_derived_row(combat_section, "Мана (база)", str(mana))
	_add_derived_row(combat_section, "Макс. очки действий (база)", "5")
	_add_derived_row(resistance_section, "Броня по зонам", "Данные экипировки")
	_add_derived_row(resistance_section, "Сопротивления стихиям", "Ожидает расчёта")


func _add_derived_row(parent: VBoxContainer, caption: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var left := _label(caption, 14, MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := _label(value, 14, GOLD)
	row.add_child(right)
