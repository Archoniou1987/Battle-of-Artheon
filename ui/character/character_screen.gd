class_name CharacterScreen
extends Control

signal stats_committed

## Self-contained responsive character view. No combat simulation mutations.
const PRIMARY_PAR_IDS := ["PAR001", "PAR002", "PAR003", "PAR004", "PAR005", "PAR006"]
const BG := Color("#172334")
const PANEL := Color("#243247")
const GOLD := Color("#e9d2a5")
const MUTED := Color("#bac6d4")
var item_repository: ItemRepository
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
var square_host: Control
var square_content: Control
var layout_row: BoxContainer
var details_panel: PanelContainer
var detail_tabs: TabContainer
const DETAIL_TAB_NAMES := ["Атака", "Защита", "Магия", "Прочее"]
const DETAIL_LABELS := {
	"physical_damage_flat": "Физический урон (бонус)",
	"slash_damage": "Модификатор режущего урона",
	"pierce_damage": "Модификатор колющего урона",
	"chop_damage": "Модификатор рубящего урона",
	"blunt_damage": "Модификатор дробящего урона",
	"main_hand_damage": "Урон основной рукой",
	"main_hand_min_damage": "Осн. рука: мин. урон",
	"main_hand_max_damage": "Осн. рука: макс. урон",
	"off_hand_damage": "Урон второй рукой",
	"off_hand_min_damage": "Вторая рука: мин. урон",
	"off_hand_max_damage": "Вторая рука: макс. урон",
	"hit_chance_rating": "Шанс попадания",
	"anti_dodge_rating": "Рейтинг антиуворота",
	"crit_chance_rating": "Рейтинг критического удара",
	"crit_damage_pct": "Критический урон (бонус)",
	"armour_penetration_flat": "Пробивание брони",
	"armour_penetration_rating": "Пробивание брони, %",
	"block_penetration_flat": "Пробивание блока",
	"block_penetration_rating": "Пробивание блока, %",
	"tempo": "Темп",
	"attack_speed_pct": "Скорость атаки",
	"counterattack_rating": "Рейтинг контрудара",
	"counterattack_damage_pct": "Урон контрудара",
	"dodge_rating": "Рейтинг уворота",
	"anti_crit_rating": "Рейтинг антикрита",
	"manual_block_rating": "Ручной блок",
	"shield_auto_block_rating": "Автоблок щитом",
	"block_strength": "Сила блока",
	"control_resistance_rating": "Сопротивление контролю",
	"armour_head": "Броня головы",
	"armour_arms": "Броня рук",
	"armour_chest": "Броня груди",
	"armour_waist": "Броня пояса",
	"armour_legs": "Броня ног",
	"physical_damage_reduction_pct": "Снижение физ. урона",
	"slash_resistance_pct": "Сопр. режущему",
	"pierce_resistance_pct": "Сопр. колющему",
	"chop_resistance_pct": "Сопр. рубящему",
	"blunt_resistance_pct": "Сопр. дробящему",
	"magic_damage_pct": "Магический урон (бонус)",
	"magic_damage_flat": "Магический урон",
	"magic_hit_rating": "Рейтинг магической точности",
	"magic_crit_rating": "Рейтинг магического крита",
	"magic_penetration_flat": "Магическое пробивание",
	"magic_penetration_rating": "Магическое пробивание, %",
	"fire_damage": "Урон огнём",
	"water_damage": "Урон водой",
	"air_damage": "Урон воздухом",
	"earth_damage": "Урон землёй",
	"dark_damage": "Урон тьмой",
	"light_damage": "Урон светом",
	"magic_resistance": "Магическое сопротивление",
	"fire_resistance": "Сопр. огню",
	"water_resistance": "Сопр. воде",
	"air_resistance": "Сопр. воздуху",
	"earth_resistance": "Сопр. земле",
	"dark_resistance": "Сопр. тьме",
	"light_resistance": "Сопр. свету",
	"max_hp_flat": "Макс. HP (бонус)",
	"max_mana_flat": "Макс. мана (бонус)",
	"max_energy": "Макс. энергия",
	"max_rage": "Макс. ярость",
	"hp_regen": "Восстановление HP",
	"mana_regen": "Восстановление маны",
	"energy_regen": "Восстановление энергии",
	"vision_range": "Дальность обзора",
	"movement_speed_pct": "Скорость передвижения",
	"gathering_speed_pct": "Скорость добычи",
	"experience_bonus_pct": "Бонус опыта",
	"loot_bonus_pct": "Бонус добычи",
	"carry_capacity": "Грузоподъёмность"
}
var detail_values: Dictionary = {}

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
	layout_row = BoxContainer.new()
	layout_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(layout_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	square_host = Control.new()
	square_host.name = "CharacterPanel"
	square_host.clip_contents = true
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layout_row.add_child(square_host)
	square_content = Control.new()
	square_content.name = "SquareContent"
	square_content.custom_minimum_size = Vector2(480, 480)
	square_host.add_child(square_content)
	scroll.position = Vector2.ZERO
	scroll.size = Vector2(480, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	square_content.add_child(scroll)
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
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color("#f0c43c")
	xp_fill.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
	var xp_empty := StyleBoxFlat.new()
	xp_empty.bg_color = Color("#303238")
	xp_empty.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("background", xp_empty)
	level_content.add_child(xp_bar)
	var stats_card := _panel()
	body.add_child(stats_card)
	var stats_content := VBoxContainer.new()
	stats_card.add_child(stats_content)
	points_label = _label("", 17, GOLD)
	stats_content.add_child(points_label)
	for par_id in PRIMARY_PAR_IDS:
		var row := HBoxContainer.new()
		stats_content.add_child(row)
		var definitions := ParCalculationService.registry()
		var definition: Dictionary = definitions.get(par_id, {})
		var name_label := _label(String(definition.get("name", par_id)), 16, MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value := _label("", 17, GOLD)
		value.custom_minimum_size.x = 45
		row.add_child(value)
		stat_values[par_id] = value
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(46, 44)
		minus.pressed.connect(_remove_pending.bind(par_id))
		row.add_child(minus)
		stat_minus_buttons[par_id] = minus
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(46, 44)
		plus.pressed.connect(_allocate.bind(par_id))
		row.add_child(plus)
		stat_buttons[par_id] = plus
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
	# Reserved adaptive panel: detailed character statistics will be designed later.
	details_panel = _panel()
	details_panel.name = "CharacterDetailsPanel"
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_row.add_child(details_panel)
	_build_detail_tabs()
	refresh()
	resized.connect(_apply_layout)
	call_deferred("_apply_layout")

func _build_detail_tabs() -> void:
	# All rows are driven by the editable catalog; unsupported values stay unknown.
	detail_tabs = TabContainer.new()
	detail_tabs.name = "DetailTabs"
	detail_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_panel.add_child(detail_tabs)
	var config := PrimaryStatEffects.load_config()
	var categories: Dictionary = config.get("categories", {})
	for tab_name in DETAIL_TAB_NAMES:
		var page := ScrollContainer.new()
		page.name = tab_name
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		detail_tabs.add_child(page)
		var content := VBoxContainer.new()
		content.name = "DetailsContent"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_child(content)
		var groups: Dictionary = categories.get(tab_name, {})
		for group_name in groups:
			var heading := _label(String(group_name), 17, GOLD)
			content.add_child(heading)
			for raw_key in groups[group_name]:
				var key := String(raw_key)
				var row := HBoxContainer.new()
				content.add_child(row)
				var caption := _label(_detail_caption(key), 14, MUTED)
				caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.add_child(caption)
				var value := _label("—", 14, GOLD)
				row.add_child(value)
				detail_values[key] = value


func _detail_caption(key: String) -> String:
	if DETAIL_LABELS.has(key):
		return String(DETAIL_LABELS[key])
	if key.ends_with("_rating"):
		var base := key.trim_suffix("_rating")
		var legacy := base + "_pct"
		if DETAIL_LABELS.has(legacy):
			return String(DETAIL_LABELS[legacy]).replace(", %", "")
		if DETAIL_LABELS.has(base):
			return String(DETAIL_LABELS[base])
	return key

func _refresh_detail_values() -> void:
	for value in detail_values.values():
		(value as Label).text = "—"
	if character == null:
		return
	var config := PrimaryStatEffects.load_config()
	var bonuses := CharacterStatsService.snapshot(character, item_repository)
	var rating_stats: Array = config.get("rating_stats", [])
	var percent_stats: Array = config.get("direct_percent_stats", [])
	var level := character.progression.level
	for key in detail_values:
		var stat_key := String(key)
		var value: Label = detail_values[key]
		if stat_key == "main_hand_damage" and bonuses.has("main_hand_damage"):
			var damage_range: Array = bonuses["main_hand_damage"]
			value.text = "%s–%s" % [_format_stat_number(float(damage_range[0])), _format_stat_number(float(damage_range[1]))]
		elif stat_key == "off_hand_damage" and bonuses.has("off_hand_damage"):
			var offhand_range: Array = bonuses["off_hand_damage"]
			value.text = "%s–%s" % [_format_stat_number(float(offhand_range[0])), _format_stat_number(float(offhand_range[1]))]
		elif rating_stats.has(stat_key):
			var rating := float(bonuses.get(stat_key, 0.0))
			var percent := CharacterStatsService.rating_effect(bonuses, stat_key)
			value.text = "%s (%s%%)" % [_format_stat_number(rating), _format_stat_number(percent)]
		elif bonuses.has(stat_key):
			var amount := float(bonuses[stat_key])
			var suffix := "%" if percent_stats.has(stat_key) or stat_key.ends_with("_pct") else ""
			var sign := "+" if amount >= 0.0 else ""
			value.text = sign + _format_stat_number(amount) + suffix
		elif percent_stats.has(stat_key) or stat_key.ends_with("_pct") or stat_key in ["slash_damage", "pierce_damage", "chop_damage", "blunt_damage", "fire_damage", "water_damage", "air_damage", "earth_damage", "dark_damage", "light_damage"]:
			value.text = "+0%"

func _format_stat_number(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(int(roundf(amount)))
	var formatted := "%.2f" % amount
	while formatted.ends_with("0"):
		formatted = formatted.trim_suffix("0")
	return formatted.trim_suffix(".")


func _apply_layout() -> void:
	if square_host == null or square_content == null:
		return
	var portrait := size.y > size.x
	layout_row.vertical = portrait
	layout_row.add_theme_constant_override("separation", 10)
	var square_size := maxf(1.0, minf(size.x, size.y))
	square_host.custom_minimum_size = Vector2(square_size, square_size)
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	square_content.scale = Vector2.ONE * (square_size / 480.0)
	# In portrait the flexible panel follows below; in landscape it fills the right side.
	details_panel.custom_minimum_size = Vector2.ZERO

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
	if character != null and character.progression.remove_pending_stat(String(PRIMARY_STORAGE_KEYS.get(stat, ""))):
		refresh()

func _reset_pending() -> void:
	if character != null:
		character.progression.reset_pending_stats()
		refresh()

func _save_pending() -> void:
	if character != null and character.progression.save_pending_stats():
		stats_committed.emit()
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
	var par_snapshot := ParCalculationService.calculate(character, item_repository)
	var par_totals: Dictionary = par_snapshot.get("totals", {})
	var par_sources: Dictionary = par_snapshot.get("sources", {})
	for par_id in PRIMARY_PAR_IDS:
		var pending := int(progression.pending_stats.get(par_id, 0))
		var parts: Dictionary = par_sources.get(par_id, {})
		var equipment_bonus := int(round(float(parts.get("equipment", 0))))
		var total := int(round(float(par_totals.get(par_id, 0)))) + pending
		(stat_values[par_id] as Label).text = ("%d (+%d)" % [total, equipment_bonus]) if equipment_bonus > 0 else (("%d (%d)" % [total, equipment_bonus]) if equipment_bonus < 0 else str(total))
		(stat_buttons[par_id] as Button).disabled = progression.unspent_stat_points <= 0
		(stat_minus_buttons[par_id] as Button).disabled = pending <= 0
	save_button.disabled = progression.pending_stats.is_empty()
	reset_button.disabled = progression.pending_stats.is_empty()
	_refresh_detail_values()

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
	var hp := 100 + int(stats.get("PAR006", 0)) * 10
	var mana := int(stats.get("PAR005", 0)) * 15
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
