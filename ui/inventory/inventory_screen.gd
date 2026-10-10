class_name InventoryScreen
extends Control

## Responsive inventory shell. Uses live inventory/equipment instance IDs.
const SLOT_ROWS := [
	["head", "shoulders", "neck", "back"],
	["chest", "wrists", "waist", "legs"],
	["main_hand", "off_hand", "ring1", "ring2"],
	["feet"]
]
const SLOT_NAMES := {
	"head": "Голова", "shoulders": "Плечи", "neck": "Шея", "back": "Спина",
	"chest": "Грудь", "wrists": "Руки", "waist": "Пояс", "legs": "Ноги",
	"main_hand": "Осн. рука", "off_hand": "Вторая рука",
	"ring1": "Кольцо I", "ring2": "Кольцо II", "feet": "Ступни"
}
var character: CharacterState
var repository: ItemRepository
var back_button: Button
var equipment_grid: GridContainer
var bag_grid: GridContainer
var detail_dialog: ItemDetailDialog
var layout_row: BoxContainer
var selected_instance_id := ""
var slot_buttons: Dictionary = {}
var _last_portrait := false

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
	var equipment_panel := PanelContainer.new()
	equipment_panel.name = "EquipmentPanel"
	equipment_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_row.add_child(equipment_panel)
	var equipment_content := VBoxContainer.new()
	equipment_panel.add_child(equipment_content)
	var equipment_title := Label.new()
	equipment_title.text = "Экипировка"
	equipment_content.add_child(equipment_title)
	equipment_grid = GridContainer.new()
	equipment_grid.columns = 4
	equipment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_content.add_child(equipment_grid)
	for row in SLOT_ROWS:
		for slot in row:
			var button := Button.new()
			button.name = slot
			button.text = SLOT_NAMES[slot]
			button.custom_minimum_size = Vector2(74, 58)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_select_slot.bind(slot))
			equipment_grid.add_child(button)
			slot_buttons[slot] = button
		for filler in range(4 - row.size()):
			var spacer := Control.new()
			spacer.custom_minimum_size.y = 58
			equipment_grid.add_child(spacer)
	var portrait := PanelContainer.new()
	portrait.name = "CharacterPortrait"
	portrait.custom_minimum_size.y = 135
	equipment_content.add_child(portrait)
	var portrait_label := Label.new()
	portrait_label.text = "Герой"
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(portrait_label)
	var bag_panel := PanelContainer.new()
	bag_panel.name = "BagPanel"
	bag_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_row.add_child(bag_panel)
	var bag_content := VBoxContainer.new()
	bag_panel.add_child(bag_content)
	var bag_title := Label.new()
	bag_title.text = "Сумка"
	bag_content.add_child(bag_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_content.add_child(scroll)
	bag_grid = GridContainer.new()
	bag_grid.columns = 4
	bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bag_grid)
	detail_dialog = ItemDetailDialog.new(character, repository)
	add_child(detail_dialog)
	detail_dialog.changed.connect(refresh)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()

func _apply_layout() -> void:
	if layout_row == null:
		return
	var portrait := size.y > size.x
	if portrait == _last_portrait and layout_row.get_child_count() == 2:
		return
	_last_portrait = portrait
	layout_row.vertical = portrait
	var equipment_panel := layout_row.get_node("EquipmentPanel") as Control
	equipment_panel.custom_minimum_size = Vector2.ZERO if portrait else Vector2(380, 0)

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
	for slot in slot_buttons:
		var button := slot_buttons[slot] as Button
		var id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		button.text = SLOT_NAMES[slot] if id == null else SLOT_NAMES[slot] + "\n" + str(id)
	for child in bag_grid.get_children():
		child.queue_free()
	if character == null or repository == null:
		return
	for instance_id in character.inventory.instance_ids():
		var item := repository.get_item(String(instance_id))
		var button := Button.new()
		button.text = str(item.get("name", instance_id))
		button.custom_minimum_size = Vector2(80, 66)
		button.pressed.connect(_select_item.bind(String(instance_id)))
		bag_grid.add_child(button)
