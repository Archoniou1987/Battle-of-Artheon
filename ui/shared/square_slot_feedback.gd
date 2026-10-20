class_name SquareSlotFeedback
extends RefCounted

## Shared, restrained feedback for square-panel controls.
## Does NOT own the slot artwork, item rarity, click handlers or game rules.
## Overlays never intercept input and never alter geometry/scaling.
const HOVER_OVERLAY := "SquareInteractionFeedback"
const SELECTION_OVERLAY := "SquareSelectionFeedback"

static func attach(button: BaseButton, role: String = "equipment") -> void:
	if button == null or button.has_node(HOVER_OVERLAY):
		return
	var overlay := Panel.new()
	overlay.name = HOVER_OVERLAY
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.19, 0.34, 0.48, 0.16)
	hover_style.border_color = Color("#87b4cb", 0.8) if role == "equipment" else Color("#c5ab75", 0.8)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(3)
	hover_style.set_content_margin_all(0)
	overlay.add_theme_stylebox_override("panel", hover_style)
	button.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.modulate.a = 0.0
	button.mouse_entered.connect(_hover.bind(button, overlay, true))
	button.mouse_exited.connect(_hover.bind(button, overlay, false))
	button.button_down.connect(_down.bind(button, overlay))
	button.button_up.connect(_up.bind(button, overlay))
	button.pressed.connect(_flash.bind(button, overlay))

	var selected := Panel.new()
	selected.name = SELECTION_OVERLAY
	selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var selection_style := StyleBoxFlat.new()
	selection_style.bg_color = Color.TRANSPARENT
	selection_style.border_color = Color("#d8b47b", 0.94)
	selection_style.set_border_width_all(2)
	selection_style.set_corner_radius_all(3)
	selection_style.set_content_margin_all(0)
	selected.add_theme_stylebox_override("panel", selection_style)
	button.add_child(selected)
	selected.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	selected.visible = false

static func set_selected(button: BaseButton, selected: bool) -> void:
	if button == null:
		return
	var highlight := button.get_node_or_null(SELECTION_OVERLAY) as Control
	if highlight != null:
		highlight.visible = selected

static func style_abi_square(button: Button) -> void:
	# Slot shape only. Actual ABI art (when available) will be a separate layer.
	var base := StyleBoxFlat.new()
	base.bg_color = Color("#171d27")
	base.border_color = Color("#68737e")
	base.set_border_width_all(1)
	base.set_corner_radius_all(3)
	base.set_content_margin_all(0)
	button.add_theme_stylebox_override("normal", base)
	button.add_theme_stylebox_override("hover", base.duplicate())
	button.add_theme_stylebox_override("pressed", base.duplicate())
	button.add_theme_stylebox_override("hover_pressed", base.duplicate())
	var inactive := base.duplicate() as StyleBoxFlat
	inactive.bg_color = Color("#11161e")
	inactive.border_color = Color("#4b535c")
	button.add_theme_stylebox_override("disabled", inactive)
	button.add_theme_color_override("font_color", Color("#e8ddc9"))
	button.add_theme_color_override("font_disabled_color", Color("#65717b"))

static func attach_art(button: BaseButton, art: CanvasItem) -> void:
	# The End Turn button has a separate atlas TextureRect above its hit area.
	# Animate the visible art, not the invisible underlying Button.
	if button == null or art == null:
		return
	button.button_down.connect(_art_tint.bind(art, Color("#afa49a"), 0.05))
	button.button_up.connect(_art_tint.bind(art, Color.WHITE, 0.12))
	button.pressed.connect(_art_flash.bind(art))

static func _hover(button: BaseButton, overlay: Panel, entered: bool) -> void:
	if not button.disabled:
		_fade(overlay, 0.38 if entered else 0.0, 0.12)

static func _down(button: BaseButton, overlay: Panel) -> void:
	if button.disabled or not is_instance_valid(overlay):
		return
	# Touch feedback must be visible on the SAME frame as button_down.
	# A newly queued Tween may not advance before a short mobile tap or
	# in headless UI tests, so never depend on its first tick.
	var previous: Variant = overlay.get_meta("_square_feedback_tween") if overlay.has_meta("_square_feedback_tween") else null
	if previous is Tween and is_instance_valid(previous):
		(previous as Tween).kill()
	overlay.modulate.a = 0.9

static func _up(button: BaseButton, overlay: Panel) -> void:
	if not is_instance_valid(overlay):
		return
	# Release always removes the down state, even when gameplay disables
	# the button synchronously after a successful click.
	_fade(overlay, 0.3 if button.is_hovered() and not button.disabled else 0.0, 0.13)

static func _flash(button: BaseButton, overlay: Panel) -> void:
	if not is_instance_valid(overlay):
		return
	var tween := _new_tween(overlay)
	tween.tween_property(overlay, "modulate:a", 0.95, 0.045)
	tween.tween_property(overlay, "modulate:a", 0.3 if button.is_hovered() and not button.disabled else 0.0, 0.21)

static func _fade(overlay: Panel, opacity: float, duration: float) -> void:
	if not is_instance_valid(overlay):
		return
	var tween := _new_tween(overlay)
	tween.tween_property(overlay, "modulate:a", opacity, duration)

static func _new_tween(target: CanvasItem) -> Tween:
	# In Godot 4.5 get_meta(key, null) still logs ERROR for a missing
	# key. First interaction has no tween metadata yet; guard explicitly.
	if target.has_meta("_square_feedback_tween"):
		var previous: Variant = target.get_meta("_square_feedback_tween")
		if previous is Tween and is_instance_valid(previous):
			(previous as Tween).kill()
	var tween := target.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	target.set_meta("_square_feedback_tween", tween)
	return tween

static func _art_flash(art: CanvasItem) -> void:
	if not is_instance_valid(art):
		return
	var tween := _new_tween(art)
	tween.tween_property(art, "modulate", Color("#f4dab1"), 0.065)
	tween.tween_property(art, "modulate", Color.WHITE, 0.20)

static func _art_tint(art: CanvasItem, color: Color, duration: float) -> void:
	if not is_instance_valid(art):
		return
	var tween := _new_tween(art)
	tween.tween_property(art, "modulate", color, duration)
