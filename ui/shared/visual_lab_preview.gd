class_name VisualLabPreview
extends RefCounted

## Read-only mock equipment tiles. No item instances, repository writes or game stats.
const OVERLAY := "VisualLabMockItem"
const SCENARIOS := ["Живые данные", "Пример редкости", "Заполненная экипировка"]
const RARITIES := ["green", "blue", "purple", "orange", "red"]

static func show_mock(icon: ItemIcon, enabled: bool, rarity_index: int = 0) -> void:
	if icon == null:
		return
	var existing := icon.get_node_or_null(OVERLAY) as Panel
	# Never cover genuine equipment with a fake icon.
	if not enabled or not icon._shown_item.is_empty():
		if existing != null:
			existing.queue_free()
			existing.name = "VisualLabMockRetiring"
		return
	if existing == null:
		existing = Panel.new()
		existing.name = OVERLAY
		existing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(existing)
		existing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var label := Label.new()
		label.name = "MockLabel"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		existing.add_child(label)
	var rarity: String = String(RARITIES[clampi(rarity_index, 0, RARITIES.size() - 1)])
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#263342")
	frame.border_color = Color(String(ItemIcon.RARITY_COLORS[rarity]))
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(4)
	existing.add_theme_stylebox_override("panel", frame)
	(existing.get_node("MockLabel") as Label).text = "◆"
	existing.tooltip_text = "Visual Lab: макет, не предмет"
