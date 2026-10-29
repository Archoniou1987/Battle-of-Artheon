class_name ItemGeneratorLabScreen
extends Control

## Standalone developer UI. Does not grant generated items or alter real equipment.
const BG := Color("#111922")
const PANEL := Color("#202936")
const BORDER := Color("#52606e")
const PALETTE := {
	"white": Color("#e4e4e4"),
	"green": Color("#57d779"),
	"blue": Color("#65a9f9"),
	"purple": Color("#c38cf4")
}
const PERCENT_PARS := ["PAR030", "PAR031", "PAR032", "PAR033", "PAR034", "PAR035",
	"PAR100", "PAR101", "PAR102", "PAR103", "PAR104", "PAR105", "PAR106",
	"PAR107", "PAR108", "PAR109", "PAR110", "PAR111", "PAR112",
	"PAR113", "PAR114", "PAR115", "PAR116", "PAR117", "PAR118",
	"PAR119", "PAR120", "PAR121", "PAR122", "PAR123", "PAR124",
	"PAR151", "PAR190", "PAR191", "PAR192", "PAR193", "PAR194", "PAR195", "PAR196"]

var engine := ItemGeneratorLab.new()
var knobs: Dictionary = {}
var archetype_list: ItemList
var mode_select: OptionButton
var card_grid: GridContainer
var status: Label
var result_items: Array = []
var _last_columns := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_resize_cards)
	call_deferred("_generate")

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 12)
	outer.add_theme_constant_override("margin_right", 12)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	add_child(outer)
	var scroller := ScrollContainer.new()
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	scroller.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _text("BoA · ITEM GENERATOR LAB", 22, Color("#e8d6a5"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "← В город"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main/main.tscn"))
	header.add_child(back)
	root.add_child(_text("Реальные шаблоны Project 25 · экспериментальные экземпляры · никаких изменений лута и сохранений.", 13, Color("#a8bac8")))
	var settings := _panel()
	root.add_child(settings)
	var settings_body := VBoxContainer.new()
	settings_body.add_theme_constant_override("separation", 8)
	settings.add_child(settings_body)
	settings_body.add_child(_text("ПАРАМЕТРЫ ГЕНЕРАЦИИ", 17, Color("#f2dbb6")))
	var group := HFlowContainer.new()
	group.add_theme_constant_override("h_separation", 10)
	group.add_theme_constant_override("v_separation", 6)
	settings_body.add_child(group)
	_knob(group, "Количество", "count", 100, 4, 200, 1)
	_knob(group, "Item Lv от", "level_min", 10, 1, 100, 1)
	_knob(group, "Item Lv до", "level_max", 30, 1, 100, 1)
	_knob(group, "Seed", "seed", 20261029, 1, 99999999, 1)
	_knob(group, "Треб. высок. %", "high_requirement_pct", 70, 0, 150, 5)
	_knob(group, "Треб. средн. %", "medium_requirement_pct", 40, 0, 150, 5)
	_knob(group, "Вес GRP011 ×", "crit_weight", 1, 0, 10, 0.25)
	_knob(group, "Величина PAR ×", "par_value_scale", 1, 0.1, 5, 0.1)
	_knob(group, "Разброс ± %", "spread_pct", 5, 0, 20, 1)
	_knob(group, "Урон ×", "damage_scale", 1, 0.25, 3, 0.1)
	_knob(group, "Броня ×", "armour_scale", 1, 0.25, 3, 0.1)
	_knob(group, "Уровень расчёта %", "viewer_level", 25, 1, 100, 1)
	settings_body.add_child(_text("Веса редкостей (используются только среди разрешённых уровнем):", 13, Color("#bbc8d7")))
	var rarities := HFlowContainer.new()
	rarities.add_theme_constant_override("h_separation", 8)
	rarities.add_theme_constant_override("v_separation", 6)
	settings_body.add_child(rarities)
	_knob(rarities, "Белая", "weight_white", 15, 0, 100, 5)
	_knob(rarities, "Зелёная", "weight_green", 60, 0, 100, 5)
	_knob(rarities, "Синяя", "weight_blue", 25, 0, 100, 5)
	_knob(rarities, "Фиолетовая", "weight_purple", 0, 0, 100, 5)
	var filters := HBoxContainer.new()
	settings_body.add_child(filters)
	filters.add_child(_text("Архетипы (можно несколько):", 14, Color("#f1dbb7")))
	var all_button := Button.new()
	all_button.text = "Все"
	all_button.pressed.connect(_select_all_archetypes)
	filters.add_child(all_button)
	var none_button := Button.new()
	none_button.text = "Снять выбор"
	none_button.pressed.connect(func() -> void: archetype_list.deselect_all())
	filters.add_child(none_button)
	archetype_list = ItemList.new()
	archetype_list.select_mode = ItemList.SELECT_MULTI
	archetype_list.custom_minimum_size.y = 170
	archetype_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for archetype in engine.archetypes():
		archetype_list.add_item(String(archetype))
	settings_body.add_child(archetype_list)
	settings_body.add_child(_text("Без выделения — все архетипы. Выбор нескольких — только эти архетипы.", 12, Color("#95a5b6")))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	settings_body.add_child(actions)
	mode_select = OptionButton.new()
	mode_select.add_item("Список · независимые предметы", 0)
	mode_select.add_item("Сравнение · 4 редкости", 1)
	actions.add_child(mode_select)
	var run := Button.new()
	run.text = "⚙ Сгенерировать"
	run.pressed.connect(_generate)
	actions.add_child(run)
	status = _text("Готово к генерации", 14, Color("#e1c38a"))
	root.add_child(status)
	root.add_child(_text("Карточка: база → постоянные PAR → бонусы редкости → требования. Заблокированные цвета в сравнении помечаются как лабораторные.", 12, Color("#9aaaba")))
	card_grid = GridContainer.new()
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", 10)
	card_grid.add_theme_constant_override("v_separation", 10)
	root.add_child(card_grid)

func _knob(parent: Control, label_text: String, key: String, value: float, minimum: float, maximum: float, step: float) -> void:
	var field := VBoxContainer.new()
	field.custom_minimum_size.x = 126
	parent.add_child(field)
	field.add_child(_text(label_text, 12, Color("#c3d0de")))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 126
	field.add_child(spin)
	knobs[key] = spin

func _select_all_archetypes() -> void:
	for i in range(archetype_list.item_count):
		archetype_list.select(i, false)

func _settings() -> Dictionary:
	var c := {}
	for key in knobs:
		c[key] = knobs[key].value
	c["count"] = int(c["count"])
	c["level_min"] = int(c["level_min"])
	c["level_max"] = maxi(int(c["level_min"]), int(c["level_max"]))
	c["seed"] = int(c["seed"])
	c["viewer_level"] = int(c["viewer_level"])
	c["comparison"] = mode_select.selected == 1
	c["rarity_weights"] = {
		"white": c["weight_white"], "green": c["weight_green"],
		"blue": c["weight_blue"], "purple": c["weight_purple"]
	}
	var selected: Array = []
	for i in archetype_list.get_selected_items():
		selected.append(archetype_list.get_item_text(i))
	c["archetypes"] = selected
	return c

func _generate() -> void:
	var settings := _settings()
	var output := engine.generate(settings)
	if not bool(output.get("ok", false)):
		status.text = String(output.get("reason", "Ошибка генерации"))
		return
	result_items = output.get("items", [])
	var counts := {"white": 0, "green": 0, "blue": 0, "purple": 0}
	var crit_count := 0
	for item in result_items:
		var q := String(item.get("quality", "white"))
		counts[q] = int(counts.get(q, 0)) + 1
		if (item.get("total_par", {}) as Dictionary).has("PAR033"):
			crit_count += 1
	status.text = "Создано %d · доступных шаблонов %d · PAR033 у %d · Б %d / З %d / С %d / Ф %d" % [
		result_items.size(), int(output.get("templates_available", 0)), crit_count,
		counts["white"], counts["green"], counts["blue"], counts["purple"]]
	_render(settings)

func _render(config: Dictionary) -> void:
	for node in card_grid.get_children():
		card_grid.remove_child(node)
		node.queue_free()
	_resize_cards()
	for item in result_items:
		card_grid.add_child(_card(item, int(config.get("viewer_level", 25))))
	_resize_cards()

func _resize_cards() -> void:
	if card_grid == null:
		return
	var width := get_viewport_rect().size.x
	var comparison := mode_select != null and mode_select.selected == 1
	var columns := 1
	if comparison and width >= 1320:
		columns = 4
	elif width >= 860:
		columns = 2
	if columns != _last_columns:
		card_grid.columns = columns
		_last_columns = columns

func _card(item: Dictionary, viewer_level: int) -> PanelContainer:
	var quality := String(item.get("quality", "white"))
	var tint: Color = PALETTE.get(quality, Color.WHITE)
	var panel := _panel(tint)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(272, 100)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var name := String(item.get("archetype", "Предмет"))
	body.add_child(_text(name, 17, tint))
	body.add_child(_text("%s · %s · Item Lv %d" % [item.get("rarity_name", ""), item.get("slot", ""), int(item.get("level", 1))], 13, Color("#d1d9e2")))
	body.add_child(_text("%s · %s" % [item.get("instance_id", ""), item.get("template_id", "")], 11, Color("#94a6b9")))
	if bool(item.get("comparison_only", false)):
		body.add_child(_text("ТЕСТ: в обычной игре эта редкость недоступна", 12, Color("#f3af71")))
	body.add_child(HSeparator.new())
	var damage: Array = item.get("damage", [])
	if damage.size() >= 2:
		body.add_child(_text("Урон: %d–%d" % [int(damage[0]), int(damage[1])], 14, Color("#ecedf1")))
	var armour: Dictionary = item.get("base_armour", {})
	if not armour.is_empty():
		body.add_child(_text("Броня: " + _values_text(armour, viewer_level), 13, Color("#c0d2e2")))
	var fixed: Dictionary = item.get("fixed_par", {})
	if not fixed.is_empty():
		body.add_child(_text("Постоянные PAR:", 12, Color("#dacfae")))
		body.add_child(_text(_values_text(fixed, viewer_level), 13, Color("#dbe3ed")))
	var bonuses: Array = item.get("bonuses", [])
	if bonuses.is_empty():
		body.add_child(_text("Бонусов редкости нет", 12, Color("#9babb8")))
	for bonus in bonuses:
		body.add_child(_text("%s · %s" % [String(bonus.get("group", "")), _values_text(bonus.get("values", {}), viewer_level)], 13, tint))
	body.add_child(HSeparator.new())
	var req: Dictionary = item.get("requirements", {})
	body.add_child(_text("Требования: " + ("нет" if req.is_empty() else _values_text(req, viewer_level, false)), 12, Color("#ebb780")))
	return panel

func _values_text(values: Dictionary, viewer_level: int, bonus: bool = true) -> String:
	var result: Array[String] = []
	var keys: Array = values.keys()
	keys.sort()
	for raw_key in keys:
		var key := String(raw_key)
		var amount := int(values[key])
		var info: Dictionary = engine.database.get("parameters", {}).get(key, {})
		var label := String(info.get("name", key))
		var prefix := "+" if bonus and amount >= 0 else ""
		var line := "%s %s%s" % [label, prefix, str(amount)]
		if bonus and PERCENT_PARS.has(key):
			var share := float(amount) / 100.0 * (10.0 - 9.0 * float(viewer_level - 1) / 99.0)
			line += " (%.2f%%)" % share
		result.append(line)
	return "\n".join(PackedStringArray(result))

func _panel(border: Color = BORDER) -> PanelContainer:
	var pane := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	pane.add_theme_stylebox_override("panel", style)
	return pane

func _text(value: String, size_px: int, tint: Color) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", tint)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
