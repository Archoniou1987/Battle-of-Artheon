class_name ArenaScreen
extends Control

## Arena UI foundation. Combat commands are deliberately not simulated here.
signal back_requested

const SLOTS_LEFT := ["head", "shoulders", "chest", "main_hand", "waist", "legs", "feet"]
const SLOTS_RIGHT := ["neck", "back", "wrists", "hands", "off_hand", "ring1", "ring2"]
const ZONES := ["head", "chest", "arms", "waist", "legs"]
const ZONE_NAMES := ["Голова", "Корпус", "Руки", "Пояс", "Ноги"]
const ZONE_ICONS := ["◎", "▣", "✋", "◇", "♧"]
const SLOT_SYMBOLS := {"head":"♙", "shoulders":"♜", "neck":"◉", "back":"▤", "chest":"▣", "wrists":"▥", "hands":"✋", "waist":"▰", "legs":"♧", "feet":"♧", "main_hand":"⚔", "off_hand":"⬟", "ring1":"◯", "ring2":"◯"}
const AVATAR_PATH := "res://assets/avatars/hero_realistic_01.png"

var character: CharacterState
var repository: ItemRepository
var layout: BoxContainer
var square_host: Control
var square_content: Control
var log_view: RichTextLabel
var round_button: Button
var defense_zone := "chest"
var defense_capacity := 1
var defense_start := 1
var attack_zones: Array[String] = []
var attack_count := 2
var defense_buttons: Array[Button] = []
var attack_buttons: Array[Button] = []
var hp_bars: Dictionary = {}
var hp_overlays: Dictionary = {}
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
	_build_fighter(Vector2(4, 8), true)
	_build_fighter(Vector2(244, 8), false)
	var abilities := HBoxContainer.new()
	abilities.position = Vector2(10, 389)
	abilities.add_theme_constant_override("separation", 5)
	square_content.add_child(abilities)
	for index in range(8):
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 36)
		button.text = str(index + 1) if index < 5 else "🔒"
		button.tooltip_text = "Активная способность %d" % (index + 1) if index < 5 else "Резервный слот"
		button.toggle_mode = true
		button.disabled = true # Five agreed active slots; three reserved, no gameplay effect.
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
	panel.custom_minimum_size = Vector2(232, 352)
	square_content.add_child(panel)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(232, 328)
	panel.add_child(inner)
	var name_label := Label.new()
	name_label.text = "ИГРОК" if is_player else "ПРОТИВНИК"
	name_label.position = Vector2(65, 3)
	inner.add_child(name_label)
	var portrait := TextureRect.new()
	portrait.position = Vector2(48, 48)
	portrait.custom_minimum_size = Vector2(136, 140)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if is_player and ResourceLoader.exists(AVATAR_PATH):
		portrait.texture = load(AVATAR_PATH)
	inner.add_child(portrait)
	var inspect := Button.new()
	inspect.flat = true
	inspect.position = Vector2(40, 44)
	inspect.custom_minimum_size = Vector2(152, 145)
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
			icon.position = Vector2(2 if side == 0 else 190, 44 + index * 40)
			icon.custom_minimum_size = Vector2(30, 30)
			icon.scale = Vector2.ONE * 0.74
			inner.add_child(icon)
			if is_player:
				player_slots[slot] = icon
			else:
				enemy_slots[slot] = icon
			icon.set_item({}, String(SLOT_SYMBOLS.get(slot, "◇")))
			icon.pressed.connect(_show_equipment_details.bind(is_player, slot))
	var health_bar := ProgressBar.new()
	health_bar.position = Vector2(38, 23)
	health_bar.custom_minimum_size = Vector2(156, 15)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	health_bar.value = 100 if is_player else 0
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#35383e")
	bar_bg.border_color = Color("#b39a69")
	bar_bg.set_border_width_all(1)
	health_bar.add_theme_stylebox_override("background", bar_bg)
	inner.add_child(health_bar)
	var health := Label.new()
	health.position = Vector2(38, 22)
	health.custom_minimum_size = Vector2(156, 17)
	health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health.add_theme_font_size_override("font_size", 12)
	health.add_theme_color_override("font_color", Color.WHITE)
	health.text = "HP —" if is_player else "HP ? / ?"
	inner.add_child(health)
	hp_bars["player" if is_player else "enemy"] = health_bar
	hp_overlays["player" if is_player else "enemy"] = health
	if is_player:
		hp_label = health
	var elixir_row := HBoxContainer.new()
	elixir_row.position = Vector2(48, 285)
	elixir_row.add_theme_constant_override("separation", 4)
	inner.add_child(elixir_row)
	for elixir_index in range(4):
		var elixir_button := Button.new()
		elixir_button.custom_minimum_size = Vector2(31, 32)
		elixir_button.add_theme_font_size_override("font_size", 10)
		elixir_button.disabled = true # UI only; no consumption or round action yet.
		elixir_row.add_child(elixir_button)
		if is_player:
			player_elixir_slots.append(elixir_button)
		else:
			enemy_elixir_slots.append(elixir_button)
	_update_elixir_slots()
	var zone_row := HBoxContainer.new()
	zone_row.position = Vector2(3, 330)
	zone_row.add_theme_constant_override("separation", 1)
	inner.add_child(zone_row)
	for index in range(ZONES.size()):
		var zone: String = ZONES[index]
		var button := Button.new()
		button.text = ZONE_ICONS[index]
		button.add_theme_font_size_override("font_size", 21)
		button.tooltip_text = ZONE_NAMES[index]
		button.custom_minimum_size = Vector2(44, 34)
		button.toggle_mode = true
		button.button_pressed = is_player and zone == "chest"
		button.pressed.connect(_select_zone.bind(is_player, zone))
		zone_row.add_child(button)
		if is_player:
			defense_buttons.append(button)
		else:
			attack_buttons.append(button)
	for row_type in ["Баффы", "Дебаффы"]:
		var row := HBoxContainer.new()
		row.position = Vector2(49, 146 if row_type == "Баффы" else 168)
		row.add_theme_constant_override("separation", 1)
		inner.add_child(row)
		var label := Label.new()
		label.text = "↑" if row_type == "Баффы" else "↓"
		label.custom_minimum_size.x = 13
		row.add_child(label)
		for i in range(5):
			var icon := PanelContainer.new()
			icon.custom_minimum_size = Vector2(19, 19)
			icon.tooltip_text = "Нет эффекта"
			row.add_child(icon)
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
		(enemy_slots[slot] as ItemIcon).set_item(item, String(SLOT_SYMBOLS.get(slot, "◇")) if not item.is_empty() else "?")

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
				button.text = "🔒"
				button.tooltip_text = "Слот эликсира недоступен — нужен пояс"
				continue
			if index >= entries.size() or entries[index].is_empty():
				button.text = "♧"
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
	overlay.text = "HP %d / %d" % [current, maximum]
	var fraction := float(current) / float(maxi(1, maximum))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e34b4b") if fraction <= 0.20 else (Color("#e3bf42") if fraction <= 0.50 else Color("#35bd61"))
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)

func refresh() -> void:
	for slot in player_slots:
		var icon := player_slots[slot] as ItemIcon
		var instance_id: Variant = character.equipment.get_equipped_instance_id(slot) if character != null else null
		var item: Dictionary = repository.get_item(String(instance_id)) if instance_id != null and repository != null else {}
		icon.set_item(item, String(SLOT_SYMBOLS.get(slot, "◇")), instance_id != null)
	for slot in enemy_slots:
		var icon := enemy_slots[slot] as ItemIcon
		var disclosed: Dictionary = disclosed_enemy_equipment.get(slot, {})
		icon.set_item(disclosed, String(SLOT_SYMBOLS.get(slot, "◇")) if not disclosed.is_empty() else "?")
	if character != null and repository != null and hp_label != null:
		var snapshot := CharacterCombatBuilder.build(character, repository)
		_update_hp(hp_bars["player"], hp_label, snapshot.hp, snapshot.max_hp)

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
