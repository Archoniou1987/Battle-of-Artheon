class_name VisualLabPresets
extends RefCounted

## Non-persistent visual experiments. Never modifies item/character/combat data.
## The neutral design is deliberately the production baseline.
const THEMES := [
	{"id":"original","title":"Оригинал · синий камень","background":"#ffffff","empty_fill":"#263346","empty_border":"#83b8d9"},
	{"id":"bronze","title":"Бронза · тёплый металл","background":"#e8c99d","empty_fill":"#322720","empty_border":"#c5a16a"},
	{"id":"steel","title":"Сталь · холодный графит","background":"#b7c3d4","empty_fill":"#20262e","empty_border":"#9aabb8"}
]

static func theme(index: int) -> Dictionary:
	return Dictionary(THEMES[clampi(index, 0, THEMES.size() - 1)]).duplicate(true)

static func configure_empty(icon: ItemIcon, theme_index: int, show_ghost: bool, show_frame: bool) -> void:
	if icon == null:
		return
	icon.set_empty_placeholder_icon_visible(show_ghost)
	if not icon._shown_item.is_empty():
		return
	var colors := theme(theme_index)
	# Apply visual overrides to the empty cell only; occupied cells retain
	# their rarity frame regardless of Visual Lab settings.
	var style := icon.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	style.bg_color = Color(String(colors["empty_fill"])) if not show_ghost else Color.TRANSPARENT
	style.border_color = Color(String(colors["empty_border"]))
	style.set_border_width_all(2 if show_frame else 0)
	icon.add_theme_stylebox_override("normal", style)
	icon.add_theme_stylebox_override("hover", style.duplicate())
	icon.add_theme_stylebox_override("pressed", style.duplicate())
