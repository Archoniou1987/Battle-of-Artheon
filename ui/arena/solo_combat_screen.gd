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
const NPC_PLACEHOLDER_AVATAR := "res://assets/avatars/wanderer_01.svg"
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
var square_host: Control
var square_content: Control
var roster_allies: VBoxContainer
var roster_enemies: VBoxContainer
var roster_page: HBoxContainer
var tab_container: TabContainer
var log_view: RichTextLabel
var actions_column: VBoxContainer
var scroll: ScrollContainer
var round_button: Button
var round_label: Label
var instruction_label: Label
var detail_popup: AcceptDialog
var detail_text: Label
var zone_atlas: Texture2D

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
	tab_container = TabContainer.new()
	tab_container.name = "CombatTabs"
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(tab_container)
	arena_layout = BoxContainer.new()
	arena_layout.name = "Поединок"
	arena_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_layout.add_theme_constant_override("separation", 6)
	tab_container.add_child(arena_layout)
	square_host = Control.new()
	square_host.name = "FaceToFaceSquare"
	square_host.clip_contents = true
	arena_layout.add_child(square_host)
	square_content = Control.new()
	square_content.name = "FaceToFaceContent"
	square_content.size = Vector2.ONE * SQUARE_EDGE
	square_host.add_child(square_content)
	# Actions are scrollable but the square remains visible as one entity.
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	arena_layout.add_child(scroll)
	actions_column = VBoxContainer.new()
	actions_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_column.add_theme_constant_override("separation", 7)
	scroll.add_child(actions_column)

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

	detail_popup = AcceptDialog.new()
	detail_popup.title = "Информация"
	detail_popup.min_size = Vector2i(300, 180)
	add_child(detail_popup)
	detail_text = Label.new()
	detail_text.custom_minimum_size = Vector2(280, 110)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_popup.add_child(detail_text)
	resized.connect(_apply_orientation)
	tab_container.resized.connect(_apply_orientation)
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
	# On landscape a separate scrollable command column sits alongside it.
	var room: Vector2 = tab_container.size
	var edge: float = minf(room.x - (0.0 if portrait else 340.0), maxf(1.0, room.y - 36.0) * (0.66 if portrait else 1.0))
	edge = floorf(maxf(1.0, edge))
	if portrait:
		edge = minf(edge, room.x - 4.0)
	SquareUiGeometry.fit(square_host, square_content, edge, SQUARE_EDGE)
	# The scroll pane fills the remaining area; no long group roster in combat.
	scroll.custom_minimum_size = Vector2.ZERO
	if not portrait:
		scroll.custom_minimum_size.x = 330.0

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
	for child in actions_column.get_children():
		actions_column.remove_child(child)
		child.queue_free()
	for child in square_content.get_children():
		square_content.remove_child(child)
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
	_build_face_to_face()
	_build_roster()
	_build_actions()
	_build_log()
	_apply_orientation()
	_update_selection()
	if scroll != null:
		scroll.scroll_vertical = 0

func _build_face_to_face() -> void:
	var background := TextureRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2.ONE * SQUARE_EDGE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BACKGROUND):
		background.texture = load(BACKGROUND) as Texture2D
	square_content.add_child(background)
	var hero: Dictionary = snapshot.get("player", {})
	var enemies: Array = snapshot.get("enemies", [])
	var controls: Dictionary = snapshot.get("controls", {})
	var active_id := String(controls.get("target_id", ""))
	var enemy: Dictionary = {}
	for raw_enemy in enemies:
		if raw_enemy is Dictionary and String(raw_enemy.get("id", "")) == active_id:
			enemy = raw_enemy
			break
	if enemy.is_empty():
		for raw_enemy in enemies:
			if raw_enemy is Dictionary and not bool(raw_enemy.get("dead", false)):
				enemy = raw_enemy
				break
	if enemy.is_empty() and not enemies.is_empty() and enemies[0] is Dictionary:
		enemy = enemies[0]
	_build_face_actor(Vector2(4, 8), hero, true, Array(snapshot.get("equipment_slots", [])))
	_build_face_actor(Vector2(244, 8), enemy, false, [])
	var separator := Label.new()
	separator.text = "VS"
	separator.position = Vector2(224, 164)
	separator.add_theme_font_size_override("font_size", 16)
	separator.add_theme_color_override("font_color", Color("#ebc58b"))
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square_content.add_child(separator)
	var commands := Label.new()
	commands.name = "PreparedActions"
	commands.position = Vector2(14, 346)
	commands.size = Vector2(452, 36)
	commands.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commands.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	commands.add_theme_font_size_override("font_size", 14)
	commands.add_theme_color_override("font_color", Color("#ecd5b0"))
	square_content.add_child(commands)
	# These strips echo Arena's slots without duplicating command handlers.
	# The larger actual touch controls live in the action column.
	var abi_caption := Label.new()
	abi_caption.text = "ABI  1     2     3     4     5"
	abi_caption.position = Vector2(135, 395)
	abi_caption.size = Vector2(210, 25)
	abi_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abi_caption.add_theme_font_size_override("font_size", 14)
	square_content.add_child(abi_caption)
	var status := Label.new()
	status.text = "ДЕЙСТВИЯ — справа или ниже"
	status.position = Vector2(90, 433)
	status.size = Vector2(300, 28)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Color("#b5c1d0"))
	square_content.add_child(status)

## 232 logical px per fighter. Only the selected NPC appears opposite
## the hero; all other participants live in the separate roster tab.
func _build_face_actor(origin: Vector2, actor: Dictionary, hero: bool, equipment: Array) -> void:
	var panel := Panel.new()
	panel.position = origin
	panel.size = Vector2(232, 331)
	var border := StyleBoxFlat.new()
	border.bg_color = Color("#19283b", 0.76)
	border.border_color = Color("#5d7691") if hero else Color("#895e65")
	border.set_border_width_all(1)
	border.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", border)
	square_content.add_child(panel)
	var actor_name := String(actor.get("name", "Герой" if hero else "Нет цели"))
	var level := int(actor.get("level", 0))
	var label := Label.new()
	label.position = Vector2(6, 5)
	label.size = Vector2(220, 21)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.text = "%s%s" % [actor_name, " [%d]" % level if level > 0 else ""]
	label.clip_text = true
	label.tooltip_text = actor_name
	panel.add_child(label)
	_face_bar(panel, 8, 28, int(actor.get("hp", 0)), int(actor.get("max_hp", 1)), "#bc4350", "HP")
	_face_bar(panel, 8, 48, int(actor.get("mana", 0)), int(actor.get("max_mana", 0)), "#367eb6", "MP")
	var ap := Label.new()
	ap.position = Vector2(12, 69)
	ap.size = Vector2(210, 18)
	ap.add_theme_font_size_override("font_size", 11)
	ap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if actor.has("max_ap"):
		ap.text = "AP  %d / %d" % [int(actor.get("ap", 0)), int(actor.get("max_ap", 0))]
	elif bool(actor.get("dead", false)):
		ap.text = "ПОБЕЖДЁН"
	else:
		ap.text = " " if hero else "ПРОТИВНИК"
	panel.add_child(ap)
	var avatar := Control.new()
	avatar.position = Vector2(46, 92)
	avatar.custom_minimum_size = Vector2(140, 217)
	panel.add_child(avatar)
	var art := TextureRect.new()
	art.size = Vector2(140, 217)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hero and ResourceLoader.exists(HERO_AVATAR):
		art.texture = load(HERO_AVATAR) as Texture2D
	elif not hero and ResourceLoader.exists(NPC_PLACEHOLDER_AVATAR):
		# Shared anonymous NPC artwork, not an assertion of NPC identity.
		art.texture = load(NPC_PLACEHOLDER_AVATAR) as Texture2D
		art.modulate = Color("#a8a4a7")
	avatar.add_child(art)
	if not hero and (art.texture == null or bool(actor.get("dead", false))):
		var silhouette := Label.new()
		silhouette.text = "†" if bool(actor.get("dead", false)) else "?"
		silhouette.position = Vector2(53, 65)
		silhouette.add_theme_font_size_override("font_size", 36)
		avatar.add_child(silhouette)
	_add_effect_rows(avatar, Array(actor.get("effects", [])))
	if hero:
		var indexed: Dictionary = {}
		for raw in equipment:
			if raw is Dictionary:
				indexed[String(raw.get("slot", ""))] = raw
		for index in range(EQUIPMENT.size()):
			var slot := String(EQUIPMENT[index])
			var entry: Dictionary = indexed.get(slot, {})
			var icon := ItemIcon.new()
			icon.position = Vector2(6 if index < 5 else 195, 97 + (index % 5) * 40)
			icon.custom_minimum_size = Vector2(34, 34)
			icon.set_empty_placeholder_icon_visible(false)
			panel.add_child(icon)
			var item: Dictionary = entry.get("item", {})
			icon.call_deferred("set_item", item.duplicate(true), slot, not String(entry.get("instance_id", "")).is_empty())
			if not bool(entry.get("active", true)) and not item.is_empty():
				icon.modulate = Color("#a66f77")
			var item_name := String(entry.get("name", ""))
			var description := SquareUiGeometry.equipment_name(slot) + ": " + (item_name if not item_name.is_empty() else "Пусто")
			icon.tooltip_text = description
			icon.pressed.connect(_show_item.bind(description))

func _face_bar(panel: Control, x: float, y: float, current: int, maximum: int, color: String, kind: String) -> void:
	var bar := ProgressBar.new()
	bar.position = Vector2(x, y)
	bar.size = Vector2(216, 17)
	bar.max_value = maxi(1, maximum)
	bar.value = clampi(current, 0, maxi(1, maximum))
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(color)
	bar.add_theme_stylebox_override("fill", fill)
	panel.add_child(bar)
	var text := Label.new()
	text.position = Vector2(x, y)
	text.size = Vector2(216, 17)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 11)
	text.text = "%d / %d %s" % [current, maximum, kind]
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)

## This is an information-only tab. Viewing another participant never
## changes GroupCombatSimulator's authoritative active opponent.
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

func _add_effect_rows(avatar: Control, effects: Array) -> void:
	for polarity in ["BUFF", "DEBUFF"]:
		var row := HBoxContainer.new()
		row.position = Vector2(2, avatar.custom_minimum_size.y - (54 if polarity == "BUFF" else 27))
		row.add_theme_constant_override("separation", 1)
		avatar.add_child(row)
		var matching: Array[Dictionary] = []
		for raw in effects:
			if raw is Dictionary and String(raw.get("polarity", "")).to_upper() == polarity:
				matching.append(raw)
		var shown := mini(5, matching.size())
		for index in range(shown):
			var button := Button.new()
			button.custom_minimum_size = Vector2(25, 25)
			button.add_theme_font_size_override("font_size", 12)
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
	abilities.add_theme_constant_override("separation", 10)
	actions_column.add_child(abilities)
	for index in range(5):
		var entry: Dictionary = abi_slots[index] if index < abi_slots.size() else {}
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 80)
		button.text = String(entry.get("id", "")) if not String(entry.get("id", "")).is_empty() else "—"
		button.add_theme_font_size_override("font_size", 15)
		button.tooltip_text = "%s • %s • %d MP" % [String(entry.get("id", "Пусто")), String(entry.get("name", "Нет ABI")), int(entry.get("mana_cost", 0))]
		button.pressed.connect(_choose_ability.bind(index))
		abilities.add_child(button)
		abi_buttons.append(button)
	_section("ЭЛИКСИРЫ • общий откат")
	var potions := HBoxContainer.new()
	potions.add_theme_constant_override("separation", 10)
	actions_column.add_child(potions)
	var loadout: Dictionary = snapshot.get("elixir_loadout", {})
	var potion_slots: Array = loadout.get("slots", [])
	for index in range(4):
		var entry: Dictionary = potion_slots[index] if index < potion_slots.size() else {}
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 79)
		var charges := int(entry.get("charges", 0))
		var maximum := int(entry.get("max_charges", 0))
		button.text = "%d/%d" % [charges, maximum] if not String(entry.get("instance_id", "")).is_empty() else "—"
		button.add_theme_font_size_override("font_size", 17)
		button.tooltip_text = "%s • %d/%d" % [String(entry.get("instance_id", "Пусто")), charges, maximum]
		button.pressed.connect(_choose_elixir.bind(index))
		potions.add_child(button)
		potion_buttons.append(button)

func _section(title: String) -> void:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", Color("#e4d6b9"))
	heading.add_theme_font_size_override("font_size", 19)
	actions_column.add_child(heading)

func _zone_buttons(attack: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	actions_column.add_child(row)
	for i in range(ZONES.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 83)
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
	var description := square_content.get_node_or_null("PreparedActions") as Label
	if description != null:
		var selected_attacks := ", ".join(chosen_attack)
		var selected_defense := ", ".join(chosen_blocks)
		description.text = "АТАКА  %s    |    БЛОК  %s" % [
			selected_attacks if not selected_attacks.is_empty() else "—",
			selected_defense if not selected_defense.is_empty() else "—"
		]
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
