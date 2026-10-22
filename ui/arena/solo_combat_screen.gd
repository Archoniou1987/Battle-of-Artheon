class_name SoloCombatScreen
extends Control

## Presentation only. Never creates CombatState, resolves combat or writes saves.
## The parent is responsible for authoritative preflight and checkpointed play_round().
signal round_requested(orders: Dictionary)
signal elixir_selected(slot: int)

const ZONES := ["head", "chest", "arms", "waist", "legs"]
const ZONE_NAMES := ["Голова", "Грудь", "Руки", "Пояс", "Ноги"]
const EQUIPMENT := ["head", "chest", "hands", "waist", "legs", "main_hand", "off_hand", "ring1", "ring2", "feet"]
const ZONE_ATLAS := "res://assets/ui/slots/BOA_COMBAT_ZONES_v2.png"
const HERO_AVATAR := "res://assets/avatars/hero_realistic_01.png"
const BACKGROUND := "res://assets/ui/arena/BOA_ARENA_BACKGROUND_V1.png"

var snapshot: Dictionary = {}
var chosen_attack: Array[String] = []
var chosen_blocks: Array[String] = []
var chosen_abi := ""
var chosen_elixir := -1
var abi_slots: Array = []
var abi_buttons: Array[Button] = []
var potion_buttons: Array[Button] = []
var attack_buttons: Array[Button] = []
var block_buttons: Array[Button] = []
var arena_layout: BoxContainer
var fighters_column: VBoxContainer
var actions_column: VBoxContainer
var scroll: ScrollContainer
var round_button: Button
var round_label: Label
var instruction_label: Label
var detail_popup: AcceptDialog
var detail_text: Label
var zone_atlas: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#142235")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shell := VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 5)
	add_child(shell)
	var top := PanelContainer.new()
	_panel_style(top)
	shell.add_child(top)
	var title_row := HBoxContainer.new()
	top.add_child(title_row)
	var title := Label.new()
	title.text = "BATTLE OF ARTHEON   •   БОЙ"
	title.add_theme_color_override("font_color", Color("#ead9b9"))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	round_label = Label.new()
	round_label.text = "Раунд —"
	title_row.add_child(round_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	arena_layout = BoxContainer.new()
	arena_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_layout.add_theme_constant_override("separation", 8)
	scroll.add_child(arena_layout)
	fighters_column = VBoxContainer.new()
	fighters_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fighters_column.add_theme_constant_override("separation", 6)
	arena_layout.add_child(fighters_column)
	actions_column = VBoxContainer.new()
	actions_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_column.add_theme_constant_override("separation", 6)
	arena_layout.add_child(actions_column)
	var footer := PanelContainer.new()
	_panel_style(footer)
	shell.add_child(footer)
	var footer_row := HBoxContainer.new()
	footer.add_child(footer_row)
	instruction_label = Label.new()
	instruction_label.text = "Выберите действие"
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction_label.add_theme_font_size_override("font_size", 11)
	footer_row.add_child(instruction_label)
	round_button = Button.new()
	round_button.name = "EndRound"
	round_button.custom_minimum_size = Vector2(142, 53)
	round_button.text = "ЗАВЕРШИТЬ РАУНД"
	round_button.disabled = true
	round_button.pressed.connect(_submit)
	footer_row.add_child(round_button)
	detail_popup = AcceptDialog.new()
	detail_popup.title = "Информация"
	detail_popup.min_size = Vector2i(300, 180)
	add_child(detail_popup)
	detail_text = Label.new()
	detail_text.custom_minimum_size = Vector2(280, 110)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_popup.add_child(detail_text)
	resized.connect(_apply_orientation)
	_apply_orientation()

func _panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1c2c40")
	style.border_color = Color("#59667a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

func _apply_orientation() -> void:
	if arena_layout == null:
		return
	arena_layout.vertical = size.y >= size.x
	fighters_column.custom_minimum_size.x = 0 if arena_layout.vertical else maxf(320.0, size.x * 0.52)
	actions_column.custom_minimum_size.x = 0 if arena_layout.vertical else maxf(300.0, size.x * 0.38)

func present(view: Dictionary) -> void:
	snapshot = view.duplicate(true)
	chosen_attack.clear()
	chosen_blocks.clear()
	chosen_abi = ""
	chosen_elixir = -1
	abi_slots = Array(snapshot.get("ability_slots", [])).duplicate(true)
	abi_buttons.clear()
	potion_buttons.clear()
	attack_buttons.clear()
	block_buttons.clear()
	for column in [fighters_column, actions_column]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var controls: Dictionary = snapshot.get("controls", {})
	if not bool(controls.get("stunned", false)):
		if int(controls.get("attack_count", 0)) > 0:
			chosen_attack.append("chest")
		var capacity := clampi(int(controls.get("block_capacity", 0)), 0, 5)
		for zone in ["chest", "arms", "waist", "legs", "head"]:
			if chosen_blocks.size() >= capacity:
				break
			chosen_blocks.append(zone)
	round_label.text = "Раунд %d" % (int(snapshot.get("round", 0)) + 1)
	var hero: Dictionary = snapshot.get("player", {})
	fighters_column.add_child(_fighter_card(hero, true, Array(snapshot.get("equipment_slots", []))))
	var enemies: Array = snapshot.get("enemies", [])
	var active_target := String(controls.get("target_id", ""))
	for raw_enemy in enemies:
		if raw_enemy is Dictionary:
			var enemy: Dictionary = raw_enemy
			fighters_column.add_child(_fighter_card(enemy, false, [], String(enemy.get("id", "")) == active_target))
	if enemies.is_empty():
		var none := Label.new()
		none.text = "Противники отсутствуют"
		fighters_column.add_child(none)
	_build_actions()
	_apply_orientation()
	_update_selection()
	if scroll != null:
		scroll.scroll_vertical = 0

func _fighter_card(fighter: Dictionary, hero: bool, equipment: Array, targeted: bool = false) -> Control:
	var panel := PanelContainer.new()
	_panel_style(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	var name := Label.new()
	var level := int(fighter.get("level", 0))
	name.text = "%s%s%s" % [String(fighter.get("name", "Герой" if hero else "NPC")), (" [%d]" % level if level > 0 else ""), ("  ◀ ЦЕЛЬ" if targeted else "")]
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", Color("#f0dcb6") if hero else Color("#e2b5a5"))
	column.add_child(name)
	_add_bar(column, int(fighter.get("hp", 0)), int(fighter.get("max_hp", 1)), Color("#b63b48"), "HP")
	if hero or int(fighter.get("max_mana", 0)) > 0:
		_add_bar(column, int(fighter.get("mana", 0)), int(fighter.get("max_mana", 0)), Color("#367eb6"), "MP")
	if fighter.has("max_ap"):
		var ap := Label.new()
		ap.text = "AP %d / %d" % [int(fighter.get("ap", 0)), int(fighter.get("max_ap", 0))]
		ap.add_theme_font_size_override("font_size", 11)
		column.add_child(ap)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)
	var avatar := Control.new()
	avatar.custom_minimum_size = Vector2(105, 130 if hero else 90)
	body.add_child(avatar)
	var portrait := TextureRect.new()
	portrait.position = Vector2.ZERO
	portrait.size = avatar.custom_minimum_size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if hero and ResourceLoader.exists(HERO_AVATAR):
		portrait.texture = load(HERO_AVATAR) as Texture2D
	elif ResourceLoader.exists(BACKGROUND):
		portrait.texture = load(BACKGROUND) as Texture2D
	avatar.add_child(portrait)
	if not hero:
		var unknown := Label.new()
		unknown.text = "?" if not bool(fighter.get("dead", false)) else "†"
		unknown.position = Vector2(42, 22)
		unknown.add_theme_font_size_override("font_size", 32)
		avatar.add_child(unknown)
	_add_effect_rows(avatar, Array(fighter.get("effects", [])))
	if hero:
		var gear := GridContainer.new()
		gear.columns = 5
		gear.add_theme_constant_override("h_separation", 3)
		gear.add_theme_constant_override("v_separation", 3)
		gear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(gear)
		var indexed: Dictionary = {}
		for raw_slot in equipment:
			if raw_slot is Dictionary:
				var equipped: Dictionary = raw_slot
				indexed[String(equipped.get("slot", ""))] = equipped
		for slot in EQUIPMENT:
			var entry: Dictionary = indexed.get(slot, {})
			var icon := ItemIcon.new()
			icon.custom_minimum_size = Vector2(34, 34)
			icon.set_empty_placeholder_icon_visible(false)
			gear.add_child(icon)
			var item: Dictionary = entry.get("item", {})
			icon.set_item(item, slot, not String(entry.get("instance_id", "")).is_empty())
			if not bool(entry.get("active", true)) and not item.is_empty():
				icon.modulate = Color("#a66f77")
			var item_name := String(entry.get("name", "Пусто"))
			icon.tooltip_text = SquareUiGeometry.equipment_name(slot) + ": " + (item_name if not item_name.is_empty() else "Пусто")
			icon.pressed.connect(_show_item.bind(icon.tooltip_text))
	else:
		var info := Label.new()
		info.text = "Выбрана движком" if targeted else "Участник группы"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 11)
		body.add_child(info)
	return panel

func _add_bar(parent: Control, current: int, maximum: int, fill: Color, resource_name: String) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 19)
	parent.add_child(holder)
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = maxi(1, maximum)
	bar.value = clampi(current, 0, maxi(1, maximum))
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	bar.add_theme_stylebox_override("fill", style)
	holder.add_child(bar)
	var numbers := Label.new()
	numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numbers.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	numbers.add_theme_font_size_override("font_size", 11)
	numbers.text = "%d / %d %s" % [current, maximum, resource_name]
	numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(numbers)

func _add_effect_rows(avatar: Control, effects: Array) -> void:
	for polarity in ["BUFF", "DEBUFF"]:
		var row := HBoxContainer.new()
		row.position = Vector2(2, avatar.custom_minimum_size.y - (39 if polarity == "BUFF" else 20))
		row.add_theme_constant_override("separation", 1)
		avatar.add_child(row)
		var matching: Array[Dictionary] = []
		for raw in effects:
			if raw is Dictionary and String(raw.get("polarity", "")).to_upper() == polarity:
				matching.append(raw)
		var shown := mini(5, matching.size())
		for index in range(shown):
			var button := Button.new()
			button.custom_minimum_size = Vector2(19, 19)
			button.add_theme_font_size_override("font_size", 9)
			var overflow := matching.size() > 5 and index == 4
			var detail := ""
			if overflow:
				button.text = "+%d" % (matching.size() - 4)
				for effect in matching:
					detail += "%s ×%d (%d р.)\n" % [String(effect.get("name", "?")), int(effect.get("stacks", 1)), int(effect.get("remaining_rounds", 0))]
			else:
				var effect: Dictionary = matching[index]
				button.text = "▲" if polarity == "BUFF" else "▼"
				detail = "%s ×%d (%d р.)" % [String(effect.get("name", "?")), int(effect.get("stacks", 1)), int(effect.get("remaining_rounds", 0))]
			_style_button(button, false, Color("#55bf73") if polarity == "BUFF" else Color("#d95757"))
			button.tooltip_text = detail
			row.add_child(button)
			button.pressed.connect(_show_item.bind(detail))

func _build_actions() -> void:
	_section("АТАКА • красные зоны")
	_zone_buttons(true)
	_section("ЗАЩИТА • синие зоны")
	_zone_buttons(false)
	_section("СПОСОБНОСТИ • 5 ABI")
	var abilities := HBoxContainer.new()
	abilities.add_theme_constant_override("separation", 5)
	actions_column.add_child(abilities)
	for index in range(5):
		var entry: Dictionary = abi_slots[index] if index < abi_slots.size() else {}
		var button := Button.new()
		button.custom_minimum_size = Vector2(49, 48)
		button.text = String(entry.get("id", "")) if not String(entry.get("id", "")).is_empty() else "—"
		button.add_theme_font_size_override("font_size", 9)
		button.tooltip_text = "%s • %s • %d MP" % [String(entry.get("id", "Пусто")), String(entry.get("name", "Нет ABI")), int(entry.get("mana_cost", 0))]
		button.pressed.connect(_choose_ability.bind(index))
		abilities.add_child(button)
		abi_buttons.append(button)
	_section("ЭЛИКСИРЫ • общий откат")
	var potions := HBoxContainer.new()
	potions.add_theme_constant_override("separation", 5)
	actions_column.add_child(potions)
	var loadout: Dictionary = snapshot.get("elixir_loadout", {})
	var potion_slots: Array = loadout.get("slots", [])
	for index in range(4):
		var entry: Dictionary = potion_slots[index] if index < potion_slots.size() else {}
		var button := Button.new()
		button.custom_minimum_size = Vector2(57, 47)
		var charges := int(entry.get("charges", 0))
		var maximum := int(entry.get("max_charges", 0))
		button.text = "%d/%d" % [charges, maximum] if not String(entry.get("instance_id", "")).is_empty() else "—"
		button.tooltip_text = "%s • %d/%d" % [String(entry.get("instance_id", "Пусто")), charges, maximum]
		button.pressed.connect(_choose_elixir.bind(index))
		potions.add_child(button)
		potion_buttons.append(button)
	var log_title := Label.new()
	log_title.text = "ЖУРНАЛ • последний раунд"
	log_title.add_theme_color_override("font_color", Color("#e2d0ab"))
	actions_column.add_child(log_title)
	var log := RichTextLabel.new()
	log.fit_content = true
	log.scroll_active = false
	log.custom_minimum_size.y = 90
	var lines: PackedStringArray = []
	for line in Array(snapshot.get("last_round_log", [])):
		lines.append(String(line))
	log.text = "\n".join(lines) if not lines.is_empty() else "Боевые события появятся после первого раунда."
	actions_column.add_child(log)

func _section(title: String) -> void:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", Color("#e4d6b9"))
	heading.add_theme_font_size_override("font_size", 12)
	actions_column.add_child(heading)

func _zone_buttons(attack: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	actions_column.add_child(row)
	for i in range(ZONES.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(53, 50)
		button.text = ZONE_NAMES[i].substr(0, 1)
		var zone_icon := _zone_texture(not attack, i)
		if zone_icon != null:
			button.icon = zone_icon
			button.text = ""
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.expand_icon = true
		button.tooltip_text = ZONE_NAMES[i]
		button.pressed.connect(_choose_zone.bind(attack, ZONES[i]))
		row.add_child(button)
		if attack:
			attack_buttons.append(button)
		else:
			block_buttons.append(button)

func _zone_texture(defense: bool, index: int) -> Texture2D:
	if zone_atlas == null and ResourceLoader.exists(ZONE_ATLAS):
		zone_atlas = load(ZONE_ATLAS) as Texture2D
	if zone_atlas == null:
		return null
	var width := float(zone_atlas.get_width()) / 5.0
	var height := float(zone_atlas.get_height()) / 2.0
	var cell := AtlasTexture.new()
	cell.atlas = zone_atlas
	cell.region = Rect2(float(index) * width, 0.0 if defense else height, width, height)
	cell.filter_clip = true
	return cell

func _choose_zone(attack: bool, zone: String) -> void:
	var chosen: Array[String] = chosen_attack if attack else chosen_blocks
	if attack:
		if chosen.has(zone):
			chosen.erase(zone)
		elif chosen.size() < 2:
			chosen.append(zone)
		else:
			chosen[chosen.size() - 1] = zone
	else:
		var controls: Dictionary = snapshot.get("controls", {})
		var limit := int(controls.get("block_capacity", 0))
		if chosen.has(zone):
			if chosen.size() > 1:
				chosen.erase(zone)
		elif chosen.size() < limit:
			chosen.append(zone)
		elif not chosen.is_empty():
			chosen.remove_at(0)
			chosen.append(zone)
	_update_selection()

func _choose_ability(index: int) -> void:
	if index >= abi_slots.size():
		return
	var slot: Dictionary = abi_slots[index]
	if not bool(slot.get("available", false)):
		return
	var id := String(slot.get("id", ""))
	chosen_abi = "" if chosen_abi == id else id
	_update_selection()

func _choose_elixir(index: int) -> void:
	var available: Array = snapshot.get("elixir_availability", [])
	if index >= available.size() or not bool(available[index]):
		return
	chosen_elixir = -1 if chosen_elixir == index else index
	elixir_selected.emit(chosen_elixir)
	_update_selection()

## Authoritative availability is projected by GroupCombatSimulator.player_controls.
## In particular a mana potion can enable an otherwise unaffordable ABI.
func set_ability_options(options: Array) -> void:
	var indexed: Dictionary = {}
	for raw in options:
		if raw is Dictionary:
			indexed[String(raw.get("id", ""))] = raw
	for i in range(abi_slots.size()):
		var slot: Dictionary = abi_slots[i]
		var id := String(slot.get("id", ""))
		slot["available"] = not id.is_empty() and indexed.has(id) and bool(Dictionary(indexed.get(id, {})).get("available", false))
		abi_slots[i] = slot
	if not chosen_abi.is_empty():
		var remains := false
		for raw_slot in abi_slots:
			var slot: Dictionary = raw_slot
			if String(slot.get("id", "")) == chosen_abi and bool(slot.get("available", false)):
				remains = true
		if not remains:
			chosen_abi = ""
	_update_selection()

func _style_button(button: Button, selected: bool, accent: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#24354a") if selected else Color("#17283c")
	style.border_color = accent if selected else Color("#59677b")
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(5)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("#f0e2c8"))

func _update_selection() -> void:
	if round_button == null:
		return
	var controls: Dictionary = snapshot.get("controls", {})
	var finished := bool(snapshot.get("finished", false))
	var stunned := bool(controls.get("stunned", false))
	for index in range(attack_buttons.size()):
		_style_button(attack_buttons[index], chosen_attack.has(ZONES[index]), Color("#d95757"))
		attack_buttons[index].disabled = stunned or finished
	for index in range(block_buttons.size()):
		_style_button(block_buttons[index], chosen_blocks.has(ZONES[index]), Color("#468cce"))
		block_buttons[index].disabled = stunned or finished or int(controls.get("block_capacity", 0)) == 0
	for index in range(abi_buttons.size()):
		var slot: Dictionary = abi_slots[index] if index < abi_slots.size() else {}
		abi_buttons[index].disabled = finished or not bool(slot.get("available", false))
		_style_button(abi_buttons[index], not chosen_abi.is_empty() and chosen_abi == String(slot.get("id", "")), Color("#ac8edb"))
	for index in range(potion_buttons.size()):
		var availability: Array = snapshot.get("elixir_availability", [])
		potion_buttons[index].disabled = finished or index >= availability.size() or not bool(availability[index])
		_style_button(potion_buttons[index], chosen_elixir == index, Color("#66ab8b"))
	var count := int(controls.get("attack_count", 0))
	var block_count := int(controls.get("block_capacity", 0))
	var valid := bool(controls.get("ok", false)) and (stunned or (not chosen_attack.is_empty() and count > 0 and chosen_blocks.size() == block_count))
	if finished:
		round_button.text = "ПОДТВЕРДИТЬ ИТОГ"
		instruction_label.text = "Исход сохранён в боевом checkpoint"
		round_button.disabled = false
	elif stunned:
		round_button.text = "ПРОПУСТИТЬ РАУНД"
		instruction_label.text = "Оглушение: действия недоступны"
		round_button.disabled = not valid
	else:
		round_button.text = "ЗАВЕРШИТЬ РАУНД"
		instruction_label.text = "%d удар(ов), %d блок(ов)" % [count, block_count] if valid else "Выберите зоны атаки и защиты"
		round_button.disabled = not valid

func _submit() -> void:
	if round_button.disabled:
		return
	if bool(snapshot.get("finished", false)):
		round_requested.emit({})
		return
	var controls: Dictionary = snapshot.get("controls", {})
	var orders: Dictionary = {
		"player_id": String(Dictionary(snapshot.get("player", {})).get("id", "")),
		"attack_zones": [],
		"block_zones": [],
		"ability_id": chosen_abi,
		"elixir_slot": chosen_elixir
	}
	if not bool(controls.get("stunned", false)):
		var attacks: Array[String] = []
		for i in range(int(controls.get("attack_count", 0))):
			attacks.append(chosen_attack[mini(i, chosen_attack.size() - 1)])
		orders["attack_zones"] = attacks
		orders["block_zones"] = chosen_blocks.duplicate()
	round_button.disabled = true
	round_requested.emit(orders)

func show_problem(message: String) -> void:
	instruction_label.text = message
	round_button.disabled = true

func _show_item(description: String) -> void:
	detail_text.text = description
	detail_popup.popup_centered()
