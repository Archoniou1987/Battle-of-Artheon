class_name ItemLabNumericKeypad
extends Control

## Canvas-native keypad for Android browser/Web Preview, where platform keyboards
## are not guaranteed to appear. Also accepts a hardware/native keyboard via LineEdit.
var target: SpinBox
var value_edit: LineEdit
var caption: Label
var hint: Label
var replace_on_first_digit := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.08, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = 312
	center.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 18)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(caption)
	value_edit = LineEdit.new()
	value_edit.custom_minimum_size.y = 52
	value_edit.max_length = 20
	value_edit.select_all_on_focus = true
	value_edit.virtual_keyboard_enabled = true
	value_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	value_edit.text_submitted.connect(func(_text: String) -> void: apply_value())
	column.add_child(value_edit)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	for symbol in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "±", "0", ".", "←", "C", "ОК"]:
		var button := Button.new()
		button.text = symbol
		button.custom_minimum_size = Vector2(96, 48)
		button.add_theme_font_size_override("font_size", 21)
		button.pressed.connect(_key.bind(symbol))
		grid.add_child(button)
	var cancel_button := Button.new()
	cancel_button.text = "Отмена"
	cancel_button.custom_minimum_size.y = 42
	cancel_button.pressed.connect(cancel)
	column.add_child(cancel_button)
	hide()

func open_for(spin: SpinBox, label: String) -> void:
	if spin == null:
		return
	target = spin
	caption.text = label
	value_edit.text = _display_number(spin.value, spin.step)
	hint.text = "Диапазон: %s … %s" % [
		_display_number(spin.min_value, spin.step),
		_display_number(spin.max_value, spin.step)]
	replace_on_first_digit = true
	show()
	# Do not autofocus: Android Web Preview might bring a native keyboard over
	# the built-in keypad. Tap the text field to type with a platform keyboard.

func _key(symbol: String) -> void:
	if symbol == "ОК":
		apply_value()
		return
	if symbol == "C":
		value_edit.text = ""
		replace_on_first_digit = false
		return
	if symbol == "←":
		if replace_on_first_digit:
			value_edit.text = ""
		elif not value_edit.text.is_empty():
			value_edit.text = value_edit.text.substr(0, value_edit.text.length() - 1)
		replace_on_first_digit = false
		return
	if symbol == "±":
		value_edit.text = value_edit.text.trim_prefix("-") if value_edit.text.begins_with("-") else "-" + value_edit.text
		replace_on_first_digit = false
		return
	if symbol == ".":
		if target != null and target.step >= 1.0:
			return
		if replace_on_first_digit:
			value_edit.text = "0"
			replace_on_first_digit = false
		if not value_edit.text.contains(".") and not value_edit.text.contains(","):
			value_edit.text += "."
		return
	if symbol.length() != 1 or not symbol.is_valid_int():
		return
	if replace_on_first_digit:
		value_edit.text = ""
		replace_on_first_digit = false
	if value_edit.text == "0":
		value_edit.text = symbol
	else:
		value_edit.text += symbol

func apply_value() -> bool:
	if target == null:
		return false
	var source := value_edit.text.strip_edges().replace(",", ".")
	if source.is_empty() or not source.is_valid_float():
		hint.text = "Введите число (например 25 или 1.5)."
		return false
	var value := float(source)
	if not is_finite(value):
		hint.text = "Некорректное значение."
		return false
	if value < target.min_value or value > target.max_value:
		hint.text = "Число вне диапазона: %s … %s" % [
			_display_number(target.min_value, target.step),
			_display_number(target.max_value, target.step)]
		return false
	target.value = value
	cancel()
	return true

func cancel() -> void:
	hide()
	target = null

static func _display_number(number: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(number)))
	var formatted := "%.3f" % number
	while formatted.ends_with("0"):
		formatted = formatted.substr(0, formatted.length() - 1)
	return formatted.trim_suffix(".")
