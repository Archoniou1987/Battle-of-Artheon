class_name ItemGeneratorLabScreen
extends Control

## Four standard editor tabs. Editable lab profiles live separately in user://.
const TINT := {
	"white": Color("#dddddd"), "green": Color("#71d88b"),
	"blue": Color("#73adff"), "purple": Color("#c795ed")
}
const SHORT := {"PAR001":"STR", "PAR002":"DEX", "PAR003":"INTU",
	"PAR004":"INT", "PAR005":"WIS", "PAR006":"STA"}

var engine := ItemBalanceWorkbench.new()
var numeric_keypad: ItemLabNumericKeypad
var tab: TabContainer
var archetype_name: LineEdit
var archetype_number: SpinBox
var archetype_code_label: Label
var par_picker: OptionButton
var requirement_first: OptionButton
var requirement_second: OptionButton
var par_rows: VBoxContainer
var weights_label: Label
var par_weights: Dictionary = {}
var par_settings: Dictionary = {}
var preview_level_spin: SpinBox
var profile_status: Label
var par_search: LineEdit
var par_list: ItemList
var detail: VBoxContainer
var detail_fields: Dictionary = {}
var selected_par := ""
var controls: Dictionary = {}
var type_list: VBoxContainer
var type_search: LineEdit
var type_checks: Dictionary = {}
var quality_checks: Dictionary = {}
var mode_picker: OptionButton
var result_box: VBoxContainer
var summary: Label
var result_items: Array = []
var result_rows: Array = []
var last_generation_config: Dictionary = {}
var last_generation_output: Dictionary = {}
var csv_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	par_weights = engine.default_archetype()
	var saved := engine.load_profile()
	_build()
	if not saved.is_empty():
		_apply_profile(saved)
		profile_status.text = "Профиль восстановлен из памяти устройства"
	call_deferred("_run_test")

func _build() -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_constant_override("separation", 4)
	add_child(panel)
	var header := HBoxContainer.new()
	panel.add_child(header)
	var heading := _text("BoA · Генератор / баланс", 19)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close := Button.new()
	close.text = "В город"
	close.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	header.add_child(close)
	var profile_line := HBoxContainer.new()
	panel.add_child(profile_line)
	var save_button := Button.new()
	save_button.text = "Сохранить настройки"
	save_button.pressed.connect(_save_profile)
	profile_line.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Загрузить"
	load_button.pressed.connect(_load_profile)
	profile_line.add_child(load_button)
	profile_status = _text("Несохранённый лабораторный профиль · отдельный от сохранений игрока", 12, Color("#b6c0ce"))
	profile_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_line.add_child(profile_status)
	tab = TabContainer.new()
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(tab)
	_build_archetype_tab()
	_build_par_tab()
	_build_items_tab()
	_build_results_tab()
	numeric_keypad = ItemLabNumericKeypad.new()
	add_child(numeric_keypad)

func _save_profile() -> void:
	var stored := _settings()
	stored["preview_level"] = int(preview_level_spin.value)
	if engine.save_profile(stored):
		profile_status.text = "Настройки сохранены локально (не в игровых сохранениях)"
	else:
		profile_status.text = "Не удалось сохранить настройки!"

func _load_profile() -> void:
	var saved := engine.load_profile()
	if saved.is_empty():
		profile_status.text = "Сохранённого профиля нет"
		return
	_apply_profile(saved)
	profile_status.text = "Настройки загружены"
	_run_test()

func _apply_profile(saved: Dictionary) -> void:
	var weights: Variant = saved.get("par_weights", null)
	if weights is Dictionary:
		par_weights.clear()
		for raw in weights:
			var key := String(raw)
			if engine.registry.has(key) and (weights[raw] is float or weights[raw] is int):
				par_weights[key] = clampf(float(weights[raw]),0.0,10000.0)
	var overrides: Variant = saved.get("par_settings", null)
	if overrides is Dictionary:
		par_settings.clear()
		for raw in overrides:
			var key := String(raw)
			if engine.registry.has(key) and overrides[raw] is Dictionary:
				par_settings[key] = (overrides[raw] as Dictionary).duplicate(true)
	archetype_name.text = String(saved.get("archetype_name",archetype_name.text)).substr(0,100)
	var stored_number := int(saved.get("archetype_number", 1))
	archetype_number.value = clampi(stored_number,1,999999)
	_update_archetype_code()
	_restore_requirement_choices(saved)
	_refresh_archetype()
	preview_level_spin.value = clampf(float(saved.get("preview_level",25)),1.0,100.0)
	_filter_pars()
	for key in controls:
		if saved.has(key):
			(controls[key] as SpinBox).value = clampf(float(saved[key]),(controls[key] as SpinBox).min_value,(controls[key] as SpinBox).max_value)
	mode_picker.select(0 if bool(saved.get("unique_templates",true)) else 1)
	var rarities: Variant = saved.get("rarities",null)
	if rarities is Dictionary:
		for key in quality_checks:
			(quality_checks[key] as CheckBox).button_pressed = float(rarities.get(key,1.0)) > 0.0
	var types: Variant = saved.get("types",null)
	if types is Array:
		for key in type_checks:
			(type_checks[key] as CheckBox).button_pressed = types.has(key)

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box

func _text(label: String, font_size: int = 14, color: Color = Color("#e0e4e8")) -> Label:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _spin(parent: Control, label_text: String, val: float, low: float,
	high: float, step: float = 1.0) -> SpinBox:
	var field := VBoxContainer.new()
	field.custom_minimum_size.x = 135
	parent.add_child(field)
	field.add_child(_text(label_text, 12, Color("#bfcad6")))
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.value = val
	s.custom_minimum_size.x = 128
	field.add_child(s)
	_attach_numeric_input(field, s, label_text)
	return s

func _attach_numeric_input(parent: Control, spin: SpinBox, caption_text: String) -> void:
	# Numeric controls still expose SpinBox.value, so existing generator/formula
	# bindings and save/load remain unchanged. The touch target opens a keypad.
	spin.hide()
	var button := Button.new()
	button.custom_minimum_size = Vector2(118, 42)
	button.text = ItemLabNumericKeypad._display_number(spin.value, spin.step) + "  ⌨"
	button.pressed.connect(func() -> void: numeric_keypad.open_for(spin, caption_text))
	spin.value_changed.connect(func(_value: float) -> void:
		button.text = ItemLabNumericKeypad._display_number(spin.value, spin.step) + "  ⌨")
	spin.set_meta("lab_numeric_button", button)
	parent.add_child(button)

func _row(parent: Control) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 6)
	parent.add_child(h)
	return h

func _build_archetype_tab() -> void:
	var body := _page("1 · Архетип")
	body.add_child(_text("Архетип из конкретных PAR (без GRP)", 16))
	body.add_child(_text("Выбирай характеристики и задавай их относительный вес. Один PAR может выпадать несколько раз. Вес 0 отключает его.", 12, Color("#aab9c9")))
	var line := HBoxContainer.new()
	body.add_child(line)
	line.add_child(_text("Название:", 13))
	archetype_name = LineEdit.new()
	archetype_name.text = "Мобильный"
	archetype_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(archetype_name)
	var id_row := _row(body)
	archetype_number = _spin(id_row, "Номер архетипа", 1.0, 1.0, 999999.0)
	archetype_code_label = _text("", 14, Color("#d8c88f"))
	id_row.add_child(archetype_code_label)
	archetype_number.value_changed.connect(func(_v: float) -> void: _update_archetype_code())
	var use_id := Button.new()
	use_id.text = "Использовать ID как название"
	use_id.pressed.connect(func() -> void: archetype_name.text = _archetype_code())
	id_row.add_child(use_id)
	body.add_child(_text("Если поле названия не открывает клавиатуру телефона, задай номер через экранную цифровую клавиатуру. Например 17 → ARC-0017.", 12, Color("#aab9c9")))
	_update_archetype_code()
	body.add_child(_text("Требования ко ВСЕМ предметам архетипа (только PAR, без чисел)", 14))
	var req_row := _row(body)
	requirement_first = _requirement_choice(req_row, "Требование 1")
	requirement_second = _requirement_choice(req_row, "Требование 2")
	body.add_child(_text("Например DEX + STA (PAR002 + PAR006). Значение каждого требования зависит от уровня и слота. При выборе «Авто» для обоих действует прежнее правило.", 12, Color("#aab9c9")))
	var add_line := _row(body)
	par_picker = OptionButton.new()
	par_picker.custom_minimum_size.x = 220
	var keys: Array = engine.parameter_ids()
	keys.sort()
	for par in keys:
		var p := String(par)
		var meta: Dictionary = engine.registry[p]
		par_picker.add_item("%s · %s" % [p, String(meta.get("name", ""))])
		par_picker.set_item_metadata(par_picker.item_count - 1, p)
	add_line.add_child(par_picker)
	var add_button := Button.new()
	add_button.text = "+ Добавить PAR"
	add_button.pressed.connect(_add_selected_par)
	add_line.add_child(add_button)
	weights_label = _text("", 13, Color("#e3d19e"))
	body.add_child(weights_label)
	par_rows = VBoxContainer.new()
	par_rows.add_theme_constant_override("separation", 4)
	body.add_child(par_rows)
	var quick := _row(body)
	var preset := Button.new()
	preset.text = "Мобильный · по умолчанию"
	preset.pressed.connect(func() -> void:
		par_weights = engine.default_archetype()
		archetype_name.text = "Мобильный"
		_refresh_archetype())
	quick.add_child(preset)
	var zero := Button.new()
	zero.text = "Очистить"
	zero.pressed.connect(func() -> void:
		par_weights.clear()
		_refresh_archetype())
	quick.add_child(zero)
	var simple := _row(body)
	for preset_config in [
		{"name":"Крит", "weights":{"PAR033":100.0}},
		{"name":"Уворот", "weights":{"PAR031":100.0}},
		{"name":"Сила", "weights":{"PAR001":100.0}},
		{"name":"Крит + сила крита", "weights":{"PAR033":65.0,"PAR035":35.0}}
	]:
		var b := Button.new()
		b.text = String(preset_config["name"])
		var configuration: Dictionary = preset_config["weights"]
		var display_name := String(preset_config["name"])
		b.pressed.connect(func() -> void:
			archetype_name.text = display_name
			par_weights = configuration.duplicate(true)
			_refresh_archetype())
		simple.add_child(b)
	_refresh_archetype()

func _archetype_code() -> String:
	return "ARC-%04d" % int(archetype_number.value)

func _update_archetype_code() -> void:
	if archetype_code_label != null and archetype_number != null:
		archetype_code_label.text = "ID: " + _archetype_code()


func _requirement_choice(parent: Control, caption: String) -> OptionButton:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 140
	parent.add_child(box)
	box.add_child(_text(caption, 12, Color("#bfcad6")))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(140, 42)
	picker.add_item("Авто / нет")
	picker.set_item_metadata(0, "")
	for par in ParCalculationService.PRIMARY_IDS:
		var key := String(par)
		var shorthand := String(SHORT.get(key,key))
		var suffix := " (END)" if key == "PAR006" else ""
		picker.add_item("%s%s · %s" % [shorthand,suffix,key])
		picker.set_item_metadata(picker.item_count-1,key)
	box.add_child(picker)
	return picker

func _selected_requirement_pars() -> Array:
	var chosen: Array = []
	for picker in [requirement_first, requirement_second]:
		if picker == null or picker.selected < 0:
			continue
		var par := String(picker.get_item_metadata(picker.selected))
		if not par.is_empty():
			chosen.append(par)
	return chosen

func _restore_requirement_choices(saved: Dictionary) -> void:
	var chosen: Variant = saved.get("requirement_pars", [])
	var values: Array = chosen if chosen is Array else []
	for n in range(2):
		var picker: OptionButton = [requirement_first, requirement_second][n]
		var requested := String(values[n]) if n < values.size() else ""
		picker.select(0)
		for i in range(picker.item_count):
			if String(picker.get_item_metadata(i)) == requested:
				picker.select(i)
				break

func _add_selected_par() -> void:
	if par_picker.item_count == 0:
		return
	var key := String(par_picker.get_item_metadata(par_picker.selected))
	if not par_weights.has(key):
		par_weights[key] = 10.0
	_refresh_archetype()

func _refresh_archetype() -> void:
	if par_rows == null:
		return
	for child in par_rows.get_children():
		par_rows.remove_child(child)
		child.queue_free()
	var total := 0.0
	for key in par_weights:
		total += maxf(0.0, float(par_weights[key]))
	weights_label.text = "Сумма весов: %.1f. Вероятности нормализуются автоматически." % total
	var keys: Array = par_weights.keys()
	keys.sort()
	for raw in keys:
		var key := String(raw)
		var line := HBoxContainer.new()
		par_rows.add_child(line)
		var caption := _text("%s · %s" % [key, _par_name(key)], 13)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(caption)
		var weight := SpinBox.new()
		weight.min_value = 0
		weight.max_value = 10000
		weight.step = 1
		weight.value = float(par_weights[key])
		weight.custom_minimum_size.x = 90
		weight.value_changed.connect(func(v: float) -> void:
			par_weights[key] = v
			_update_weight_label())
		line.add_child(weight)
		_attach_numeric_input(line, weight, "Вес %s" % key)
		var remove := Button.new()
		remove.text = "×"
		remove.pressed.connect(func() -> void:
			par_weights.erase(key)
			_refresh_archetype())
		line.add_child(remove)

func _update_weight_label() -> void:
	var total := 0.0
	for v in par_weights.values():
		total += maxf(0.0, float(v))
	weights_label.text = "Сумма весов: %.1f. Вероятности нормализуются автоматически." % total

func _build_par_tab() -> void:
	var body := _page("2 · PAR шкала")
	body.add_child(_text("PAR = MAX = % · по уровням", 16))
	body.add_child(_text("Главный ориентир: сколько % дают 100 рейтинга на выбранном уровне. Настройки независимы от боевого движка.", 12, Color("#aab9c9")))
	var preview_row := _row(body)
	preview_level_spin = _spin(preview_row, "Уровень героя для 100 рейтинга", 25.0, 1.0, 100.0, 1.0)
	preview_level_spin.value_changed.connect(func(_v: float) -> void: _update_par_preview())
	par_search = LineEdit.new()
	par_search.placeholder_text = "Найти PAR по номеру или названию"
	par_search.text_changed.connect(func(_v: String) -> void: _filter_pars())
	body.add_child(par_search)
	par_list = ItemList.new()
	par_list.select_mode = ItemList.SELECT_SINGLE
	par_list.custom_minimum_size.y = 180
	par_list.item_selected.connect(_selected_par)
	body.add_child(par_list)
	detail = VBoxContainer.new()
	body.add_child(detail)
	_filter_pars()

func _filter_pars() -> void:
	if par_list == null:
		return
	par_list.clear()
	var search := par_search.text.strip_edges().to_lower()
	var keys: Array = engine.parameter_ids()
	keys.sort()
	for raw in keys:
		var key := String(raw)
		var title := "%s  %s" % [key, _par_name(key)]
		if not search.is_empty() and not title.to_lower().contains(search):
			continue
		par_list.add_item(title)
		par_list.set_item_metadata(par_list.item_count - 1, key)
	if par_list.item_count > 0:
		var idx := 0
		for i in range(par_list.item_count):
			if String(par_list.get_item_metadata(i)) == selected_par:
				idx = i
				break
		par_list.select(idx)
		_selected_par(idx)

func _selected_par(index: int) -> void:
	selected_par = String(par_list.get_item_metadata(index))
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	detail_fields.clear()
	detail.add_child(_text("%s · %s" % [selected_par, _par_name(selected_par)], 15, Color("#d8c88f")))
	var current := engine.parameter_settings(selected_par, par_settings)
	var fields := _row(detail)
	_detail_spin(fields, "MAX (рейтинг)", "max", float(current["max"]), 0.0, 100000.0, 1.0)
	_detail_spin(fields, "Первый Item Lv", "min_level", float(current["min_level"]), 1.0, 999.0, 1.0)
	_detail_spin(fields, "Рост по Lv ^", "growth", float(current["growth"]), 0.1, 5.0, 0.1)
	_detail_spin(fields, "Значение ×", "value_scale", float(current["value_scale"]), 0.0, 20.0, 0.1)
	if engine.is_percentage(selected_par):
		var percents := _row(detail)
		_detail_spin(percents, "100 рейтинга на Lv1 = %", "rating100_lv1", float(current["rating100_lv1"]), 0.0, 100.0, 0.1)
		_detail_spin(percents, "100 рейтинга на Lv100 = %", "rating100_lv100", float(current["rating100_lv100"]), 0.0, 100.0, 0.1)
		var dimin := _row(detail)
		_detail_spin(dimin, "DR с % (0 = выкл.)", "diminish_start_pct", float(current["diminish_start_pct"]), 0.0, 100.0, 1.0)
		_detail_spin(dimin, "DR ширина %", "diminish_width_pct", float(current["diminish_width_pct"]), 0.1, 100.0, 0.5)
		_detail_spin(dimin, "Цель от вещей на Lv25, %", "gear_target_pct", float(current["gear_target_pct"]), 0.0, 100.0, 0.5)
	else:
		detail.add_child(_text("Этот PAR не является процентным рейтингом; его значение показывается числом.", 12, Color("#aab9c9")))
	var reset := Button.new()
	reset.text = "Сбросить настройки этого PAR"
	reset.pressed.connect(func() -> void:
		par_settings.erase(selected_par)
		_selected_par(par_list.get_selected_items()[0]))
	detail.add_child(reset)
	_update_par_preview()

func _detail_spin(parent: Control, caption: String, field: String, val: float, low: float, high: float, step: float) -> void:
	var spin := _spin(parent, caption, val, low, high, step)
	var key := selected_par
	spin.value_changed.connect(func(value: float) -> void:
		if not par_settings.has(key):
			par_settings[key] = {}
		par_settings[key][field] = value
		_update_par_preview())
	detail_fields[field] = spin

func _update_par_preview() -> void:
	if detail == null or selected_par.is_empty():
		return
	var existing := detail.get_node_or_null("ParPreview") as Label
	if existing == null:
		existing = _text("")
		existing.name = "ParPreview"
		detail.add_child(existing)
	var options: Dictionary = engine.parameter_settings(selected_par, par_settings)
	var sample_level := int(preview_level_spin.value)
	if engine.is_percentage(selected_par):
		var hundred := engine.percentage(selected_par,100.0,sample_level,par_settings)
		var at_max := engine.percentage(selected_par,float(options["max"]),sample_level,par_settings)
		existing.text = "100 рейтинга = %.2f%% на Lv%d | MAX %.0f = %.2f%%" % [
			hundred,sample_level,float(options["max"]),at_max]
		existing.text += "\nДля сравнения: Lv1 %.2f%% · Lv25 %.2f%% · Lv30 %.2f%% · Lv100 %.2f%% за 100 рейтинга." % [
			engine.percentage(selected_par,100.0,1,par_settings),
			engine.percentage(selected_par,100.0,25,par_settings),
			engine.percentage(selected_par,100.0,30,par_settings),
			engine.percentage(selected_par,100.0,100,par_settings)]
		var target := float(options["gear_target_pct"])
		if target > 0.0:
			var goal := engine.required_rating(selected_par,target,sample_level,par_settings)
			var one_roll := engine.expected_affix(selected_par,sample_level,par_settings)
			existing.text += "\nЦель от вещей: %.1f%% ≈ %.0f рейтинга (без DR). Один бонус на Lv%d ≈ %.0f рейтинга." % [
				target,goal,sample_level,one_roll]
		if float(options["diminish_start_pct"]) > 0.0:
			existing.text += "\nDR активен: прирост от 100 рейтинга зависит от уже накопленных рейтингов."
	else:
		existing.text = "Не процентный PAR: MAX %.0f · первый Item Lv %d." % [
			float(options["max"]),int(options["min_level"])]

func _par_name(par: String) -> String:
	return engine.par_name(par)

func _build_items_tab() -> void:
	var body := _page("3 · Предметы")
	body.add_child(_text("Меню предметов", 16))
	body.add_child(_text("Отметь 1, 5 или все типы галочками. Уникальные шаблоны не повторяются; случайные экземпляры могут повторять основу.", 12, Color("#aab9c9")))
	var basic := _row(body)
	controls["min_level"] = _spin(basic, "Уровень от", 10, 1, 100)
	controls["max_level"] = _spin(basic, "Уровень до", 30, 1, 100)
	controls["count"] = _spin(basic, "Количество", 100, 1, 500)
	controls["seed"] = _spin(basic, "Seed", 20261029, 1, 99999999)
	var options := _row(body)
	controls["high_requirement"] = _spin(options, "Требования 70%", 70, 0, 150)
	controls["medium_requirement"] = _spin(options, "Требования 40%", 40, 0, 150)
	controls["bonus_scale"] = _spin(options, "Бонус PAR ×", 1, 0, 20, 0.1)
	controls["spread"] = _spin(options, "Разброс ±%", 5, 0, 20)
	controls["damage_scale"] = _spin(options, "База урона ×", 1, 0.1, 5, 0.1)
	controls["armour_scale"] = _spin(options, "База брони ×", 1, 0.1, 5, 0.1)
	var modes := HBoxContainer.new()
	body.add_child(modes)
	modes.add_child(_text("Режим:", 13))
	mode_picker = OptionButton.new()
	mode_picker.add_item("Уникальные шаблоны (без дублей)", 0)
	mode_picker.add_item("Экземпляры (повторы допустимы)", 1)
	modes.add_child(mode_picker)
	body.add_child(_text("Редкости для режима экземпляров (в уникальном режиме показываются все доступные цвета):", 12))
	var qualities := _row(body)
	for quality in ItemBalanceWorkbench.QUALITY:
		var check := CheckBox.new()
		check.text = {"white":"Белая", "green":"Зелёная", "blue":"Синяя", "purple":"Фиолетовая"}[quality]
		check.button_pressed = true
		qualities.add_child(check)
		quality_checks[quality] = check
	var actions := _row(body)
	var select_all := Button.new()
	select_all.text = "Выбрать все"
	select_all.pressed.connect(func() -> void:
		for check in type_checks.values():
			check.button_pressed = true)
	actions.add_child(select_all)
	var clear := Button.new()
	clear.text = "Снять все"
	clear.pressed.connect(func() -> void:
		for check in type_checks.values():
			check.button_pressed = false)
	actions.add_child(clear)
	var axes := Button.new()
	axes.text = "Только топоры 2H"
	axes.pressed.connect(func() -> void: _select_2h_axes())
	actions.add_child(axes)
	type_search = LineEdit.new()
	type_search.placeholder_text = "Фильтр типов предметов"
	type_search.text_changed.connect(func(_v: String) -> void: _filter_types())
	body.add_child(type_search)
	type_list = VBoxContainer.new()
	body.add_child(type_list)
	for raw in engine.available_types():
		var key := String(raw)
		var check := CheckBox.new()
		check.text = key
		check.button_pressed = key.contains("Топор 2H")
		type_list.add_child(check)
		type_checks[key] = check
	var run := Button.new()
	run.text = "СГЕНЕРИРОВАТЬ → РЕЗУЛЬТАТЫ"
	run.pressed.connect(_run_test)
	body.add_child(run)

func _filter_types() -> void:
	var term := type_search.text.to_lower()
	for name in type_checks:
		(type_checks[name] as CheckBox).visible = term.is_empty() or String(name).to_lower().contains(term)

func _select_2h_axes() -> void:
	for key in type_checks:
		(type_checks[key] as CheckBox).button_pressed = String(key).contains("Топор 2H")

func _build_results_tab() -> void:
	var body := _page("4 · Результаты")
	summary = _text("Сначала сгенерируй предметы на вкладке 3.", 13)
	body.add_child(summary)
	csv_button = Button.new()
	csv_button.text = "Скачать CSV: настройки + все предметы"
	csv_button.disabled = true
	csv_button.custom_minimum_size.y = 44
	csv_button.pressed.connect(_export_csv)
	body.add_child(csv_button)
	body.add_child(_text("CSV отражает настройки последней генерации. После изменения PAR или типов предметов запусти генерацию заново.", 12, Color("#acb9c5")))
	body.add_child(_text("Одна строка = один шаблон; ниже варианты редкости. Требования: выбранные PAR архетипа, а числовые значения зависят от слота и уровня.", 12, Color("#acb9c5")))
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 3)
	body.add_child(result_box)

func _export_csv() -> void:
	if last_generation_config.is_empty() or result_rows.is_empty():
		summary.text = "Сначала создай предметы — сохранять пока нечего."
		return
	var csv := ItemLabCsvExporter.build(last_generation_config, last_generation_output, engine)
	var time := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var name := "BOA_Item_Lab_%s.csv" % time
	if OS.has_feature("web"):
		# Download synchronously within the actual button click: mobile browsers
		# may block download_buffer() if invoked after a deferred callback.
		JavaScriptBridge.download_buffer(csv.to_utf8_buffer(), name, "text/csv;charset=utf-8")
		summary.text = "Запрошено скачивание %s · %d шаблонов" % [name, result_rows.size()]
		return
	var local_path := "user://" + name
	var output := FileAccess.open(local_path, FileAccess.WRITE)
	if output == null:
		summary.text = "Ошибка сохранения CSV (%d)" % FileAccess.get_open_error()
		return
	output.store_string(csv)
	output.flush()
	output.close()
	summary.text = "CSV сохранён: " + ProjectSettings.globalize_path(local_path)

func _settings() -> Dictionary:
	var types: Array = []
	for key in type_checks:
		if (type_checks[key] as CheckBox).button_pressed:
			types.append(key)
	var rarities := {}
	for quality in quality_checks:
		rarities[quality] = 1.0 if quality_checks[quality].button_pressed else 0.0
	var c := {
		"types":types, "par_weights":par_weights.duplicate(true),
		"archetype_number":int(archetype_number.value),
		"archetype_id":_archetype_code(),
		"requirement_pars":_selected_requirement_pars(),
		"par_settings":par_settings.duplicate(true),
		"unique_templates":mode_picker.selected == 0,
		"rarities":rarities, "archetype_name":archetype_name.text
	}
	for key in controls:
		c[key] = controls[key].value
	return c

func _run_test() -> void:
	var c := _settings()
	if (c["types"] as Array).is_empty():
		summary.text = "Не выбрано ни одного типа предметов."
		tab.current_tab = 3
		return
	var result := engine.generate(c)
	if not bool(result.get("ok", false)):
		summary.text = String(result.get("reason", "Ошибка"))
		tab.current_tab = 3
		return
	result_rows = result.get("rows", [])
	result_items = result_rows
	last_generation_config = c.duplicate(true)
	last_generation_output = result.duplicate(true)
	csv_button.disabled = false
	var lines := 0
	for record in result_rows:
		lines += (record.get("variants", []) as Array).size()
	summary.text = "%s · %d шаблонов/экземпляров · %d цветных строк · %d уникальных основ+уровней доступно · запрошено %d" % [
		("%s / %s" % [String(c.get("archetype_id", "ARC-0001")),String(c["archetype_name"])]), result_rows.size(), lines,
		int(result.get("available_unique", 0)), int(result.get("requested", 0))]
	_render_results()
	tab.current_tab = 3

func _render_results() -> void:
	for node in result_box.get_children():
		result_box.remove_child(node)
		node.queue_free()
	for raw in result_rows:
		var record: Dictionary = raw
		var title := _text("%s — Lv%d — %s (%s)" % [
			String(record.get("item_type", "")), int(record.get("level", 1)),
			String(record.get("id", "")), String(record.get("source_template", ""))], 13, Color("#e2d6b9"))
		result_box.add_child(title)
		for v in record.get("variants", []):
			var variant: Dictionary = v
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			result_box.add_child(line)
			var color := String(variant.get("quality", "white"))
			var marker := ColorRect.new()
			marker.color = TINT.get(color, Color.WHITE)
			marker.custom_minimum_size = Vector2(7, 12)
			line.add_child(marker)
			var label := _text(_compact_line(variant, int(record.get("level", 1))), 12, TINT.get(color, Color.WHITE))
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(label)
		result_box.add_child(HSeparator.new())

func _compact_line(v: Dictionary, level: int) -> String:
	var parts: Array[String] = []
	var quality := String(v.get("quality", "white"))
	parts.append({"white":"Б", "green":"З", "blue":"С", "purple":"Ф"}[quality])
	var damage: Array = v.get("damage", [])
	if damage.size() >= 2:
		parts.append("%d–%d урон" % [int(damage[0]), int(damage[1])])
	var armour: Dictionary = v.get("armour", {})
	if not armour.is_empty():
		parts.append("броня " + _compact_pars(armour, level))
	var bonuses: Dictionary = v.get("total_par", {})
	if not bonuses.is_empty():
		parts.append(_compact_pars(bonuses, level))
	var req: Dictionary = v.get("requirements", {})
	if not req.is_empty():
		var req_text: Array[String] = []
		var keys: Array = req.keys()
		keys.sort()
		for par in keys:
			req_text.append("%s %d" % [SHORT.get(par, par), int(req[par])])
		parts.append("треб.: " + ", ".join(PackedStringArray(req_text)))
	return "   ".join(PackedStringArray(parts))

func _compact_pars(stats: Dictionary, level: int) -> String:
	var strings: Array[String] = []
	var keys: Array = stats.keys()
	keys.sort()
	for raw in keys:
		var key := String(raw)
		var amount := int(stats[key])
		var name := _par_name(key)
		var text_line := "+%d %s [%s]" % [amount, name, key]
		if engine.is_percentage(key):
			text_line += " (%.2f%%)" % engine.percentage(key, float(amount), level, par_settings)
		strings.append(text_line)
	return ", ".join(PackedStringArray(strings))
