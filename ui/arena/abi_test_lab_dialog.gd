class_name AbiTestLabDialog
extends AcceptDialog

## Visible QA tool, deliberately separate from ArenaCombatSession.
## No access to persistent player HP, mana, equipment or inventory.
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

func _ready() -> void:
	title = "ABI Test Lab · Физика / Магия"
	min_size = Vector2i(330, 430)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(310, 480)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 310
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var caption := Label.new()
	caption.text = "Независимый тестовый бой. Сохранения, HP и мана героя не затрагиваются."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(caption)

	preset_select = OptionButton.new()
	for id in ["ABI003", "LAB_PHYSICAL", "LAB_MAGIC"]:
		preset_select.add_item("%s — %s" % [id, String(AbiTestLabSession.PRESETS[id])])
		preset_select.set_item_metadata(preset_select.item_count - 1, id)
	_add_control_row(content, "Способность", preset_select)
	preset_select.item_selected.connect(_preset_changed)

	custom_name = LineEdit.new()
	custom_name.text = "Тестовая способность"
	_add_control_row(content, "Название", custom_name)
	custom_name.text_changed.connect(_mark_dirty)

	type_select = OptionButton.new()
	for id in AbiTestLabSession.DAMAGE_TYPES:
		type_select.add_item(String(TYPE_NAMES.get(id, id)))
		type_select.set_item_metadata(type_select.item_count - 1, id)
	_add_control_row(content, "Тип урона", type_select)
	type_select.item_selected.connect(_mark_dirty)

	_add_spin(content, "Базовый урон", "damage", 100, 0, 100000)
	_add_spin(content, "Мана (тест ABI)", "mana_cost", 0, 0, 1000)
	_add_spin(content, "КД (тест ABI)", "cooldown_rounds", 0, 0, 20)
	_add_spin(content, "Уровень игрока", "caster_level", 1, 1, 100)
	_add_spin(content, "Уровень манекена", "dummy_level", 1, 1, 100)
	_add_spin(content, "Бросок попадания (1–100)", "hit_roll", 1, 1, 100)
	_add_spin(content, "Бросок крита (1–100)", "crit_roll", 100, 1, 100)

	var par_heading := Label.new()
	par_heading.text = "Изменение PAR · только реализованные боевые параметры"
	content.add_child(par_heading)
	par_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	par_select = OptionButton.new()
	for key in PAR_CHOICES.keys():
		par_select.add_item(String(PAR_CHOICES[key]))
		par_select.set_item_metadata(par_select.item_count - 1, String(key))
	_add_control_row(content, "PAR", par_select)
	par_value = SpinBox.new()
	par_value.min_value = 0
	par_value.max_value = 100000
	par_value.step = 1
	par_value.value = 100
	par_value.allow_greater = false
	_add_control_row(content, "Новое значение PAR", par_value)
	var add_par := Button.new()
	add_par.text = "Применить значение PAR в тесте"
	add_par.pressed.connect(_add_par)
	content.add_child(add_par)
	var clear_par := Button.new()
	clear_par.text = "Очистить все PAR-изменения"
	clear_par.pressed.connect(_clear_par)
	content.add_child(clear_par)
	par_label = Label.new()
	par_label.text = "Изменения: нет"
	par_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(par_label)

	var toolbar := HBoxContainer.new()
	content.add_child(toolbar)
	var reset_button := Button.new()
	reset_button.text = "Новый тест"
	reset_button.pressed.connect(_reset_session)
	toolbar.add_child(reset_button)
	var cast_button := Button.new()
	cast_button.text = "ABI → манекен"
	cast_button.pressed.connect(_next_round.bind(true))
	toolbar.add_child(cast_button)
	var skip_button := Button.new()
	skip_button.text = "Пропустить раунд"
	skip_button.pressed.connect(_next_round.bind(false))
	toolbar.add_child(skip_button)

	output = TextEdit.new()
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.custom_minimum_size = Vector2(310, 250)
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(output)
	_preset_changed(0)
	_reset_session()

func _add_control_row(host: VBoxContainer, caption: String, control: Control) -> void:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(control)

func _add_spin(host: VBoxContainer, title_text: String, key: String, value: int, minimum: int, maximum: int) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.select_all_on_focus = true
	fields[key] = spin
	_add_control_row(host, title_text, spin)
	spin.value_changed.connect(_mark_dirty)

func _preset_id() -> String:
	return String(preset_select.get_item_metadata(preset_select.selected))

func _selected_type() -> String:
	return String(type_select.get_item_metadata(type_select.selected))

func _preset_changed(_index: int) -> void:
	var preset := _preset_id()
	type_select.disabled = preset == "ABI003"
	custom_name.editable = preset != "ABI003"
	(fields["mana_cost"] as SpinBox).editable = preset != "ABI003"
	(fields["cooldown_rounds"] as SpinBox).editable = preset != "ABI003"
	(fields["mana_cost"] as SpinBox).value = 10 if preset == "ABI003" else 0
	(fields["cooldown_rounds"] as SpinBox).value = 1 if preset == "ABI003" else 0
	var expected_type := "slashing" if preset == "LAB_PHYSICAL" else "fire"
	for index in range(type_select.item_count):
		if String(type_select.get_item_metadata(index)) == expected_type:
			type_select.select(index)
			break
	_mark_dirty()

func _mark_dirty(_value: Variant = null) -> void:
	session = null
	if output != null:
		output.text = "Параметры изменены. Нажмите «Новый тест» или примените ABI для автоматического сброса лаборатории."

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
	for key in keys:
		lines.append("%s = %s" % [String(key), str(par_values[key])])
	par_label.text = " | ".join(lines)

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
		output.text = "ABI LAB ERROR: " + JSON.stringify(result)
		return
	session = candidate
	output.text = "ABI Test Lab запущен\n" + JSON.stringify(result) + "\n"
	output.text += "Формула и исходы берутся из CombatEngine. В тесте используются заданные броски попадания/крита.\n"
	output.text += "PAR018 и незавершённые магические PAR намеренно недоступны.\n"

func _next_round(cast_ability: bool) -> void:
	if session == null:
		_reset_session()
	if session == null:
		return
	var result: Dictionary = session.next_round(cast_ability)
	if not bool(result.get("ok", false)):
		output.text += "\nОТКАЗ: " + JSON.stringify(result)
		return
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
	popup_centered_ratio(0.88)
