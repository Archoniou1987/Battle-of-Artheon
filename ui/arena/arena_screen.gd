class_name ArenaScreen
extends Control

## Arena UI foundation. Combat commands are deliberately not simulated here.
signal back_requested

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
var defense_zone := "chest"
var defense_capacity := 1
var defense_start := 1
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
var selected_ability := ""
var player_slots: Dictionary = {}
var enemy_slots: Dictionary = {}
var hp_label: Label
var tabs: TabContainer
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
const RATING_KEYS := ["crit_chance_rating", "anti_crit_rating", "dodge_rating", "anti_dodge_rating", "hit_chance_rating", "manual_block_rating", "shield_auto_block_rating", "block_penetration_rating", "armour_penetration_rating", "counterattack_rating"]
const RATING_NAMES := {"crit_chance_rating":"Крит", "anti_crit_rating":"Антикрит", "dodge_rating":"Уворот", "anti_dodge_rating":"Антиуворот", "hit_chance_rating":"Точность", "manual_block_rating":"Ручной блок", "shield_auto_block_rating":"Автоблок", "block_penetration_rating":"Пробивание блока", "armour_penetration_rating":"Пробивание брони", "counterattack_rating":"Контрудар"}
const PRIMARY_NAMES := {"STR":"Сила", "DEX":"Ловкость", "INTU":"Интуиция", "WIS":"Мудрость", "INT":"Интеллект", "END":"Выносливость"}

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
	var header := HBoxContainer.new()
	log_column.add_child(header)
	var back := Button.new()
	back.text = "← Назад"
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
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
	abilities.position = Vector2(144, 389)
	abilities.add_theme_constant_override("separation", 4)
	square_content.add_child(abilities)
	for index in range(5):
		var button := Button.new()
		button.custom_minimum_size = Vector2(34, 34)
		button.text = ""
		var abi_style := StyleBoxTexture.new()
		abi_style.texture = ItemIcon.empty_slot_texture("abi")
		if abi_style.texture != null:
			for state in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(state, abi_style)
		button.tooltip_text = "Активная способность %d" % (index + 1)
		button.toggle_mode = true
		button.disabled = true # UI only until CombatCommandApi integration.
		abilities.add_child(button)
	_build_resource_display(true)
	_build_resource_display(false)
	round_button = Button.new()
	round_button.text = "ПРОВЕСТИ РАУНД"
	round_button.position = Vector2(90, 426)
	round_button.custom_minimum_size = Vector2(300, 42)
	round_button.disabled = true # No fake rounds: wait for CombatCommandApi integration.
	round_button.tooltip_text = "Подключение CombatCommandApi — следующий этап"
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
	name_label.position = Vector2(35, -5)
	name_label.add_theme_font_size_override("font_size", 12)
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
		elixir_button.disabled = true # UI only; no consumption or round action yet.
		var elixir_style := StyleBoxTexture.new()
		elixir_style.texture = ItemIcon.empty_slot_texture("elixir")
		if elixir_style.texture != null:
			for state in ["normal", "hover", "pressed", "disabled"]:
				elixir_button.add_theme_stylebox_override(state, elixir_style)
		elixir_row.add_child(elixir_button)
		if is_player:
			player_elixir_slots.append(elixir_button)
		else:
			enemy_elixir_slots.append(elixir_button)
	_update_elixir_slots()
	var zone_row := HBoxContainer.new()
	zone_row.position = Vector2(6, 333)
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
		button.tooltip_text = ZONE_NAMES[index]
		button.custom_minimum_size = Vector2(42, 44)
		button.toggle_mode = true
		button.button_pressed = is_player and zone == "chest"
		button.pressed.connect(_select_zone.bind(is_player, zone))
		zone_row.add_child(button)
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
		row.visible = true # Temporary debug markers for layout review
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(row)
		for i in range(5):
			var effect_icon := ColorRect.new()
			effect_icon.custom_minimum_size = Vector2(19, 19)
			effect_icon.color = Color(0.18, 0.43, 0.65, 0.55) if row_type == "Баффы" else Color(0.65, 0.24, 0.28, 0.55)
			effect_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _show_equipment_details(is_player: bool, slot: String) -> void:
	var item: Dictionary = {}
	if is_player:
		if character != null and repository != null:
			var instance_id: Variant = character.equipment.get_equipped_instance_id(slot)
			if instance_id != null:
				item = repository.get_item(String(instance_id))
	else:
		item = disclosed_enemy_equipment.get(slot, {})
	if item.is_empty():
		item_popup.title = "Слот экипировки"
		item_popup_text.text = "Нет доступной информации о предмете."
	else:
		item_popup.title = String(item.get("name", "Предмет"))
		var lines: PackedStringArray = []
		lines.append("[b]%s[/b]" % String(item.get("name", "Предмет")))
		for field in ["type", "rarity", "item_level", "description"]:
			if item.has(field):
				lines.append("%s: %s" % [field, str(item[field])])
		for field in ["guaranteed_stats", "bonuses", "requirements"]:
			var values: Variant = item.get(field, {})
			if values is Dictionary and not values.is_empty():
				lines.append("")
				lines.append("[b]%s[/b]" % field)
				for key in values:
					lines.append("%s: %s" % [str(key), str(values[key])])
		item_popup_text.text = "\n".join(lines)
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
	if primary.is_empty() and ratings.is_empty():
		lines.append("Нет доступных характеристик")
	fighter_popup_text.text = "\n".join(lines)
	fighter_popup.popup_centered()

func _select_zone(is_player: bool, zone: String) -> void:
	var index := ZONES.find(zone)
	if is_player:
		defense_start = mini(index, ZONES.size() - defense_capacity)
		defense_zone = ZONES[defense_start]
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
	defense_capacity = clampi(capacity, 1, 3)
	defense_start = mini(defense_start, ZONES.size() - defense_capacity)
	_update_zone_buttons()

func set_attack_count(count: int) -> void:
	attack_count = maxi(1, count)
	while attack_zones.size() > attack_count:
		attack_zones.pop_back()
	_update_zone_buttons()

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
	for i in range(defense_start, defense_start + defense_capacity):
		result.append(ZONES[i])
	return result

func _update_zone_buttons() -> void:
	for i in range(defense_buttons.size()):
		defense_buttons[i].set_pressed_no_signal(i >= defense_start and i < defense_start + defense_capacity)
	for i in range(attack_buttons.size()):
		attack_buttons[i].set_pressed_no_signal(attack_zones.has(ZONES[i]))

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
	if character != null and repository != null and hp_label != null:
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
	var logical_size := Vector2(ARENA_LOGICAL_EXTENT, ARENA_LOGICAL_EXTENT)
	square_host.custom_minimum_size = Vector2(edge, edge)
	square_host.size = Vector2(edge, edge)
	square_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	square_host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	square_content.position = Vector2.ZERO
	square_content.size = logical_size
	square_content.scale = Vector2.ONE * (edge / ARENA_LOGICAL_EXTENT)
	if arena_background != null:
		arena_background.size = logical_size
