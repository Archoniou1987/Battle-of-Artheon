class_name ItemDetailDialog
extends Control

## Shared item details for bag and equipped slots. Requirements are red if unmet.
signal changed

var character: CharacterState
var repository: ItemRepository
var item_id := ""
var source_slot := ""
var backdrop: ColorRect
var panel: PanelContainer
var content: VBoxContainer

func _init(p_character: CharacterState = null, p_repository: ItemRepository = null) -> void:
	character = p_character
	repository = p_repository

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.8)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 280
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	visible = false

func show_item(instance_id: String, slot: String = "") -> void:
	if character == null or repository == null or not repository.has_item(instance_id):
		return
	item_id = instance_id
	source_slot = slot
	visible = true
	_render()

func _render() -> void:
	for child in content.get_children():
		child.queue_free()
	var item := repository.get_item(item_id)
	_add_text(str(item.get("name", item_id)), Color("#f1ddbb"), 21)
	_add_text("Тип: %s    Уровень предмета: %s" % [str(item.get("type", "—")), str(item.get("item_level", "—"))], Color.WHITE)
	_add_text("Редкость: " + str(item.get("rarity", "—")), Color("#e0c38d"))
	_add_dictionary("Характеристики", item.get("guaranteed_stats", {}))
	_add_dictionary("Дополнительные свойства", item.get("bonuses", {}))
	var requirements: Variant = item.get("requirements", {})
	var allowed := true
	if requirements is Dictionary and not requirements.is_empty():
		_add_text("Требования", Color("#f1ddbb"), 17)
		for stat in requirements:
			var needed := int(requirements[stat])
			var actual := int(character.effective_stats(repository, item_id).get(stat, 0))
			var met := actual >= needed
			if not met:
				allowed = false
			_add_text("%s: %d / %d" % [str(stat), actual, needed], Color("#e2e5eb") if met else Color("#e05d5d"))
	var description := str(item.get("description", ""))
	if not description.is_empty():
		_add_text(description, Color("#bac6d4"))
	var action := Button.new()
	if not source_slot.is_empty():
		action.text = "Снять"
		action.disabled = character.in_combat
		action.pressed.connect(_unequip)
	else:
		action.text = "Надеть"
		action.disabled = not allowed or not character.meets_requirements(item, repository) or item.get("equip_slots", []).is_empty() or character.in_combat
		action.pressed.connect(_equip)
	content.add_child(action)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func() -> void: visible = false)
	content.add_child(close)

func _add_dictionary(title: String, values: Variant) -> void:
	if not values is Dictionary or values.is_empty():
		return
	_add_text(title, Color("#f1ddbb"), 17)
	for key in values:
		_add_text("%s: %s" % [str(key), str(values[key])], Color("#e2e5eb"))

func _add_text(value: String, tint: Color, font_size: int = 15) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", font_size)
	content.add_child(label)

func _equip() -> void:
	var item := repository.get_item(item_id)
	for slot in item.get("equip_slots", []):
		if character.equip(String(slot), item_id, repository):
			changed.emit()
			visible = false
			return

func _unequip() -> void:
	if character.unequip(source_slot, repository) != null:
		changed.emit()
		visible = false
