class_name ArenaScreen
extends Control

## Arena UI foundation. Combat commands are deliberately not simulated here.
signal back_requested
signal end_turn_requested(attack_targets: Array[String], block_zones: Array[String])
## Notify the owning scene to save persistent HP/mana after an accepted round.
signal resources_changed
signal inventory_changed

const SLOTS_LEFT := ["head", "shoulders", "chest", "main_hand", "waist", "legs", "feet"]
const SLOTS_RIGHT := ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]
const ZONES := ["head", "chest", "arms", "waist", "legs"]
const ZONE_NAMES := ["Голова", "Корпус", "Руки", "Пояс", "Ноги"]
const END_TURN_SKIN_COUNT := 10
const ARENA_LOGICAL_EXTENT := 480.0
const PORTRAIT_LOG_MIN_HEIGHT := 180.0
const LANDSCAPE_LOG_MIN_WIDTH := 260.0
const END_TURN_ATLAS_PATH := "res://assets/ui/buttons/end_turn/BOA_END_TURN_SKINS_ATLAS_V1.png"
const COMBAT_ZONE_ATLAS := "res://assets/ui/slots/BOA_COMBAT_ZONES_v2.png"
var end_turn_atlas: Texture2D
var zone_atlas: Texture2D
var zone_textures: Dictionary = {}

func _zone_texture(is_player: bool, index: int) -> Texture2D:
	if zone_atlas == null:
		if not ResourceLoader.exists(COMBAT_ZONE_ATLAS):
			return null
		zone_atlas = load(COMBAT_ZONE_ATLAS) as Texture2D
	if zone_atlas == null:
		return null
	var cell_key := index if is_player else index + 5
	if zone_textures.has(cell_key):
		return zone_textures[cell_key] as Texture2D
	# The corrected atlas is a clean 5x2 grid; do not trim frame pixels.
	var cell_width := float(zone_atlas.get_width()) / 5.0
	var cell_height := float(zone_atlas.get_height()) / 2.0
	var cropped := AtlasTexture.new()
	cropped.atlas = zone_atlas
	cropped.region = Rect2(index * cell_width, (0 if is_player else 1) * cell_height, cell_width, cell_height)
	cropped.filter_clip = true
	zone_textures[cell_key] = cropped
	return cropped
const SLOT_SYMBOLS := {"head":"♙", "shoulders":"♜", "neck":"◉", "back":"▤", "chest":"▣", "wrists":"▥", "hands":"✋", "waist":"▰", "legs":"♧", "feet":"♧", "main_hand":"⚔", "off_hand":"⬟", "ring1":"◯", "ring2":"◯"}
const AVATAR_PATH := "res://assets/avatars/hero_realistic_01.png"

var character: CharacterState
var repository: ItemRepository
var layout: BoxContainer
var square_host: Control
var square_content: Control
var arena_background: TextureRect
var log_view: RichTextLabel
var round_button: Button
var round_button_art: TextureRect
var defense_zones: Array[String] = ["chest"]
var defense_capacity := 1
var attack_zones: Array[String] = []
var attack_count := 2
var defense_buttons: Array[Button] = []
var attack_buttons: Array[Button] = []
var hp_bars: Dictionary = {}
var hp_overlays: Dictionary = {}
var fighter_names: Dictionary = {}
var mana_bars: Dictionary = {}
var mana_labels: Dictionary = {}
var ap_segments: Dictionary = {}
var ap_labels: Dictionary = {}
var effects_rows: Dictionary = {}
var effect_detail_labels: Dictionary = {}
var selected_ability := ""
var ability_buttons: Array[Button] = []
var combat_session: ArenaCombatSession
var test_player_level := 1
var test_enemy_level := 1
var level_settings_dialog: AcceptDialog
var level_player_value: Label
var level_enemy_value: Label
var player_slots: Dictionary = {}
var enemy_slots: Dictionary = {}
var hp_label: Label
var tabs: TabContainer
var par_report_dialog: AcceptDialog
var par_report_text: TextEdit
var abi_lab_dialog: AbiTestLabDialog
var fighter_popup: AcceptDialog
var item_popup: AcceptDialog
var item_popup_text: RichTextLabel
var fighter_popup_text: RichTextLabel
var disclosed_enemy_stats: Dictionary = {}
var disclosed_enemy_ratings: Dictionary = {}
var disclosed_enemy_equipment: Dictionary = {}
var player_elixir_slots: Array[Button] = []
var enemy_elixir_slots: Array[Button] = []
var player_elixirs: Array[Dictionary] = []
var enemy_elixirs: Array[Dictionary] = []
var player_belt_capacity := 0
var enemy_belt_capacity := 0
var elixir_global_cooldown := 0
const RATING_KEYS := ["crit_chance_rating", "anti_crit_rating", "dodge_rating", "anti_dodge_rating", "hit_chance_rating", "manual_block_rating", "shield_auto_block_rating", "block_crush", "armour_penetration_percent", "counterattack_rating"]
const RATING_NAMES := {"crit_chance_rating":"Крит", "anti_crit_rating":"Антикрит", "dodge_rating":"Уворот", "anti_dodge_rating":"Антиуворот", "hit_chance_rating":"Точность", "manual_block_rating":"Ручной блок", "shield_auto_block_rating":"Автоблок", "block_crush":"Пробивание блока, %", "armour_penetration_percent":"Пробивание брони, %", "counterattack_rating":"Контрудар"}
const PRIMARY_NAMES := {"PAR001":"Сила", "PAR002":"Ловкость", "PAR003":"Интуиция", "PAR005":"Мудрость", "PAR004":"Интеллект", "PAR006":"Выносливость"}

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
	square_content.size = Vector2(ARENA_LOGICAL_EXTENT, ARENA_LOGICAL_EXTENT)
	square_content.mouse_filter = Control.MOUSE_FILTER_PASS
	square_host.add_child(square_content)
	_build_square()
	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(log_panel)
	var log_column := VBoxContainer.new()
	log_panel.add_child(log_column)
	# Wrap controls on narrow portrait screens instead of clipping ABI Lab.
	var header := HFlowContainer.new()
	log_column.add_child(header)
	var back := Button.new()
	back.text = "← Назад"
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
	var report_button := Button.new()
	report_button.text = "PAR 108"
	report_button.tooltip_text = "Снимок всех PAR персонажа и боевого участника"
	report_button.pressed.connect(_show_par_report)
	header.add_child(report_button)
	var abi_lab_button := Button.new()
	abi_lab_button.text = "ABI Lab"
	abi_lab_button.tooltip_text = "Изолированная проверка ABI, PAR, урона и эффектов на манекене"
	abi_lab_button.pressed.connect(_open_abi_test_lab)
	header.add_child(abi_lab_button)
	var level_button := Button.new()
	level_button.text = "Уровень игрока"
	level_button.pressed.connect(func() -> void: _open_level_settings(true))
	header.add_child(level_button)
	var dummy_level_button := Button.new()
	dummy_level_button.text = "Уровень манекена"
	dummy_level_button.pressed.connect(func() -> void: _open_level_settings(false))
	header.add_child(dummy_level_button)
	_build_level_settings()
	abi_lab_dialog = AbiTestLabDialog.new()
	add_child(abi_lab_dialog)
	par_report_dialog = AcceptDialog.new()
	par_report_dialog.title = "PAR / Combat — 108 параметров"
	par_report_dialog.min_size = Vector2i(350, 540)
	add_child(par_report_dialog)
	par_report_text = TextEdit.new()
	par_report_text.editable = false
	par_report_text.custom_minimum_size = Vector2(320, 470)
	par_report_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	par_report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	par_report_dialog.add_child(par_report_text)
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_column.add_child(tabs)
	for title in ["Журнал", "Баффы", "Дебаффы"]:
		if title == "Журнал":
			var page := RichTextLabel.new()
			page.name = title
			page.bbcode_enabled = true
			page.size_flags_vertical = Control.SIZE_EXPAND_FILL
			page.text = "Арена готова. Боевые события появятся после подключения CombatEngine."
			tabs.add_child(page)
			log_view = page
		else:
			var comparison := HBoxContainer.new()
			comparison.name = title
			comparison.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tabs.add_child(comparison)
			for fighter_name in ["Игрок", "Противник"]:
				var column := VBoxContainer.new()
				column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				comparison.add_child(column)
				var heading := Label.new()
				heading.text = fighter_name
				column.add_child(heading)
				var details := Label.new()
				details.text = "Нет активных эффектов" if fighter_name == "Игрок" else "Нет известных эффектов"
				details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				column.add_child(details)
				effect_detail_labels[("player_" if fighter_name=="Игрок" else "enemy_")+title] = details
	item_popup = AcceptDialog.new()
	item_popup.title = "Предмет"
	item_popup.min_size = Vector2i(320, 260)
	add_child(item_popup)
	item_popup_text = RichTextLabel.new()
	item_popup_text.bbcode_enabled = true
	item_popup_text.custom_minimum_size = Vector2(290, 220)
	item_popup.add_child(item_popup_text)
	fighter_popup = AcceptDialog.new()
	fighter_popup.title = "Характеристики"
	fighter_popup.min_size = Vector2i(340, 370)
	add_child(fighter_popup)
	fighter_popup_text = RichTextLabel.new()
	fighter_popup_text.bbcode_enabled = true
	fighter_popup_text.custom_minimum_size = Vector2(310, 330)
	fighter_popup.add_child(fighter_popup_text)
	resized.connect(_apply_layout)
	_apply_layout()
	refresh()
	_start_combat_session()

func _open_level_settings(is_player: bool) -> void:
	level_settings_dialog.title = "Уровень игрока" if is_player else "Уровень манекена"
	level_settings_dialog.popup_centered()

func _build_level_settings() -> void:
	level_settings_dialog = AcceptDialog.new()
	level_settings_dialog.title = "Тестовые уровни Arena"
	level_settings_dialog.min_size = Vector2i(340, 250)
	add_child(level_settings_dialog)
	var content := VBoxContainer.new()
	level_settings_dialog.add_child(content)
	for is_player in [true, false]:
		var row := HBoxContainer.new()
		content.add_child(row)
		var name_label := Label.new()
		name_label.text = "Игрок" if is_player else "Манекен"
		name_label.custom_minimum_size.x = 100
		row.add_child(name_label)
		var minus := Button.new()
		minus.text = "−10"
		row.add_child(minus)
		minus.pressed.connect(_change_test_level.bind(is_player, -10))
		var minus_one := Button.new()
		minus_one.text = "−1"
		row.add_child(minus_one)
		minus_one.pressed.connect(_change_test_level.bind(is_player, -1))
		var value_label := Label.new()
		value_label.text = "1"
		value_label.custom_minimum_size.x = 34
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value_label)
		if is_player:
			level_player_value = value_label
		else:
			level_enemy_value = value_label
		for delta in [1, 10]:
			var plus := Button.new()
			plus.text = "+%d" % delta
			row.add_child(plus)
			plus.pressed.connect(_change_test_level.bind(is_player, delta))
	var apply := Button.new()
	apply.text = "Начать бой с выбранными уровнями"
	apply.pressed.connect(func() -> void:
		level_settings_dialog.hide()
		_start_combat_session()
	)
	content.add_child(apply)
	# This panel is diagnostic only. A defeated character must not be
	# silently healed on Arena re-entry; explicit refill keeps testing usable.
	var refill := Button.new()
	refill.text = "Тест: восстановить HP и ману"
	refill.tooltip_text = "Только для отладки Arena. Сброс текущих ресурсов и новый поединок."
	refill.pressed.connect(_refill_training_resources)
	content.add_child(refill)

func _refill_training_resources() -> void:
	if character == null or repository == null:
		return
	if character.reset_resources_to_full(repository):
		resources_changed.emit()
		_start_combat_session()
		level_settings_dialog.hide()

func _change_test_level(is_player: bool, delta: int) -> void:
	if is_player:
		test_player_level = clampi(test_player_level + delta, 1, 100)
		level_player_value.text = str(test_player_level)
	else:
		test_enemy_level = clampi(test_enemy_level + delta, 1, 100)
		level_enemy_value.text = str(test_enemy_level)

func _build_square() -> void:
	arena_background = TextureRect.new()
	arena_background.texture = load("res://assets/ui/arena/BOA_ARENA_BACKGROUND_V1.png") as Texture2D
	arena_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena_background.custom_minimum_size = Vector2.ZERO
	arena_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arena_background.stretch_mode = TextureRect.STRETCH_SCALE
	arena_background.size = Vector2(ARENA_LOGICAL_EXTENT, ARENA_LOGICAL_EXTENT)
	arena_background.clip_contents = false
	arena_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square_content.add_child(arena_background)
	_build_fighter(Vector2(4, 8), true)
	_build_fighter(Vector2(242, 8), false)
	var abilities := HBoxContainer.new()
	abilities.name = "AbilitySlots"
	# Permanent 5-square system strip: MH 1-3, Head 4, Chest 5.
	abilities.position = Vector2((ARENA_LOGICAL_EXTENT - 5.0 * 34.0) / 2.0, 389)
	abilities.add_theme_constant_override("separation", 0)
	square_content.add_child(abilities)
	for index in range(5):
		var button := Button.new()
		button.name = "ABI%d" % (index + 1)
		button.custom_minimum_size = Vector2(34, 34)
		button.text = ""
		SquareSlotFeedback.style_abi_square(button)
		button.tooltip_text = SquareUiGeometry.abi_source(index) + " — пусто"
		button.toggle_mode = true
		button.disabled = true
		button.pressed.connect(_select_ability.bind(index))
		abilities.add_child(button)
		SquareSlotFeedback.attach(button, "ability")
		ability_buttons.append(button)
	_build_resource_display(true)
	_build_resource_display(false)
	round_button = Button.new()
	round_button.text = "ПРОВЕСТИ РАУНД"
	round_button.position = Vector2(90, 423)
	round_button.custom_minimum_size = Vector2(300, 42)
	round_button.disabled = true # Enabled by the combat session controller.
	round_button.tooltip_text = "Ожидание боевого сеанса"
	round_button.pressed.connect(_request_end_turn)
	end_turn_requested.connect(_play_combat_round)
	square_content.add_child(round_button)
	var invisible_button_style := StyleBoxEmpty.new()
	for button_state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		round_button.add_theme_stylebox_override(button_state, invisible_button_style)
	round_button_art = TextureRect.new()
	round_button_art.position = round_button.position
	round_button_art.size = Vector2(300, 42)
	round_button_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	round_button_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	round_button_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square_content.add_child(round_button_art)
	# Cosmetic END TURN skins; the first skin is the default.
	# Until the transparent PNGs are uploaded, keep the original button.
	_apply_end_turn_skin(1)
	SquareSlotFeedback.attach_art(round_button, round_button_art)


## Skin IDs follow atlas reading order: left-to-right, top-to-bottom.
## Exposed for a future settings selector; visual only, no combat behavior.
func set_end_turn_skin(skin_id: int) -> void:
	_apply_end_turn_skin(skin_id)

func _apply_end_turn_skin(skin_id: int) -> void:
	if round_button == null:
		return
	if end_turn_atlas == null:
		if not ResourceLoader.exists(END_TURN_ATLAS_PATH):
			return
		end_turn_atlas = load(END_TURN_ATLAS_PATH) as Texture2D
	if end_turn_atlas == null:
		return
	var selected_id: int = clampi(skin_id, 1, END_TURN_SKIN_COUNT)
	var cell_width := float(end_turn_atlas.get_width()) / 2.0
	var cell_height := float(end_turn_atlas.get_height()) / 5.0
	var index := selected_id - 1
	var texture := AtlasTexture.new()
	texture.atlas = end_turn_atlas
	texture.region = Rect2((index % 2) * cell_width, floori(float(index) / 2.0) * cell_height, cell_width, cell_height)
	texture.filter_clip = true
	if round_button_art != null:
		round_button_art.texture = texture
	round_button.text = "" # END TURN is baked into the atlas artwork.
	round_button.tooltip_text = "END TURN · скин %d" % selected_id

func _build_fighter(origin: Vector2, is_player: bool) -> void:
	var panel := PanelContainer.new()
	panel.position = origin
	panel.custom_minimum_size = Vector2(232, 352)
	square_content.add_child(panel)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(232, 328)
	panel.add_child(inner)
	var name_label := Label.new()
	name_label.text = "Герой [1]" if is_player else "Противник [1]"
	name_label.position = Vector2(38, 1)
	name_label.custom_minimum_size = Vector2(156, 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color("#f1ddbb"))
	var name_font := SystemFont.new()
	name_font.font_weight = 700
	name_label.add_theme_font_override("font", name_font)
	inner.add_child(name_label)
	fighter_names["player" if is_player else "enemy"] = name_label
	var portrait := TextureRect.new()
	portrait.position = Vector2(48, 39)
	portrait.custom_minimum_size = Vector2(136, 233)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if is_player and ResourceLoader.exists(AVATAR_PATH):
		portrait.texture = load(AVATAR_PATH)
	inner.add_child(portrait)
	var inspect := Button.new()
	inspect.flat = true
	inspect.position = Vector2(40, 35)
	inspect.custom_minimum_size = Vector2(152, 237)
	inspect.tooltip_text = "Посмотреть характеристики"
	inspect.pressed.connect(_show_fighter_details.bind(is_player))
	inner.add_child(inspect)
	if not is_player:
		var hidden := Label.new()
		hidden.text = "?"
		hidden.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hidden.position = Vector2(106, 100)
		hidden.add_theme_font_size_override("font_size", 34)
		inner.add_child(hidden)
	for side in range(2):
		var slots: Array = SLOTS_LEFT if side == 0 else SLOTS_RIGHT
		for index in range(slots.size()):
			var slot: String = slots[index]
			var icon := ItemIcon.new()
			icon.name = slot
			icon.position = Vector2(5 if side == 0 else 187, 35 + index * 42)
			icon.custom_minimum_size = Vector2(30, 30)
			icon.scale = Vector2.ONE * 0.74
			inner.add_child(icon)
			if is_player:
				player_slots[slot] = icon
			else:
				enemy_slots[slot] = icon
			icon.set_item({}, slot)
			icon.pressed.connect(_show_equipment_details.bind(is_player, slot))
	_add_resource_frame(inner, Vector2(36, 17), Vector2(160, 15))
	var health_bar := ProgressBar.new()
	health_bar.position = Vector2(38, 19)
	health_bar.custom_minimum_size = Vector2(156, 11)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	health_bar.value = 100 if is_player else 0
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#35383e")
	bar_bg.border_color = Color("#35383e")
	bar_bg.set_border_width_all(0)
	health_bar.add_theme_stylebox_override("background", bar_bg)
	inner.add_child(health_bar)
	var health := Label.new()
	health.position = Vector2(38, 17)
	health.custom_minimum_size = Vector2(156, 14)
	health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health.add_theme_font_size_override("font_size", 9)
	health.add_theme_color_override("font_color", Color.WHITE)
	health.text = "— / —"
	inner.add_child(health)
	hp_bars["player" if is_player else "enemy"] = health_bar
	hp_overlays["player" if is_player else "enemy"] = health
	if is_player:
		hp_label = health
	var elixir_row := HBoxContainer.new()
	elixir_row.position = Vector2(48, 296)
	elixir_row.add_theme_constant_override("separation", 4)
	inner.add_child(elixir_row)
	for elixir_index in range(4):
		var elixir_button := Button.new()
		elixir_button.custom_minimum_size = Vector2(31, 32)
		elixir_button.add_theme_font_size_override("font_size", 10)
		elixir_button.disabled = true
		var elixir_style := StyleBoxTexture.new()
		elixir_style.texture = ItemIcon.empty_slot_texture("elixir")
		if elixir_style.texture != null:
			for state in ["normal", "hover", "pressed", "disabled"]:
				elixir_button.add_theme_stylebox_override(state, elixir_style)
		elixir_row.add_child(elixir_button)
		SquareSlotFeedback.attach(elixir_button, "elixir")
		if is_player:
			elixir_button.pressed.connect(_use_elixir.bind(elixir_index))
			player_elixir_slots.append(elixir_button)
		else:
			enemy_elixir_slots.append(elixir_button)
	_update_elixir_slots()
	var zone_row := HBoxContainer.new()
	zone_row.position = Vector2(6 if is_player else 2, 333)
	zone_row.add_theme_constant_override("separation", 4)
	inner.add_child(zone_row)
	for index in range(ZONES.size()):
		var zone: String = ZONES[index]
		var button := Button.new()
		button.text = ""
		var zone_texture := _zone_texture(is_player, index)
		if zone_texture != null:
			var zone_style := StyleBoxTexture.new()
			zone_style.texture = zone_texture
			for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
				button.add_theme_stylebox_override(state, zone_style)
		# A persistent outline belongs to the selected zone, not keyboard focus.
		# Overlay does not consume touch input or change the existing icon.
		var selection_outline := Panel.new()
		selection_outline.name = "SelectionOutline"
		selection_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		selection_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var outline_style := StyleBoxFlat.new()
		outline_style.bg_color = Color(0, 0, 0, 0)
		outline_style.border_color = Color("#f5f0dc")
		outline_style.set_border_width_all(3)
		outline_style.set_corner_radius_all(3)
		selection_outline.add_theme_stylebox_override("panel", outline_style)
		selection_outline.visible = false
		button.add_child(selection_outline)
		button.tooltip_text = ZONE_NAMES[index]
		button.custom_minimum_size = Vector2(42, 44)
		button.toggle_mode = true
		button.button_pressed = is_player and zone == "chest"
		button.pressed.connect(_select_zone.bind(is_player, zone))
		zone_row.add_child(button)
		SquareSlotFeedback.attach(button, "zone")
		if is_player:
			defense_buttons.append(button)
		else:
			attack_buttons.append(button)
	# Effect indicators occupy the bottom-left of the portrait and stay hidden
	# until actual effect data is supplied. No placeholder icons over the face.
	for row_type in ["Баффы", "Дебаффы"]:
		var row := HBoxContainer.new()
		row.position = Vector2(elixir_row.position.x, elixir_row.position.y - (43 if row_type == "Баффы" else 22))
		row.add_theme_constant_override("separation", 1)
		row.visible = false # No placeholder EFF icons before actual combat state exists.
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		inner.add_child(row)
		for i in range(5):
			var effect_icon := Button.new()
			effect_icon.custom_minimum_size = Vector2(19, 19)
			effect_icon.add_theme_font_size_override("font_size", 10)
			effect_icon.focus_mode = Control.FOCUS_NONE
			effect_icon.visible = false
			effect_icon.pressed.connect(_show_effect_detail.bind(is_player,row_type,i))
			row.add_child(effect_icon)
		effects_rows[("player_" if is_player else "enemy_") + row_type] = row
	_update_zone_buttons()

## UI-only disclosure contract. Callers must provide ratings computed from visible
## primary stats and disclosed equipment; never pass combatant totals here.
func set_disclosed_enemy(primary_stats: Dictionary, ratings: Dictionary, equipment: Dictionary = {}) -> void:
	disclosed_enemy_stats = primary_stats.duplicate(true)
	disclosed_enemy_ratings = ratings.duplicate(true)
	disclosed_enemy_equipment = equipment.duplicate(true)
	for slot in enemy_slots:
		var item: Dictionary = disclosed_enemy_equipment.get(slot, {})
		(enemy_slots[slot] as ItemIcon).set_item(item, slot)

## UI-only belt capacity and charge snapshots. The caller owns gameplay state.
## Each entry may contain icon, charges and max_charges; no charges are spent here.
func set_elixir_display(is_player: bool, belt_slots: int, elixirs: Array[Dictionary]) -> void:
	if is_player:
		player_belt_capacity = clampi(belt_slots, 0, 4)
		player_elixirs = elixirs.duplicate(true)
	else:
		enemy_belt_capacity = clampi(belt_slots, 0, 4)
		enemy_elixirs = elixirs.duplicate(true)
	_update_elixir_slots()

func set_elixir_cooldown(rounds_remaining: int) -> void:
	elixir_global_cooldown = maxi(0, rounds_remaining)
	_update_elixir_slots()

func _update_elixir_slots() -> void:
	for is_player in [true, false]:
		var buttons: Array[Button] = player_elixir_slots if is_player else enemy_elixir_slots
		var capacity: int = player_belt_capacity if is_player else enemy_belt_capacity
		var entries: Array[Dictionary] = player_elixirs if is_player else enemy_elixirs
		for index in range(buttons.size()):
			var button := buttons[index]
			button.disabled = true
			if index >= capacity:
				button.text = ""
				button.tooltip_text = "Слот эликсира недоступен — нужен пояс"
				continue
			if index >= entries.size() or entries[index].is_empty():
				button.text = ""
				button.tooltip_text = "Пустой слот эликсира"
				continue
			var item: Dictionary = entries[index]
			var charges := maxi(0, int(item.get("charges", 0)))
			var maximum := maxi(1, int(item.get("max_charges", 1)))
			var symbol := String(item.get("icon", "♧"))
			button.text = "%s\n%d/%d" % [symbol, charges, maximum]
			button.tooltip_text = "%s — %d/%d зарядов" % [String(item.get("name", "Эликсир")), charges, maximum]
			if elixir_global_cooldown > 0:
				button.text = "%s\nКД %d" % [symbol, elixir_global_cooldown]
				button.tooltip_text += " | Общее КД: %d раунд(ов)" % elixir_global_cooldown
			button.disabled = not is_player or not bool(item.get("available",false)) or charges <= 0 or elixir_global_cooldown>0

func _show_equipment_details(is_player: bool, slot: String) -> void:
	var item: Dictionary = {}
	if is_player:
		if character != null and repository != null:
			var instance_id: Variant = character.equipment.get_equipped_instance_id(slot)
			if instance_id != null:
				item = repository.get_item(String(instance_id))
	else:
		item = disclosed_enemy_equipment.get(slot, {})
	# Undisclosed opponent equipment must not reveal whether a slot is empty.
	if item.is_empty():
		if is_player:
			item_popup.title = "Слот экипировки"
			item_popup_text.clear()
			item_popup_text.add_text("%s — пусто" % SquareUiGeometry.equipment_name(slot))
			item_popup.popup_centered()
		return
	var rarity := String(item.get("rarity", "grey")).to_lower()
	var quality_color := String(ItemIcon.RARITY_COLORS.get(rarity, "#aab0b8"))
	var item_name := String(item.get("name", "Предмет"))
	item_popup.title = item_name
	item_popup_text.clear()
	var texture: Texture2D = null
	var icon_path := String(item.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		texture = load(icon_path) as Texture2D
	elif item.has("icon_id"):
		texture = ItemIcon._texture_from_icon_id(String(item["icon_id"]))
	elif item.has("atlas_index") and ResourceLoader.exists(ItemIcon.ATLAS_PATH):
		texture = ItemIcon._atlas_cell(load(ItemIcon.ATLAS_PATH) as Texture2D, int(item["atlas_index"]), ItemIcon.ATLAS_COLUMNS, ItemIcon.ATLAS_ROWS)
	if texture != null:
		item_popup_text.add_image(texture, 56, 56)
		item_popup_text.add_text("\n")
	item_popup_text.push_color(Color(quality_color))
	item_popup_text.push_bold()
	item_popup_text.add_text(item_name)
	item_popup_text.pop()
	item_popup_text.pop()
	item_popup_text.add_text("\nУровень: %s   Слот: %s\n" % [str(item.get("item_level", "—")), slot])
	for field in ["par_stats", "par_bonuses", "requirements"]:
		var values: Variant = item.get(field, {})
		if values is Dictionary and not values.is_empty():
			item_popup_text.push_bold()
			item_popup_text.add_text("\n%s\n" % field)
			item_popup_text.pop()
			for key in values:
				var par_name := String(Dictionary(ParCalculationService.registry().get(str(key), {})).get("name", str(key)))
				item_popup_text.add_text("%s — %s: %s\n" % [str(key), par_name, str(values[key])])
	var description := String(item.get("description", ""))
	if not description.is_empty():
		item_popup_text.add_text("\n" + description)
	item_popup.popup_centered()

func _show_fighter_details(is_player: bool) -> void:
	var primary: Dictionary = {}
	var ratings: Dictionary = {}
	if is_player and character != null and repository != null:
		primary = character.effective_stats(repository)
		ratings = CharacterStatsService.snapshot(character, repository)
	elif not is_player:
		primary = disclosed_enemy_stats
		ratings = disclosed_enemy_ratings
	fighter_popup.title = "Игрок" if is_player else "Противник"
	var lines: PackedStringArray = []
	lines.append("[b]Характеристики[/b]")
	for key in PRIMARY_NAMES:
		if primary.has(key):
			lines.append("%s: %s" % [PRIMARY_NAMES[key], str(primary[key])])
	lines.append("")
	lines.append("[b]Рейтинги[/b]")
	for key in RATING_KEYS:
		if ratings.has(key):
			lines.append("%s: %s" % [RATING_NAMES[key], str(ratings[key])])
	if combat_session != null:
		var fighter := combat_session.fighter(is_player)
		if fighter != null:
			lines.append("")
			lines.append("[b]Tempo PAR019–021[/b]")
			lines.append("Текущее: %s  •  Базовое: %s" % [str(fighter.tempo), str(fighter.base_tempo)])
			lines.append("Максимум: %s  •  Восстановление/раунд: %s" % [str(fighter.max_tempo), str(fighter.tempo_regen)])
			var round_number := combat_session.state.round_number
			lines.append("Состояние: %s" % ("Оглушён" if CombatTempoService.is_stunned(fighter, round_number) else ("Иммунитет к стану" if CombatTempoService.is_immune(fighter, round_number) else "Обычное")))
			if fighter.tempo_stun_round > round_number:
				lines.append("Оглушение назначено на раунд %d" % fighter.tempo_stun_round)
			elif fighter.tempo_immunity_until_round >= round_number and fighter.tempo_immunity_until_round > 0:
				lines.append("Иммунитет до конца раунда %d" % fighter.tempo_immunity_until_round)
	if primary.is_empty() and ratings.is_empty():
		lines.append("Нет доступных характеристик")
	fighter_popup_text.text = "\n".join(lines)
	fighter_popup.popup_centered()

func _select_zone(is_player: bool, zone: String) -> void:
	var index := ZONES.find(zone)
	if is_player:
		# Each protected zone is individually chosen; non-adjacent combinations work.
		if defense_zones.has(zone):
			if defense_zones.size() > 1:
				defense_zones.erase(zone)
		elif defense_zones.size() < defense_capacity:
			defense_zones.append(zone)
		else:
			defense_zones[defense_zones.size() - 1] = zone
	else:
		if attack_zones.has(zone):
			attack_zones.erase(zone)
		elif attack_zones.size() < attack_count:
			attack_zones.append(zone)
		else:
			# Replacing the second target is quicker than clearing both selections.
			attack_zones[attack_zones.size() - 1] = zone
	_update_zone_buttons()

func set_defense_capacity(capacity: int) -> void:
	defense_capacity = clampi(capacity, 1, 4)
	while defense_zones.size() > defense_capacity:
		defense_zones.pop_back()
	# Preserve the familiar ready-to-fight default while allowing any zone combination.
	for zone in ["chest", "arms", "waist", "legs", "head"]:
		if defense_zones.size() >= defense_capacity:
			break
		if not defense_zones.has(zone):
			defense_zones.append(zone)
	_update_zone_buttons()

func set_attack_count(count: int) -> void:
	attack_count = maxi(1, count)
	while attack_zones.size() > attack_count:
		attack_zones.pop_back()
	_update_zone_buttons()

func _select_ability(index: int) -> void:
	if combat_session == null or index < 0 or index >= ability_buttons.size():
		return
	var options := combat_session.player_ability_options()
	if index >= options.size() or not bool(Dictionary(options[index]).get("available",false)):
		return
	var ability_id := String(Dictionary(options[index]).get("id",""))
	var result := combat_session.activate_ability(ability_id)
	if not bool(result.get("ok",false)):
		_prepend_combat_log("ABI отклонена: " + String(result.get("reason","unknown")))
		return
	selected_ability = ability_id
	_sync_combat_session()
	# Instant resolves on this click; Standard is now irrevocably locked.
	_prepend_combat_log("%s: %s" % [ability_id, "эффект применён" if String(result.get("timing",""))=="instant" else "действие зафиксировано до конца раунда"])
	if character != null and repository != null:
		if character.commit_combat_resources(combat_session.fighter(true), repository):
			resources_changed.emit()

func _use_elixir(index: int) -> void:
	if combat_session == null:
		return
	var result := combat_session.use_elixir(index)
	if not bool(result.get("ok",false)):
		_prepend_combat_log("Эликсир отклонён: " + String(result.get("reason","unknown")))
		return
	_sync_combat_session()
	_prepend_combat_log("Эликсир использован — осталось зарядов: %d" % int(result.get("charges",0)))
	if character != null and repository != null:
		if character.commit_combat_resources(combat_session.fighter(true), repository):
			resources_changed.emit()
	inventory_changed.emit()

func _refresh_ability_buttons() -> void:
	if combat_session == null:
		return
	var options:=combat_session.player_ability_options()
	var selected_still_valid:=false
	for index in range(ability_buttons.size()):
		var button:=ability_buttons[index]
		var option:Dictionary=options[index] if index<options.size() else {}
		var ability_id:=String(option.get("id",""))
		var available:=bool(option.get("available",false))
		if (selected_ability==ability_id and available and not ability_id.is_empty()) or combat_session.locked_ability_id==ability_id and not ability_id.is_empty():
			selected_still_valid=true
		button.disabled=not available
		button.text=ability_id if not ability_id.is_empty() else ""
		button.add_theme_font_size_override("font_size",8)
		var source := SquareUiGeometry.abi_source(index)
		button.tooltip_text=("%s | %s — %s | Мана: %d | Цель: %s" % [source, ability_id, String(option.get("name",ability_id)),int(option.get("mana_cost",0)),String(option.get("target_label","—"))]) if bool(option.get("defined",false)) else (source + ": ABI не определена — " + ability_id if not ability_id.is_empty() else source + " — пусто")
		button.set_pressed_no_signal((available and selected_ability==ability_id) or combat_session.locked_ability_id==ability_id and not ability_id.is_empty())
		SquareSlotFeedback.set_selected(button, combat_session.locked_ability_id==ability_id and not ability_id.is_empty())
	if not selected_still_valid:
		selected_ability=""

func set_combat_ready(ready: bool) -> void:
	if round_button != null:
		round_button.disabled = not ready

func _request_end_turn() -> void:
	if round_button == null or round_button.disabled:
		return
	end_turn_requested.emit(selected_attack_targets(), selected_block_zones())

func selected_attack_targets() -> Array[String]:
	var result: Array[String] = []
	if attack_zones.is_empty():
		return result
	if attack_zones.size() == 1:
		for i in range(attack_count):
			result.append(attack_zones[0])
	else:
		for i in range(attack_count):
			result.append(attack_zones[mini(i, attack_zones.size() - 1)])
	return result

func selected_block_zones() -> Array[String]:
	var result: Array[String] = []
	for zone in defense_zones:
		result.append(zone)
	return result

func _update_zone_buttons() -> void:
	for i in range(defense_buttons.size()):
		var chosen := defense_zones.has(ZONES[i])
		defense_buttons[i].set_pressed_no_signal(chosen)
		defense_buttons[i].modulate = Color.WHITE
		var outline := defense_buttons[i].get_node_or_null("SelectionOutline")
		if outline != null:
			outline.visible = chosen
	for i in range(attack_buttons.size()):
		var chosen := attack_zones.has(ZONES[i])
		attack_buttons[i].set_pressed_no_signal(chosen)
		attack_buttons[i].modulate = Color.WHITE
		var outline := attack_buttons[i].get_node_or_null("SelectionOutline")
		if outline != null:
			outline.visible = chosen

func _update_hp(bar: ProgressBar, overlay: Label, current: int, maximum: int) -> void:
	bar.max_value = maxi(1, maximum)
	bar.value = clampi(current, 0, maxi(1, maximum))
	overlay.text = "%d / %d" % [current, maximum]
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#b93642")
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)


## UI-only snapshots; resource mechanics are owned by gameplay services.
func set_fighter_header(is_player: bool, fighter_name: String, fighter_level: int) -> void:
	var key := "player" if is_player else "enemy"
	if fighter_names.has(key):
		(fighter_names[key] as Label).text = "%s [%d]" % [fighter_name, maxi(1, fighter_level)]

func set_fighter_hp(is_player: bool, current: int, maximum: int) -> void:
	var key := "player" if is_player else "enemy"
	if hp_bars.has(key):
		_update_hp(hp_bars[key], hp_overlays[key], current, maximum)

func set_fighter_resources(is_player: bool, mana: int, max_mana: int, ap: int, max_ap: int) -> void:
	var key := "player" if is_player else "enemy"
	if not mana_bars.has(key):
		return
	var bar := mana_bars[key] as ProgressBar
	bar.max_value = maxi(1, max_mana)
	bar.value = clampi(mana, 0, maxi(0, max_mana))
	(mana_labels[key] as Label).text = "%d / %d" % [maxi(0, mana), maxi(0, max_mana)]
	var segments: Array = ap_segments[key]
	var capped_max := clampi(max_ap, 0, 8)
	var gap := 3.0
	var segment_width := (124.0 - gap * float(maxi(0, capped_max - 1))) / float(maxi(1, capped_max))
	for i in range(segments.size()):
		var segment := segments[i] as ColorRect
		segment.visible = i < capped_max
		segment.custom_minimum_size = Vector2(segment_width, 9)
		segment.color = Color("#c09a49") if i < clampi(ap, 0, capped_max) else Color("#41392b")
	(ap_labels[key] as Label).text = "%d / %d AP" % [clampi(ap, 0, capped_max), capped_max]

func _add_resource_frame(parent: Control, frame_position: Vector2, frame_size: Vector2) -> void:
	var frame := Panel.new()
	frame.position = frame_position
	frame.size = frame_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.border_color = Color("#b99a5c")
	border.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", border)
	parent.add_child(frame)

func _build_resource_display(is_player: bool) -> void:
	var key := "player" if is_player else "enemy"
	var host := Control.new()
	host.position = Vector2(12 if is_player else 344, 389)
	host.custom_minimum_size = Vector2(124, 47)
	square_content.add_child(host)
	_add_resource_frame(host, Vector2(-2, -2), Vector2(128, 20))
	_add_resource_frame(host, Vector2(-2, 19), Vector2(128, 13))
	var mana := ProgressBar.new()
	mana.position = Vector2.ZERO
	mana.custom_minimum_size = Vector2(124, 16)
	mana.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#172b43")
	mana.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#347abd")
	mana.add_theme_stylebox_override("fill", fill)
	host.add_child(mana)
	var mana_text := Label.new()
	mana_text.position = Vector2.ZERO
	mana_text.custom_minimum_size = Vector2(124, 16)
	mana_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_text.add_theme_font_size_override("font_size", 10)
	mana_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(mana_text)
	var ap_row := HBoxContainer.new()
	ap_row.position = Vector2(0, 21)
	ap_row.add_theme_constant_override("separation", 3)
	host.add_child(ap_row)
	var segments: Array = []
	for i in range(8):
		var segment := ColorRect.new()
		segment.custom_minimum_size = Vector2(13, 9)
		ap_row.add_child(segment)
		segments.append(segment)
	var ap_text := Label.new()
	ap_text.position = Vector2(0, 31)
	ap_text.custom_minimum_size = Vector2(124, 14)
	ap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_text.add_theme_font_size_override("font_size", 9)
	host.add_child(ap_text)
	mana_bars[key] = mana
	mana_labels[key] = mana_text
	ap_segments[key] = segments
	ap_labels[key] = ap_text
	set_fighter_resources(is_player, 0, 0, 5, 5)

func _start_combat_session() -> void:
	if character == null or repository == null:
		return
	selected_ability = ""
	combat_session = ArenaCombatSession.new(character, repository)
	# Test-only level override on combat snapshots; persistent character data is untouched.
	combat_session.fighter(true).level = test_player_level
	combat_session.fighter(false).level = test_enemy_level
	set_fighter_header(true, combat_session.fighter(true).display_name, test_player_level)
	disclosed_enemy_equipment = combat_session.enemy_equipment_display.duplicate(true)
	set_attack_count(combat_session.player_attack_count())
	set_defense_capacity(CombatModifierService.manual_block_zone_capacity(combat_session.fighter(true)))
	set_fighter_header(false, combat_session.fighter(false).display_name, combat_session.fighter(false).level)
	_sync_combat_session()
	var can_fight := combat_session.fighter(true).hp > 0
	log_view.text = "Тренировочный бой начат. Выберите зоны атаки и защиты." if can_fight else "HP персонажа равно 0. Для продолжения тестов откройте «Уровень игрока» → «Тест: восстановить HP и ману»."
	set_combat_ready(can_fight)

func _play_combat_round(targets: Array[String], blocks: Array[String]) -> void:
	if combat_session == null:
		return
	set_combat_ready(false)
	var result: Dictionary = combat_session.play_round(targets, blocks)
	if not bool(result.get("ok", false)):
		_prepend_combat_log("Команда отклонена: %s" % String(result.get("reason", "unknown")))
		set_combat_ready(true)
		return
	# A successful round has already finalized HP and mana. Keep persistent
	# character resources in step with the live Arena combatant before the
	# player can exit, reopen inventory, or start another test duel.
	if character != null and repository != null:
		if character.commit_combat_resources(combat_session.fighter(true), repository):
			resources_changed.emit()
		else:
			push_error("Arena resource write-back rejected: player snapshot mismatch")
	selected_ability=""
	_sync_combat_session()
	var round_lines: Array[String] = ["Раунд %d" % int(result.get("round", 0))]
	for line in Array(result.get("lines", [])):
		round_lines.append(String(line))
	if String(result.get("outcome", "ongoing")) == "ongoing":
		set_combat_ready(true)
	else:
		round_lines.append("Бой завершён: " + String(result.get("outcome", "")))
	_prepend_combat_log("\n".join(round_lines))

func _prepend_combat_log(entry: String) -> void:
	if log_view == null:
		return
	var previous := log_view.text
	log_view.text = entry if previous.is_empty() else entry + "\n\n" + previous
	log_view.scroll_to_line(0)


## Compact two-row EFF view. Five cells per row; last cell becomes +N when
## there are more than five active/pending effects. Tap for details on mobile.
func _effect_entries(is_player:bool,row_type:String) -> Array:
	if combat_session == null:
		return []
	var snapshot:=combat_session.effect_view(is_player)
	return Array(snapshot.get("buffs" if row_type=="Баффы" else "debuffs",[]))

func _effect_symbol(kind:String) -> String:
	match kind:
		"dot", "poison", "bleed": return "!"
		"hot", "regen", "regeneration": return "+"
		"shield", "buff": return "↑"
		"stun", "freeze", "fear", "root": return "×"
		"slow", "debuff": return "↓"
	return "•"

func _effect_description(effect:Dictionary) -> String:
	var label:=String(effect.get("name",effect.get("id","EFF")))
	var remaining:=int(effect.get("remaining_rounds",0))
	var stacks:=int(effect.get("stacks",1))
	var result:="%s (%s) — %d раунд(ов)" % [label,String(effect.get("id","")),remaining]
	if stacks>1:
		result+=" ×%d" % stacks
	if bool(effect.get("pending",false)):
		result+=" — вступит в следующем раунде"
	return result

func _refresh_effect_display() -> void:
	if combat_session==null:
		return
	for is_player in [true,false]:
		var fighter_key: String = "player_" if is_player else "enemy_"
		for row_type in ["Баффы", "Дебаффы"]:
			var key: String = fighter_key + String(row_type)
			var row:=effects_rows.get(key) as HBoxContainer
			if row==null:
				continue
			var effects: Array = _effect_entries(is_player, String(row_type))
			row.visible = not effects.is_empty()
			var visible_count: int = mini(5, effects.size())
			for index in range(row.get_child_count()):
				var button:=row.get_child(index) as Button
				if button==null:
					continue
				button.visible=index<visible_count
				if index>=visible_count:
					continue
				var extra: int = effects.size()-4 if effects.size()>5 and index==4 else 0
				if extra>0:
					button.text="+%d" % extra
					button.tooltip_text="Ещё %d эффект(ов) — нажмите для списка" % extra
				else:
					var entry:Dictionary=effects[index]
					button.text=_effect_symbol(String(entry.get("kind","")))
					button.tooltip_text=_effect_description(entry)
				button.modulate=Color("#9ebfdb") if row_type=="Баффы" else Color("#e0a3a3")
			var detail:=effect_detail_labels.get(key) as Label
			if detail!=null:
				if effects.is_empty():
					detail.text="Нет активных эффектов"
				else:
					var all_lines:PackedStringArray=[]
					for item in effects:
						all_lines.append(_effect_description(Dictionary(item)))
					detail.text="\n".join(all_lines)

func _show_effect_detail(is_player:bool,row_type:String,index:int) -> void:
	var effects:=_effect_entries(is_player,row_type)
	if index>=effects.size() and not (effects.size()>5 and index==4):
		return
	var lines:PackedStringArray=[]
	if effects.size()>5 and index==4:
		for i in range(4,effects.size()):
			lines.append(_effect_description(Dictionary(effects[i])))
	else:
		lines.append(_effect_description(Dictionary(effects[index])))
	item_popup.title=("%s — %s" % ["Игрок" if is_player else "Противник",row_type])
	item_popup_text.clear()
	item_popup_text.add_text("\n".join(lines))
	item_popup.popup_centered()

func _sync_combat_session() -> void:
	if combat_session == null:
		return
	var player := combat_session.fighter(true)
	var enemy := combat_session.fighter(false)
	set_fighter_hp(true, player.visible_hp(), player.max_hp)
	set_fighter_hp(false, enemy.visible_hp(), enemy.max_hp)
	set_fighter_resources(true, player.mana, player.max_mana, player.action_points, player.max_action_points)
	set_fighter_resources(false, enemy.mana, enemy.max_mana, enemy.action_points, enemy.max_action_points)
	set_elixir_display(true, character.elixir_capacity(repository), combat_session.elixir_options())
	set_elixir_display(false, 0, [])
	set_elixir_cooldown(combat_session.elixir_cooldown())
	_refresh_ability_buttons()
	_refresh_effect_display()

func refresh() -> void:
	for slot in player_slots:
		var icon := player_slots[slot] as ItemIcon
		var instance_id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		var item: Dictionary = repository.get_item(String(instance_id)) if instance_id != null and repository != null else {}
		icon.set_item(item, slot, instance_id != null)
	for slot in enemy_slots:
		var icon := enemy_slots[slot] as ItemIcon
		var disclosed: Dictionary = disclosed_enemy_equipment.get(slot, {})
		icon.set_item(disclosed, slot)
		if disclosed.is_empty():
			icon.tooltip_text = "Снаряжение противника неизвестно"
	if character != null and repository != null and hp_label != null and combat_session == null:
		var snapshot := CharacterCombatBuilder.build(character, repository)
		_update_hp(hp_bars["player"], hp_label, snapshot.hp, snapshot.max_hp)
		set_fighter_header(true, character.display_name, character.level)
		set_fighter_resources(true, snapshot.mana, snapshot.max_mana, snapshot.action_points, snapshot.max_action_points)

func _apply_layout() -> void:
	if layout == null:
		return
	var portrait := size.y > size.x
	layout.vertical = portrait
	var separation := float(layout.get_theme_constant("separation"))
	var available_width := size.x
	var available_height := size.y
	if portrait:
		available_height = maxf(1.0, size.y - PORTRAIT_LOG_MIN_HEIGHT - separation)
	else:
		available_width = maxf(1.0, size.x - LANDSCAPE_LOG_MIN_WIDTH - separation)
	var edge := floorf(maxf(1.0, minf(available_width, available_height)))
	SquareUiGeometry.fit(square_host, square_content, edge, ARENA_LOGICAL_EXTENT)
	if arena_background != null:
		arena_background.size = Vector2.ONE * ARENA_LOGICAL_EXTENT

## Read-only diagnostic snapshot. No combat calculations are changed.
func _show_par_report() -> void:
	if combat_session == null or character == null or repository == null:
		return
	var registry := ParCalculationService.registry()
	var snapshot := ParCalculationService.calculate(character, repository)
	var totals: Dictionary = snapshot.get("totals", {})
	var fighter := combat_session.fighter(true)
	var combat_totals: Dictionary = fighter.combat_stats.get("par_totals", {})
	var ids := registry.keys()
	ids.sort()
	var lines: Array[String] = [
		"PAR / COMBAT DIAGNOSTIC",
		"Round: %d | Level: %d" % [combat_session.state.round_number, fighter.level],
		"Character PAR | Combat PAR | Status",
		"NOTE: Combat PAR is the snapshot captured when the arena opened.",
		"NOTE: NOT USED means no direct runtime field mapping; not a failure.",
		""
	]
	var mismatch_count := 0
	var missing_count := 0
	for raw_id in ids:
		var id := String(raw_id)
		var definition: Dictionary = registry[id]
		var name := String(definition.get("name_ru", definition.get("name", id)))
		var current := float(totals.get(id, 0.0))
		var has_combat := combat_totals.has(id)
		var combat_value := float(combat_totals.get(id, 0.0))
		var status := "OK" if has_combat and is_equal_approx(current, combat_value) else "MISMATCH"
		if not has_combat:
			status = "MISSING"
			missing_count += 1
		elif status == "MISMATCH":
			mismatch_count += 1
		var source_key := String(definition.get("source_key", ""))
		var runtime := ""
		if not source_key.is_empty() and fighter.combat_stats.has(source_key):
			runtime = " | runtime %s=%s" % [source_key, str(fighter.combat_stats[source_key])]
		lines.append("%s %s | %s | %s | %s%s" % [id, name, str(current), str(combat_value) if has_combat else "-", status, runtime])
	lines.append("")
	lines.append("Total: %d | Mismatch: %d | Missing: %d" % [ids.size(), mismatch_count, missing_count])
	lines.append("Combat contract: " + JSON.stringify(ParCombatContract.validate(fighter)))
	par_report_text.text = "\n".join(lines)
	par_report_dialog.popup_centered()

## Development-only dialog. Never acts on the persistent Arena session.
func _open_abi_test_lab() -> void:
	if abi_lab_dialog != null:
		abi_lab_dialog.open_lab()
