class_name SoloCombatScreen
extends Control

## Presentation only. Never creates CombatState, resolves combat or writes saves.
## The parent is responsible for authoritative preflight and checkpointed play_round().
signal round_requested(orders: Dictionary)
signal elixir_selected(slot: int)

const ZONES := ["head", "chest", "arms", "waist", "legs"]
const ZONE_NAMES := ["Голова", "Грудь", "Руки", "Пояс", "Ноги"]
const EQUIPMENT := ["head", "chest", "hands", "waist", "legs", "main_hand", "off_hand", "ring1", "ring2", "feet"]

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
var square_host: Control
var square_content: Control
var shared_arena: ArenaScreen
var roster_allies: VBoxContainer
var roster_enemies: VBoxContainer
var roster_page: HBoxContainer
var tab_container: TabContainer
var log_view: RichTextLabel
var round_button: Button
var round_label: Label
var instruction_label: Label
var detail_popup: AcceptDialog
var detail_text: Label

const SQUARE_EDGE := 480.0

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
	title.text = "BATTLE OF ARTHEON  •  БОЙ"
	title.add_theme_color_override("font_color", Color("#ead9b9"))
	title.add_theme_font_size_override("font_size", 19)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	round_label = Label.new()
	round_label.text = "Раунд —"
	title_row.add_child(round_label)

	# The battle tab always holds ONE 1:1 Face to Face arena. A group roster
	# never causes additional fighter cards to appear in the main arena.
	arena_layout = BoxContainer.new()
	arena_layout.name = "BattleLayout"
	arena_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_layout.add_theme_constant_override("separation", 6)
	shell.add_child(arena_layout)
	square_host = Control.new()
	square_host.name = "FaceToFaceSquare"
	square_host.clip_contents = true
	arena_layout.add_child(square_host)
	square_content = Control.new()
	square_content.name = "FaceToFaceContent"
	square_content.size = Vector2.ONE * SQUARE_EDGE
	square_host.add_child(square_content)
	# Reuse the actual Arena UI. The expedition owns the engine, not this view.
	shared_arena = ArenaScreen.new()
	shared_arena.name = "SharedArenaUI"
	shared_arena.external_combat_mode = true
	shared_arena.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shared_arena.size = Vector2.ONE * SQUARE_EDGE
	square_content.add_child(shared_arena)
	shared_arena.end_turn_requested.connect(func(_attacks: Array[String], _blocks: Array[String]) -> void: _submit())
	shared_arena.live_ability_selected.connect(_choose_ability)
	shared_arena.live_elixir_selected.connect(_choose_elixir)
	shared_arena.live_selection_changed.connect(_on_shared_selection)
	# Secondary information tabs are outside the immutable Arena square.
	tab_container = TabContainer.new()
	tab_container.name = "CombatTabs"
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_layout.add_child(tab_container)

	roster_page = HBoxContainer.new()
	roster_page.name = "Участники"
	roster_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_page.add_theme_constant_override("separation", 8)
	tab_container.add_child(roster_page)
	for is_ally in [true, false]:
		var side := ScrollContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.size_flags_vertical = Control.SIZE_EXPAND_FILL
		side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		roster_page.add_child(side)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 5)
		side.add_child(column)
		if is_ally:
			roster_allies = column
		else:
			roster_enemies = column

	var log_page := VBoxContainer.new()
	log_page.name = "Журнал"
	log_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(log_page)
	log_view = RichTextLabel.new()
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 18)
	log_page.add_child(log_view)

	var footer := PanelContainer.new()
	_panel_style(footer)
	shell.add_child(footer)
	var footer_row := HBoxContainer.new()
	footer.add_child(footer_row)
	instruction_label = Label.new()
	instruction_label.text = "Выберите действие"
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction_label.add_theme_font_size_override("font_size", 17)
	footer_row.add_child(instruction_label)
	round_button = Button.new()
	round_button.name = "EndRound"
	round_button.custom_minimum_size = Vector2(238, 82)
	round_button.text = "ЗАВЕРШИТЬ РАУНД"
	round_button.disabled = true
	round_button.add_theme_font_size_override("font_size", 18)
	round_button.pressed.connect(_submit)
	footer_row.add_child(round_button)
	footer.visible = false # Arena owns the sole visible End Round button.

	detail_popup = AcceptDialog.new()
	detail_popup.title = "Информация"
	detail_popup.min_size = Vector2i(300, 180)
	add_child(detail_popup)
	detail_text = Label.new()
	detail_text.custom_minimum_size = Vector2(280, 110)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_popup.add_child(detail_text)
	resized.connect(_apply_orientation)
	arena_layout.resized.connect(_apply_orientation)
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
	if arena_layout == null or square_host == null:
		return
	var portrait := size.y >= size.x
	arena_layout.vertical = portrait
	# Retain the same 480x480 logical composition, with one uniform scale.
	# On landscape the participants and journal tabs sit beside the square.
	# Reserve the information zone FIRST, then scale the original 480x480
	# Arena once within the actual remaining BattleLayout bounds (not full screen).
	# The native Arena square itself never scales or rearranges its children.
	var info_min := Vector2(0, 190) if portrait else Vector2(330, 0)
	if tab_container.custom_minimum_size != info_min:
		tab_container.custom_minimum_size = info_min
	var room: Vector2 = arena_layout.size
	var gap := float(arena_layout.get_theme_constant("separation"))
	var available_width := room.x - (info_min.x + gap if not portrait else 0.0)
	var available_height := room.y - (info_min.y + gap if portrait else 0.0)
	var edge := floorf(maxf(1.0, minf(SQUARE_EDGE, minf(available_width, available_height))))
	SquareUiGeometry.fit(square_host, square_content, edge, SQUARE_EDGE)

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
	# Shared Arena is persistent; never delete its square during snapshots.
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
	_build_face_to_face()
	_build_roster()
	# No duplicate command widgets: all five zones, ABI and elixirs live in Arena.
	_build_log()
	_apply_orientation()
	_update_selection()

func _build_face_to_face() -> void:
	shared_arena.present_external(snapshot)

func _build_roster() -> void:
	for column in [roster_allies, roster_enemies]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var hero: Dictionary = snapshot.get("player", {})
	var allies: Array = [hero]
	for member in Array(snapshot.get("allies", [])):
		if member is Dictionary and String(member.get("id", "")) != String(hero.get("id", "")):
			allies.append(member)
	var enemies: Array = snapshot.get("enemies", [])
	var title_left := Label.new()
	title_left.text = "СОЮЗНИКИ (%d)" % allies.size()
	title_left.add_theme_font_size_override("font_size", 18)
	roster_allies.add_child(title_left)
	var title_right := Label.new()
	title_right.text = "ПРОТИВНИКИ (%d)" % enemies.size()
	title_right.add_theme_font_size_override("font_size", 18)
	roster_enemies.add_child(title_right)
	var controls: Dictionary = snapshot.get("controls", {})
	var target := String(controls.get("target_id", ""))
	for raw in allies:
		if raw is Dictionary:
			roster_allies.add_child(_roster_card(raw, false))
	for raw in enemies:
		if raw is Dictionary:
			roster_enemies.add_child(_roster_card(raw, String(raw.get("id", "")) == target))

func _roster_card(actor: Dictionary, targeted: bool) -> Control:
	var panel := PanelContainer.new()
	_panel_style(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)
	var name := Button.new()
	var actor_name := String(actor.get("name", "?"))
	name.text = actor_name + ("  ◀" if targeted else "")
	name.clip_text = true
	name.tooltip_text = actor_name + " • Просмотр участника, без смены цели"
	name.add_theme_font_size_override("font_size", 16)
	name.pressed.connect(_show_item.bind("%s\nHP %d/%d • MP %d/%d" % [
		actor_name, int(actor.get("hp", 0)), int(actor.get("max_hp", 1)),
		int(actor.get("mana", 0)), int(actor.get("max_mana", 0))
	]))
	stack.add_child(name)
	_add_bar(stack, int(actor.get("hp", 0)), int(actor.get("max_hp", 1)), Color("#b63b48"), "HP")
	var effects: Array = actor.get("effects", [])
	if not effects.is_empty():
		var label := Label.new()
		label.text = "Эффекты: %d" % effects.size()
		label.add_theme_font_size_override("font_size", 13)
		stack.add_child(label)
	return panel

func _build_log() -> void:
	var lines: PackedStringArray = []
	for line in Array(snapshot.get("last_round_log", [])):
		lines.append(String(line))
	log_view.text = "\n".join(lines) if not lines.is_empty() else "Боевые события появятся после первого раунда."

func _add_bar(parent: Control, current: int, maximum: int, fill: Color, resource_name: String) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 27)
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
	numbers.add_theme_font_size_override("font_size", 16)
	numbers.text = "%d / %d %s" % [current, maximum, resource_name]
	numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(numbers)

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
	if shared_arena != null:
		for index in range(shared_arena.ability_buttons.size()):
			var option: Dictionary = abi_slots[index] if index < abi_slots.size() else {}
			shared_arena.ability_buttons[index].disabled = not bool(option.get("available", false))
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
	if shared_arena != null:
		chosen_attack = shared_arena.attack_zones.duplicate()
		chosen_blocks = shared_arena.defense_zones.duplicate()
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
	if shared_arena != null:
		shared_arena.set_combat_ready(not round_button.disabled)

func _on_shared_selection() -> void:
	_update_selection()

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
	shared_arena.set_combat_ready(false)
	round_requested.emit(orders)

func show_problem(message: String) -> void:
	instruction_label.text = message
	round_button.disabled = true
	if shared_arena != null:
		shared_arena.set_combat_ready(false)

func _show_item(description: String) -> void:
	detail_text.text = description
	detail_popup.popup_centered()
