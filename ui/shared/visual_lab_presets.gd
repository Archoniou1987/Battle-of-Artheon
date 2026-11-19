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

## Themed square-button chrome. Call only on ABI/elixir buttons; never on
## textured attack/defense icons, whose red/blue meaning must remain intact.
static func configure_system_button(button: Button, theme_index: int) -> void:
	if button == null:
		return
	var colors: Dictionary = theme(theme_index)
	var base := StyleBoxFlat.new()
	base.bg_color = Color(String(colors["empty_fill"]))
	base.border_color = Color(String(colors["empty_border"]))
	base.set_border_width_all(2)
	base.set_corner_radius_all(3)
	base.set_content_margin_all(0)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, base.duplicate())
	var disabled_style := base.duplicate() as StyleBoxFlat
	disabled_style.bg_color = base.bg_color.darkened(0.24)
	disabled_style.border_color = base.border_color.darkened(0.20)
	button.add_theme_stylebox_override("disabled", disabled_style)

## The zone illustration is deliberately untouched; tint only the separately
## rendered selection border, not semantic red/blue defense/attack artwork.
static func configure_zone_outline(button: Button, theme_index: int) -> void:
	if button == null:
		return
	var outline := button.get_node_or_null("SelectionOutline") as Panel
	if outline == null:
		return
	var colors: Dictionary = theme(theme_index)
	var style := outline.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = Color(String(colors["empty_border"]))
	outline.add_theme_stylebox_override("panel", style)
