class_name ItemTemplateGeneratorV12Screen
extends Control

## Independent v1.2 lab, with its own controls, engine and local profile.
const COLOURS := {"white":"#d8d8d8","green":"#78d594","blue":"#83afff","purple":"#cba0fa"}
var engine := ItemTemplateGeneratorV12.new()
var numeric_keypad: ItemLabNumericKeypad
var tabs: TabContainer
var kind_select: OptionButton
var archetype_select: OptionButton
var school_select: OptionButton
var slot_select: OptionButton
var hand_select: OptionButton
var quality_select: OptionButton
var level_min: SpinBox
var level_max: SpinBox
var count_spin: SpinBox
var seed_spin: SpinBox
var status: Label
var result_status: Label
var result_list: VBoxContainer
var csv_button: Button
var results: Array = []
var last_config: Dictionary = {}

func _ready() -> void:
	_build()
	call_deferred("_generate")

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#16202d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _label("Генератор шаблонов v1.2", 20, Color("#f3dfb5"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "В город"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	header.add_child(back)
	status = _label("Изолированная лаборатория · старый генератор не меняется", 12)
	root.add_child(status)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	numeric_keypad = ItemLabNumericKeypad.new()
	add_child(numeric_keypad)
	var settings := _page("1 · Параметры")
	settings.add_child(_label("Утверждённые правила Project 25 · 21 оружейный + 14 броневых архетипов", 13, Color("#c4d5e4")))
	settings.add_child(_label("Калибровка: HP/мана — эталоны; СА/СЗ — интерполяция целей сборки; прочие PAR — предварительно.", 12, Color("#dfbd8e")))
	kind_select = _option(settings,"Категория",[["Все","all"],["Оружие","weapon"],["Броня","armor"]])
	kind_select.item_selected.connect(func(_ix: int) -> void: _refresh_archetypes())
	archetype_select = _option(settings,"Архетип",[["Все архетипы","all"]])
	_refresh_archetypes()
	school_select = _option(settings,"Школа посоха",[["Любая","any"]])
	for school in engine.schools():
		var data: Dictionary = school
		school_select.add_item(String(data["name"]))
		school_select.set_item_metadata(school_select.item_count - 1,String(data["id"]))
	hand_select = _option(settings,"Рука оружия",[["Любая","any"],["Основная (MH)","MH"],["Вторая (OH)","OH"],["Двуручное (2H)","2H"]])
	slot_select = _option(settings,"Слот брони",[["Любой","any"]])
	for slot in engine.rules.get("armor_slots",[]):
		slot_select.add_item(String(slot))
		slot_select.set_item_metadata(slot_select.item_count - 1,String(slot))
	quality_select = _option(settings,"Редкость",[["Любая","any"],["Белая","white"],["Зелёная","green"],["Синяя","blue"],["Фиолетовая","purple"]])
	var level_row := HFlowContainer.new()
	settings.add_child(level_row)
	level_min = _spin(level_row,"Уровень от",10,1,100)
	level_max = _spin(level_row,"Уровень до",30,1,100)
	count_spin = _spin(level_row,"Количество",100,1,500)
	seed_spin = _spin(level_row,"Seed",20261101,1,999999999)
	var start := Button.new()
	start.text = "Сгенерировать по v1.2"
	start.custom_minimum_size.y = 52
	start.pressed.connect(_generate)
	settings.add_child(start)
	var tools := HFlowContainer.new()
	settings.add_child(tools)
	var save := Button.new()
	save.text = "Сохранить настройки"
	save.pressed.connect(_save_profile)
	tools.add_child(save)
	var load_button := Button.new()
	load_button.text = "Загрузить настройки"
	load_button.pressed.connect(_load_profile)
	tools.add_child(load_button)
	settings.add_child(_label("Сила атаки v1.2 пока лабораторный параметр: канонический PAR ещё не назначен. Сохранения персонажей не изменяются.",12,Color("#dfbd8e")))
	var output := _page("2 · Результаты")
	result_status = _label("Генерация ещё не запускалась",13)
	output.add_child(result_status)
	output.add_child(_label("Численные статусы: подтверждённый эталон / интерполяция / предварительный экстремум. Подробнее — в CSV.",12,Color("#dfbd8e")))
	csv_button = Button.new()
	csv_button.text = "Экспорт CSV · все предметы"
	csv_button.custom_minimum_size.y = 48
	csv_button.disabled = true
	csv_button.pressed.connect(_export_csv)
	output.add_child(csv_button)
	result_list = VBoxContainer.new()
	output.add_child(result_list)

func _page(title: String) -> VBoxContainer:
	var scroller := ScrollContainer.new()
	scroller.name = title
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroller)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroller.add_child(content)
	return content

func _label(s: String, size: int = 14, color: Color = Color("#e2e6eb")) -> Label:
	var result := Label.new()
	result.text = s
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color",color)
	return result

func _option(parent: Control,caption: String,choices: Array) -> OptionButton:
	parent.add_child(_label(caption,12,Color("#b7c8d6")))
	var result := OptionButton.new()
	result.custom_minimum_size.y = 46
	parent.add_child(result)
	for entry in choices:
		result.add_item(String(entry[0]))
		result.set_item_metadata(result.item_count - 1,String(entry[1]))
	result.select(0)
	return result

func _spin(parent: Control, caption: String, value: float, minimum: float, maximum: float) -> SpinBox:
	var container := VBoxContainer.new()
	container.custom_minimum_size.x = 130
	parent.add_child(container)
	container.add_child(_label(caption,12,Color("#b7c8d6")))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	container.add_child(spin)
	spin.hide()
	var edit := Button.new()
	edit.custom_minimum_size.y = 46
	edit.text = str(int(spin.value)) + "  ⌨"
	edit.pressed.connect(func() -> void: numeric_keypad.open_for(spin,caption))
	spin.value_changed.connect(func(v: float) -> void: edit.text = str(int(v)) + "  ⌨")
	container.add_child(edit)
	return spin

func _pick(option: OptionButton) -> String:
	if option.selected < 0:
		return "any"
	return String(option.get_item_metadata(option.selected))

func _select_value(option: OptionButton, value: String) -> void:
	for i in range(option.item_count):
		if String(option.get_item_metadata(i)) == value:
			option.select(i)
			return
	option.select(0)

func _refresh_archetypes() -> void:
	if archetype_select == null:
		return
	var old := _pick(archetype_select)
	archetype_select.clear()
	archetype_select.add_item("Все архетипы")
	archetype_select.set_item_metadata(0,"all")
	var kind := _pick(kind_select)
	for raw in engine.archetypes():
		var item: Dictionary = raw
		if kind != "all" and kind != String(item["kind"]):
			continue
		archetype_select.add_item(String(item["name"]))
		archetype_select.set_item_metadata(archetype_select.item_count-1,String(item["id"]))
	_select_value(archetype_select,old)

func _config() -> Dictionary:
	var ids: Array = []
	var current := _pick(archetype_select)
	if current != "all":
		ids.append(current)
	else:
		var kind := _pick(kind_select)
		for raw in engine.archetypes():
			var spec: Dictionary = raw
			if kind == "all" or String(spec["kind"]) == kind:
				ids.append(String(spec["id"]))
	return {"archetypes":ids,"school":_pick(school_select),"armor_slot":_pick(slot_select),"weapon_hand":_pick(hand_select),
		"quality":_pick(quality_select),"min_level":int(level_min.value),
		"max_level":int(level_max.value),"count":int(count_spin.value),"seed":int(seed_spin.value)}

func _generate() -> void:
	if int(level_min.value) > int(level_max.value):
		status.text = "Ошибка: минимальный уровень больше максимального"
		return
	var config := _config()
	var result := engine.generate(config)
	if not bool(result.get("ok",false)):
		status.text = "Ошибка: " + String(result.get("reason","Неизвестная ошибка"))
		return
	results = result.get("rows",[])
	last_config = config.duplicate(true)
	csv_button.disabled = results.is_empty()
	result_status.text = "v1.2 · %d предметов · %d комбинаций доступно · seed %d" % [
		results.size(),int(result.get("candidate_count",0)),int(config["seed"])]
	status.text = "Готово · %d вариантов (в CSV все; на экране первые 50)" % results.size()
	_render()
	tabs.current_tab = 1

func _render() -> void:
	for node in result_list.get_children():
		result_list.remove_child(node)
		node.queue_free()
	for i in range(mini(results.size(),50)):
		var entry: Dictionary = results[i]
		var v: Dictionary = entry["variant"]
		var txt := "%s · Lv%d · %s · %s" % [
			String(entry["archetype_name"]),int(entry["level"]),
			String(entry["slot"]),String(entry["school"])]
		result_list.add_child(_label(txt,13,Color("#f0d9af")))
		var details: Array[String] = []
		var damage: Array = v.get("damage",[])
		if damage.size() == 2:
			details.append("Урон %d–%d" % [int(damage[0]),int(damage[1])])
		var offhand_damage: Array = v.get("offhand_damage",[])
		if offhand_damage.size() == 2:
			details.append("OH %d–%d" % [int(offhand_damage[0]),int(offhand_damage[1])])
		var armour: Dictionary = v.get("armour",{})
		if not armour.is_empty():
			var fields: Array[String] = []
			for key in armour:
				fields.append("%s +%d" % [String(key),int(armour[key])])
			details.append("Броня: " + ", ".join(PackedStringArray(fields)))
		var slot_budget := float(v.get("par_slot_budget_pct",0.0))
		if slot_budget > 0.0:
			var provisional := " · 2H предварительно" if String(v.get("par_slot_budget_status","")) == "PROVISIONAL_2H" else ""
			details.append("Бюджет PAR слота %.2f%%%s" % [slot_budget,provisional])
		var budget_split: Dictionary = v.get("budget_split",{})
		if not budget_split.is_empty():
			details.append("Бюджет: защита %d%% / атака %d%%" % [
				int(budget_split["defence_pct"]),int(budget_split["attack_pct"])])
		var line_budget: Dictionary = v.get("par_line_budget",{})
		if String(line_budget.get("status","")) == "V12_K16":
			details.append("PAR-линии: %d × %.2f%% бюджета (диагностика)" % [
				int(line_budget["line_count"]),float(line_budget["share_pct"])])
		elif String(line_budget.get("status","")) == "UNRESOLVED_V12_FIVE_LINES":
			details.append("PAR-линии: 5 · распределение бюджета НЕ УТВЕРЖДЕНО")
		var stable_rolls: Array = v.get("core_rolls",[])
		for raw in stable_rolls:
			var line: Dictionary = raw
			details.append("CORE %s +%d [%s]" % [String(line["name"]),int(line["rating"]),String(line["par"])])
		var rolls: Array = v.get("rolls",[])
		for raw in rolls:
			var line: Dictionary = raw
			details.append("%s +%d [%s]" % [String(line["name"]),int(line["rating"]),String(line["par"])])
		var preview: Dictionary = v.get("preview",{})
		var zone_summary: Array[String] = []
		var armour_effects: Dictionary = preview.get("armour",{})
		var names := {"PAR100":"Голова","PAR101":"Грудь","PAR102":"Руки","PAR103":"Пояс","PAR104":"Ноги"}
		for zone in ["PAR100","PAR101","PAR102","PAR103","PAR104"]:
			if armour_effects.has(zone):
				var eff: Dictionary = armour_effects[zone]
				zone_summary.append("%s %.1f→%.1f%%" % [String(names[zone]),float(eff["raw_pct"]),float(eff["after_dr_pct"])])
		if not zone_summary.is_empty():
			details.append("Броня до/после DR: " + ", ".join(PackedStringArray(zone_summary)))
		var rating_effects: Dictionary = preview.get("ratings",{})
		for par in ["PAR031","PAR033","PAR032"]:
			if rating_effects.has(par):
				var eff: Dictionary = rating_effects[par]
				details.append("%s %.1f→%.1f%%" % [engine.par_label(par),float(eff["raw_pct"]),float(eff["after_dr_pct"])])
		var req: Dictionary = v.get("requirements",{})
		var req_bits: Array[String] = []
		for key in req:
			req_bits.append("%s %d" % [String(key),int(req[key])])
		details.append("Требования: " + ", ".join(PackedStringArray(req_bits)))
		result_list.add_child(_label(" · ".join(PackedStringArray(details)),12,Color(String(COLOURS.get(String(entry["quality"]),"#d8d8d8")))))
		result_list.add_child(HSeparator.new())

func _save_profile() -> void:
	status.text = "Настройки v1.2 сохранены" if engine.save_profile(_config()) else "Ошибка сохранения настроек"

func _load_profile() -> void:
	var config := engine.load_profile()
	if config.is_empty():
		status.text = "Сохранённых настроек v1.2 нет"
		return
	var chosen: Array = config.get("archetypes",[])
	if chosen.size() == 1:
		var requested := String(chosen[0])
		_select_value(kind_select,"all")
		_refresh_archetypes()
		_select_value(archetype_select,requested)
	else:
		_select_value(kind_select,"all")
		_refresh_archetypes()
	_select_value(school_select,String(config.get("school","any")))
	_select_value(slot_select,String(config.get("armor_slot","any")))
	_select_value(hand_select,String(config.get("weapon_hand","any")))
	_select_value(quality_select,String(config.get("quality","any")))
	level_min.value = float(config.get("min_level",10))
	level_max.value = float(config.get("max_level",30))
	count_spin.value = float(config.get("count",100))
	seed_spin.value = float(config.get("seed",20261101))
	status.text = "Настройки v1.2 загружены"

func _export_csv() -> void:
	if results.is_empty():
		return
	var lines: Array[String] = []
	lines.append("record_type,id,archetype_id,archetype,slot,school,level,quality,damage,offhand_damage,armour,budget_split,par_slot_budget_pct,par_slot_budget_status,par_line_budget,core_rolls,rarity_rolls,par_bonuses,requirements,preview_dr")
	var config_row: Array = ["CONFIG"]
	while config_row.size() < 20:
		config_row.append("")
	config_row[8] = JSON.stringify(last_config)
	lines.append(_csv_row(config_row))
	for item in results:
		var row: Dictionary = item
		var v: Dictionary = row["variant"]
		lines.append(_csv_row(["ITEM",String(row["id"]),String(row["archetype_id"]),
			String(row["archetype_name"]),String(row["slot"]),String(row["school"]),
			str(int(row["level"])),String(row["quality"]),JSON.stringify(v["damage"]),
			JSON.stringify(v["offhand_damage"]),JSON.stringify(v["armour"]),JSON.stringify(v["budget_split"]),str(float(v["par_slot_budget_pct"])),String(v["par_slot_budget_status"]),JSON.stringify(v["par_line_budget"]),JSON.stringify(v["core_rolls"]),JSON.stringify(v["rolls"]),JSON.stringify(v["total_par"]),JSON.stringify(v["requirements"]),JSON.stringify(v["preview"])]))
	var csv := "\n".join(PackedStringArray(lines)) + "\n"
	var filename := "BOA_Template_v12_%d.csv" % int(Time.get_unix_time_from_system())
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(csv.to_utf8_buffer(),filename,"text/csv;charset=utf-8")
		status.text = "CSV: запрос скачивания отправлен"
	else:
		var file := FileAccess.open("user://" + filename,FileAccess.WRITE)
		if file == null:
			status.text = "Не удалось сохранить CSV"
			return
		file.store_string(csv)
		file.close()
		status.text = "CSV: " + ProjectSettings.globalize_path("user://" + filename)

func _csv_row(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append('"' + String(value).replace('"','""') + '"')
	return ",".join(PackedStringArray(parts))
