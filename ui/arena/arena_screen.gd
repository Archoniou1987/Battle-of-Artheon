class_name ArenaScreen
extends Control

## Arena UI foundation. Combat commands are deliberately not simulated here.
signal back_requested

const SLOTS_LEFT := ["head", "shoulders", "chest", "main_hand", "waist", "legs", "feet"]
const SLOTS_RIGHT := ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]
const ZONES := ["head", "chest", "arms", "waist", "legs"]
const ZONE_NAMES := ["Голова", "Корпус", "Руки", "Пояс", "Ноги"]
const AVATAR_PATH := "res://assets/avatars/hero_realistic_01.png"

var character: CharacterState
var repository: ItemRepository
var layout: BoxContainer
var square_host: Control
var square_content: Control
var log_view: RichTextLabel
var round_button: Button
var defense_zone := "chest"
var attack_zone := "chest"
var selected_ability := ""
var player_slots: Dictionary = {}
var enemy_slots: Dictionary = {}
var hp_label: Label

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
	layout = BoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)
	square_host = Control.new()
	square_host.clip_contents = true
	layout.add_child(square_host)
	square_content = Control.new()
	square_content.custom_minimum_size = Vector2(480, 480)
	square_host.add_child(square_content)
	_build_square()
	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(log_panel)
	var log_column := VBoxContainer.new()
	log_panel.add_child(log_column)
	var header := HBoxContainer.new()
	log_column.add_child(header)
	var back := Button.new()
	back.text = "← Назад"
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
	var heading := Label.new()
	heading.text = "ЖУРНАЛ БОЯ"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.text = "Арена готова. Выберите защиту, атаку и способность.\nПодключение боевого раунда — следующий этап."
	log_column.add_child(log_view)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()

func _build_square() -> void:
	var title := Label.new()
	title.text = "АРЕНА — ПОЕДИНОК"
	title.position = Vector2(12, 4)
	title.add_theme_font_size_override("font_size", 18)
	square_content.add_child(title)
	_build_fighter(Vector2(4, 34), true)
	_build_fighter(Vector2(244, 34), false)
	var ability_title := Label.new()
	ability_title.text = "АКТИВНЫЕ СПОСОБНОСТИ (ABI)"
	ability_title.position = Vector2(106, 366)
	square_content.add_child(ability_title)
	var abilities := HBoxContainer.new()
	abilities.position = Vector2(10, 389)
	abilities.add_theme_constant_override("separation", 5)
	square_content.add_child(abilities)
	for index in range(8):
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 36)
		button.text = "ABI %d" % (index + 1)
		button.toggle_mode = true
		button.disabled = true # Enabled when the character's actual ABI loadout is wired.
		abilities.add_child(button)
	round_button = Button.new()
	round_button.text = "ПРОВЕСТИ РАУНД"
	round_button.position = Vector2(30, 433)
	round_button.custom_minimum_size = Vector2(420, 39)
	round_button.disabled = true # No fake rounds: wait for CombatCommandApi integration.
	round_button.tooltip_text = "Подключение CombatCommandApi — следующий этап"
	square_content.add_child(round_button)

func _build_fighter(origin: Vector2, is_player: bool) -> void:
	var panel := PanelContainer.new()
	panel.position = origin
	panel.custom_minimum_size = Vector2(232, 328)
	square_content.add_child(panel)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(232, 328)
	panel.add_child(inner)
	var name_label := Label.new()
	name_label.text = "ИГРОК" if is_player else "ПРОТИВНИК"
	name_label.position = Vector2(65, 3)
	inner.add_child(name_label)
	var portrait := TextureRect.new()
	portrait.position = Vector2(36, 27)
	portrait.custom_minimum_size = Vector2(160, 174)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if is_player and ResourceLoader.exists(AVATAR_PATH):
		portrait.texture = load(AVATAR_PATH)
	inner.add_child(portrait)
	if not is_player:
		var hidden := Label.new()
		hidden.text = "?"
		hidden.position = Vector2(106, 90)
		hidden.add_theme_font_size_override("font_size", 34)
		inner.add_child(hidden)
	for side in range(2):
		var slots: Array = SLOTS_LEFT if side == 0 else SLOTS_RIGHT
		for index in range(slots.size()):
			var slot: String = slots[index]
			var icon := ItemIcon.new()
			icon.name = slot
			icon.position = Vector2(2 if side == 0 else 199, 27 + index * 25)
			icon.custom_minimum_size = Vector2(30, 30)
			icon.scale = Vector2.ONE * 0.52
			inner.add_child(icon)
			if is_player:
				player_slots[slot] = icon
			else:
				enemy_slots[slot] = icon
			icon.set_item({}, InventoryScreen.SLOT_NAMES.get(slot, slot))
			icon.disabled = true
	var health := Label.new()
	health.position = Vector2(55, 206)
	health.text = "HP —" if is_player else "HP ? / ?"
	inner.add_child(health)
	if is_player:
		hp_label = health
	var subtitle := Label.new()
	subtitle.text = "ЗАЩИТА — зона блока" if is_player else "АТАКА — зона удара"
	subtitle.position = Vector2(35, 236)
	inner.add_child(subtitle)
	var zone_row := HBoxContainer.new()
	zone_row.position = Vector2(3, 264)
	zone_row.add_theme_constant_override("separation", 1)
	inner.add_child(zone_row)
	var group := ButtonGroup.new()
	for index in range(ZONES.size()):
		var zone: String = ZONES[index]
		var button := Button.new()
		button.text = ZONE_NAMES[index].substr(0, 3)
		button.tooltip_text = ZONE_NAMES[index]
		button.custom_minimum_size = Vector2(44, 38)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = zone == "chest"
		button.pressed.connect(_select_zone.bind(is_player, zone))
		zone_row.add_child(button)

func _select_zone(is_player: bool, zone: String) -> void:
	if is_player:
		defense_zone = zone
	else:
		attack_zone = zone

func refresh() -> void:
	for slot in player_slots:
		var icon := player_slots[slot] as ItemIcon
		var instance_id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		var item: Dictionary = repository.get_item(String(instance_id)) if instance_id != null and repository != null else {}
		icon.set_item(item, InventoryScreen.SLOT_NAMES.get(slot, slot), instance_id != null)
	for slot in enemy_slots:
		var icon := enemy_slots[slot] as ItemIcon
		icon.set_item({}, "?")
	if character != null and repository != null and hp_label != null:
		var snapshot := CharacterCombatBuilder.build(character, repository)
		hp_label.text = "HP %d / %d" % [snapshot.hp, snapshot.max_hp]

func _apply_layout() -> void:
	if layout == null:
		return
	var portrait := size.y > size.x
	layout.vertical = portrait
	var edge := maxf(1.0, minf(size.x, size.y))
	square_host.custom_minimum_size = Vector2(edge, edge)
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	square_content.scale = Vector2.ONE * (edge / 480.0)
