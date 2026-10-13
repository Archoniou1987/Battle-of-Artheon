class_name ItemDetailDialog
extends Control

## Shared item details for bag and equipped slots. Requirements are red if unmet.
signal changed
signal elixir_requested(instance_id: String)

var character: CharacterState
var repository: ItemRepository
var item_id := ""
var source_slot := ""
var backdrop: ColorRect
var anchor_rect: Rect2 = Rect2()
var panel: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var actions: HBoxContainer
var status_label: Label

func _init(p_character: CharacterState = null, p_repository: ItemRepository = null) -> void:
	character = p_character
	repository = p_repository

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "ItemTooltip"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size.x = 280
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202b3b")
	style.border_color = Color("#94774e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 80)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("#e6a06f"))
	body.add_child(status_label)
	actions = HBoxContainer.new()
	body.add_child(actions)
	resized.connect(_update_dialog_size)
	call_deferred("_update_dialog_size")
	visible = false

func show_item(instance_id: String, slot: String = "", target: Control = null) -> void:
	if character == null or repository == null or not repository.has_item(instance_id):
		return
	item_id = instance_id
	source_slot = slot
	if target != null:
		anchor_rect = Rect2(target.get_global_rect().position - get_global_rect().position, target.size)
	visible = true
	status_label.text = ""
	_render()
	call_deferred("_update_dialog_size")

func _render() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	var item := repository.get_item(item_id)
	_add_text(str(item.get("name", item_id)), Color("#f1ddbb"), 21)
	_add_text("Уровень %s · %s" % [str(item.get("item_level", item.get("level", "—"))), _stat_label(String(item.get("type", "предмет")))], Color("#b6c2d0"))
	_add_separator()
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
			_add_text("%d %s" % [needed, _stat_label(String(stat))], Color("#e2e5eb") if met else Color("#e05d5d"))
	_add_separator()
	_add_stat_lines(item.get("guaranteed_stats", {}), Color("#f1f4f8"))
	_add_stat_lines(item.get("bonuses", {}), Color("#65d58b"))
	var damage: Dictionary = item.get("damage", {})
	if not damage.is_empty():
		_add_text("Урон %s–%s" % [str(damage.get("min", 0)), str(damage.get("max", 0))], Color("#f1f4f8"))
	var block_zones := int(item.get("manual_block_zones_added", 0))
	if block_zones > 0:
		_add_text("+%d зона ручного блока" % block_zones, Color("#f1f4f8"))
	var armour: Dictionary = item.get("armour_by_zone", {})
	for zone in ["head", "chest", "arms", "waist", "legs"]:
		if armour.has(zone):
			_add_text("+%s брони: %s" % [str(armour[zone]), _stat_label(zone)], Color("#f1f4f8"))
	if not source_slot.is_empty() and not character.is_equipment_active(item_id, repository):
		_add_text("НЕАКТИВНО — требования не выполнены", Color("#ed5961"), 17)
	var description := str(item.get("description", ""))
	if not description.is_empty():
		_add_separator()
		_add_text(description, Color("#bac6d4"))
	var action := Button.new()
	if String(item.get("type", "")) == "consumable":
		action.text = "В слот эликсира"
		action.disabled = not character.inventory.owns(item_id)
		action.pressed.connect(func() -> void: elixir_requested.emit(item_id))
	elif not source_slot.is_empty():
		action.text = "Снять"
		action.disabled = character.in_combat
		action.pressed.connect(_unequip)
	else:
		action.text = "Надеть"
		action.disabled = not allowed or not character.meets_requirements(item, repository) or item.get("equip_slots", []).is_empty() or character.in_combat or not character.inventory.owns(item_id) or character.equipment.is_equipped(item_id) or not ItemDurabilityService.is_usable(item)
		action.pressed.connect(_equip)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(action)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(func() -> void: visible = false)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(close)

func _update_dialog_size() -> void:
	if panel == null or scroll == null:
		return
	var available_width := maxf(160.0, size.x - 28.0)
	var available_height := maxf(150.0, size.y - 36.0)
	panel.custom_minimum_size.x = minf(420.0, available_width)
	scroll.custom_minimum_size.x = 0.0
	var content_height := content.get_combined_minimum_size().y
	var scroll_height := minf(content_height + 12.0, maxf(80.0, available_height - 120.0))
	scroll.custom_minimum_size.y = maxf(80.0, scroll_height)
	panel.reset_size()
	var panel_size := panel.get_combined_minimum_size()
	var px := anchor_rect.end.x + 8.0
	if px + panel_size.x > size.x - 8.0:
		px = anchor_rect.position.x - panel_size.x - 8.0
	px = clampf(px, 8.0, maxf(8.0, size.x - panel_size.x - 8.0))
	var py := clampf(anchor_rect.position.y, 8.0, maxf(8.0, size.y - panel_size.y - 8.0))
	panel.position = Vector2(px, py)


const STAT_NAMES := {
	"STR":"Силы", "DEX":"Ловкости", "INTU":"Интуиции", "WIS":"Мудрости",
	"INT":"Интеллекта", "END":"Выносливости", "STA":"Выносливости",
	"crit_chance_rating":"рейтинг крита", "crit_rating":"рейтинг крита",
	"dodge_rating":"рейтинг уворота", "anti_dodge_rating":"рейтинг антиуворота",
	"hit_chance_rating":"рейтинг попадания", "anti_crit_rating":"рейтинг антикрита",
	"manual_block_rating":"рейтинг блокирования", "head":"голова", "chest":"грудь", "arms":"руки", "waist":"пояс", "legs":"ноги",
	"max_hp_flat":"макс. HP", "max_mana_flat":"макс. маны",
	"weapon":"Оружие", "armour":"Доспех", "armor":"Доспех",
	"ring":"Кольцо", "shield":"Щит", "consumable":"Расходный предмет"
}

func _stat_label(key: String) -> String:
	return String(STAT_NAMES.get(key, key.replace("_", " ")))

func _add_separator() -> void:
	var line := HSeparator.new()
	content.add_child(line)

func _add_stat_lines(values: Variant, tint: Color) -> void:
	if not values is Dictionary:
		return
	for key in values:
		var value: Variant = values[key]
		var amount := str(value)
		if value is int or value is float:
			amount = ("+" + str(value)) if float(value) >= 0.0 else str(value)
		_add_text("%s %s" % [amount, _stat_label(String(key))], tint)

func _add_text(value: String, tint: Color, font_size: int = 15) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", font_size)
	content.add_child(label)

func _equip() -> void:
	if character.in_combat:
		status_label.text = "Нельзя менять экипировку во время боя."
		return
	var item := repository.get_item(item_id)
	var candidates: Array = item.get("equip_slots", []).duplicate()
	if candidates.has("ring1") and not candidates.has("ring2"):
		candidates.append("ring2")
	elif candidates.has("ring2") and not candidates.has("ring1"):
		candidates.append("ring1")
	candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
		return character.equipment.get_equipped_instance_id(String(a)) == null and character.equipment.get_equipped_instance_id(String(b)) != null)
	for slot in candidates:
		if character.equip(String(slot), item_id, repository):
			changed.emit()
			visible = false
			return
	status_label.text = "Не удалось надеть: проверьте требования, слоты и вместимость сумки."

func _unequip() -> void:
	if character.unequip(source_slot, repository) != null:
		changed.emit()
		visible = false
	else:
		status_label.text = "Не удалось снять: бой или недостаточно места в сумке."
