class_name AbiTestLabDialog
extends AcceptDialog

## Development-only ABI sandbox UI. Actions are always visible below the tabs.
## Uses AbiTestLabSession; the live ArenaCombatSession is never modified.
const PAR_CHOICES := {
	"caster:PAR030": "Игрок · PAR030 Точность (рейтинг)",
	"caster:PAR033": "Игрок · PAR033 Шанс крита (рейтинг)",
	"caster:PAR035": "Игрок · PAR035 Сила крита (рейтинг)",
	"caster:PAR125": "Игрок · PAR125 Плоское пробитие брони",
	"caster:PAR126": "Игрок · PAR126 Пробитие брони, %",
	"caster:PAR150": "Игрок · PAR150 Магический урон (рейтинг)",
	"dummy:PAR034": "Манекен · PAR034 Антикрит (рейтинг)",
	"dummy:PAR101": "Манекен · PAR101 Броня груди",
	"dummy:PAR135": "Манекен · PAR135 Общее снижение урона, %",
	"dummy:PAR190": "Манекен · PAR190 Общее сопротивление магии",
	"dummy:PAR191": "Манекен · PAR191 Сопротивление огню",
	"dummy:PAR192": "Манекен · PAR192 Сопротивление воде",
	"dummy:PAR193": "Манекен · PAR193 Сопротивление воздуху",
	"dummy:PAR194": "Манекен · PAR194 Сопротивление земле",
	"dummy:PAR195": "Манекен · PAR195 Сопротивление тьме",
	"dummy:PAR196": "Манекен · PAR196 Сопротивление свету"
}
const TYPE_NAMES := {
	"slashing": "Рубящий (slashing)", "piercing": "Колющий (piercing)",
	"chopping": "Секущий (chopping)", "blunt": "Дробящий (blunt)",
	"fire": "Огонь", "water": "Вода", "air": "Воздух",
	"earth": "Земля", "dark": "Тьма", "light": "Свет"
}

var session: AbiTestLabSession
var preset_select: OptionButton
var type_select: OptionButton
var custom_name: LineEdit
var fields: Dictionary = {}
var par_select: OptionButton
var par_value: SpinBox
var par_label: Label
var output: TextEdit
var par_values: Dictionary = {}

var pages: TabContainer
var ability_scroll: ScrollContainer
var par_scroll: ScrollContainer
var status_label: Label
var locked_details: Label
var custom_name_row: HBoxContainer
var type_row: HBoxContainer
var mana_row: HBoxContainer
var cooldown_row: HBoxContainer
var action_toolbar: HBoxContainer
var reset_button: Button
var cast_button: Button
var skip_button: Button

func _ready() -> void:
	title = "ABI Test Lab · Физика / Магия"
	min_size = Vector2i(310, 340)
	get_ok_button().text = "Закрыть"

	# AcceptDialog measures its first Control child for its minimum size.
	# Do NOT add the VBoxContainer directly: TabContainer otherwise propagates
	# the full height of the long ability form and makes the popup full-screen.
	# A plain Control host creates a bounded viewport for the flexible layout.
	var host := Control.new()
	host.custom_minimum_size = Vector2(300, 310)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(host)

	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("separation", 6)
	host.add_child(frame)

	status_label = Label.new()
	status_label.text = "Изолированный тест · HP и мана героя не изменяются"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(status_label)

	# A second non-Container boundary prevents any tab's full form height
	# from enlarging the toolbar's parent. The tab pages scroll internally.
	var tab_viewport := Control.new()
	tab_viewport.custom_minimum_size = Vector2(295, 225)
	tab_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_viewport.clip_contents = true
	frame.add_child(tab_viewport)
	pages = TabContainer.new()
	tab_viewport.add_child(pages)
	pages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL

	ability_scroll = ScrollContainer.new()
	ability_scroll.name = "Способность"
	ability_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(ability_scroll)
	var ability_page := VBoxContainer.new()
	ability_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_page.add_theme_constant_override("separation", 5)
	ability_scroll.add_child(ability_page)
	_build_ability_page(ability_page)

	par_scroll = ScrollContainer.new()
	par_scroll.name = "PAR"
	par_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	par_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(par_scroll)
	var par_page := VBoxContainer.new()
	par_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	par_page.add_theme_constant_override("separation", 7)
	par_scroll.add_child(par_page)
	_build_par_page(par_page)

	var results_page := VBoxContainer.new()
	results_page.name = "Результаты"
	results_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(results_page)
	var result_hint := Label.new()
	result_hint.text = "Журнал реального CombatEngine · ACTION / ATTACK / DAMAGE / EFF"
	result_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	results_page.add_child(result_hint)
	output = TextEdit.new()
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.custom_minimum_size = Vector2(280, 165)
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_page.add_child(output)

	# This toolbar is a sibling of the tab container, never in its scroll area.
	action_toolbar = HBoxContainer.new()
	action_toolbar.add_theme_constant_override("separation", 4)
	frame.add_child(action_toolbar)
	reset_button = _add_action("Новый тест", _reset_session)
	cast_button = _add_action("Применить ABI", _cast)
	skip_button = _add_action("Пропустить", _skip)
	_preset_changed(0)
	_reset_session()

func _build_ability_page(page: VBoxContainer) -> void:
	preset_select = OptionButton.new()
	for id in ["ABI003", "LAB_PHYSICAL", "LAB_MAGIC"]:
		preset_select.add_item("%s — %s" % [id, String(AbiTestLabSession.PRESETS[id])])
		preset_select.set_item_metadata(preset_select.item_count - 1, id)
	_add_full_row(page, "Способность", preset_select)
	preset_select.item_selected.connect(_preset_changed)

	locked_details = Label.new()
	locked_details.text = "Fireball · огонь · 10 маны · КД 1 · EFF003 Горение"
	locked_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(locked_details)

	custom_name = LineEdit.new()
	custom_name.text = "Тестовая способность"
	custom_name_row = _add_compact_row(page, "Название", custom_name)
	custom_name.text_changed.connect(_mark_dirty)

	type_select = OptionButton.new()
	type_row = _add_compact_row(page, "Тип урона", type_select)
	type_select.item_selected.connect(_mark_dirty)

	_add_spin(page, "Базовый урон", "damage", 100, 0, 100000)
	mana_row = _add_spin(page, "Мана (тест)", "mana_cost", 0, 0, 1000)
	cooldown_row = _add_spin(page, "КД (тест)", "cooldown_rounds", 0, 0, 20)
	_add_spin(page, "Уровень игрока", "caster_level", 1, 1, 100)
	_add_spin(page, "Уровень манекена", "dummy_level", 1, 1, 100)
	_add_spin(page, "Бросок попадания", "hit_roll", 1, 1, 100)
	_add_spin(page, "Бросок крита", "crit_roll", 100, 1, 100)

	var hint := Label.new()
	hint.text = "Броски от 1 до 100. Изменение настроек начинает новый тест."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)

func _build_par_page(page: VBoxContainer) -> void:
	var caption := Label.new()
	caption.text = "Изменения действуют только на манекен и тестового героя. Выбирайте только реализованные PAR."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(caption)

	par_select = OptionButton.new()
	var keys: Array = PAR_CHOICES.keys()
	keys.sort()
	for raw_key in keys:
		var key := String(raw_key)
		par_select.add_item(String(PAR_CHOICES[key]))
		par_select.set_item_metadata(par_select.item_count - 1, key)
	_add_full_row(page, "Параметр", par_select)

	par_value = SpinBox.new()
	par_value.min_value = 0
	par_value.max_value = 100000
	par_value.step = 1
	par_value.value = 100
	par_value.allow_greater = false
	par_value.select_all_on_focus = true
	_add_compact_row(page, "Новое значение", par_value)

	var add_par := Button.new()
	add_par.text = "Добавить / обновить PAR"
	add_par.pressed.connect(_add_par)
	page.add_child(add_par)

	var clear_par := Button.new()
	clear_par.text = "Очистить изменения PAR"
	clear_par.pressed.connect(_clear_par)
	page.add_child(clear_par)

	par_label = Label.new()
	par_label.text = "Изменения: нет"
	par_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(par_label)

func _add_full_row(host: VBoxContainer, caption: String, control: Control) -> void:
	var label := Label.new()
	label.text = caption
	host.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(control)

func _add_compact_row(host: VBoxContainer, caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 132
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _add_spin(host: VBoxContainer, title_text: String, key: String, value: int, minimum: int, maximum: int) -> HBoxContainer:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.select_all_on_focus = true
	spin.custom_minimum_size.x = 95
	fields[key] = spin
	var row := _add_compact_row(host, title_text, spin)
	spin.value_changed.connect(_mark_dirty)
	return row

func _add_action(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(callback)
	action_toolbar.add_child(button)
	return button

func _cast() -> void:
	_next_round(true)

func _skip() -> void:
	_next_round(false)

func _preset_id() -> String:
	return String(preset_select.get_item_metadata(preset_select.selected))

func _selected_type() -> String:
	return String(type_select.get_item_metadata(type_select.selected))

func _preset_changed(_index: int) -> void:
	var preset := _preset_id()
	var locked := preset == "ABI003"
	locked_details.visible = locked
	custom_name_row.visible = not locked
	type_row.visible = not locked
	mana_row.visible = not locked
	cooldown_row.visible = not locked

	# Never offer invalid physical/magical combinations.
	type_select.clear()
	for id in AbiTestLabSession.DAMAGE_TYPES:
		var physical := CombatDamagePayload.is_physical_damage_type(String(id))
		if locked and id != "fire":
			continue
		if preset == "LAB_PHYSICAL" and not physical:
			continue
		if preset == "LAB_MAGIC" and physical:
			continue
		type_select.add_item(String(TYPE_NAMES.get(id, id)))
		type_select.set_item_metadata(type_select.item_count - 1, id)
	type_select.select(0)
	(fields["mana_cost"] as SpinBox).value = 10 if locked else 0
	(fields["cooldown_rounds"] as SpinBox).value = 1 if locked else 0
	_mark_dirty()

func _mark_dirty(_value: Variant = null) -> void:
	session = null
	if status_label != null:
		status_label.text = "Параметры изменены · следующий запуск начнёт новый тест"
	if output != null:
		output.text = "Настройки изменены. Примените ABI или нажмите «Новый тест»."

func _add_par() -> void:
	var id := String(par_select.get_item_metadata(par_select.selected))
	par_values[id] = par_value.value
	_update_par_label()
	_mark_dirty()

func _clear_par() -> void:
	par_values.clear()
	_update_par_label()
	_mark_dirty()

func _update_par_label() -> void:
	if par_values.is_empty():
		par_label.text = "Изменения: нет"
		return
	var lines: Array[String] = []
	var keys: Array = par_values.keys()
	keys.sort()
	for raw_key in keys:
		var key := String(raw_key)
		lines.append("%s = %s" % [key, str(par_values[key])])
	par_label.text = "\n".join(lines)

func _settings() -> Dictionary:
	var result := {"preset": _preset_id(), "damage_type": _selected_type(),
		"name": custom_name.text, "par_values": par_values.duplicate(true)}
	for key in fields:
		result[key] = int((fields[key] as SpinBox).value)
	return result

func _reset_session() -> void:
	var candidate := AbiTestLabSession.new()
	var result: Dictionary = candidate.reset(_settings())
	if not bool(result.get("ok", false)):
		session = null
		status_label.text = "Ошибка настройки лаборатории"
		output.text = "ABI LAB ERROR: " + JSON.stringify(result)
		pages.current_tab = 2
		return
	session = candidate
	status_label.text = "Раунд 0 · манекен 10000 HP · тестовая мана 500"
	output.text = "ABI Test Lab запущен\n" + JSON.stringify(result) + "\n"
	output.text += "Исходы и формулы — из CombatEngine. Броски заданы для диагностики.\n"
	output.text += "PAR018 и незавершённые магические PAR недоступны.\n"
	pages.current_tab = 0

func _next_round(cast_ability: bool) -> void:
	if session == null:
		_reset_session()
	if session == null:
		return
	var result: Dictionary = session.next_round(cast_ability)
	pages.current_tab = 2
	if not bool(result.get("ok", false)):
		status_label.text = "Тест остановлен: " + String(result.get("reason", "error"))
		output.text += "\nОТКАЗ: " + JSON.stringify(result)
		return
	status_label.text = "Раунд %d · манекен %d HP · мана %d · урон %d" % [
		int(result["round"]), int(result["hp_after"]),
		int(result["mana_after"]), int(result["damage_dealt"])]
	var lines: Array[String] = []
	lines.append("\n──── Раунд %d ────" % int(result["round"]))
	lines.append("ABI: %s | %s" % [String(result["ability_id"]), String(result["cast_status"])])
	lines.append("Мана: %d → %d | HP манекена: %d → %d | урон: %d" % [
		int(result["mana_before"]), int(result["mana_after"]),
		int(result["hp_before"]), int(result["hp_after"]), int(result["damage_dealt"])])
	for raw_effect in result["effects"]:
		var eff: Dictionary = raw_effect
		lines.append("%s: %d стак(ов), общий таймер %d" % [
			String(eff.get("effect_id", "")), int(eff.get("stacks", 1)),
			int(eff.get("remaining_rounds", 0))])
	for line in result["report"]:
		lines.append(String(line))
	output.text += "\n".join(lines) + "\n"
	output.set_caret_line(output.get_line_count() - 1)

func open_lab() -> void:
	# Use bounded dimensions so the toolbar and tab bar fit on portrait AND
	# landscape screens. Tabs own their scrolling; the dialog never needs to.
	var viewport_size := get_viewport().get_visible_rect().size
	var preferred_width := mini(590, int(viewport_size.x * 0.92))
	var preferred_height := mini(640, int(viewport_size.y * 0.82))
	popup_centered(Vector2i(maxi(310, preferred_width), maxi(340, preferred_height)))
